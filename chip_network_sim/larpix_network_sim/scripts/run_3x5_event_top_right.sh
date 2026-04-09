#!/usr/bin/env bash
set -euo pipefail

# 3x5 live-network analog/cosim event FIFO-occupancy test.
#
# Test intent:
# - instantiate a 3-row by 5-column LArPix network with source chip (0,0)
# - run the bootstrap CHIP_ID assignment flow without per-assignment readbacks
# - configure the remote top-right chip at (4,2), final chip_id=14, so all 64
#   channels can emit natural event packets
# - inject one charge pulse into all 64 channels of chip 14 through the
#   analog/cosim stimulus path
# - capture chip-14 FIFO occupancy from the live runtime starting at the
#   injection tick and generate an occupancy-vs-tick PNG plot
# - verify that the FPGA receives downstream data packets from chip 14
#
# Required passing conditions:
# - the startup schedule is fully transmitted into the live network
# - the all-channel charge pulse is applied to runtime_id 14 after configuration
# - occupancy CSV rows are captured starting at the injection tick
# - an occupancy PNG plot is generated from that CSV
# - the FPGA receives at least one valid downstream data packet from chip_id=14

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo_root/build"
work_dir="$build_dir/larpix_3x5_event_top_right"
startup_in="$repo_root/larpix_network_sim/config/startup_3x5_event_top_right.json"
stimulus_json="$repo_root/larpix_network_sim/config/stimulus_3x5_event_top_right.json"
startup_compiled="$work_dir/startup_3x5_event_top_right.compiled.json"
occupancy_csv="$work_dir/chip14_occupancy.csv"
occupancy_png="$work_dir/chip14_occupancy.png"
occupancy_zoom_png="$work_dir/chip14_occupancy_zoom.png"
channel_generation_csv="$work_dir/chip14_occupancy_channel_generation.csv"
channel_fifo_detail_csv="$work_dir/chip14_occupancy_channel_fifo_detail.csv"
log_file="$work_dir/run.log"
mkdir -p "$work_dir"

python3 "$repo_root/larpix_network_sim/scripts/generate_bootstrap_event_startup_json.py" \
  --rows 3 \
  --cols 5 \
  --s 0 \
  --target-x 4 \
  --target-y 2 \
  --out "$startup_in"

cmake -S "$repo_root" -B "$build_dir"
cmake --build "$build_dir" --target fpga_larpix orchestrator_larpix chip_larpix_build -j

python3 "$repo_root/larpix_network_sim/scripts/compile_startup_json.py" \
  "$startup_in" \
  "$startup_compiled"

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
  if "$build_dir/orchestrator_larpix" \
    -rows 3 \
    -cols 5 \
    -ticks "$ticks" \
    -source_x 0 \
    -source_y 0 \
    -chip_bin "$build_dir/chip_larpix" \
    -fpga_bin "$build_dir/fpga_larpix" \
    -startup_json "$startup_compiled" \
    -stimulus_json "$stimulus_json" \
    -occupancy_csv "$occupancy_csv" \
    -occupancy_runtime_id 14 \
    -occupancy_tick_start "$injection_tick" \
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
ax.set_title(f'Chip 14 FIFO Occupancy From Injection Tick {injection_tick}', fontfamily='monospace')
style_axes(ax)
ax.legend(prop={'family': 'monospace', 'size': 9})
fig.tight_layout()
fig.savefig(png_path)
plt.close(fig)

first_nonzero = next((row['tick'] for row in rows if row['chip_fifo'] > 0), None)
first_peak = next((row['tick'] for row in rows if row['chip_fifo'] >= 63), None)
if first_nonzero is None or first_peak is None:
    raise SystemExit('FAIL: could not determine chip FIFO 0->63 ramp window from occupancy CSV')
zoom_rows = [row for row in rows if first_nonzero <= row['tick'] <= first_peak]
if not zoom_rows:
    raise SystemExit('FAIL: no occupancy rows found inside chip FIFO 0->63 ramp window')
with detail_csv_path.open() as f:
    detail_rows = list(csv.DictReader(f))
detail_rows = [row for row in detail_rows if first_nonzero <= int(row['tick']) <= first_peak]
if not detail_rows:
    raise SystemExit('FAIL: no detailed channel FIFO rows found inside chip FIFO 0->63 ramp window')
zoom_ticks = [row['tick'] for row in zoom_rows]
fig, ax = plt.subplots(figsize=(11, 7), dpi=150)
fig.patch.set_facecolor('#f6f3eb')
for channel in range(64):
    name = f'ch{channel}_fifo'
    ax.plot([int(row['tick']) for row in detail_rows], [int(row[name]) for row in detail_rows], color='#b9c3d0', linewidth=0.9, alpha=0.55)
for name in series_names:
    ax.plot(zoom_ticks, [row[name] for row in zoom_rows], label=name, color=colors[name], linewidth=2.0)
ax.set_title(f'Chip 14 FIFO Ramp Zoom ({first_nonzero} to {first_peak})', fontfamily='monospace')
style_axes(ax)
ax.set_xlim(first_nonzero, first_peak)
ax.legend(prop={'family': 'monospace', 'size': 9})
fig.tight_layout()
fig.savefig(zoom_png_path)
PLOT

python3 - "$startup_compiled" "$log_file" "$occupancy_csv" "$occupancy_png" "$occupancy_zoom_png" "$channel_generation_csv" "$channel_fifo_detail_csv" "$repo_root/larpix_network_sim/scripts/larpix_uart.py" <<'PY2'
import csv
import importlib.util
import json
import pathlib
import re
import sys

compiled = pathlib.Path(sys.argv[1])
log_path = pathlib.Path(sys.argv[2])
occupancy_csv = pathlib.Path(sys.argv[3])
occupancy_png = pathlib.Path(sys.argv[4])
occupancy_zoom_png = pathlib.Path(sys.argv[5])
channel_generation_csv = pathlib.Path(sys.argv[6])
channel_fifo_detail_csv = pathlib.Path(sys.argv[7])
helper_path = pathlib.Path(sys.argv[8])
compiled_raw = json.loads(compiled.read_text())
frames = compiled_raw.get('frames', [])
text = log_path.read_text()
observed_tx = len(re.findall(r'transmitted frame at seq=', text))
expected_tx = len(frames)
if observed_tx != expected_tx:
    print(text)
    raise SystemExit(f'FAIL: expected {expected_tx} transmitted startup frames, observed {observed_tx}')
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
    if fields.odd_parity_ok and decoded['chip_id'] == 14 and decoded['downstream'] == 1 and decoded['trigger_type'] == 0:
        matching.append((word, fields))
        channels.add(decoded['channel_id'])
if not matching:
    raise SystemExit('FAIL: no received data packet matched chip_id=14 with downstream=1 and trigger_type=0')
peak_chip_fifo = max(int(row['chip_fifo']) for row in occupancy_rows)
peak_ch0 = max(int(row['ch0_fifo']) for row in occupancy_rows)
peak_ch4 = max(int(row['ch4_fifo']) for row in occupancy_rows)
locally_generated_channels = [int(row['channel']) for row in generation_rows if int(row['generated_any']) != 0]
missing_local_channels = [int(row['channel']) for row in generation_rows if int(row['generated_any']) == 0]
print('PASS: 3x5 LArPix analog/cosim remote all-channel occupancy test')
print(f'expected_frame_count={expected_tx}')
print(f'observed_transmitted_frame_count={observed_tx}')
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
PY2
