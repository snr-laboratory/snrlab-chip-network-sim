#!/usr/bin/env bash
set -euo pipefail

# 2x2 live-network msg_rtl mixed message/data probe.
#
# Layout (runtime ids):
#   y=1: 2 3
#   y=0: 0 1
#
# This probe keeps the internal MSG_OP generator enabled on all chips and also
# injects analog charge into runtime/chip 2 so we can observe event-data packets
# interacting with message packets in the same network.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo_root/build"
ticks="${TICKS:-3000}"
chip_target="${CHIP_TARGET:-chip_larpix_msg_rtl_build}"
chip_bin_name="${CHIP_BIN_NAME:-chip_larpix_msg_rtl}"
rtl_version_label="${RTL_VERSION_LABEL:-msg_rtl}"
build_binaries="${BUILD_BINARIES:-1}"
chip_variant="${CHIP_VARIANT_LABEL:-msg}"
scenario_name="larpix_2x2_msg_data_probe"
work_dir="$build_dir/${scenario_name}__${chip_variant}"
init_json="$work_dir/init_2x2_msg_data_probe_preconfigured.json"
stimulus_json="$work_dir/stimulus_2x2_msg_data_probe.json"
log_file="$work_dir/run.log"
trace_jsonl="$work_dir/trace.jsonl"
playback_json="$work_dir/live_event_2x2_msg_data_probe.json"
rx_debug_csv="$work_dir/chip0_rx_debug.csv"
summary_json="$work_dir/msg_data_probe_summary.json"
run_metrics_json="$work_dir/run_metrics.json"
mkdir -p "$work_dir"

python3 "$repo_root/sim_core/tools/generate_bootstrap_preconfigured_event_init_json.py" \
  --rows 2 \
  --cols 2 \
  --s 0 \
  --target 1,0 \
  --target 0,1 \
  --out "$init_json"

python3 - "$stimulus_json" <<'PYSTIM'
import json
import pathlib
import sys

injection_tick = 1000
channels = list(range(15))
charges = []
for channel in channels:
    charges.append({
        'runtime_id': 2,
        'tick': injection_tick,
        'channel': channel,
        'charge': -5.0e-15,
    })
pathlib.Path(sys.argv[1]).write_text(
    '// 2x2 msg/data mixed probe stimulus\n'
    + json.dumps({'charges': charges}, indent=2)
    + '\n'
)
PYSTIM

if [[ "$build_binaries" != "0" && "$build_binaries" != "1" ]]; then
  echo "BUILD_BINARIES must be 0 or 1" >&2
  exit 2
fi

if [[ "$build_binaries" == "1" ]]; then
  cmake -S "$repo_root" -B "$build_dir"
  cmake --build "$build_dir" --target fpga_larpix trace_collector_larpix orchestrator_larpix "$chip_target" -j
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

run_ok=0
for attempt in 1 2 3 4 5; do
  base_uri="$(python3 - <<'PYU'
import random
print(f"tcp://127.0.0.1:{random.randint(20000, 45000)}")
PYU
)"
  if python3 - "$build_dir" "$init_json" "$stimulus_json" "$trace_jsonl" "$log_file" "$run_metrics_json" "$rx_debug_csv" "$base_uri" "$ticks" <<'PYRUN'
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
rx_debug_csv = pathlib.Path(sys.argv[7])
base_uri = sys.argv[8]
ticks = int(sys.argv[9])

cmd = [
    str(build_dir / 'orchestrator_larpix'),
    '-rows', '2',
    '-cols', '2',
    '-ticks', str(ticks),
    '-startup_ms', '3000',
    '-ack_timeout_ms', '5000',
    '-source_x', '0',
    '-source_y', '0',
    '-base_uri', base_uri,
    '-chip_bin', str(build_dir / os.environ.get('CHIP_BIN_NAME', 'chip_larpix_msg_rtl')),
    '-fpga_bin', str(build_dir / 'fpga_larpix'),
    '-init_regs_json', str(init_json),
    '-stimulus_json', str(stimulus_json),
    '-trace_out', str(trace_jsonl),
    '-rx_debug_csv', str(rx_debug_csv),
    '-rx_debug_runtime_id', '0',
]

allowed = {'orchestrator_larpix', os.environ.get('CHIP_BIN_NAME', 'chip_larpix_msg_rtl'), 'fpga_larpix', 'trace_collector_larpix'}
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

python3 "$repo_root/sim_core/visualizers/packet_transmission/convert_live_trace_to_playback.py" \
  --rows 2 \
  --cols 2 \
  --source-x 0 \
  --source-y 0 \
  --init-regs-json "$init_json" \
  --run-log "$log_file" \
  --trace-jsonl "$trace_jsonl" \
  --out "$playback_json" \
  --rtl-version "$rtl_version_label" \
  --name "2x2 msg/data mixed probe"

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

python3 - "$trace_jsonl" "$log_file" "$summary_json" "$repo_root/sim_core/tools/larpix_uart.py" <<'PYSUM'
import importlib.util
import json
import pathlib
import re
import sys

trace_jsonl = pathlib.Path(sys.argv[1])
log_file = pathlib.Path(sys.argv[2])
summary_json = pathlib.Path(sys.argv[3])
helper_path = pathlib.Path(sys.argv[4])

spec = importlib.util.spec_from_file_location('larpix_uart', helper_path)
mod = importlib.util.module_from_spec(spec)
sys.modules['larpix_uart'] = mod
spec.loader.exec_module(mod)
decode_packet = mod.decode_packet

def kind(word):
    return decode_packet(word).kind

tx_by_runtime = {}
rx_by_runtime = {}
chip0_rx_by_edge = {'north': {'msg': 0, 'data': 0}, 'east': {'msg': 0, 'data': 0}, 'south': {'msg': 0, 'data': 0}, 'west': {'msg': 0, 'data': 0}}
chip2_data_channels = set()

for line in trace_jsonl.read_text().splitlines():
    if not line.strip():
        continue
    event = json.loads(line)
    name = str(event.get('event', ''))
    runtime_id = int(event.get('runtime_id', 0))
    word_raw = event.get('packet_word')
    if word_raw is None:
        continue
    word = int(word_raw, 0) if isinstance(word_raw, str) else int(word_raw)
    decoded = decode_packet(word)
    packet_kind = decoded.kind
    if name == 'tx_packet':
        entry = tx_by_runtime.setdefault(runtime_id, {'msg': 0, 'data': 0})
        if packet_kind == 'msg':
            entry['msg'] += 1
        elif packet_kind == 'data':
            entry['data'] += 1
            if runtime_id == 2:
                chip2_data_channels.add(int(decoded.decoded.get('channel_id', -1)))
    elif name == 'rx_packet':
        entry = rx_by_runtime.setdefault(runtime_id, {'msg': 0, 'data': 0})
        if packet_kind == 'msg':
            entry['msg'] += 1
        elif packet_kind == 'data':
            entry['data'] += 1
        if runtime_id == 0:
            edge = str(event.get('edge', ''))
            if edge in chip0_rx_by_edge:
                if packet_kind == 'msg':
                    chip0_rx_by_edge[edge]['msg'] += 1
                elif packet_kind == 'data':
                    chip0_rx_by_edge[edge]['data'] += 1

fpga_counts = {'msg': 0, 'data': 0}
fpga_data_channels = set()
for match in re.finditer(r'fpga_larpix\[\d+\] received packet at seq=(\d+):\s*(0x[0-9a-fA-F]+)', log_file.read_text()):
    word = int(match.group(2), 16)
    decoded = decode_packet(word)
    if decoded.kind == 'msg':
        fpga_counts['msg'] += 1
    elif decoded.kind == 'data':
        fpga_counts['data'] += 1
        fpga_data_channels.add(int(decoded.decoded.get('channel_id', -1)))

summary = {
    'scenario': '2x2 msg/data mixed probe',
    'injected_runtime_id': 2,
    'injected_chip_id': 2,
    'injected_charge': -5.0e-15,
    'injected_channels': list(range(15)),
    'tx_by_runtime': {str(k): v for k, v in sorted(tx_by_runtime.items())},
    'rx_by_runtime': {str(k): v for k, v in sorted(rx_by_runtime.items())},
    'chip0_rx_by_edge': chip0_rx_by_edge,
    'chip2_distinct_data_channels_tx': sorted(v for v in chip2_data_channels if v >= 0),
    'fpga_counts': fpga_counts,
    'fpga_distinct_data_channels': sorted(v for v in fpga_data_channels if v >= 0),
}
summary_json.write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))

if fpga_counts['msg'] == 0:
    raise SystemExit('FAIL: no MSG packets reached FPGA')
if fpga_counts['data'] == 0:
    raise SystemExit('FAIL: no data packets reached FPGA')
PYSUM

echo
printf 'Artifacts:\n'
printf '  run log:      %s\n' "$log_file"
printf '  trace jsonl:  %s\n' "$trace_jsonl"
printf '  playback:     %s\n' "$playback_json"
printf '  rx debug csv: %s\n' "$rx_debug_csv"
printf '  summary json: %s\n' "$summary_json"
