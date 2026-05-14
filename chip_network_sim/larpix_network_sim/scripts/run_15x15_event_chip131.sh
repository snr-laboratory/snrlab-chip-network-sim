#!/usr/bin/env bash
set -euo pipefail

# 15x15 live-network analog/cosim event test for final chip_id=131 using
# RTL-preconfigured chip state rather than runtime startup packets.
#
# Test intent:
# - instantiate a 15-row by 15-column LArPix network with source chip (0,0)
# - preload the true RTL register file of each chip with the final CHIP_ID and
#   TX-lane state implied by the existing bootstrap assignment protocol
# - enable all 64 channels on final chip_id 131, which lands at coordinate
#   (11,8) and runtime_id 131 for rows=15 cols=15 s=0
# - inject one charge pulse into all 64 channels of runtime 131
# - capture shared/channel FIFO occupancy for runtime 131 from the injection tick
# - generate a visualizer playback JSON for the preconfigured 15x15 scenario
# - verify that the FPGA receives downstream data packets from chip 131

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo_root/build"
work_dir="$build_dir/larpix_15x15_event_chip131"
init_json="$work_dir/init_15x15_event_chip131_preconfigured.json"
stimulus_json="$work_dir/stimulus_15x15_event_chip131.json"
occupancy_csv="$work_dir/chip131_occupancy.csv"
occupancy_png="$work_dir/chip131_occupancy.png"
occupancy_zoom_png="$work_dir/chip131_occupancy_zoom.png"
channel_generation_csv="$work_dir/chip131_occupancy_channel_generation.csv"
channel_fifo_detail_csv="$work_dir/chip131_occupancy_channel_fifo_detail.csv"
log_file="$work_dir/run.log"
trace_jsonl="$work_dir/trace.jsonl"
playback_json="$work_dir/live_event_15x15_chip131.json"
run_metrics_json="$work_dir/run_metrics.json"
mkdir -p "$work_dir"

python3 "$repo_root/larpix_network_sim/scripts/generate_bootstrap_preconfigured_event_init_json.py" \
  --rows 15 \
  --cols 15 \
  --s 0 \
  --target-x 11 \
  --target-y 8 \
  --out "$init_json"

cmake -S "$repo_root" -B "$build_dir"
cmake --build "$build_dir" --target fpga_larpix trace_collector_larpix orchestrator_larpix chip_larpix_build -j

read -r injection_tick ticks <<<"$(python3 - "$stimulus_json" <<'PYT'
import json
import pathlib
import sys

injection_tick = 1000
charges = [
    {
        'runtime_id': 131,
        'tick': injection_tick,
        'channel': channel,
        'charge': -5.0e-15,
    }
    for channel in range(64)
]
pathlib.Path(sys.argv[1]).write_text(
    '// 15x15 analog/cosim preconfigured event test stimulus for final chip_id 131.\n'
    + json.dumps({'charges': charges}, indent=2)
    + '\n'
)
print(injection_tick, injection_tick + 7000)
PYT
)"

run_ok=0
for attempt in 1 2 3 4 5; do
  base_uri="$(python3 - <<'PYU'
import random
print(f"tcp://127.0.0.1:{random.randint(20000, 45000)}")
PYU
)"
  if python3 - "$build_dir" "$init_json" "$stimulus_json" "$trace_jsonl" "$occupancy_csv" "$log_file" "$run_metrics_json" "$base_uri" "$ticks" "$injection_tick" <<'PYRUN'
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
occupancy_csv = pathlib.Path(sys.argv[5])
log_file = pathlib.Path(sys.argv[6])
run_metrics_json = pathlib.Path(sys.argv[7])
base_uri = sys.argv[8]
ticks = int(sys.argv[9])
injection_tick = int(sys.argv[10])

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
    '-chip_bin', str(build_dir / 'chip_larpix'),
    '-fpga_bin', str(build_dir / 'fpga_larpix'),
    '-init_regs_json', str(init_json),
    '-stimulus_json', str(stimulus_json),
    '-trace_out', str(trace_jsonl),
    '-occupancy_csv', str(occupancy_csv),
    '-occupancy_runtime_id', '131',
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
  --rows 15 \
  --cols 15 \
  --source-x 0 \
  --source-y 0 \
  --init-regs-json "$init_json" \
  --run-log "$log_file" \
  --trace-jsonl "$trace_jsonl" \
  --out "$playback_json" \
  --rtl-version "v3b" \
  --name "15x15 RTL-Preconfigured Event Chip 131 Injection"

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
    ax.plot(ticks, [row[name] for row in rows], label=name, color=colors[name], linewidth=2.0)
ax.set_title(f'Chip 131 FIFO Occupancy From Injection Tick {injection_tick}', fontfamily='monospace')
style_axes(ax)
ax.legend(prop={'family': 'monospace', 'size': 9})
fig.tight_layout()
fig.savefig(png_path)
plt.close(fig)

first_nonzero = next((row['tick'] for row in rows if row['chip_fifo'] > 0), None)
peak_tick = max((row['tick'] for row in rows if row['chip_fifo'] == max(row['chip_fifo'] for row in rows)), default=injection_tick)
zoom_start = first_nonzero if first_nonzero is not None else injection_tick
zoom_rows = [row for row in rows if zoom_start <= row['tick'] <= peak_tick]
if not zoom_rows:
    raise SystemExit('FAIL: no occupancy rows found inside chip FIFO zoom window')
with detail_csv_path.open() as f:
    detail_rows = list(csv.DictReader(f))
detail_rows = [row for row in detail_rows if zoom_start <= int(row['tick']) <= peak_tick]
if not detail_rows:
    raise SystemExit('FAIL: no detailed channel FIFO rows found inside chip FIFO zoom window')
zoom_ticks = [row['tick'] for row in zoom_rows]
fig, ax = plt.subplots(figsize=(11, 7), dpi=150)
fig.patch.set_facecolor('#f6f3eb')
for channel in range(64):
    name = f'ch{channel}_fifo'
    ax.plot([int(row['tick']) for row in detail_rows], [int(row[name]) for row in detail_rows], color='#b9c3d0', linewidth=0.9, alpha=0.55)
for name in series_names:
    ax.plot(zoom_ticks, [row[name] for row in zoom_rows], label=name, color=colors[name], linewidth=2.0)
ax.set_title(f'Chip 131 FIFO Zoom ({zoom_start} to {peak_tick})', fontfamily='monospace')
style_axes(ax)
ax.set_xlim(zoom_start, peak_tick)
ax.legend(prop={'family': 'monospace', 'size': 9})
fig.tight_layout()
fig.savefig(zoom_png_path)
PLOT

python3 - "$init_json" "$log_file" "$occupancy_csv" "$occupancy_png" "$occupancy_zoom_png" "$channel_generation_csv" "$channel_fifo_detail_csv" "$trace_jsonl" "$playback_json" "$repo_root/larpix_network_sim/scripts/larpix_uart.py" <<'PY2'
import csv
import importlib.util
import json
import pathlib
import re
import sys

init_json = pathlib.Path(sys.argv[1])
log_path = pathlib.Path(sys.argv[2])
occupancy_csv = pathlib.Path(sys.argv[3])
occupancy_png = pathlib.Path(sys.argv[4])
occupancy_zoom_png = pathlib.Path(sys.argv[5])
channel_generation_csv = pathlib.Path(sys.argv[6])
channel_fifo_detail_csv = pathlib.Path(sys.argv[7])
trace_jsonl = pathlib.Path(sys.argv[8])
playback_json = pathlib.Path(sys.argv[9])
helper_path = pathlib.Path(sys.argv[10])
init_raw = json.loads(init_json.read_text())
text = log_path.read_text()
if not occupancy_csv.exists() or occupancy_csv.stat().st_size == 0:
    raise SystemExit('FAIL: occupancy CSV was not produced')
with occupancy_csv.open() as f:
    occupancy_rows = list(csv.DictReader(f))
if not occupancy_rows:
    raise SystemExit('FAIL: occupancy CSV has no data rows')
if not occupancy_png.exists() or occupancy_png.stat().st_size == 0:
    raise SystemExit('FAIL: occupancy PNG plot was not produced')
if not occupancy_zoom_png.exists() or occupancy_zoom_png.stat().st_size == 0:
    raise SystemExit('FAIL: occupancy zoom PNG plot was not produced')
if not channel_generation_csv.exists() or channel_generation_csv.stat().st_size == 0:
    raise SystemExit('FAIL: channel generation summary CSV was not produced')
if not channel_fifo_detail_csv.exists() or channel_fifo_detail_csv.stat().st_size == 0:
    raise SystemExit('FAIL: detailed channel FIFO CSV was not produced')
if not trace_jsonl.exists() or trace_jsonl.stat().st_size == 0:
    raise SystemExit('FAIL: trace JSONL was not produced')
if not playback_json.exists() or playback_json.stat().st_size == 0:
    raise SystemExit('FAIL: playback JSON was not produced')
with channel_generation_csv.open() as f:
    generation_rows = list(csv.DictReader(f))
if len(generation_rows) != 64:
    raise SystemExit(f'FAIL: expected 64 channel generation rows, observed {len(generation_rows)}')

spec = importlib.util.spec_from_file_location('larpix_uart', helper_path)
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)

raw_packets = re.findall(r'received packet at seq=\d+: (0x[0-9a-fA-F]+)', text)
if not raw_packets:
    print(text)
    raise SystemExit('FAIL: fpga_larpix did not receive any reply packets')

data_packets = []
for raw in raw_packets:
    word = int(raw, 0)
    fields = mod.decode_packet(word)
    if fields.kind == 'data':
        data_packets.append((word, fields))
if not data_packets:
    print(text)
    raise SystemExit('FAIL: fpga_larpix received packets, but none decoded as data packets')

matching = []
channels = set()
for word, fields in data_packets:
    decoded = fields.decoded
    if fields.odd_parity_ok and decoded['chip_id'] == 131 and decoded['downstream'] == 1 and decoded['trigger_type'] == 0:
        matching.append((word, fields))
        channels.add(decoded['channel_id'])
if not matching:
    raise SystemExit('FAIL: no received data packet matched chip_id=131 with downstream=1 and trigger_type=0')

playback = json.loads(playback_json.read_text())
initial_chips = {(entry['x'], entry['y']): entry for entry in playback.get('initial_chips', [])}
chip131 = initial_chips.get((11, 8))
if chip131 is None or chip131.get('chip_id') != 131:
    raise SystemExit('FAIL: playback initial state does not show chip_id 131 at (11,8)')
peak_chip_fifo = max(int(row['chip_fifo']) for row in occupancy_rows)
peak_ch0 = max(int(row['ch0_fifo']) for row in occupancy_rows)
peak_ch4 = max(int(row['ch4_fifo']) for row in occupancy_rows)
locally_generated_channels = [int(row['channel']) for row in generation_rows if int(row['generated_any']) != 0]
missing_local_channels = [int(row['channel']) for row in generation_rows if int(row['generated_any']) == 0]
print('PASS: 15x15 LArPix analog/cosim chip-131 all-channel event test (rtl_preconfigured)')
print(f'preloaded_register_writes={len(init_raw.get("register_writes", []))}')
print(f'occupancy_samples={len(occupancy_rows)}')
print(f'peak_chip_fifo={peak_chip_fifo}')
print(f'peak_ch0_fifo={peak_ch0}')
print(f'peak_ch4_fifo={peak_ch4}')
print(f'distinct_event_channels={len(channels)}')
print('observed_event_channels=' + ','.join(str(v) for v in sorted(channels)))
print(f'locally_generated_channels={len(locally_generated_channels)}')
print('observed_local_generation_channels=' + ','.join(str(v) for v in locally_generated_channels))
print('missing_local_generation_channels=' + ','.join(str(v) for v in missing_local_channels))
first_word, first_fields = matching[0]
print(f'first_matching_reply_packet=0x{first_word:016x}')
print('first_matching_chip_id={chip_id} channel_id={channel_id} adc={adc} downstream={downstream} trigger_type={trigger_type}'.format(**first_fields.decoded))
print(f'occupancy_csv={occupancy_csv}')
print(f'occupancy_png={occupancy_png}')
print(f'occupancy_zoom_png={occupancy_zoom_png}')
print(f'channel_generation_csv={channel_generation_csv}')
print(f'channel_fifo_detail_csv={channel_fifo_detail_csv}')
print(f'trace_jsonl={trace_jsonl}')
print(f'playback_json={playback_json}')
print('visualizer_url_hint=http://localhost:8000/larpix_network_sim/visualizers/packet_transmission/?playback=/build/larpix_15x15_event_chip131/live_event_15x15_chip131.json')
PY2
