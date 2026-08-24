# chip_network_sim

`chip_network_sim` is a process-level inter-chip digital network simulator.
The active branch is organized around:

- `sim_core/`: runtime, tooling, scenarios, config assets, and visualizer
- `rtl/`: supported LArPix-like RTL trees
- `doc/`: architecture notes and workflow documentation

## Runtime Model

- The orchestrator uses one asynchronous NNG request/reply transaction per
  process to distribute each control message and gather all `DONE` responses.
- Unanswered control requests are retried. Each process validates the control
  sequence and caches its most recent `DONE` response so a retry cannot
  evaluate the RTL twice.
- Each chip issues requests on all connected neighbor edges before gathering
  their replies, allowing independent link transactions to progress
  concurrently.

## Build
```bash
cmake -S . -B build
cmake --build build -j
```

The active simulator links against the local `nng` checkout at:
- `nng/include`
- `nng/build/libnng.so`

Common active targets:
- `orchestrator_larpix`
- `fpga_larpix`
- `trace_collector_larpix`
- `chip_larpix_build`
- `chip_larpix_v2_build`
- `chip_larpix_v3c_build`
- `chip_larpix_v3c2_build`
- `chip_larpix_msg_rtl_build`

## Repository Layout
```text
chip_network_sim/
  sim_core/
    src/          # active runtime implementation
    include/      # active runtime headers
    tools/        # JSON generators, compilers, UART helpers
    scenarios/    # runnable scenario/probe scripts
    config/       # startup/stimulus/config assets
    visualizers/  # browser playback tools
  rtl/
    v3b/
    v3b_v2/
    v3c/
    v3c2/
    msg_rtl/
  doc/
```

## Running Scenarios
The active workflow is scenario-driven. Scenario launch scripts live under:
- `sim_core/scenarios/`

Examples:
- `sim_core/scenarios/run_3x3_msg_center_charge_probe.sh`
- `sim_core/scenarios/run_6x6_msg_rerouting_second_wave_probe.sh`

These scripts typically:
- build the required binaries
- generate startup/init/stimulus JSON inputs
- launch the live network
- write outputs under `build/<scenario_name>/`
- generate playback JSON for the visualizer

## Tools
Helper scripts live under:
- `sim_core/tools/`

Examples:
- `compile_startup_json.py`
- `generate_bootstrap_chip_id_readback_json.py`
- `generate_bootstrap_preconfigured_event_init_json.py`
- `larpix_uart.py`

## Visualizer
The active visualizer is:
- `sim_core/visualizers/packet_transmission/index.html`

Playback conversion tools are in the same directory.

## Notes
- This branch assumes a LArPix-like RTL contract rather than an arbitrary generic RTL.
- The active RTL-backed flow uses Verilator with top module `digital_core`.
- See `doc/` for architecture notes and onboarding/workflow documents.
