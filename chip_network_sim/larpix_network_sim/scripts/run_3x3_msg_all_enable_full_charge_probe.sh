#!/usr/bin/env bash
set -euo pipefail

# 3x3 live-network msg_rtl probe with network-wide runtime MSG_OP enable writes
# and full center-chip analog charge injection.
#
# Layout (runtime ids / chip ids for the default bootstrap-preconfigured map):
#   y=2: 6 7 8
#   y=1: 3 4 5
#   y=0: 0 1 2
#
# This probe:
# - preloads final CHIP_ID and lane-enable register state on all chips
# - preloads analog-trigger/channel enable state on all chips
# - injects startup CONFIG_WRITE packets to all 9 chip ids setting DMONITOR0[5]=1
# - injects analog charge into channels 0..63 of runtime/chip 4
# - summarizes how msg and data traffic propagate after the center-chip event

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo_root/build"
work_dir="$build_dir/larpix_3x3_msg_all_enable_full_charge_probe"
init_json="$work_dir/init_3x3_msg_all_enable_full_charge_probe_preconfigured.json"
startup_in_json="$work_dir/startup_3x3_msg_all_enable_full_charge_probe.json"
startup_compiled_json="$work_dir/startup_3x3_msg_all_enable_full_charge_probe_compiled.json"
stimulus_json="$work_dir/stimulus_3x3_msg_all_enable_full_charge_probe.json"
log_file="$work_dir/run.log"
trace_jsonl="$work_dir/trace.jsonl"
rx_debug_csv="$work_dir/runtime4_rx_debug.csv"
summary_json="$work_dir/msg_all_enable_full_charge_probe_summary.json"
run_metrics_json="$work_dir/run_metrics.json"
playback_json="$work_dir/live_event_3x3_msg_all_enable_full_charge_probe.json"
ticks="${TICKS:-4500}"
chip_target="${CHIP_TARGET:-chip_larpix_msg_rtl_build}"
chip_bin_name="${CHIP_BIN_NAME:-chip_larpix_msg_rtl}"
rtl_version_label="${RTL_VERSION_LABEL:-msg_rtl}"
mkdir -p "$work_dir"

python3 "$repo_root/larpix_network_sim/scripts/generate_bootstrap_preconfigured_event_init_json.py" \
  --rows 3 \
  --cols 3 \
  --s 0 \
  --target 0,0 \
  --target 1,0 \
  --target 2,0 \
  --target 0,1 \
  --target 1,1 \
  --target 2,1 \
  --target 0,2 \
  --target 1,2 \
  --target 2,2 \
  --out "$init_json"

python3 - "$startup_in_json" <<'PYSTART'
import json
import pathlib
import sys

frames = []
for chip_id in range(9):
    frames.append({
        "tick_start": 20 + (chip_id * 90),
        "type": "write",
        "chip_id": chip_id,
        "register_addr": 114,
        "register_data": 0x20,
        "label": f"enable msg generation on chip {chip_id} via DMONITOR0[5]",
    })

pathlib.Path(sys.argv[1]).write_text(
    json.dumps({"frames": frames}, indent=2) + "\n"
)
PYSTART

python3 "$repo_root/larpix_network_sim/scripts/compile_startup_json.py" \
  "$startup_in_json" \
  "$startup_compiled_json"

python3 - "$stimulus_json" <<'PYSTIM'
import json
import pathlib
import sys

injection_tick = 1500
charges = []
for channel in range(64):
    charges.append({
        "runtime_id": 4,
        "tick": injection_tick,
        "channel": channel,
        "charge": -5.0e-15,
    })

pathlib.Path(sys.argv[1]).write_text(
    "// 3x3 msg_rtl all-enable full-charge probe stimulus\n"
    + json.dumps({"charges": charges}, indent=2)
    + "\n"
)
PYSTIM

cmake -S "$repo_root" -B "$build_dir"
cmake --build "$build_dir" --target fpga_larpix trace_collector_larpix orchestrator_larpix "$chip_target" -j1

run_ok=0
for attempt in 1 2 3 4 5; do
  base_uri="$(python3 - <<'PYU'
import random
print(f"tcp://127.0.0.1:{random.randint(20000, 45000)}")
PYU
)"
  if python3 - "$build_dir" "$init_json" "$startup_compiled_json" "$stimulus_json" "$trace_jsonl" "$log_file" "$run_metrics_json" "$rx_debug_csv" "$base_uri" "$ticks" <<'PYRUN'
import json
import os
import pathlib
import subprocess
import sys
import time

build_dir = pathlib.Path(sys.argv[1])
init_json = pathlib.Path(sys.argv[2])
startup_json = pathlib.Path(sys.argv[3])
stimulus_json = pathlib.Path(sys.argv[4])
trace_jsonl = pathlib.Path(sys.argv[5])
log_file = pathlib.Path(sys.argv[6])
run_metrics_json = pathlib.Path(sys.argv[7])
rx_debug_csv = pathlib.Path(sys.argv[8])
base_uri = sys.argv[9]
ticks = int(sys.argv[10])

cmd = [
    str(build_dir / 'orchestrator_larpix'),
    '-rows', '3',
    '-cols', '3',
    '-ticks', str(ticks),
    '-startup_ms', '3000',
    '-ack_timeout_ms', '5000',
    '-source_x', '0',
    '-source_y', '0',
    '-base_uri', base_uri,
    '-chip_bin', str(build_dir / os.environ.get('CHIP_BIN_NAME', 'chip_larpix_msg_rtl')),
    '-fpga_bin', str(build_dir / 'fpga_larpix'),
    '-startup_json', str(startup_json),
    '-init_regs_json', str(init_json),
    '-stimulus_json', str(stimulus_json),
    '-trace_out', str(trace_jsonl),
    '-rx_debug_csv', str(rx_debug_csv),
    '-rx_debug_runtime_id', '4',
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

python3 "$repo_root/larpix_network_sim/visualizers/packet_transmission/convert_live_trace_to_playback.py" \
  --rows 3 \
  --cols 3 \
  --source-x 0 \
  --source-y 0 \
  --startup-json "$startup_compiled_json" \
  --init-regs-json "$init_json" \
  --run-log "$log_file" \
  --trace-jsonl "$trace_jsonl" \
  --out "$playback_json" \
  --rtl-version "$rtl_version_label" \
  --name "3x3 msg all-enable full-charge probe"

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

python3 - "$trace_jsonl" "$log_file" "$summary_json" "$run_metrics_json" <<'PYSUM'
import json
import pathlib
import re
import sys

trace_jsonl = pathlib.Path(sys.argv[1])
log_file = pathlib.Path(sys.argv[2])
summary_json = pathlib.Path(sys.argv[3])
run_metrics_json = pathlib.Path(sys.argv[4])

MSG_OP = 0b00
DATA_OP = 0b01
CONFIG_WRITE_OP = 0b10
CONFIG_READ_OP = 0b11

center_runtime = 4
neighbor_ids = {1, 3, 5, 7}
all_chip_ids = set(range(9))

tx_by_runtime = {}
rx_by_runtime = {}
chip4_msg_tx_edges = {"north": 0, "east": 0, "south": 0, "west": 0}
chip4_msg_tx_words = []
neighbor_msg_rx = {str(k): 0 for k in sorted(neighbor_ids)}
chip4_data_tx_channels = set()
chip4_charge_events = 0
config_write_seen_by_chip = {str(k): 0 for k in sorted(all_chip_ids)}
msg_tx_by_chip = {str(k): 0 for k in sorted(all_chip_ids)}
msg_rx_by_chip = {str(k): 0 for k in sorted(all_chip_ids)}

for line in trace_jsonl.read_text().splitlines():
    if not line.strip():
        continue
    event = json.loads(line)
    runtime_id = int(event.get("runtime_id", 0))
    event_name = str(event.get("event", ""))
    word_raw = event.get("packet_word")
    word = int(word_raw, 0) if isinstance(word_raw, str) else int(word_raw or 0)
    packet_type = word & 0x3

    if event_name == "charge_injected" and runtime_id == center_runtime:
        chip4_charge_events += 1
        continue

    if event_name == "tx_packet":
        entry = tx_by_runtime.setdefault(str(runtime_id), {"msg": 0, "data": 0, "config_write": 0, "config_read": 0})
        if packet_type == MSG_OP:
            entry["msg"] += 1
            msg_tx_by_chip[str(runtime_id)] = msg_tx_by_chip.get(str(runtime_id), 0) + 1
            if runtime_id == center_runtime:
                edge = str(event.get("edge", ""))
                if edge in chip4_msg_tx_edges:
                    chip4_msg_tx_edges[edge] += 1
                chip4_msg_tx_words.append(f"0x{word:016x}")
        elif packet_type == DATA_OP:
            entry["data"] += 1
            if runtime_id == center_runtime:
                chip4_data_tx_channels.add((word >> 10) & 0x3F)
        elif packet_type == CONFIG_WRITE_OP:
            entry["config_write"] += 1
        elif packet_type == CONFIG_READ_OP:
            entry["config_read"] += 1

    elif event_name == "rx_packet":
        entry = rx_by_runtime.setdefault(str(runtime_id), {"msg": 0, "data": 0, "config_write": 0, "config_read": 0})
        if packet_type == MSG_OP:
            entry["msg"] += 1
            msg_rx_by_chip[str(runtime_id)] = msg_rx_by_chip.get(str(runtime_id), 0) + 1
            if runtime_id in neighbor_ids:
                neighbor_msg_rx[str(runtime_id)] += 1
        elif packet_type == DATA_OP:
            entry["data"] += 1
        elif packet_type == CONFIG_WRITE_OP:
            entry["config_write"] += 1
            reg_addr = (word >> 10) & 0xFF
            reg_data = (word >> 18) & 0xFF
            if reg_addr == 114 and reg_data == 0x20:
                config_write_seen_by_chip[str(runtime_id)] += 1
        elif packet_type == CONFIG_READ_OP:
            entry["config_read"] += 1

fpga_packets = {"msg": 0, "data": 0, "config_write": 0, "config_read": 0}
for match in re.finditer(r'fpga_larpix\[\d+\] received packet at seq=(\d+):\s*(0x[0-9a-fA-F]+)', log_file.read_text()):
    word = int(match.group(2), 16)
    packet_type = word & 0x3
    if packet_type == MSG_OP:
        fpga_packets["msg"] += 1
    elif packet_type == DATA_OP:
        fpga_packets["data"] += 1
    elif packet_type == CONFIG_WRITE_OP:
        fpga_packets["config_write"] += 1
    elif packet_type == CONFIG_READ_OP:
        fpga_packets["config_read"] += 1

summary = {
    "scenario": "3x3 msg all-enable full-charge probe",
    "center_runtime_id": center_runtime,
    "center_chip_id": 4,
    "msg_enable_register_addr": 114,
    "msg_enable_register_data": 32,
    "msg_enable_target_chip_ids": sorted(all_chip_ids),
    "charge_events_on_center_chip": chip4_charge_events,
    "config_write_seen_by_chip": config_write_seen_by_chip,
    "chip4_msg_tx_total": sum(chip4_msg_tx_edges.values()),
    "chip4_msg_tx_by_edge": chip4_msg_tx_edges,
    "chip4_msg_tx_words_first16": chip4_msg_tx_words[:16],
    "neighbor_msg_rx_counts": neighbor_msg_rx,
    "chip4_data_tx_channel_count": len(chip4_data_tx_channels),
    "chip4_data_tx_channels_sorted": sorted(chip4_data_tx_channels),
    "msg_tx_by_chip": msg_tx_by_chip,
    "msg_rx_by_chip": msg_rx_by_chip,
    "tx_by_runtime": tx_by_runtime,
    "rx_by_runtime": rx_by_runtime,
    "fpga_received": fpga_packets,
    "run_metrics": json.loads(run_metrics_json.read_text()),
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
PYSUM

echo "Artifacts:"
echo "  init:     $init_json"
echo "  startup:  $startup_compiled_json"
echo "  stimulus: $stimulus_json"
echo "  log:      $log_file"
echo "  trace:    $trace_jsonl"
echo "  playback: $playback_json"
echo "  summary:  $summary_json"
