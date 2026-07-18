#!/usr/bin/env bash
set -euo pipefail

# 10x10 live v3c bootstrap verification.
#
# No RTL register-preload JSON is used. Every chip starts from the v3c reset
# state: CHIP_ID=1, ENABLE_PISO_UP=0, and ENABLE_PISO_DOWN=0. The FPGA then
# performs the full bootstrap process to assign IDs 0..99 and establish
# upstream/downstream routing. This scenario intentionally omits CHIP_ID reads;
# write frames use 75-tick spacing, safely above the observed 68-tick forwarding
# service interval.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo_root/build"
chip_target="${CHIP_TARGET:-chip_larpix_v3c_build}"
chip_bin_name="${CHIP_BIN_NAME:-chip_larpix_v3c}"
chip_variant="${CHIP_VARIANT_LABEL:-v3c}"
rtl_version_label="${RTL_VERSION_LABEL:-v3c}"
build_binaries="${BUILD_BINARIES:-1}"
drain_tail_ticks="${DRAIN_TAIL_TICKS:-20000}"
ack_timeout_ms="${ACK_TIMEOUT_MS:-120000}"
scenario_name="larpix_10x10_bootstrap_startup"
work_dir="$build_dir/${scenario_name}__${chip_variant}"
startup_json="$work_dir/startup_10x10_bootstrap.json"
startup_compiled="$work_dir/startup_10x10_bootstrap.compiled.json"
log_file="$work_dir/run.log"
trace_jsonl="$work_dir/trace.jsonl"
playback_json="$work_dir/live_bootstrap_10x10.json"
summary_json="$work_dir/bootstrap_summary.json"
run_metrics_json="$work_dir/run_metrics.json"
mkdir -p "$work_dir"

if [[ "$build_binaries" != "0" && "$build_binaries" != "1" ]]; then
  echo "BUILD_BINARIES must be 0 or 1" >&2
  exit 2
fi

if [[ "$build_binaries" == "1" ]]; then
  cmake -S "$repo_root" -B "$build_dir"
  cmake --build "$build_dir" \
    --target fpga_larpix trace_collector_larpix orchestrator_larpix "$chip_target" -j
fi

for required_bin in \
  "$build_dir/fpga_larpix" \
  "$build_dir/trace_collector_larpix" \
  "$build_dir/orchestrator_larpix" \
  "$build_dir/$chip_bin_name"
do
  if [[ ! -x "$required_bin" ]]; then
    echo "missing required binary: $required_bin" >&2
    exit 2
  fi
done

python3 "$repo_root/sim_core/tools/generate_bootstrap_chip_id_readback_json.py" \
  --rows 10 \
  --cols 10 \
  --s 0 \
  --no-readbacks \
  --tick-step 75 \
  --out "$startup_json"

python3 "$repo_root/sim_core/tools/compile_startup_json.py" \
  "$startup_json" \
  "$startup_compiled"

ticks="$(python3 - "$startup_compiled" "$drain_tail_ticks" <<'PYTICKS'
import json
import pathlib
import sys

compiled = json.loads(pathlib.Path(sys.argv[1]).read_text())
tail = int(sys.argv[2])
last_scheduled_tick = max(
    (int(frame['tick_start']) for frame in compiled.get('frames', [])),
    default=0,
)
print(last_scheduled_tick + tail)
PYTICKS
)"

run_ok=0
for attempt in 1 2 3 4 5; do
  base_uri="$(python3 - <<'PYURI'
import random
print(f"tcp://127.0.0.1:{random.randint(20000, 40000)}")
PYURI
)"
  if python3 - \
    "$build_dir" "$startup_compiled" "$trace_jsonl" "$log_file" \
    "$run_metrics_json" "$base_uri" "$ticks" "$ack_timeout_ms" <<'PYRUN'
import json
import os
import pathlib
import subprocess
import sys
import time

build_dir = pathlib.Path(sys.argv[1])
startup_compiled = pathlib.Path(sys.argv[2])
trace_jsonl = pathlib.Path(sys.argv[3])
log_file = pathlib.Path(sys.argv[4])
run_metrics_json = pathlib.Path(sys.argv[5])
base_uri = sys.argv[6]
ticks = int(sys.argv[7])
ack_timeout_ms = sys.argv[8]
chip_bin_name = os.environ.get('CHIP_BIN_NAME', 'chip_larpix_v3c')

cmd = [
    str(build_dir / 'orchestrator_larpix'),
    '-rows', '10',
    '-cols', '10',
    '-ticks', str(ticks),
    '-startup_ms', '10000',
    '-ack_timeout_ms', ack_timeout_ms,
    '-source_x', '0',
    '-source_y', '0',
    '-base_uri', base_uri,
    '-chip_bin', str(build_dir / chip_bin_name),
    '-fpga_bin', str(build_dir / 'fpga_larpix'),
    '-startup_json', str(startup_compiled),
    '-trace_out', str(trace_jsonl),
]

start = time.monotonic()
with log_file.open('w') as log_fp:
    result = subprocess.run(cmd, stdout=log_fp, stderr=subprocess.STDOUT)
runtime_sec = time.monotonic() - start
run_metrics_json.write_text(json.dumps({
    'ticks': ticks,
    'runtime_sec': runtime_sec,
    'ticks_per_sec': ticks / runtime_sec if runtime_sec > 0 else 0.0,
    'chip_count': 100,
    'initial_chip_id': 1,
    'preconfigured': False,
}, indent=2) + '\n')
raise SystemExit(result.returncode)
PYRUN
  then
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

python3 "$repo_root/sim_core/visualizers/packet_transmission/convert_live_trace_to_playback.py" \
  --rows 10 \
  --cols 10 \
  --source-x 0 \
  --source-y 0 \
  --startup-json "$startup_compiled" \
  --run-log "$log_file" \
  --trace-jsonl "$trace_jsonl" \
  --out "$playback_json" \
  --rtl-version "$rtl_version_label" \
  --name "Live v3c 10x10 Bootstrap Configuration"

python3 - \
  "$startup_json" "$log_file" "$playback_json" "$summary_json" \
  "$run_metrics_json" "$repo_root/sim_core/tools/larpix_uart.py" <<'PYVERIFY'
import importlib.util
import json
import pathlib
import re
import sys

startup_path = pathlib.Path(sys.argv[1])
log_path = pathlib.Path(sys.argv[2])
playback_path = pathlib.Path(sys.argv[3])
summary_path = pathlib.Path(sys.argv[4])
run_metrics_path = pathlib.Path(sys.argv[5])
helper_path = pathlib.Path(sys.argv[6])

startup = json.loads(startup_path.read_text())
log_text = log_path.read_text()
frames = startup.get('frames', [])

tx_matches = re.findall(
    r'transmitted frame at seq=(\d+)\s*:\s*(0x[0-9a-fA-F]+)(?:\s+label=([^\n]+))?',
    log_text,
)
rx_matches = re.findall(
    r'received packet at seq=(\d+):\s*(0x[0-9a-fA-F]+)',
    log_text,
)
if len(tx_matches) != len(frames):
    raise SystemExit(
        f'FAIL: transmitted frame count mismatch: expected {len(frames)}, '
        f'observed {len(tx_matches)}'
    )

spec = importlib.util.spec_from_file_location('larpix_uart', helper_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

expected_readbacks = [
    int(frame['chip_id'])
    for frame in frames
    if frame.get('type') == 'read' and int(frame.get('register_addr', -1)) == 122
]
observed_readbacks = []
for _, raw_word in rx_matches:
    packet = module.decode_packet(int(raw_word, 0))
    if packet.kind != 'config_read':
        continue
    decoded = packet.decoded
    if int(decoded.get('register_addr', -1)) != 122:
        continue
    if not packet.odd_parity_ok:
        raise SystemExit('FAIL: bootstrap CHIP_ID readback parity check failed')
    observed_readbacks.append(int(decoded['register_data']))

if observed_readbacks != expected_readbacks:
    raise SystemExit(
        'FAIL: bootstrap CHIP_ID readback mismatch\n'
        f'expected={expected_readbacks}\n'
        f'observed={observed_readbacks}'
    )

assigned_ids = sorted({
    int(frame['register_data'])
    for frame in frames
    if frame.get('type') == 'write' and int(frame.get('register_addr', -1)) == 122
    and 0 <= int(frame['register_data']) < 100
})
if assigned_ids != list(range(100)):
    raise SystemExit(f'FAIL: startup did not assign all IDs 0..99: {assigned_ids}')

upstream_writes = sum(
    1 for frame in frames
    if frame.get('type') == 'write' and int(frame.get('register_addr', -1)) == 124
)
downstream_writes = sum(
    1 for frame in frames
    if frame.get('type') == 'write' and int(frame.get('register_addr', -1)) == 125
)

summary = {
    'scenario': 'Live v3c 10x10 Bootstrap Configuration Without Readbacks',
    'rows': 10,
    'cols': 10,
    'chip_count': 100,
    'preconfigured': False,
    'rtl_reset_chip_id': 1,
    'rtl_reset_enable_piso_up': 0,
    'rtl_reset_enable_piso_down': 0,
    'startup_frame_count': len(frames),
    'transmitted_frame_count': len(tx_matches),
    'chip_id_readback_count': len(observed_readbacks),
    'assigned_chip_ids': assigned_ids,
    'upstream_lane_write_count': upstream_writes,
    'downstream_lane_write_count': downstream_writes,
    'last_transmitted_frame_tick': int(tx_matches[-1][0]) if tx_matches else None,
    'run_metrics': json.loads(run_metrics_path.read_text()),
}
summary_path.write_text(json.dumps(summary, indent=2) + '\n')

playback = json.loads(playback_path.read_text())
playback['run_summary'] = summary['run_metrics']
playback['bootstrap_summary'] = summary
playback_path.write_text(json.dumps(playback, indent=2) + '\n')

print('PASS: live v3c 10x10 bootstrap configuration')
print(json.dumps(summary, indent=2))
PYVERIFY

echo
printf 'Artifacts:\n'
printf '  startup JSON:  %s\n' "$startup_json"
printf '  compiled:      %s\n' "$startup_compiled"
printf '  run log:       %s\n' "$log_file"
printf '  trace jsonl:   %s\n' "$trace_jsonl"
printf '  playback:      %s\n' "$playback_json"
printf '  summary:       %s\n' "$summary_json"
