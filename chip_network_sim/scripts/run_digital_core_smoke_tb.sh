#!/usr/bin/env bash
set -euo pipefail

# Pass criteria for digital_core_smoke_tb.sv:
# 1. Reset/default config must come up correctly:
#    - config_bits[CHIP_ID] = 8'h01
#    - config_bits[ENABLE_POSI][3:0] = 4'hF
#    - tx_enable stays 4'h0 by default
#    - sample[0] returns high after reset completes
# 2. Hierarchical config pokes must enable channel 0, unmask channel 0,
#    and enable downstream TX lane 0.
# 3. One injected natural hit plus ADC done pulse must produce a local
#    event at event_router.
# 4. The observed event packet must contain no X/Z bits.
# 5. The observed event packet fields must match the expected local-data
#    packet format: data type, chip ID 0x01, channel ID 0, ADC value 42,
#    natural-trigger encoding, and downstream marker set.
# 6. The reconstructed expected packet, including parity, must match the
#    observed event packet.
# 7. The event must enter the Hydra/TX path and assert UART0 tx_busy.
# 8. UART0 must leave the idle state after transmission starts.
# Any failed check triggers $fatal(1), so the test only prints PASS if
# every condition above succeeds.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verilator_bin="${VERILATOR_BIN:-/home/lxusers/y/ymei/OpenICEDA/bin/verilator}"
cxx_bin="${CXX_BIN:-clang++}"
link_bin="${LINK_BIN:-clang++}"
build_dir="${BUILD_DIR:-$repo_root/build/verilated_digital_core_smoke_tb}"

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
  "$repo_root/larpix_v3b/testbench/unit_tests/digital_core_smoke_tb.sv"
)

rm -rf "$build_dir"
mkdir -p "$build_dir"

"$verilator_bin" --binary --sv --timing -Wall -Wno-fatal \
  -I"$repo_root/larpix_v3b/src" \
  -Mdir "$build_dir" \
  -CFLAGS "-std=c++20" \
  --top-module digital_core_smoke_tb \
  "${sv_sources[@]}" || true

make -C "$build_dir" -f Vdigital_core_smoke_tb.mk CXX="$cxx_bin" LINK="$link_bin"
"$build_dir/Vdigital_core_smoke_tb"
