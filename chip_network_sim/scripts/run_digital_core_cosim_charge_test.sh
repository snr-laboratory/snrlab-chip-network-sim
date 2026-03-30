#!/usr/bin/env bash
set -euo pipefail

# This script builds and runs a mixed C++/RTL co-simulation for the LArPix
# digital core. The test uses a software analog-front-end model to inject one
# charge pulse into a selected channel, feeds the resulting hit/ADC/done signals
# into a Verilated digital_core instance, and checks that the digital core
# produces a correctly formatted local data packet and launches it toward TX.
#
# Relevant files used by this flow:
# - larpix_v3b/testbench/cosim/digital_core_cosim_harness.cpp
#   Main self-checking C++ co-simulation harness. It applies configuration,
#   injects charge, captures the generated packet, and checks TX-path progress.
# - larpix_v3b/cpp/analog_core_model.h
# - larpix_v3b/cpp/analog_core_model.cpp
#   Software analog-core replacement. It models CSA state, threshold crossing,
#   ADC quantization, and produces dout/hit/done for the RTL digital core.
# - larpix_v3b/src/digital_core.sv
#   Top-level RTL digital core under test.
# - larpix_v3b/src/config_regfile.sv
# - larpix_v3b/src/config_regfile_assign.sv
#   Register-file/default-configuration RTL used by digital_core.
# - larpix_v3b/src/channel_ctrl.sv
# - larpix_v3b/src/event_router.sv
# - larpix_v3b/src/external_interface.sv
# - larpix_v3b/src/hydra_ctrl.sv
# - larpix_v3b/src/uart*.sv
#   Key RTL sub-blocks on the event-generation and transmission path.
#
# In short: this is a digital_core co-sim smoke/integration test that replaces
# the old SystemVerilog analog wrapper with a C++ analog model and verifies that
# one injected analog charge can become a transmit-ready digital packet.
#
# Pass criteria for digital_core_cosim_harness.cpp:
# 1. Reset/default config must come up correctly:
#    - config_bits[CHIP_ID] = 0x01
#    - config_bits[ENABLE_POSI][3:0] = 0xF
#    - tx_enable stays 0 by default
#    - sample for the injected channel returns high after reset
# 2. Direct config pokes must enable the injected channel, unmask it,
#    disable interfering trigger-mode modifiers, and enable downstream
#    TX lane 0.
# 3. A charge pulse into the software analog model must create a hit on
#    the injected channel and lead to a local event packet.
# 4. The observed event packet must match the expected local-data packet
#    fields: data packet type, chip ID 0x01, injected channel ID,
#    analog-model ADC code, natural-trigger encoding, downstream bit set,
#    and valid parity.
# 5. The event must progress into the TX path: Hydra FIFO activity must
#    be observed, UART0 tx_busy must assert, and UART0 must leave idle.
# Any failed check throws in the harness and exits nonzero, so the test
# only prints PASS if every condition above succeeds.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verilator_bin="${VERILATOR_BIN:-/home/lxusers/y/ymei/OpenICEDA/bin/verilator}"
cxx_bin="${CXX_BIN:-clang++}"
link_bin="${LINK_BIN:-clang++}"
build_dir="${BUILD_DIR:-$repo_root/build/verilated_digital_core_cosim_charge_test}"

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
  "$repo_root/larpix_v3b/testbench/cosim/digital_core_cosim_harness.cpp"
)

rm -rf "$build_dir"
mkdir -p "$build_dir"

"$verilator_bin" --cc --exe --sv -Wall -Wno-fatal -DVERILATOR   -I"$repo_root/larpix_v3b/src"   -Mdir "$build_dir"   -CFLAGS "-std=c++17 -I$repo_root/larpix_v3b/cpp -I$repo_root/larpix_v3b/testbench/cosim"   --top-module digital_core   "${sv_sources[@]}"   "${cpp_sources[@]}"

make -C "$build_dir" -f Vdigital_core.mk CXX="$cxx_bin" LINK="$link_bin"
"$build_dir/Vdigital_core" "$@"
