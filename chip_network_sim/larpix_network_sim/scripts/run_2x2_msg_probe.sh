#!/usr/bin/env bash
set -euo pipefail

# 2x2 live-network msg_rtl message probe.
#
# Layout (runtime ids):
#   y=1: 2 3
#   y=0: 0 1
#
# The msg_rtl backend generates broadcast-style MSG_OP packets internally
# inside msg_logic on every chip. This probe runs a 2x2 grid with no analog
# stimulus and verifies that MSG_OP traffic appears on chip-to-chip links and
# reaches the FPGA sink.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo_root/build"
work_dir="$build_dir/larpix_2x2_msg_probe"
init_json="$work_dir/init_2x2_msg_probe_preconfigured.json"
stimulus_json="$work_dir/stimulus_2x2_msg_probe.json"
log_file="$work_dir/run.log"
trace_jsonl="$work_dir/trace.jsonl"
rx_debug_csv="$work_dir/chip0_rx_debug.csv"
summary_json="$work_dir/msg_probe_summary.json"
run_metrics_json="$work_dir/run_metrics.json"
ticks="${TICKS:-2000}"
chip_target="${CHIP_TARGET:-chip_larpix_msg_rtl_build}"
chip_bin_name="${CHIP_BIN_NAME:-chip_larpix_msg_rtl}"
mkdir -p "$work_dir"

python3 "$repo_root/larpix_network_sim/scripts/generate_bootstrap_preconfigured_event_init_json.py" \
  --rows 2 \
  --cols 2 \
  --s 0 \
  --target 1,0 \
  --target 0,1 \
  --out "$init_json"

python3 - "$stimulus_json" <<'PYEMPTY'
import json
import pathlib
import sys
pathlib.Path(sys.argv[1]).write_text(
    '// 2x2 msg_rtl probe stimulus (no analog charge injection)\n'
    + json.dumps({'charges': []}, indent=2)
    + '\n'
)
PYEMPTY

cmake -S "$repo_root" -B "$build_dir"
cmake --build "$build_dir" --target fpga_larpix trace_collector_larpix orchestrator_larpix "$chip_target" -j

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

python3 - "$trace_jsonl" "$log_file" "$summary_json" "$run_metrics_json" "$repo_root/larpix_network_sim/scripts/larpix_uart.py" <<'PYSUM'
import importlib.util
import json
import pathlib
import re
import sys

trace_jsonl = pathlib.Path(sys.argv[1])
log_file = pathlib.Path(sys.argv[2])
summary_json = pathlib.Path(sys.argv[3])
run_metrics_json = pathlib.Path(sys.argv[4])
helper_path = pathlib.Path(sys.argv[5])

spec = importlib.util.spec_from_file_location('larpix_uart', helper_path)
mod = importlib.util.module_from_spec(spec)
sys.modules['larpix_uart'] = mod
spec.loader.exec_module(mod)
decode_packet = mod.decode_packet

msg_rx_by_runtime = {}
msg_tx_by_runtime = {}
chip0_rx_by_edge = {'north': 0, 'east': 0, 'south': 0, 'west': 0}
chip0_rx_words_by_edge = {'north': [], 'east': [], 'south': [], 'west': []}

for line in trace_jsonl.read_text().splitlines():
    if not line.strip():
        continue
    event = json.loads(line)
    runtime_id = int(event.get('runtime_id', 0))
    name = str(event.get('event', ''))
    word_raw = event.get('packet_word', 0)
    word = int(word_raw, 0) if isinstance(word_raw, str) else int(word_raw)
    decoded = decode_packet(word)
    if decoded.kind != 'msg':
        continue
    if name == 'rx_packet':
        msg_rx_by_runtime[runtime_id] = msg_rx_by_runtime.get(runtime_id, 0) + 1
        if runtime_id == 0:
            edge = str(event.get('edge', ''))
            if edge in chip0_rx_by_edge:
                chip0_rx_by_edge[edge] += 1
                chip0_rx_words_by_edge[edge].append(word)
    elif name == 'tx_packet':
        msg_tx_by_runtime[runtime_id] = msg_tx_by_runtime.get(runtime_id, 0) + 1

fpga_msg_packets = []
fpga_msg_by_origin = {}
for match in re.finditer(r'fpga_larpix\[\d+\] received packet at seq=(\d+):\s*(0x[0-9a-fA-F]+)', log_file.read_text()):
    word = int(match.group(2), 16)
    decoded = decode_packet(word)
    if decoded.kind == 'msg':
        msg_payload = int(decoded.decoded['msg_payload'])
        origin_chip_id = (msg_payload >> 4) & 0xFF
        fpga_msg_packets.append({
            'seq': int(match.group(1)),
            'word': word,
            'chip_id': int(decoded.decoded['chip_id']),
            'payload': msg_payload,
            'origin_chip_id': origin_chip_id,
        })
        fpga_msg_by_origin[origin_chip_id] = fpga_msg_by_origin.get(origin_chip_id, 0) + 1

summary = {
    'scenario': '2x2 msg_rtl probe',
    'ticks': json.loads(run_metrics_json.read_text())['ticks'],
    'msg_rx_by_runtime': {str(k): v for k, v in sorted(msg_rx_by_runtime.items())},
    'msg_tx_by_runtime': {str(k): v for k, v in sorted(msg_tx_by_runtime.items())},
    'chip0_msg_rx_by_edge': chip0_rx_by_edge,
    'chip0_total_msg_rx': sum(chip0_rx_by_edge.values()),
    'fpga_msg_packet_count': len(fpga_msg_packets),
    'fpga_msg_by_origin_chip_id': {str(k): v for k, v in sorted(fpga_msg_by_origin.items())},
    'fpga_msg_samples': fpga_msg_packets[:16],
}
summary_json.write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))

if not msg_tx_by_runtime:
    raise SystemExit('FAIL: no MSG_OP transmit events observed in trace')
if sum(chip0_rx_by_edge.values()) == 0:
    raise SystemExit('FAIL: chip 0 observed no incoming MSG_OP packets')
if len(fpga_msg_packets) == 0:
    raise SystemExit('FAIL: FPGA observed no MSG_OP packets')
PYSUM

echo
printf 'Artifacts:\n'
printf '  run log:      %s\n' "$log_file"
printf '  trace jsonl:  %s\n' "$trace_jsonl"
printf '  rx debug csv: %s\n' "$rx_debug_csv"
printf '  summary json: %s\n' "$summary_json"
