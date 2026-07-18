#!/usr/bin/env bash
set -euo pipefail

# 3x3 v3c convergent packet-loss probe.
#
# Layout (runtime ids):
#   y=2: 6 7 8
#   y=1: 3 4 5
#   y=0: 0 1 2
#
# Simultaneous traffic converges on chip 4:
#   chip 3 --east--> chip 4 <--west-- chip 5
#                        ^
#                        |
#                  south from chip 7
#
# Downstream routing sends chips 3, 5, and 7 into chip 4 and sends chip 4
# south. Chips 3, 4, and 5 use north-only upstream routing. Chip 7 retains
# south-only upstream routing. All other chips retain standard routing.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo_root/build"
chip_target="${CHIP_TARGET:-chip_larpix_v3c_build}"
chip_bin_name="${CHIP_BIN_NAME:-chip_larpix_v3c}"
rtl_version_label="${RTL_VERSION_LABEL:-v3c}"
chip_variant="${CHIP_VARIANT_LABEL:-v3c}"
build_binaries="${BUILD_BINARIES:-1}"
drain_tail_ticks="${DRAIN_TAIL_TICKS:-24000}"
ack_timeout_ms="${ACK_TIMEOUT_MS:-60000}"
scenario_name="larpix_3x3_convergent_packet_loss_probe"
work_dir="$build_dir/${scenario_name}__${chip_variant}"
init_json="$work_dir/init_3x3_convergent_packet_loss_probe_preconfigured.json"
startup_json="$work_dir/startup_3x3_convergent_packet_loss_probe.json"
startup_compiled="$work_dir/startup_3x3_convergent_packet_loss_probe.compiled.json"
stimulus_json="$work_dir/stimulus_3x3_convergent_packet_loss_probe.json"
log_file="$work_dir/run.log"
trace_jsonl="$work_dir/trace.jsonl"
playback_json="$work_dir/live_event_3x3_convergent_packet_loss_probe.json"
run_metrics_json="$work_dir/run_metrics.json"
chip4_debug_csv="$work_dir/chip4_rx_debug.csv"
chip0_debug_csv="$work_dir/chip0_rx_debug.csv"
summary_json="$work_dir/packet_loss_summary.json"
mkdir -p "$work_dir"

python3 "$repo_root/sim_core/tools/generate_bootstrap_preconfigured_event_init_json.py" \
  --rows 3 \
  --cols 3 \
  --s 0 \
  --target 0,1 \
  --target 2,1 \
  --target 1,2 \
  --out "$init_json"

python3 - "$init_json" <<'PYROUTE'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
config = json.loads(path.read_text())

# RTL PISO order: bit 0=W, bit 1=S, bit 2=E, bit 3=N.
downstream_overrides = {
    3: (0x4, 'east'),
    5: (0x1, 'west'),
    7: (0x2, 'south'),
    4: (0x2, 'south'),
}
upstream_overrides = {
    3: (0x8, 'north'),
    4: (0x8, 'north'),
    5: (0x8, 'north'),
    7: (0x2, 'south'),
}
for runtime_id, (mask, direction) in upstream_overrides.items():
    config['register_writes'].append({
        'runtime_id': runtime_id,
        'register_addr': 124,
        'register_data': mask,
        'label': f'convergent override: chip {runtime_id} ENABLE_PISO_UP {direction}-only',
    })
for runtime_id, (mask, direction) in downstream_overrides.items():
    config['register_writes'].append({
        'runtime_id': runtime_id,
        'register_addr': 125,
        'register_data': mask,
        'label': f'convergent override: chip {runtime_id} ENABLE_PISO_DOWN {direction}-only',
    })

config['routing_overrides'] = [
    {
        'runtime_id': runtime_id,
        'upstream_tx_direction': upstream_overrides[runtime_id][1],
        'upstream_piso_mask': upstream_overrides[runtime_id][0],
        'downstream_tx_direction': downstream_overrides[runtime_id][1],
        'downstream_piso_mask': downstream_overrides[runtime_id][0],
    }
    for runtime_id in sorted(downstream_overrides)
]
path.write_text(json.dumps(config, indent=2) + '\n')
PYROUTE

python3 - "$startup_json" <<'PYSTARTUP'
import json
import pathlib
import sys

registers = [
    (1100, 122, 'CHIP_ID'),
    (1200, 124, 'ENABLE_PISO_UP'),
    (1300, 125, 'ENABLE_PISO_DOWN'),
    (1400, 64, 'GLOBAL_THRESH'),
]
frames = [
    {
        'tick_start': tick,
        'type': 'read',
        'chip_id': 7,
        'register_addr': register_addr,
        'label': f'contention read chip 7 {register_name}',
    }
    for tick, register_addr, register_name in registers
]
pathlib.Path(sys.argv[1]).write_text(
    '// Chip 7 configuration reads during chip 4 data convergence\n'
    + json.dumps({'frames': frames}, indent=2)
    + '\n'
)
PYSTARTUP

python3 "$repo_root/sim_core/tools/compile_startup_json.py" \
  "$startup_json" \
  "$startup_compiled"

read -r injection_tick ticks <<<"$(python3 - "$stimulus_json" "$drain_tail_ticks" <<'PYSTIM'
import json
import pathlib
import sys

injection_tick = 1000
drain_tail_ticks = int(sys.argv[2])
charges = [
    {
        'runtime_id': runtime_id,
        'tick': injection_tick,
        'channel': channel,
        'charge': -5.0e-15,
    }
    for runtime_id in (3, 5, 7)
    for channel in range(64)
]
pathlib.Path(sys.argv[1]).write_text(
    '// 3x3 v3c convergent packet-loss probe stimulus\n'
    + json.dumps({'charges': charges}, indent=2)
    + '\n'
)
print(injection_tick, injection_tick + drain_tail_ticks)
PYSTIM
)"

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

run_ok=0
for attempt in 1 2 3 4 5; do
  base_uri="$(python3 - <<'PYURI'
import random
print(f"tcp://127.0.0.1:{random.randint(20000, 45000)}")
PYURI
)"
  if python3 - \
    "$build_dir" "$init_json" "$startup_compiled" "$stimulus_json" "$trace_jsonl" "$log_file" \
    "$run_metrics_json" "$chip4_debug_csv" "$chip0_debug_csv" "$base_uri" "$ticks" "$ack_timeout_ms" <<'PYRUN'
import json
import os
import pathlib
import subprocess
import sys
import time

build_dir = pathlib.Path(sys.argv[1])
init_json = pathlib.Path(sys.argv[2])
startup_compiled = pathlib.Path(sys.argv[3])
stimulus_json = pathlib.Path(sys.argv[4])
trace_jsonl = pathlib.Path(sys.argv[5])
log_file = pathlib.Path(sys.argv[6])
run_metrics_json = pathlib.Path(sys.argv[7])
chip4_debug_csv = pathlib.Path(sys.argv[8])
chip0_debug_csv = pathlib.Path(sys.argv[9])
base_uri = sys.argv[10]
ticks = int(sys.argv[11])
ack_timeout_ms = sys.argv[12]

chip_bin_name = os.environ.get('CHIP_BIN_NAME', 'chip_larpix_v3c')
cmd = [
    str(build_dir / 'orchestrator_larpix'),
    '-rows', '3',
    '-cols', '3',
    '-ticks', str(ticks),
    '-startup_ms', '3000',
    '-ack_timeout_ms', ack_timeout_ms,
    '-source_x', '0',
    '-source_y', '0',
    '-base_uri', base_uri,
    '-chip_bin', str(build_dir / chip_bin_name),
    '-fpga_bin', str(build_dir / 'fpga_larpix'),
    '-init_regs_json', str(init_json),
    '-startup_json', str(startup_compiled),
    '-stimulus_json', str(stimulus_json),
    '-trace_out', str(trace_jsonl),
    '-rx_debug_csv', str(chip4_debug_csv),
    '-rx_debug_runtime_id', '4',
    '-rx_debug_csv_aux', str(chip0_debug_csv),
    '-rx_debug_runtime_id_aux', '0',
]

allowed = {'orchestrator_larpix', chip_bin_name, 'fpga_larpix', 'trace_collector_larpix'}
peak_concurrent_cores = 0
peak_core_ids = []
start = time.monotonic()
with log_file.open('w') as log_fp:
    proc = subprocess.Popen(cmd, stdout=log_fp, stderr=subprocess.STDOUT)
    while True:
        try:
            output = subprocess.check_output(
                ['ps', '-eLo', 'ppid=,pid=,psr=,comm='],
                text=True,
            )
            sample_cores = set()
            for line in output.splitlines():
                parts = line.strip().split(None, 3)
                if len(parts) != 4:
                    continue
                ppid_text, pid_text, cpu_text, command = parts
                try:
                    ppid = int(ppid_text)
                    pid = int(pid_text)
                    cpu = int(cpu_text)
                except ValueError:
                    continue
                if cpu >= 0 and (pid == proc.pid or ppid == proc.pid) and command in allowed:
                    sample_cores.add(cpu)
            if len(sample_cores) > peak_concurrent_cores:
                peak_concurrent_cores = len(sample_cores)
                peak_core_ids = sorted(sample_cores)
        except Exception:
            pass

        return_code = proc.poll()
        if return_code is not None:
            runtime_sec = time.monotonic() - start
            run_metrics_json.write_text(json.dumps({
                'ticks': ticks,
                'runtime_sec': runtime_sec,
                'ticks_per_sec': ticks / runtime_sec if runtime_sec > 0 else 0.0,
                'cpu_cores_used': peak_concurrent_cores,
                'cpu_peak_concurrent_cores': peak_concurrent_cores,
                'cpu_core_ids_used': peak_core_ids,
                'cpu_cores_available': os.cpu_count() or 0,
            }, indent=2) + '\n')
            raise SystemExit(return_code)
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
  --rows 3 \
  --cols 3 \
  --source-x 0 \
  --source-y 0 \
  --init-regs-json "$init_json" \
  --run-log "$log_file" \
  --trace-jsonl "$trace_jsonl" \
  --out "$playback_json" \
  --rtl-version "$rtl_version_label" \
  --name "3x3 v3c Convergent Packet Loss Probe"

python3 - "$playback_json" "$run_metrics_json" <<'PYPLAYBACK'
import json
import pathlib
import sys

playback_path = pathlib.Path(sys.argv[1])
playback = json.loads(playback_path.read_text())
playback['run_summary'] = json.loads(pathlib.Path(sys.argv[2]).read_text())
playback['chip_internal_debug'] = {
    'csv_url': './chip4_rx_debug.csv',
    'monitor_chip_id': 4,
    'monitor_runtime_id': 4,
    'label': 'v3c Chip 4 Three-Way Convergence',
    'kind': 'v3c_3x3_convergent_packet_loss_chip4',
}
playback['chip_internal_debug_aux'] = {
    'csv_url': './chip0_rx_debug.csv',
    'monitor_chip_id': 0,
    'monitor_runtime_id': 0,
    'label': 'v3c Chip 0 Final Sink Path',
    'kind': 'v3c_3x3_convergent_packet_loss_chip0',
}
playback_path.write_text(json.dumps(playback, indent=2) + '\n')
PYPLAYBACK

python3 - "$trace_jsonl" "$log_file" "$summary_json" \
  "$repo_root/sim_core/tools/larpix_uart.py" "$injection_tick" <<'PYSUM'
import importlib.util
import json
import pathlib
import re
import sys

trace_path = pathlib.Path(sys.argv[1])
log_path = pathlib.Path(sys.argv[2])
summary_path = pathlib.Path(sys.argv[3])
helper_path = pathlib.Path(sys.argv[4])
injection_tick = int(sys.argv[5])

spec = importlib.util.spec_from_file_location('larpix_uart', helper_path)
module = importlib.util.module_from_spec(spec)
sys.modules['larpix_uart'] = module
spec.loader.exec_module(module)

rx_counts = {}
tx_counts = {}
chip4_sources_by_edge = {'north': set(), 'east': set(), 'south': set(), 'west': set()}
chip4_config_rx = []
chip4_config_tx = []

for raw_line in trace_path.read_text().splitlines():
    if not raw_line.strip():
        continue
    event = json.loads(raw_line)
    runtime_id = int(event.get('runtime_id', -1))
    event_name = event.get('event')
    edge = str(event.get('edge', ''))
    word_raw = event.get('packet_word', 0)
    word = int(word_raw, 0) if isinstance(word_raw, str) else int(word_raw)
    packet = module.decode_packet(word) if event_name in ('rx_packet', 'tx_packet') else None
    if event_name == 'rx_packet':
        rx_counts.setdefault(runtime_id, {}).setdefault(edge, 0)
        rx_counts[runtime_id][edge] += 1
        if runtime_id == 4 and edge in chip4_sources_by_edge:
            if packet.kind == 'data':
                chip4_sources_by_edge[edge].add(int(packet.decoded['chip_id']))
            elif packet.kind == 'config_read':
                chip4_config_rx.append({
                    'seq': int(event.get('seq', 0)),
                    'edge': edge,
                    'chip_id': int(packet.decoded['chip_id']),
                    'register_addr': int(packet.decoded['register_addr']),
                    'register_data': int(packet.decoded['register_data']),
                    'downstream': int(packet.decoded['downstream']),
                })
    elif event_name == 'tx_packet':
        tx_counts.setdefault(runtime_id, {}).setdefault(edge, 0)
        tx_counts[runtime_id][edge] += 1
        if runtime_id == 4 and packet.kind == 'config_read':
            chip4_config_tx.append({
                'seq': int(event.get('seq', 0)),
                'edge': edge,
                'chip_id': int(packet.decoded['chip_id']),
                'register_addr': int(packet.decoded['register_addr']),
                'register_data': int(packet.decoded['register_data']),
                'downstream': int(packet.decoded['downstream']),
            })

fpga_arrivals = {}
fpga_unique = {}
fpga_config_read_replies = []
for match in re.finditer(
    r'fpga_larpix\[\d+\] received packet at seq=(\d+):\s*(0x[0-9a-fA-F]+)',
    log_path.read_text(),
):
    word = int(match.group(2), 16)
    packet = module.decode_packet(word)
    if packet.kind == 'config_read' and int(packet.decoded['chip_id']) == 7:
        fpga_config_read_replies.append({
            'seq': int(match.group(1)),
            'register_addr': int(packet.decoded['register_addr']),
            'register_data': int(packet.decoded['register_data']),
            'downstream': int(packet.decoded['downstream']),
        })
    if packet.kind != 'data':
        continue
    chip_id = int(packet.decoded['chip_id'])
    fpga_arrivals[chip_id] = fpga_arrivals.get(chip_id, 0) + 1
    fpga_unique.setdefault(chip_id, set()).add(word)

summary = {
    'scenario': '3x3 v3c Convergent Packet Loss Probe',
    'source_runtime_id': 0,
    'injected_runtime_ids': [3, 5, 7],
    'injection_tick': injection_tick,
    'channels_per_injected_chip': 64,
    'expected_packets': 192,
    'routing_overrides': {
        '3': {'upstream': 'north-only', 'downstream': 'east-only'},
        '4': {'upstream': 'north-only', 'downstream': 'south-only'},
        '5': {'upstream': 'north-only', 'downstream': 'west-only'},
        '7': {'upstream': 'south-only', 'downstream': 'south-only'},
    },
    'chip4_rx_packet_counts_by_edge': rx_counts.get(4, {}),
    'chip4_distinct_data_source_ids_by_edge': {
        edge: sorted(ids) for edge, ids in chip4_sources_by_edge.items() if ids
    },
    'chip4_config_read_rx': chip4_config_rx,
    'chip4_config_read_tx': chip4_config_tx,
    'chip4_tx_packet_counts_by_edge': tx_counts.get(4, {}),
    'chip0_rx_packet_counts_by_edge': rx_counts.get(0, {}),
    'fpga_unique_packet_counts_by_chip_id': {
        str(chip_id): len(words) for chip_id, words in sorted(fpga_unique.items())
    },
    'fpga_arrival_counts_by_chip_id': {
        str(chip_id): count for chip_id, count in sorted(fpga_arrivals.items())
    },
    'fpga_total_unique_packets': sum(len(words) for words in fpga_unique.values()),
    'fpga_total_arrivals': sum(fpga_arrivals.values()),
    'fpga_chip7_config_read_replies': fpga_config_read_replies,
}
summary_path.write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
PYSUM

echo
printf 'Artifacts:\n'
printf '  run log:       %s\n' "$log_file"
printf '  trace jsonl:   %s\n' "$trace_jsonl"
printf '  playback:      %s\n' "$playback_json"
printf '  startup:       %s\n' "$startup_compiled"
printf '  chip 4 debug:  %s\n' "$chip4_debug_csv"
printf '  chip 0 debug:  %s\n' "$chip0_debug_csv"
printf '  summary json:  %s\n' "$summary_json"
