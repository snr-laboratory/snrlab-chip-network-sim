#!/usr/bin/env bash
set -euo pipefail

# 15x15 live-network analog/cosim event test with RTL-preconfigured chip state
# and staggered all-channel injections across multiple final chip IDs.
#
# Test intent:
# - instantiate a 15-row by 15-column LArPix network with source chip (0,0)
# - preload the true RTL register file of each chip with the final CHIP_ID and
#   TX-lane state implied by the existing bootstrap assignment protocol
# - enable selected event channels on two chip sequences in the 15x15 array
# - first sequence chip_ids: 48, 64, 80, 96, 112, 113, 129, 145
# - second sequence chip_ids: 183, 184, 169, 155, 141
# - inject one charge pulse into channels 0..15 on each target chip
# - use 500-tick spacing within each sequence
# - start the second sequence at tick 2000
# - stop after a shorter drain tail so the trace collector does not time out
#   during a long quiet period after the final packet has already reached the FPGA
# - generate a visualizer playback JSON for the preconfigured 15x15 scenario
# - verify that the FPGA receives downstream data packets from each injected chip

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo_root/build"
work_dir="$build_dir/larpix_15x15_event_staggered_multichip"
init_json="$work_dir/init_15x15_event_staggered_multichip_preconfigured.json"
stimulus_json="$work_dir/stimulus_15x15_event_staggered_multichip.json"
log_file="$work_dir/run.log"
trace_jsonl="$work_dir/trace.jsonl"
playback_json="$work_dir/live_event_15x15_staggered_multichip.json"
run_metrics_json="$work_dir/run_metrics.json"
chip_target="${CHIP_TARGET:-chip_larpix_build}"
chip_bin_name="${CHIP_BIN_NAME:-chip_larpix}"
case "$chip_bin_name" in
  chip_larpix_v3c) rtl_version_default="v3c" ;;
  chip_larpix_v2) rtl_version_default="v3b2" ;;
  *) rtl_version_default="v3b" ;;
esac
rtl_version_label="${RTL_VERSION_LABEL:-$rtl_version_default}"
mkdir -p "$work_dir"

python3 "$repo_root/larpix_network_sim/scripts/generate_bootstrap_preconfigured_event_init_json.py" \
  --rows 15 \
  --cols 15 \
  --s 0 \
  --target 3,3 \
  --target 4,4 \
  --target 5,5 \
  --target 6,6 \
  --target 7,7 \
  --target 8,7 \
  --target 9,8 \
  --target 10,9 \
  --target 3,12 \
  --target 4,12 \
  --target 4,11 \
  --target 5,10 \
  --target 6,9 \
  --out "$init_json"

cmake -S "$repo_root" -B "$build_dir"
cmake --build "$build_dir" --target fpga_larpix trace_collector_larpix orchestrator_larpix "$chip_target" -j

read -r first_injection_tick last_injection_tick ticks <<<"$(python3 - "$stimulus_json" <<'PYT'
import json
import pathlib
import sys

first_targets = [48, 64, 80, 96, 112, 113, 129, 145]
second_targets = [183, 184, 169, 155, 141]
base_tick = 1000
tick_spacing = 500
second_base_tick = 2000
channels = list(range(16))
charge = -5.0e-15
charges = []
for index, runtime_id in enumerate(first_targets):
    tick = base_tick + index * tick_spacing
    for channel in channels:
        charges.append({
            'runtime_id': runtime_id,
            'tick': tick,
            'channel': channel,
            'charge': charge,
        })
for index, runtime_id in enumerate(second_targets):
    tick = second_base_tick + index * tick_spacing
    for channel in channels:
        charges.append({
            'runtime_id': runtime_id,
            'tick': tick,
            'channel': channel,
            'charge': charge,
        })
pathlib.Path(sys.argv[1]).write_text(
    '// 15x15 analog/cosim preconfigured two-track staggered multi-chip event test stimulus\n'
    + json.dumps({'charges': charges}, indent=2)
    + '\n'
)
last_tick = max(
    base_tick + (len(first_targets) - 1) * tick_spacing,
    second_base_tick + (len(second_targets) - 1) * tick_spacing,
)
print(base_tick, last_tick, last_tick + 4000)
PYT
)"

run_ok=0
for attempt in 1 2 3 4 5; do
  base_uri="$(python3 - <<'PYU'
import random
print(f"tcp://127.0.0.1:{random.randint(20000, 45000)}")
PYU
)"
  if python3 - "$build_dir" "$init_json" "$stimulus_json" "$trace_jsonl" "$log_file" "$run_metrics_json" "$base_uri" "$ticks" <<'PYRUN'
import json
import os
import pathlib
import subprocess
import sys
import time

build_dir = pathlib.Path(sys.argv[1])
init_json = pathlib.Path(sys.argv[2])
stimulus_json = pathlib.Path(sys.argv[3])
trace_jsonl = pathlib.Path(sys.argv[4])
log_file = pathlib.Path(sys.argv[5])
run_metrics_json = pathlib.Path(sys.argv[6])
base_uri = sys.argv[7]
ticks = int(sys.argv[8])

cmd = [
    str(build_dir / 'orchestrator_larpix'),
    '-rows', '15',
    '-cols', '15',
    '-ticks', str(ticks),
    '-startup_ms', '3000',
    '-ack_timeout_ms', '20000',
    '-source_x', '0',
    '-base_uri', base_uri,
    '-source_y', '0',
    '-chip_bin', str(build_dir / os.environ.get('CHIP_BIN_NAME', 'chip_larpix')),
    '-fpga_bin', str(build_dir / 'fpga_larpix'),
    '-init_regs_json', str(init_json),
    '-stimulus_json', str(stimulus_json),
    '-trace_out', str(trace_jsonl),
]

allowed = {'orchestrator_larpix', 'chip_larpix', 'fpga_larpix', 'trace_collector_larpix'}
peak_concurrent_cores = 0
peak_core_ids = []
available_cores = os.cpu_count() or 0
start = time.monotonic()
with log_file.open('w') as log_fp:
    proc = subprocess.Popen(cmd, stdout=log_fp, stderr=subprocess.STDOUT)
    orch_pid = proc.pid
    while True:
        try:
            out = subprocess.check_output(['ps', '-eLo', 'ppid=,pid=,psr=,comm='], text=True)
            sample_cores = set()
            for line in out.splitlines():
                parts = line.strip().split(None, 3)
                if len(parts) != 4:
                    continue
                ppid_s, pid_s, psr_s, comm = parts
                try:
                    ppid = int(ppid_s)
                    pid = int(pid_s)
                    psr = int(psr_s)
                except ValueError:
                    continue
                if psr < 0:
                    continue
                if (pid == orch_pid or ppid == orch_pid) and comm in allowed:
                    sample_cores.add(psr)
            if len(sample_cores) > peak_concurrent_cores:
                peak_concurrent_cores = len(sample_cores)
                peak_core_ids = sorted(sample_cores)
        except Exception:
            pass
        rc = proc.poll()
        if rc is not None:
            runtime_sec = time.monotonic() - start
            summary = {
                'ticks': ticks,
                'runtime_sec': runtime_sec,
                'ticks_per_sec': (ticks / runtime_sec) if runtime_sec > 0 else 0.0,
                'cpu_cores_used': peak_concurrent_cores,
                'cpu_peak_concurrent_cores': peak_concurrent_cores,
                'cpu_core_ids_used': peak_core_ids,
                'cpu_cores_available': available_cores,
            }
            run_metrics_json.write_text(json.dumps(summary, indent=2) + '\n')
            sys.exit(rc)
        time.sleep(0.2)
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

python3 "$repo_root/larpix_network_sim/visualizers/packet_transmission/convert_live_trace_to_playback.py" \
  --rows 15 \
  --cols 15 \
  --source-x 0 \
  --source-y 0 \
  --init-regs-json "$init_json" \
  --run-log "$log_file" \
  --trace-jsonl "$trace_jsonl" \
  --out "$playback_json" \
  --rtl-version "$rtl_version_label" \
  --name "15x15 RTL-Preconfigured Two-Track Staggered Multi-Chip Injection"

python3 - "$playback_json" "$run_metrics_json" <<'PYMETRICS'
import json
import pathlib
import sys

playback_json = pathlib.Path(sys.argv[1])
run_metrics_json = pathlib.Path(sys.argv[2])
playback = json.loads(playback_json.read_text())
playback['run_summary'] = json.loads(run_metrics_json.read_text())
playback_json.write_text(json.dumps(playback, indent=2) + '\n')
PYMETRICS

python3 - "$init_json" "$log_file" "$trace_jsonl" "$playback_json" "$repo_root/larpix_network_sim/scripts/larpix_uart.py" <<'PY2'
import importlib.util
import json
import pathlib
import re
import sys

init_json = pathlib.Path(sys.argv[1])
log_path = pathlib.Path(sys.argv[2])
trace_jsonl = pathlib.Path(sys.argv[3])
playback_json = pathlib.Path(sys.argv[4])
helper_path = pathlib.Path(sys.argv[5])
init_raw = json.loads(init_json.read_text())
text = log_path.read_text()
if not trace_jsonl.exists() or trace_jsonl.stat().st_size == 0:
    raise SystemExit('FAIL: trace JSONL was not produced')
if not playback_json.exists() or playback_json.stat().st_size == 0:
    raise SystemExit('FAIL: playback JSON was not produced')

target_chip_ids = [48, 64, 80, 96, 112, 113, 129, 145, 183, 184, 169, 155, 141]
target_coords = {
    48: (3, 3),
    64: (4, 4),
    80: (5, 5),
    96: (6, 6),
    112: (7, 7),
    113: (8, 7),
    129: (9, 8),
    145: (10, 9),
    183: (3, 12),
    184: (4, 12),
    169: (4, 11),
    155: (5, 10),
    141: (6, 9),
}

raw_packets = re.findall(r'received packet at seq=\d+: (0x[0-9a-fA-F]+)', text)
if not raw_packets:
    print(text)
    raise SystemExit('FAIL: fpga_larpix did not receive any reply packets')

spec = importlib.util.spec_from_file_location('larpix_uart', helper_path)
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)

data_packets = []
for raw in raw_packets:
    word = int(raw, 0)
    fields = mod.decode_packet(word)
    if fields.kind == 'data':
        data_packets.append((word, fields))
if not data_packets:
    print(text)
    raise SystemExit('FAIL: fpga_larpix received packets, but none decoded as data packets')

observed_by_chip = {chip_id: set() for chip_id in target_chip_ids}
first_matching_by_chip = {}
for word, fields in data_packets:
    decoded = fields.decoded
    chip_id = decoded['chip_id']
    if fields.odd_parity_ok and chip_id in observed_by_chip and decoded['downstream'] == 1 and decoded['trigger_type'] == 0:
        observed_by_chip[chip_id].add(decoded['channel_id'])
        first_matching_by_chip.setdefault(chip_id, (word, fields))
missing_chips = [chip_id for chip_id, channels in observed_by_chip.items() if not channels]
if missing_chips:
    raise SystemExit('FAIL: missing matching data packets from chip_ids ' + ','.join(str(v) for v in missing_chips))

playback = json.loads(playback_json.read_text())
initial_chips = {(entry['x'], entry['y']): entry for entry in playback.get('initial_chips', [])}
for chip_id, coord in target_coords.items():
    entry = initial_chips.get(coord)
    if entry is None or entry.get('chip_id') != chip_id:
        raise SystemExit(f'FAIL: playback initial state does not show chip_id {chip_id} at {coord}')

charge_events = [event for event in playback.get('chip_events', []) if event.get('event') == 'charge_injected']
if len(charge_events) != len(target_chip_ids):
    raise SystemExit(f'FAIL: expected {len(target_chip_ids)} charge events in playback, observed {len(charge_events)}')

print('PASS: 15x15 LArPix analog/cosim two-track staggered multi-chip event test (rtl_preconfigured)')
print(f'preloaded_register_writes={len(init_raw.get("register_writes", []))}')
print(f'configured_targets={len(init_raw.get("targets", []))}')
print(f'trace_jsonl={trace_jsonl}')
print(f'playback_json={playback_json}')
for chip_id in target_chip_ids:
    channels = sorted(observed_by_chip[chip_id])
    word, fields = first_matching_by_chip[chip_id]
    print(f'chip_{chip_id}_distinct_event_channels={len(channels)}')
    print('chip_{chip_id}_observed_event_channels='.format(chip_id=chip_id) + ','.join(str(v) for v in channels))
    print(f'chip_{chip_id}_first_matching_reply_packet=0x{word:016x}')
    print(
        f'chip_{chip_id}_first_match='
        f'channel_id={fields.decoded["channel_id"]} '
        f'adc={fields.decoded["adc"]} '
        f'downstream={fields.decoded["downstream"]} '
        f'trigger_type={fields.decoded["trigger_type"]}'
    )
print('visualizer_url_hint=http://localhost:8000/larpix_network_sim/visualizers/packet_transmission/?playback=/build/larpix_15x15_event_staggered_multichip/live_event_15x15_staggered_multichip.json')
PY2
