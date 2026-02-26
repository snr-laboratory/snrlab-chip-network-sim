# chip_network_sim

Inter-chip digital network simulator using:
- C99/C11 executables (`chip`, `orchestrator`)
- RTL FIFO (`rtl/chip_fifo_router.sv`) compiled by Verilator to `chip_rtl`
- `nng` transport for control/data channels
- Python helpers for JSON-configured launch

## Build
```bash
cmake -S . -B build
cmake --build build -j
```

The build links against local `nng` at:
- headers: `nng/include`
- shared lib: `nng/build/libnng.so`

Verilator build artifact:
- `build/chip_rtl` (uses RTL FIFO behavior)

## Run
Run directly with CLI:
```bash
./build/orchestrator -rows 4 -cols 4 -ticks 200 -sync barrier_ack -route east -chip_bin ./build/chip
```

Run with RTL backend:
```bash
./build/orchestrator -rows 4 -cols 4 -ticks 200 -sync barrier_ack -route east -chip_bin ./build/chip_rtl
```

Run from JSON config:
```bash
python3 scripts/run_from_config.py -cfg config/network_2x2.json
```

Single chip wrapper:
```bash
python3 scripts/chip_wrapper.py --chip-bin ./build/chip -- -id 5 -input 2 -out 8 -sync barrier_ack
```

## Sync Modes
- `barrier_ack`: every tick waits for `DONE` from all chips
- `windowed_ack`: waits every `ack_window` ticks
- `pubsub_only`: no per-tick acknowledgements

## Current Scope
- Runtime routing model is `1-in/1-out` per chip.
- FIFO full policy is drop-incoming with drop counter.
- Ingress arbitration is local-first when local and neighbor data arrive in the same tick.
