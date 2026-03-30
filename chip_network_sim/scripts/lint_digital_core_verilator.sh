#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verilator_bin="${VERILATOR_BIN:-/home/lxusers/y/ymei/OpenICEDA/bin/verilator}"

# Do not pass include-only files as standalone Verilator sources.
# These are intentionally omitted:
# - larpix_v3b/src/larpix_constants.sv
# - larpix_v3b/src/priority_onehot.sv
# - larpix_v3b/src/config_regfile_assign.sv
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

exec "$verilator_bin" --lint-only --sv -Wall -Wno-fatal \
  -I"$repo_root/larpix_v3b/src" \
  --top-module digital_core \
  "${sv_sources[@]}"
