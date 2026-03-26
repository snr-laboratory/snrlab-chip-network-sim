# Verilator Feasibility Notes For `larpix_v3b`

## Summary

If you are willing to ignore the mixed-signal wrappers and target only the RTL in `larpix_v3b/src`, a Verilator flow is realistic.

The main constraint is that the existing full-chip LArPix top-level benches are mixed-signal behavioral simulations. Those wrappers use `real`-valued analog interfaces and analog-style timing behavior, which makes them a poor fit for Verilator.

The RTL itself is a better candidate. In particular, `digital_core` already exposes digital inputs such as `dout`, `done`, `hit`, `external_trigger`, and `posi`, so you can bypass the analog wrapper entirely and build a digital-only harness.

## Why The Existing Top-Level Benches Are A Bad Verilator Target

These files are the main reason the current top-level testbenches are not good Verilator targets:

- `larpix_v3b/testbench/larpix_v3/larpix_v2.sv`
- `larpix_v3b/testbench/analog_core/analog_core.sv`
- `larpix_v3b/testbench/analog_core/analog_channel.sv`
- the legacy MCP-based benches under `larpix_v3b/testbench/mcp`

Problems:

- They use `real` ports and internal `real` math.
- They model analog behavior rather than pure RTL behavior.
- They rely heavily on event-driven timing and procedural stimulus files.

Representative examples:

- `larpix_v2.sv` uses `input real charge_in_r [63:0]` and `output real monitor_out_r`.
- `analog_core.sv` takes `input real charge_in_r [NUMCHANNELS-1:0]`.
- `analog_channel.sv` takes `input real charge_in_r` and uses internal `real` signals such as `csa_vout_r`.

## Best First Targets For A Verilator Flow

These are the safest modules to start with:

- `larpix_v3b/src/uart_rx.sv`
- `larpix_v3b/src/uart_tx.sv`
- `larpix_v3b/src/fifo_latch.sv`
- `larpix_v3b/src/priority_fifo_arbiter.sv`
- `larpix_v3b/src/timestamp_gen.sv`
- `larpix_v3b/src/periodic_pulser.sv`
- `larpix_v3b/src/config_regfile.sv`
- `larpix_v3b/src/event_router.sv`

Why these first:

- They are mostly straightforward digital RTL.
- They do not depend on the analog wrappers.
- They let you establish a working Verilator harness quickly.

## Good Next Targets

These should also be viable under Verilator, but they are more integrated and need better testbench scaffolding:

- `larpix_v3b/src/channel_ctrl.sv`
- `larpix_v3b/src/comms_ctrl.sv`
- `larpix_v3b/src/hydra_ctrl.sv`
- `larpix_v3b/src/external_interface.sv`
- `larpix_v3b/src/digital_core.sv`

Why they are still realistic:

- `digital_core.sv` exposes digital inputs:
  - `dout`
  - `done`
  - `hit`
  - `external_trigger`
  - `posi`
- `external_interface.sv` and `hydra_ctrl.sv` are purely digital packet-routing and control logic.

## Modules Likely To Need Small Verilator Compatibility Work

These are the files most likely to need stubbing or minor patching:

- `larpix_v3b/src/gate_posedge_clk.sv`
- `larpix_v3b/src/gate_negedge_clk.sv`
- `larpix_v3b/src/uart.sv`

Why:

- `gate_posedge_clk.sv` instantiates a technology-specific cell `CKLNQD8` and uses an explicit delay:
  - `always @(EN) EN_dly = #1.5 EN;`
- `gate_negedge_clk.sv` instantiates `CKLHQD4` and also uses explicit delay:
  - `always EN_dly = #0.5 EN;`
- `uart.sv` depends on `gate_posedge_clk.sv`.

Practical fix:

- For simulation, replace the gate-cell wrappers with simple behavioral pass-through clock-enable logic or guarded simulation stubs.
- Keep the real gate-cell versions for ASIC/library flows under `ifdef`s.

## Not Worth Starting With Under Verilator

Avoid these if the goal is to get a clean Verilator flow up quickly:

- `larpix_v3b/testbench/larpix_v3/larpix_v2.sv`
- `larpix_v3b/testbench/analog_core/analog_core.sv`
- `larpix_v3b/testbench/analog_core/analog_channel.sv`
- `larpix_v3b/testbench/mcp/*`

Reason:

- mixed-signal behavior
- `real` ports
- event-driven legacy verification flow

## Recommended Bring-Up Order

1. `uart_rx`, `uart_tx`
2. `fifo_latch`, `priority_fifo_arbiter`
3. `config_regfile`, `timestamp_gen`, `periodic_pulser`
4. `channel_ctrl`
5. `comms_ctrl`
6. `hydra_ctrl`
7. `external_interface`
8. `digital_core` with a custom digital-only harness

## Practical End Target

The most realistic Verilator end target is `larpix_v3b/src/digital_core.sv`, not the full mixed-signal `larpix_v2` chip wrapper.

If you build your own testbenches and:

- avoid the analog wrappers
- use the digital RTL only
- patch or stub the clock-gating wrappers

then a Verilator-based workflow is realistic.

## Useful File References

- `larpix_v3b/src/digital_core.sv`
- `larpix_v3b/src/external_interface.sv`
- `larpix_v3b/src/hydra_ctrl.sv`
- `larpix_v3b/src/comms_ctrl.sv`
- `larpix_v3b/src/channel_ctrl.sv`
- `larpix_v3b/src/uart.sv`
- `larpix_v3b/src/uart_rx.sv`
- `larpix_v3b/src/uart_tx.sv`
- `larpix_v3b/src/gate_posedge_clk.sv`
- `larpix_v3b/src/gate_negedge_clk.sv`
- `larpix_v3b/testbench/larpix_v3/larpix_v2.sv`
- `larpix_v3b/testbench/analog_core/analog_core.sv`
- `larpix_v3b/testbench/analog_core/analog_channel.sv`
