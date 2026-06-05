#!/usr/bin/env bash
set -euo pipefail

# 6x6 live-network msg_rtl probe with msg generation pre-enabled on all chips,
# an initial full-chip injection on four runtimes, and a second network-wide wave.
#
# This probe:
# - preloads final CHIP_ID and lane-enable register state on all chips
# - preloads analog-trigger/channel enable state on all chips
# - preloads DMONITOR0[5]=1 on all chips so msg generation is enabled before tick 0
# - uses no runtime startup writes
# - injects charge into all 64 channels of runtimes 7, 14, 21, and 28 at tick 100
# - injects charge into channels 0..4 of all 36 runtimes at tick 540
# - generates playback for visual inspection

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo_root/build"
ticks="${TICKS:-2400}"
chip_target="${CHIP_TARGET:-chip_larpix_msg_rtl_build}"
chip_bin_name="${CHIP_BIN_NAME:-chip_larpix_msg_rtl}"
rtl_version_label="${RTL_VERSION_LABEL:-msg_rtl}"
build_binaries="${BUILD_BINARIES:-1}"
chip_variant="${CHIP_VARIANT_LABEL:-msg}"
scenario_name="larpix_6x6_msg_rerouting_second_wave_probe"
work_dir="$build_dir/${scenario_name}__${chip_variant}"
init_json="$work_dir/init_6x6_msg_rerouting_second_wave_probe_preconfigured.json"
stimulus_json="$work_dir/stimulus_6x6_msg_rerouting_second_wave_probe.json"
log_file="$work_dir/run.log"
trace_jsonl="$work_dir/trace.jsonl"
rx_debug_csv="$work_dir/chip0_rx_debug.csv"
summary_json="$work_dir/msg_rerouting_second_wave_probe_summary.json"
run_metrics_json="$work_dir/run_metrics.json"
playback_json="$work_dir/live_event_6x6_msg_rerouting_second_wave_probe.json"
mkdir -p "$work_dir"

target_args=()
for y in $(seq 0 5); do
  for x in $(seq 0 5); do
    target_args+=(--target "$x,$y")
  done
done

python3 "$repo_root/sim_core/tools/generate_bootstrap_preconfigured_event_init_json.py" \
  --rows 6 \
  --cols 6 \
  --s 0 \
  "${target_args[@]}" \
  --out "$init_json"

python3 - "$init_json" <<'PYINIT'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
obj = json.loads(path.read_text())
writes = list(obj.get("register_writes", []))

for runtime_id in range(36):
    writes.append({
        "runtime_id": runtime_id,
        "register_addr": 114,
        "register_data": 0x20,
        "label": f"pre-enable msg generation on runtime {runtime_id} via DMONITOR0[5]",
    })

obj["register_writes"] = writes
path.write_text(json.dumps(obj, indent=2) + "\n")
PYINIT

python3 - "$stimulus_json" <<'PYSTIM'
import json
import pathlib
import sys

charges = []

for runtime_id in (7, 14, 21, 28):
    for channel_id in range(64):
        charges.append({
            "tick": 100,
            "runtime_id": runtime_id,
            "channel": channel_id,
            "charge": -5e-15,
        })

for runtime_id in range(36):
    for channel_id in range(5):
        charges.append({
            "tick": 540,
            "runtime_id": runtime_id,
            "channel": channel_id,
            "charge": -5e-15,
        })

pathlib.Path(sys.argv[1]).write_text(
    "// 6x6 msg_rtl chip re-routing second-wave probe stimulus\n"
    + json.dumps({"charges": charges}, indent=2)
    + "\n"
)
PYSTIM

if [[ "$build_binaries" != "0" && "$build_binaries" != "1" ]]; then
  echo "BUILD_BINARIES must be 0 or 1" >&2
  exit 2
fi

if [[ "$build_binaries" == "1" ]]; then
  cmake -S "$repo_root" -B "$build_dir"
  cmake --build "$build_dir" --target fpga_larpix trace_collector_larpix orchestrator_larpix "$chip_target" -j1
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
    '-rows', '6',
    '-cols', '6',
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
  --rows 6 \
  --cols 6 \
  --source-x 0 \
  --source-y 0 \
  --init-regs-json "$init_json" \
  --run-log "$log_file" \
  --trace-jsonl "$trace_jsonl" \
  --out "$playback_json" \
  --rtl-version "$rtl_version_label" \
  --name "Chip Re-Routing Second Wave"

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

python3 - "$trace_jsonl" "$summary_json" "$run_metrics_json" <<'PYSUM'
import json
import pathlib
import sys

trace_jsonl = pathlib.Path(sys.argv[1])
summary_json = pathlib.Path(sys.argv[2])
run_metrics_json = pathlib.Path(sys.argv[3])

MSG_OP = 0b00
DATA_OP = 0b01
CONFIG_WRITE_OP = 0b10
CONFIG_READ_OP = 0b11

tx_by_runtime = {}
rx_by_runtime = {}
msg_tx_by_chip = {str(k): 0 for k in range(36)}
msg_rx_by_chip = {str(k): 0 for k in range(36)}
data_tx_by_chip = {str(k): 0 for k in range(36)}
data_rx_by_chip = {str(k): 0 for k in range(36)}

for line in trace_jsonl.read_text().splitlines():
    if not line.strip():
        continue
    event = json.loads(line)
    runtime_id = int(event.get("runtime_id", -1))
    event_name = str(event.get("event", ""))
    word_raw = event.get("packet_word")
    word = int(word_raw, 0) if isinstance(word_raw, str) else int(word_raw or 0)
    packet_type = word & 0x3

    if event_name == "tx_packet":
        entry = tx_by_runtime.setdefault(str(runtime_id), {"msg": 0, "data": 0, "config_write": 0, "config_read": 0})
        if packet_type == MSG_OP:
            entry["msg"] += 1
            msg_tx_by_chip[str(runtime_id)] += 1
        elif packet_type == DATA_OP:
            entry["data"] += 1
            data_tx_by_chip[str(runtime_id)] += 1
        elif packet_type == CONFIG_WRITE_OP:
            entry["config_write"] += 1
        elif packet_type == CONFIG_READ_OP:
            entry["config_read"] += 1

    elif event_name == "rx_packet":
        entry = rx_by_runtime.setdefault(str(runtime_id), {"msg": 0, "data": 0, "config_write": 0, "config_read": 0})
        if packet_type == MSG_OP:
            entry["msg"] += 1
            msg_rx_by_chip[str(runtime_id)] += 1
        elif packet_type == DATA_OP:
            entry["data"] += 1
            data_rx_by_chip[str(runtime_id)] += 1
        elif packet_type == CONFIG_WRITE_OP:
            entry["config_write"] += 1
        elif packet_type == CONFIG_READ_OP:
            entry["config_read"] += 1

summary = {
    "run_metrics": json.loads(run_metrics_json.read_text()),
    "tx_by_runtime": tx_by_runtime,
    "rx_by_runtime": rx_by_runtime,
    "msg_tx_by_chip": msg_tx_by_chip,
    "msg_rx_by_chip": msg_rx_by_chip,
    "data_tx_by_chip": data_tx_by_chip,
    "data_rx_by_chip": data_rx_by_chip,
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")
PYSUM

echo "Wrote playback to: $playback_json"
echo "Wrote summary to:  $summary_json"
