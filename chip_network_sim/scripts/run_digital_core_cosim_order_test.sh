#!/usr/bin/env bash
set -euo pipefail

# This script builds and runs a mixed C++/RTL co-simulation that checks event
# ordering across two staggered half-chip analog injections.
#
# Test intent:
# - Inject -5e-15 C into channels 32-63 at one cycle.
# - Inject -5e-15 C into channels 0-31 exactly 120 cycles later.
# - Confirm that the first 64 observed local event packets on the digital-core
#   event stream appear in this exact order:
#   32,33,...,63,0,1,...,31
# - Also confirm that TX launch activity occurs.
#
# Relevant files used by this flow:
# - larpix_v3b/testbench/cosim/digital_core_cosim_order_tb.cpp
#   Self-checking ordered-injection co-simulation harness.
# - larpix_v3b/cpp/analog_core_model.h
# - larpix_v3b/cpp/analog_core_model.cpp
#   Software analog-core model used to generate dout/hit/done.
# - larpix_v3b/src/digital_core.sv
#   Top-level RTL digital core under test.
# - larpix_v3b/src/channel_ctrl.sv
# - larpix_v3b/src/event_router.sv
# - larpix_v3b/src/external_interface.sv
# - larpix_v3b/src/hydra_ctrl.sv
# - larpix_v3b/src/priority_onehot.sv (included by RTL users)
#   Key RTL on the enqueue/arbitration/TX path.
#
# Pass criteria:
# 1. All channels are enabled/unmasked by direct config pokes.
# 2. Channels 32-63 all hit after the first injection.
# 3. Channels 0-31 all hit after the second injection 120 cycles later.
# 4. The first 64 observed event packets have channel IDs in exact order:
#    32..63 followed by 0..31.
# 5. Every packet in that sequence is a natural data packet with chip ID 0x01,
#    downstream set, and valid parity.
# 6. UART0 tx_busy asserts, proving launch into the TX path.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verilator_bin="${VERILATOR_BIN:-/home/lxusers/y/ymei/OpenICEDA/bin/verilator}"
cxx_bin="${CXX_BIN:-clang++}"
link_bin="${LINK_BIN:-clang++}"
build_dir="${BUILD_DIR:-$repo_root/build/verilated_digital_core_cosim_order_test}"

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
  "$repo_root/larpix_v3b/testbench/cosim/digital_core_cosim_order_tb.cpp"
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
