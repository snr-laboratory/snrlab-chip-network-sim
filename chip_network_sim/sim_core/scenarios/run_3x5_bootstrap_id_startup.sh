#!/usr/bin/env bash
set -euo pipefail

# 3x5 live-network bootstrap CHIP_ID assignment plus immediate readback test.
#
# Test intent:
# - instantiate a 3-row by 5-column LArPix network with source chip (0,0)
# - generate the live bootstrap schedule using the corrected toy bootstrap protocol
# - assign CHIP_ID values across the network using startup traffic from the FPGA
# - issue an immediate CHIP_ID readback after every CHIP_ID reassignment
# - verify that the returned readbacks match the expected bootstrap traversal
# - generate a bootstrap playback JSON for the visualizer

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo_root/build"
startup_in="$repo_root/sim_core/config/startup_3x5_bootstrap_chip_ids.json"
chip_target="${CHIP_TARGET:-chip_larpix_v3b_build}"
chip_bin_name="${CHIP_BIN_NAME:-chip_larpix_v3b}"
build_binaries="${BUILD_BINARIES:-1}"
case "$chip_bin_name" in
  chip_larpix_v3c) chip_variant_default="v3c" ;;
  chip_larpix_v3b_v2) chip_variant_default="v3b_v2" ;;
  chip_larpix_msg_rtl) chip_variant_default="msg" ;;
  chip_larpix_v3b) chip_variant_default="v3b" ;;
  chip_larpix_*) chip_variant_default="${chip_bin_name#chip_larpix_}" ;;
  *) chip_variant_default="$chip_bin_name" ;;
esac
chip_variant="${CHIP_VARIANT_LABEL:-$chip_variant_default}"
scenario_name="larpix_3x5_bootstrap_id_smoke"
work_dir="$build_dir/${scenario_name}__${chip_variant}"
startup_compiled="$work_dir/startup_3x5_bootstrap_chip_ids.compiled.json"
log_file="$work_dir/run.log"
trace_jsonl="$work_dir/trace.jsonl"
playback_json="$work_dir/live_bootstrap_3x5_chip_ids.json"

mkdir -p "$work_dir"

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

python3 "$repo_root/sim_core/tools/generate_bootstrap_chip_id_readback_json.py" \
  --rows 3 \
  --cols 5 \
  --s 0 \
  --out "$startup_in"

python3 "$repo_root/sim_core/tools/compile_startup_json.py" \
  "$startup_in" \
  "$startup_compiled"

ticks=$(python3 - "$startup_compiled" <<'PYT'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
raw = json.loads(path.read_text())
frames = raw.get("frames", [])
last_tick = max((int(frame["tick_start"]) for frame in frames), default=0)
print(last_tick + 5000)
PYT
)

run_ok=0
for attempt in 1 2 3 4 5; do
  base_uri="$(python3 - <<'PYU'
import random
print(f"tcp://127.0.0.1:{random.randint(20000, 45000)}")
PYU
)"
  if "$build_dir/orchestrator_larpix" \
    -rows 3 \
    -cols 5 \
    -ticks "$ticks" \
    -source_x 0 \
    -source_y 0 \
    -base_uri "$base_uri" \
    -chip_bin "$build_dir/$chip_bin_name" \
    -fpga_bin "$build_dir/fpga_larpix" \
    -startup_json "$startup_compiled" \
    -trace_out "$trace_jsonl" \
    > "$log_file" 2>&1
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

python3 "$repo_root/sim_core/visualizers/packet_transmission/convert_live_bootstrap_log_to_playback.py" \
  --rows 3 \
  --cols 5 \
  --s 0 \
  --startup-json "$startup_in" \
  --run-log "$log_file" \
  --out "$playback_json"

python3 - "$startup_in" "$log_file" "$playback_json" "$repo_root/sim_core/tools/larpix_uart.py" <<'PY2'
import importlib.util
import json
import pathlib
import re
import sys

startup_path = pathlib.Path(sys.argv[1])
log_path = pathlib.Path(sys.argv[2])
playback_path = pathlib.Path(sys.argv[3])
helper_path = pathlib.Path(sys.argv[4])

startup = json.loads(startup_path.read_text())
text = log_path.read_text()
if not playback_path.exists() or playback_path.stat().st_size == 0:
    raise SystemExit("FAIL: bootstrap playback JSON was not produced")

tx_packets = re.findall(r"transmitted frame at seq=\d+\s*:\s*(0x[0-9a-fA-F]+)", text)
rx_packets = re.findall(r"received packet at seq=\d+:\s*(0x[0-9a-fA-F]+)", text)
frames = startup.get("frames", [])
if len(tx_packets) != len(frames):
    raise SystemExit(f"FAIL: transmitted frame count mismatch, startup has {len(frames)} frames but log has {len(tx_packets)}")

spec = importlib.util.spec_from_file_location("larpix_uart", helper_path)
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)

expected_readbacks = [
    int(frame["chip_id"])
    for frame in frames
    if frame.get("type") == "read" and int(frame.get("register_addr", -1)) == 122
]

observed_readbacks = []
for raw in rx_packets:
    fields = mod.decode_packet(int(raw, 0))
    if fields.kind != "config_read":
        raise SystemExit(f"FAIL: expected config_read reply during bootstrap, got {fields.kind}")
    if not fields.odd_parity_ok:
        raise SystemExit("FAIL: bootstrap readback parity check failed")
    decoded = fields.decoded
    if int(decoded.get("register_addr", -1)) != 122:
        raise SystemExit(f"FAIL: expected CHIP_ID register readback, got register {decoded.get('register_addr')}")
    observed_readbacks.append(int(decoded["register_data"]))

if observed_readbacks != expected_readbacks:
    raise SystemExit(
        "FAIL: bootstrap CHIP_ID readback mismatch\n"
        f"expected={expected_readbacks}\n"
        f"observed={observed_readbacks}"
    )

print("PASS: 3x5 bootstrap CHIP_ID assignment plus readback test")
print("verified_readbacks=" + ",".join(str(v) for v in observed_readbacks))
print(f"playback_json={playback_path}")
print(
    "visualizer_url_hint=http://localhost:8000/sim_core/visualizers/packet_transmission/?playback=/build/"
    + playback_path.parent.name
    + "/"
    + playback_path.name
)
PY2
