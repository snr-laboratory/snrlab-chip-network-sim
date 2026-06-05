# Internal Inspection Mode

This document covers optional RTL adjustments that are useful for internal observability after the chip already builds and runs under Verilator.

These changes are not part of the minimal functional-cosimulation contract. They are for richer debugging, state inspection, and post-run analysis.

## 1. Purpose

The goal of this mode is to make selected internal RTL signals easier for the simulator and analysis tooling to inspect during live runs.

This mode is not required just to get a chip binary built and launched successfully.

## 2. What This Mode Is For

Use this mode if you want:

- internal debug CSV capture
- richer live-state inspection during a scenario
- support for detailed post-run debugging
- visibility into internal FIFO and control-state behavior

## 3. Optional Analysis Artifacts

Some scenario scripts can also produce optional post-run analysis artifacts beyond the minimal launch inputs and raw outputs.

Examples include:

- occupancy CSV files
- internal debug CSV files
- run-summary or metrics JSON files
- scenario-specific analysis summary JSON files

These are useful for:

- inspecting internal FIFO behavior
- understanding why a scenario passed or failed
- comparing runs across RTL variants
- debugging packet flow and timing behavior

They should be treated as optional inspection outputs, not as required artifacts for every scenario.

## 4. LArPix-Specific Optional Adjustments

For the LArPix-oriented RTL in this repository, the main optional observability adjustments were made in:

- `external_interface.sv`
- `hydra_ctrl.sv`

These edits made internal signals explicit so they could be inspected more easily after the Verilator build and during live simulation.

### `external_interface.sv`

The recorded patch history shows explicit declarations added for internal signals such as:

- `rx_data_flag`
- `ready_for_pkt`
- `comms_busy`

These are useful for observing receive-path and handshake behavior.

### `hydra_ctrl.sv`

The recorded patch history shows explicit declarations added for internal signals such as:

- `fifo_full`
- `fifo_write_n`

These are useful for observing FIFO-control behavior.

## 5. Why These Are Optional

A generic RTL can still be functionally cosimulated without exposing many of these internal signals.

The minimal required contract is the top-level functional interface needed by the simulator:

- clock/reset behavior
- top-level serial I/O
- any analog/event injection interface the flow depends on
- any required preload/config path

By contrast, the internal declarations above are primarily useful for:

- debug capture
- internal-state inspection
- richer analysis tooling
- diagnosing why a run behaved a certain way

So they should be treated as optional observability features, not core prerequisites.

## 6. When To Use This Mode

Use this mode only after:

- `prerequisite_mode.md`
- `integrate_rtl_mode.md`

In other words:

- first make the toolchain work
- then make the RTL build and run
- only then add deeper internal inspection features if you need them

## Summary

This mode separates optional observability work from the minimal functional RTL contract.

For the current LArPix case, that optional work centered on exposing additional internal signals in:

- `external_interface.sv`
- `hydra_ctrl.sv`
