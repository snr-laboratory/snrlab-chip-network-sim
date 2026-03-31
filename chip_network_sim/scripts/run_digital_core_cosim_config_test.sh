#!/usr/bin/env bash
set -euo pipefail

# This script builds and runs a mixed C++/RTL co-simulation that checks
# configuration write and configuration read behavior through the real UART
# path of the LArPix digital core.
#
# Test intent:
# - Keep the software analog model present, but idle.
# - Drive serialized CONFIG_WRITE and CONFIG_READ packets into posi[0].
# - Exercise the real path:
#   posi -> uart_rx -> hydra_ctrl -> comms_ctrl -> config_regfile
#   and for reads:
#   config_regfile -> comms_ctrl reply -> hydra FIFO/TX -> uart_tx -> piso[0]
# - Verify both internal config state and readback replies at the point Hydra loads UART0 for transmission, then confirm UART0 actually starts sending on piso[0].
#
# Relevant files used by this flow:
# - larpix_v3b/testbench/cosim/digital_core_cosim_config_tb.cpp
#   Main self-checking UART-driven co-simulation harness.
# - larpix_v3b/cpp/analog_core_model.h
# - larpix_v3b/cpp/analog_core_model.cpp
#   Software analog-core model; instantiated here but left idle.
# - larpix_v3b/src/digital_core.sv
# - larpix_v3b/src/external_interface.sv
# - larpix_v3b/src/hydra_ctrl.sv
# - larpix_v3b/src/comms_ctrl.sv
# - larpix_v3b/src/config_regfile.sv
# - larpix_v3b/src/uart.sv
# - larpix_v3b/src/uart_rx.sv
# - larpix_v3b/src/uart_tx.sv
#   RTL blocks on the configuration receive/readback path.
#
# Pass criteria:
# 1. Default config must load correctly after reset:
#    - CHIP_ID = 0x01
#    - ENABLE_POSI[3:0] = 0xF
#    - tx_enable = 0
# 2. A CONFIG_WRITE over posi[0] must set ENABLE_PISO_DOWN = 0x01,
#    and tx_enable must change to 0x1.
# 3. A second CONFIG_WRITE over posi[0] must set GLOBAL_THRESH = 0x22,
#    and threshold_global must change to 0x22.
# 4. A CONFIG_READ for ENABLE_PISO_DOWN must launch a valid reply packet into UART0
#    with chip ID 0x01, address ENABLE_PISO_DOWN, data 0x01,
#    downstream bit set, original magic number preserved, and correct parity.
# 5. A CONFIG_READ for GLOBAL_THRESH must launch a second valid reply packet into
#    UART0 with address GLOBAL_THRESH, data 0x22,
#    downstream bit set, original magic number preserved, and correct parity.
# 6. UART0 must actually launch the replies: tx_busy must assert and piso[0]
#    must leave the idle-high state.
# Any failed check causes the harness to exit nonzero, so PASS is printed only
# if every condition above succeeds.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verilator_bin="${VERILATOR_BIN:-/home/lxusers/y/ymei/OpenICEDA/bin/verilator}"
cxx_bin="${CXX_BIN:-clang++}"
link_bin="${LINK_BIN:-clang++}"
build_dir="${BUILD_DIR:-$repo_root/build/verilated_digital_core_cosim_config_test}"

sv_sources=(
  "$repo_root/larpix_v3b/src/async2sync.sv"
  "$repo_root/larpix_v3b/src/channel_ctrl.sv"
  "$repo_root/larpix_v3b/src/comms_ctrl.sv"
  "$repo_root/larpix_v3b/src/config_regfile.sv"
  "$repo_root/larpix_v3b/src/digital_core.sv"
  "$repo_root/larpix_v3b/src/digital_monitor.sv"
  "$repo_root/larpix_v3b/src/event_router.sv"
  "$repo_root/larpix_v3b/src/external_interface.sv"
  "$repo_root/larpix_v3b/src/fifo_latch.sv"
  "$repo_root/larpix_v3b/src/gate_negedge_clk.sv"
  "$repo_root/larpix_v3b/src/gate_posedge_clk.sv"
  "$repo_root/larpix_v3b/src/hydra_ctrl.sv"
  "$repo_root/larpix_v3b/src/periodic_pulser.sv"
  "$repo_root/larpix_v3b/src/priority_fifo_arbiter.sv"
  "$repo_root/larpix_v3b/src/reset_sync.sv"
  "$repo_root/larpix_v3b/src/sar_adc_cdc.sv"
  "$repo_root/larpix_v3b/src/timestamp_gen.sv"
  "$repo_root/larpix_v3b/src/uart.sv"
  "$repo_root/larpix_v3b/src/uart_rx.sv"
  "$repo_root/larpix_v3b/src/uart_tx.sv"
)

cpp_sources=(
  "$repo_root/larpix_v3b/cpp/analog_core_model.cpp"
  "$repo_root/larpix_v3b/testbench/cosim/digital_core_cosim_config_tb.cpp"
)

rm -rf "$build_dir"
mkdir -p "$build_dir"

"$verilator_bin" --cc --exe --sv -Wall -Wno-fatal -DVERILATOR \
  -I"$repo_root/larpix_v3b/src" \
  -Mdir "$build_dir" \
  -CFLAGS "-std=c++17 -I$repo_root/larpix_v3b/cpp -I$repo_root/larpix_v3b/testbench/cosim" \
  --top-module digital_core \
  "${sv_sources[@]}" \
  "${cpp_sources[@]}"

make -C "$build_dir" -f Vdigital_core.mk CXX="$cxx_bin" LINK="$link_bin"
"$build_dir/Vdigital_core" "$@"
