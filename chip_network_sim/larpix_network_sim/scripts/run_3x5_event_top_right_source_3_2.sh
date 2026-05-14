#!/usr/bin/env bash
set -euo pipefail

# 3x5 live-network analog/cosim event FIFO-occupancy test with source at (3,2).
#
# Test intent:
# - instantiate a 3-row by 5-column LArPix network with source chip (3,2)
# - run the generalized bootstrap CHIP_ID assignment flow without per-assignment readbacks
# - configure the remote top-right chip at (4,2), final chip_id=14, so all 64
#   channels can emit natural event packets
# - inject one charge pulse into all 64 channels of chip 14 through the
#   analog/cosim stimulus path
# - capture chip-14 FIFO occupancy from the live runtime starting at the
#   injection tick and generate an occupancy-vs-tick PNG plot
# - verify that the FPGA receives downstream data packets from chip 14

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo_root/build"
work_dir="$build_dir/larpix_3x5_event_top_right_source_3_2"
startup_in="$repo_root/larpix_network_sim/config/startup_3x5_event_top_right_source_3_2.json"
base_stimulus_json="$repo_root/larpix_network_sim/config/stimulus_3x5_event_top_right.json"
stimulus_json="$work_dir/stimulus_3x5_event_top_right_source_3_2.json"
startup_compiled="$work_dir/startup_3x5_event_top_right_source_3_2.compiled.json"
occupancy_csv="$work_dir/chip14_occupancy.csv"
occupancy_png="$work_dir/chip14_occupancy.png"
occupancy_zoom_png="$work_dir/chip14_occupancy_zoom.png"
channel_generation_csv="$work_dir/chip14_occupancy_channel_generation.csv"
channel_fifo_detail_csv="$work_dir/chip14_occupancy_channel_fifo_detail.csv"
log_file="$work_dir/run.log"
trace_jsonl="$work_dir/trace.jsonl"
playback_json="$work_dir/live_event_3x5_chip14_source_3_2.json"
run_metrics_json="$work_dir/run_metrics.json"
mkdir -p "$work_dir"

python3 "$repo_root/larpix_network_sim/scripts/generate_bootstrap_event_startup_json.py" \
  --rows 3 \
  --cols 5 \
  --s 3 \
  --source-y 2 \
  --target-x 4 \
  --target-y 2 \
  --out "$startup_in"

cmake -S "$repo_root" -B "$build_dir"
cmake --build "$build_dir" --target fpga_larpix trace_collector_larpix orchestrator_larpix chip_larpix_build -j

python3 "$repo_root/larpix_network_sim/scripts/compile_startup_json.py" \
  "$startup_in" \
  "$startup_compiled"

python3 - "$startup_compiled" "$base_stimulus_json" "$stimulus_json" <<'PYSTIM'
import json
import pathlib
import sys

def load_json_with_comments(path_str: str):
    path = pathlib.Path(path_str)
    lines = []
    for line in path.read_text().splitlines():
        if line.lstrip().startswith('//'):
            continue
        lines.append(line)
    return json.loads("\n".join(lines))

startup = json.loads(pathlib.Path(sys.argv[1]).read_text())
base_stim = load_json_with_comments(sys.argv[2])
out_path = pathlib.Path(sys.argv[3])
frames = startup.get('frames', [])
last_frame_tick = max((int(frame['tick_start']) for frame in frames), default=0)
charges = base_stim.get('charges', [])
base_injection_tick = min((int(ev['tick']) for ev in charges), default=0)
new_injection_tick = last_frame_tick + 1000
shift = new_injection_tick - base_injection_tick
for ev in charges:
    ev['tick'] = int(ev['tick']) + shift
out_path.write_text(json.dumps(base_stim, indent=2) + "\n")
print(new_injection_tick)
PYSTIM

read -r injection_tick ticks <<<"$(python3 - "$startup_compiled" "$stimulus_json" <<'PYT'
import json
import pathlib
import sys

def load_json_with_comments(path_str: str):
    path = pathlib.Path(path_str)
    lines = []
    for line in path.read_text().splitlines():
        if line.lstrip().startswith('//'):
            continue
        lines.append(line)
    return json.loads("\n".join(lines))

startup = json.loads(pathlib.Path(sys.argv[1]).read_text())
stim = load_json_with_comments(sys.argv[2])
frames = startup.get('frames', [])
last_frame_tick = max((int(frame['tick_start']) for frame in frames), default=0)
charges = stim.get('charges', [])
injection_tick = min((int(ev['tick']) for ev in charges), default=0)
last_charge_tick = max((int(ev['tick']) for ev in charges), default=0)
print(injection_tick, max(last_frame_tick + 7000, last_charge_tick + 7000))
PYT
)"

run_ok=0
for attempt in 1 2 3 4 5; do
  if python3 - "$build_dir" "$startup_compiled" "$stimulus_json" "$trace_jsonl" "$occupancy_csv" "$log_file" "$run_metrics_json" "$ticks" "$injection_tick" <<'PYRUN'
import json
import os
import pathlib
import subprocess
import sys
import time

build_dir = pathlib.Path(sys.argv[1])
startup_compiled = pathlib.Path(sys.argv[2])
stimulus_json = pathlib.Path(sys.argv[3])
trace_jsonl = pathlib.Path(sys.argv[4])
occupancy_csv = pathlib.Path(sys.argv[5])
log_file = pathlib.Path(sys.argv[6])
run_metrics_json = pathlib.Path(sys.argv[7])
ticks = int(sys.argv[8])
injection_tick = int(sys.argv[9])

cmd = [
    str(build_dir / 'orchestrator_larpix'),
    '-rows', '3',
    '-cols', '5',
    '-ticks', str(ticks),
    '-source_x', '3',
    '-source_y', '2',
    '-chip_bin', str(build_dir / 'chip_larpix'),
    '-fpga_bin', str(build_dir / 'fpga_larpix'),
    '-startup_json', str(startup_compiled),
    '-stimulus_json', str(stimulus_json),
    '-trace_out', str(trace_jsonl),
    '-occupancy_csv', str(occupancy_csv),
    '-occupancy_runtime_id', '14',
    '-occupancy_tick_start', str(injection_tick),
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
  --rows 3 \
  --cols 5 \
  --source-x 3 \
  --source-y 2 \
  --startup-json "$startup_compiled" \
  --run-log "$log_file" \
  --trace-jsonl "$trace_jsonl" \
  --out "$playback_json" \
  --rtl-version "v3b" \
  --name "3x5 Event Chip 14 Injection (source 3,2)"

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

python3 - "$occupancy_csv" "$channel_fifo_detail_csv" "$occupancy_png" "$occupancy_zoom_png" "$injection_tick" <<'PLOT'
import csv
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

csv_path = Path(sys.argv[1])
detail_csv_path = Path(sys.argv[2])
png_path = Path(sys.argv[3])
zoom_png_path = Path(sys.argv[4])
injection_tick = int(sys.argv[5])
rows = []
with csv_path.open() as f:
    reader = csv.DictReader(f)
    for row in reader:
        tick = int(row['tick'])
        if tick >= injection_tick:
            rows.append({k: int(v) if k != 'tick' else tick for k, v in row.items()})
if not rows:
    raise SystemExit('FAIL: occupancy CSV did not contain any rows at or after the injection tick')
series_names = ['chip_fifo', 'ch0_fifo', 'ch1_fifo', 'ch2_fifo', 'ch3_fifo', 'ch4_fifo']
colors = {
    'chip_fifo': '#d9480f',
    'ch0_fifo': '#1f77b4',
    'ch1_fifo': '#2ca02c',
    'ch2_fifo': '#9467bd',
    'ch3_fifo': '#8c564b',
    'ch4_fifo': '#e377c2',
}

def style_axes(ax):
    ax.set_facecolor('#f6f3eb')
    ax.set_xlabel('tick', fontfamily='monospace')
    ax.set_ylabel('occupancy', fontfamily='monospace')
    ax.grid(True, color='#d8d2c4', linewidth=0.8)

ticks = [row['tick'] for row in rows]
fig, ax = plt.subplots(figsize=(11, 7), dpi=150)
fig.patch.set_facecolor('#f6f3eb')
for name in series_names:
    vals = [row[name] for row in rows]
    ax.plot(ticks, vals, label=name, linewidth=1.6, color=colors[name])
style_axes(ax)
ax.set_title('3x5 chip14 occupancy after all-channel injection (source 3,2)', fontfamily='monospace')
ax.legend(frameon=True, facecolor='white', edgecolor='#b8ae9b')
fig.tight_layout()
fig.savefig(png_path)
plt.close(fig)

zoom_limit = min(injection_tick + 600, ticks[-1])
zoom_rows = [row for row in rows if row['tick'] <= zoom_limit]
fig, ax = plt.subplots(figsize=(11, 7), dpi=150)
fig.patch.set_facecolor('#f6f3eb')
zoom_ticks = [row['tick'] for row in zoom_rows]
for name in series_names:
    vals = [row[name] for row in zoom_rows]
    ax.plot(zoom_ticks, vals, label=name, linewidth=1.8, color=colors[name])
style_axes(ax)
ax.set_title('3x5 chip14 occupancy zoom after injection (source 3,2)', fontfamily='monospace')
ax.legend(frameon=True, facecolor='white', edgecolor='#b8ae9b')
fig.tight_layout()
fig.savefig(zoom_png_path)
plt.close(fig)

channel_cols = ['tick'] + [f'ch{i}_gen' for i in range(5)]
detail_cols = ['tick'] + [f'ch{i}_fifo' for i in range(64)]
if rows:
    with detail_csv_path.open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(detail_cols)
PLOT

python3 - "$log_file" "$occupancy_csv" "$playback_json" <<'PYCHECK'
import csv
import json
import pathlib
import re
import sys

THIS_DIR = pathlib.Path('larpix_network_sim/scripts').resolve()
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))
from larpix_uart import decode_packet

log_path = pathlib.Path(sys.argv[1])
occupancy_path = pathlib.Path(sys.argv[2])
playback_path = pathlib.Path(sys.argv[3])
log_text = log_path.read_text()
if 'label=disable trigger veto modes on chip 14' not in log_text:
    raise SystemExit('FAIL: startup/config sequence did not reach the final chip-14 configuration frame')
rx_words = re.findall(r'received packet at seq=\d+: (0x[0-9a-fA-F]+)', log_text)
data_packets = [decode_packet(int(word, 16)) for word in rx_words]
chip14_packets = [pkt for pkt in data_packets if pkt.kind == 'data' and int(pkt.decoded.get('chip_id', -1)) == 14]
if not data_packets:
    raise SystemExit('FAIL: FPGA did not receive any packets')
if not chip14_packets:
    raise SystemExit('FAIL: FPGA log did not contain a chip_id=14 data packet')
with occupancy_path.open() as f:
    reader = csv.DictReader(f)
    rows = list(reader)
if not rows:
    raise SystemExit('FAIL: occupancy CSV was empty')
playback = json.loads(playback_path.read_text())
if playback.get('source', {}) != {'x': 3, 'y': 2}:
    raise SystemExit(f"FAIL: playback source mismatch: {playback.get('source')}")
print('PASS: 3x5 LArPix analog/cosim remote all-channel occupancy test with source (3,2)')
print(f'occupancy_samples={len(rows)}')
PYCHECK
