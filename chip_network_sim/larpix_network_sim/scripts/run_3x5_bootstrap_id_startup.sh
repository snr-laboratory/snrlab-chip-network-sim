#!/usr/bin/env bash
set -euo pipefail

# 3x5 bootstrap chip-ID assignment plus immediate readback test.
#
# This script regenerates the startup schedule from
# `generate_bootstrap_chip_id_readback_json.py`, compiles that schedule into
# UART bitstreams, launches the live 3-row by 5-column LArPix network with
# source `(0,0)`, and checks that every chip-ID reassignment is immediately
# confirmed by a matching CHIP_ID readback at the FPGA controller.
#
# Passing result for the current protocol:
# verified_readbacks=0,99,2,3,4,5,10,6,11,7,12,8,13,9,14,1

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo_root/build"
work_dir="$build_dir/larpix_3x5_bootstrap_id_smoke"
startup_in="$repo_root/larpix_network_sim/config/startup_3x5_bootstrap_chip_ids.json"
startup_compiled="$work_dir/startup_3x5_bootstrap_chip_ids.compiled.json"
log_file="$work_dir/run.log"
trace_jsonl="$work_dir/trace.jsonl"
playback_json="$repo_root/larpix_network_sim/visualizers/packet_transmission/data/live_bootstrap_3x5.json"
mkdir -p "$work_dir"

python3 "$repo_root/larpix_network_sim/scripts/generate_bootstrap_chip_id_readback_json.py" \
  --rows 3 \
  --cols 5 \
  --s 0 \
  --out "$startup_in"

cmake -S "$repo_root" -B "$build_dir"
cmake --build "$build_dir" --target fpga_larpix trace_collector_larpix orchestrator_larpix chip_larpix_build -j

python3 "$repo_root/larpix_network_sim/scripts/compile_startup_json.py" \
  "$startup_in" \
  "$startup_compiled"

ticks="$(python3 - "$startup_compiled" <<'PYT'
import json
import pathlib
import sys
startup = json.loads(pathlib.Path(sys.argv[1]).read_text())
frames = startup.get('frames', [])
last_frame_tick = max((int(frame['tick_start']) for frame in frames), default=0)
print(last_frame_tick + 8000)
PYT
)"

run_ok=0
for attempt in 1 2 3 4 5; do
  if "$build_dir/orchestrator_larpix" \
    -rows 3 \
    -cols 5 \
    -ticks "$ticks" \
    -source_x 0 \
    -source_y 0 \
    -chip_bin "$build_dir/chip_larpix" \
    -fpga_bin "$build_dir/fpga_larpix" \
    -startup_json "$startup_compiled" \
    -trace_out "$trace_jsonl" \
    > "$log_file" 2>&1; then
    run_ok=1
    break
  fi
  if ! grep -q "Address in use" "$log_file"; then
    break
  fi
  sleep 1
done

if [[ "$run_ok" -ne 1 ]]; then
  cat "$log_file"
  exit 1
fi

python3 "$repo_root/larpix_network_sim/visualizers/packet_transmission/convert_live_trace_to_playback.py" \
  --rows 3 \
  --cols 5 \
  --source-x 0 \
  --source-y 0 \
  --startup-json "$startup_compiled" \
  --run-log "$log_file" \
  --trace-jsonl "$trace_jsonl" \
  --out "$playback_json" \
  --rtl-version "v3b" \
  --name "Live bootstrap 3x5 s=0"

python3 - "$startup_in" "$startup_compiled" "$log_file" "$trace_jsonl" "$playback_json" "$repo_root/larpix_network_sim/scripts/larpix_uart.py" <<'PY2'
import importlib.util
import json
import pathlib
import re
import sys

startup_in = pathlib.Path(sys.argv[1])
compiled = pathlib.Path(sys.argv[2])
log_path = pathlib.Path(sys.argv[3])
trace_jsonl = pathlib.Path(sys.argv[4])
playback_json = pathlib.Path(sys.argv[5])
helper_path = pathlib.Path(sys.argv[6])
startup_raw = json.loads(startup_in.read_text())
compiled_raw = json.loads(compiled.read_text())
frames = compiled_raw.get('frames', [])
expected_reads = [frame for frame in startup_raw.get('frames', []) if frame.get('type') == 'read' and int(frame.get('register_addr', -1)) == 122]
text = log_path.read_text()
observed_tx = len(re.findall(r'transmitted frame at seq=', text))
expected_tx = len(frames)
if not trace_jsonl.exists() or trace_jsonl.stat().st_size == 0:
    raise SystemExit('FAIL: bootstrap trace JSONL was not produced')
if not playback_json.exists() or playback_json.stat().st_size == 0:
    raise SystemExit('FAIL: bootstrap playback JSON was not produced')
if observed_tx != expected_tx:
    print(text)
    raise SystemExit(f'FAIL: expected {expected_tx} transmitted startup frames, observed {observed_tx}')

spec = importlib.util.spec_from_file_location('larpix_uart', helper_path)
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)

raw_packets = re.findall(r'received packet at seq=\d+: (0x[0-9a-fA-F]+)', text)
if not raw_packets:
    print(text)
    raise SystemExit('FAIL: fpga_larpix did not receive any reply packets')

observed = {}
for raw in raw_packets:
    word = int(raw, 0)
    fields = mod.decode_packet(word)
    if fields.kind != 'config_read':
        continue
    if not fields.odd_parity_ok:
        raise SystemExit(f'FAIL: config readback packet parity check failed for word 0x{word:016x}')
    decoded = fields.decoded
    if decoded['register_addr'] != 122:
        continue
    chip_id = decoded['chip_id']
    reg_data = decoded['register_data']
    observed.setdefault(chip_id, []).append(reg_data)

expected_ids = [int(frame['chip_id']) for frame in expected_reads]
missing = [chip_id for chip_id in expected_ids if chip_id not in observed]
wrong = [(chip_id, values) for chip_id, values in observed.items() if chip_id in expected_ids and chip_id not in missing and chip_id not in [eid for eid in expected_ids if eid == chip_id and any(v == chip_id for v in values)]]
if missing:
    print(text)
    raise SystemExit(f'FAIL: missing CHIP_ID readback replies for chip IDs: {missing}')
wrong = [chip_id for chip_id in expected_ids if all(v != chip_id for v in observed.get(chip_id, []))]
if wrong:
    raise SystemExit('FAIL: incorrect CHIP_ID readback values for chip IDs: ' + ', '.join(str(chip_id) for chip_id in wrong))

print('PASS: 3x5 bootstrap chip-ID assignment immediate-readback test')
print(f'expected_frame_count={expected_tx}')
print(f'observed_transmitted_frame_count={observed_tx}')
print('verified_readbacks=' + ','.join(str(i) for i in expected_ids))
print(f'trace_jsonl={trace_jsonl}')
print(f'playback_json={playback_json}')
PY2
