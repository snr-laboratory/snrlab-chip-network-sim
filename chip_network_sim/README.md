# chip_network_sim

Public-facing LArPix network simulator for lock-step, process-level chip-network runs.

This repository now exposes only the LArPix simulator stack:
- `orchestrator_larpix`
- `chip_larpix`
- `fpga_larpix`
- `trace_collector_larpix`

The older generic packet/FIFO simulator has been retired from this repo.

## Build
```bash
cmake -S . -B build
cmake --build build -j
```

The build expects local `nng` artifacts at:
- `nng/include`
- `nng/build/libnng.so`

Primary runtime targets:
- `build/orchestrator_larpix`
- `build/fpga_larpix`
- `build/trace_collector_larpix`
- `build/chip_larpix` via `chip_larpix_build` when Verilator is available

## Run
Example single-chip startup/config readback flow:
```bash
./larpix_network_sim/scripts/run_1chip_fullreg_readback_startup.sh
```

Example single-chip event-generation flow:
```bash
./larpix_network_sim/scripts/run_1chip_event_startup.sh
```

Example multi-chip bootstrap/event flow:
```bash
./larpix_network_sim/scripts/run_3x5_bootstrap_id_startup.sh
./larpix_network_sim/scripts/run_3x5_event_top_right.sh
```

## Repository Layout
```text
chip_network_sim/
  CMakeLists.txt
  README.md
  larpix_network_sim/
    config/     # startup schedules, stimulus inputs, workflow notes
    include/    # chipsim + larpixsim public headers used by the live runtime
    scripts/    # startup generation and run scripts
    src/        # orchestrator, chip runtime, FPGA runtime, trace collector
    larpix_v3b_rtl/  # reference RTL tree used by the cosim backend
  doc/
    README.md
    architecture.md
```

## Runtime Model
- One process per chip plus an optional FPGA/controller process.
- Global lock-step control over `TICK` / `DONE`.
- Four-edge bit-serial nearest-neighbor communication.
- Verilated digital core with a software analog front-end model.
- Optional JSONL trace collection plus occupancy/debug CSV capture.

## Documentation
- [doc/README.md](doc/README.md)
- [doc/architecture.md](doc/architecture.md)
- [larpix_network_sim/config/WORKFLOW.md](larpix_network_sim/config/WORKFLOW.md)
- [larpix_network_sim/config/CONFIGURATION_TESTS.md](larpix_network_sim/config/CONFIGURATION_TESTS.md)
