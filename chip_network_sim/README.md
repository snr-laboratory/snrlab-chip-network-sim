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

Run with explicit per-chip routing map:
```bash
python3 scripts/run_from_config.py -cfg config/network_2x2_custom_routes.json
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
- Routing config supports:
  - global direction via `runtime.route` (`east|west|south|north`)
  - explicit per-chip map via `routes: [{id, input_id, out_id, gen_ppm?}, ...]`
- Traffic generation supports:
  - global default via `traffic.gen_ppm`
  - per-chip override via `routes[].gen_ppm`
- Edge node conventions in explicit routing:
  - `input_id: -1` means this chip has no upstream neighbor input.
  - `out_id: -1` means this chip has no downstream neighbor output target.
- FIFO full policy is drop-incoming with drop counter.
- Ingress arbitration is local-first when local and neighbor data arrive in the same tick.

## Chip ID Layout
Chip IDs are row-major:
- `id = row * cols + col`

Example for `rows=3, cols=4`:
```text
+----+----+----+----+
|  0 |  1 |  2 |  3 |
+----+----+----+----+
|  4 |  5 |  6 |  7 |
+----+----+----+----+
|  8 |  9 | 10 | 11 |
+----+----+----+----+
```
