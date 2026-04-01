#!/usr/bin/env bash
set -euo pipefail

# 1-chip exhaustive LArPix startup/readback test.
#
# Test intent:
# - instantiate the minimal network stack: orchestrator_larpix, fpga_larpix,
#   and one chip_larpix process
# - inject startup UART traffic from the FPGA into the single directly
#   connected chip over the south edge
# - issue a CONFIG_READ for every explicit startup-default register described
#   in the mirrored RTL default-assignment file
# - verify that every returned reply matches the RTL startup-default value,
#   except register 125 which this test intentionally modifies first
#
# Sequence:
# 1. CONFIG_WRITE chip_id=1, register 125 (ENABLE_PISO_DOWN), data 0x04 so the
#    chip's south TX lane is enabled for reply traffic back to the FPGA
# 2. CONFIG_READ chip_id=1 for every explicit startup-default register in the
#    mirrored RTL, excluding register 125 because it was intentionally changed
#
# Required passing conditions:
# - build/chip_larpix exists and runs with the real analog + Verilated digital core
# - build/fpga_larpix injects the full startup frame schedule
# - build/orchestrator_larpix advances a 1x1 network in lock-step
# - fpga_larpix receives a valid CONFIG_READ reply for every expected register
# - every decoded reply matches the RTL startup-default value for that register
# - all observed replies pass the odd-parity check
#
# Note:
# - the user request referred to ENABLE_POSI as the modified register, but the
#   first write in this test actually modifies ENABLE_PISO_DOWN (register 125)
#   to enable south-edge reply traffic

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo_root/build"
work_dir="$build_dir/larpix_1chip_readback_smoke"
startup_in="$repo_root/larpix_network_sim/config/startup_1chip_full_reg_readback.json"
startup_compiled="$work_dir/startup_1chip_full_reg_readback.compiled.json"
log_file="$work_dir/run.log"
constants_file="$repo_root/larpix_network_sim/larpix_v3b_rtl/src/larpix_constants.sv"
assign_file="$repo_root/larpix_network_sim/larpix_v3b_rtl/src/config_regfile_assign.sv"

mkdir -p "$work_dir"

cmake -S "$repo_root" -B "$build_dir"
cmake --build "$build_dir" --target fpga_larpix orchestrator_larpix chip_larpix_build -j

python3 "$repo_root/larpix_network_sim/scripts/generate_1chip_full_reg_readback_json.py"   --constants "$constants_file"   --assign "$assign_file"   --out "$startup_in"

python3 "$repo_root/larpix_network_sim/scripts/compile_startup_json.py"   "$startup_in"   "$startup_compiled"

ticks=$(python3 - "$startup_compiled" <<'PYT'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
raw = json.loads(path.read_text())
frames = raw.get("frames", [])
last_tick = max((int(frame["tick_start"]) for frame in frames), default=0)
print(last_tick + 220)
PYT
)

"$build_dir/orchestrator_larpix"   -rows 1   -cols 1   -ticks "$ticks"   -source_x 0   -source_y 0   -chip_bin "$build_dir/chip_larpix"   -fpga_bin "$build_dir/fpga_larpix"   -startup_json "$startup_compiled"   > "$log_file" 2>&1

python3 - "$log_file" "$repo_root/larpix_network_sim/scripts/larpix_uart.py" "$repo_root/larpix_network_sim/scripts/rtl_config_defaults.py" "$constants_file" "$assign_file" <<'PY2'
import importlib.util
import pathlib
import re
import sys

log_path = pathlib.Path(sys.argv[1])
helper_path = pathlib.Path(sys.argv[2])
defaults_helper_path = pathlib.Path(sys.argv[3])
constants_path = pathlib.Path(sys.argv[4])
assign_path = pathlib.Path(sys.argv[5])
text = log_path.read_text()
match = re.findall(r"received packet at seq=\d+: (0x[0-9a-fA-F]+)", text)

spec = importlib.util.spec_from_file_location("larpix_uart", helper_path)
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)

spec2 = importlib.util.spec_from_file_location("rtl_config_defaults", defaults_helper_path)
mod2 = importlib.util.module_from_spec(spec2)
sys.modules[spec2.name] = mod2
spec2.loader.exec_module(mod2)

expected = mod2.parse_defaults(constants_path, assign_path)
expected.pop(125, None)
expected_count = len(expected)
if len(match) < expected_count:
    print(text)
    raise SystemExit(f"FAIL: expected at least {expected_count} reply packets, got {len(match)}")

observed = {}
for raw in match:
    word = int(raw, 0)
    fields = mod.decode_packet(word)
    if fields.kind != "config_read":
        raise SystemExit(f"FAIL: expected config_read reply, got {fields.kind}")
    if not fields.odd_parity_ok:
        raise SystemExit("FAIL: readback packet parity check failed")
    chip_id = fields.decoded["chip_id"]
    addr = fields.decoded["register_addr"]
    data = fields.decoded["register_data"]
    if chip_id != 1:
        raise SystemExit(f"FAIL: expected chip_id=1 on all replies, got {chip_id}")
    observed[addr] = data

missing = [addr for addr in expected if addr not in observed]
wrong = [(addr, expected[addr], observed[addr]) for addr in expected if addr in observed and observed[addr] != expected[addr]]
if missing:
    raise SystemExit(f"FAIL: missing readback replies for register addresses: {missing[:20]}{'...' if len(missing) > 20 else ''}")
if wrong:
    head = ', '.join(f"addr {addr}: expected 0x{exp:02X}, got 0x{got:02X}" for addr, exp, got in wrong[:10])
    raise SystemExit(f"FAIL: register readback mismatches: {head}")

print("PASS: 1-chip exhaustive LArPix startup/readback test")
print(f"verified_register_count={expected_count}")
for addr in sorted(expected)[:10]:
    print(f"sample_reply register_addr={addr} register_data=0x{observed[addr]:02X}")
PY2
