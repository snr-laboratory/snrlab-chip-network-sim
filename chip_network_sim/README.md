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

Benchmark report:
- `BENCHMARKS.md`
- `doc/architecture.md` (render with `cd doc && make html`)
- `doc/README.md` (documentation index and build guide)

## Run
Run directly with CLI:
```bash
./build/orchestrator -rows 4 -cols 4 -ticks 200 -route east -chip_bin ./build/chip
```

Run with RTL backend:
```bash
./build/orchestrator -rows 4 -cols 4 -ticks 200 -route east -chip_bin ./build/chip_rtl
```

Run from JSON config:
```bash
python3 scripts/run_from_config.py -cfg config/network_3x4_snake_to_top_left.json
```

Run with explicit per-chip routing map:
```bash
python3 scripts/run_from_config.py -cfg config/network_2x2_custom_routes.json
```

Determinism test (3x5 snake, bottom-right to top-left):
```bash
./scripts/run_determinism_3x5.sh
```
- Uses config: `config/network_3x5_determinism_snake_br_to_tl.json`
- Fixed parameters in that config:
  - grid `3x5`
  - per-chip `gen_ppm=50000` for all 15 chips
  - `fifo_depth=64`
  - fixed `seed=424242`
- Default run count is 15; override with:
```bash
RUNS=15 ./scripts/run_determinism_3x5.sh
```
- Script writes outputs under:
  - `reports/determinism_3x5/<timestamp>/results.tsv`
  - `reports/determinism_3x5/<timestamp>/determinism_report.md`
- Report includes, per run:
  - delivered packets (`tx`)
  - total drops
  - per-chip drop counts
  - cycles/sec
  - deterministic pass/fail checks across all runs

Run with packet tracing enabled:
```bash
./build/orchestrator -rows 2 -cols 2 -ticks 100 -route east -chip_bin ./build/chip \
  -trace_dir traces -trace_run_id demo_run
python3 scripts/reconstruct_trace.py -run traces/demo_run --top 10
python3 scripts/reconstruct_trace.py -run traces/demo_run --plot-top 4 \
  --plot-out traces/demo_run/packet_history.txt
# Or select explicit packet words:
python3 scripts/reconstruct_trace.py -run traces/demo_run \
  --plot-packets 0x00000000096002cb,0x000000000ab84b8a \
  --plot-out traces/demo_run/packet_history_selected.txt
# Chip-lane view for one packet (columns are chips c0..cN):
python3 scripts/reconstruct_trace.py -run traces/demo_run \
  --plot-mode chip-lanes --plot-packets 0x00000000096002cb \
  --plot-compact-range --plot-cell-width 6 \
  --plot-out traces/demo_run/packet_history_chip_lanes.txt
# Default plot range is full run tick span (0..ticks-1).
# Use compact range only around selected packet activity:
python3 scripts/reconstruct_trace.py -run traces/demo_run --plot-top 4 \
  --plot-compact-range --plot-out traces/demo_run/packet_history_compact.txt
```

Single chip wrapper:
```bash
python3 scripts/chip_wrapper.py -- -id 5 -input 2 -out 8
python3 scripts/chip_wrapper.py --rtl -- -id 5 -input 2 -out 8
```

## Lock-Step Control (`TICK`, `STOP`, `DONE`)
- There is one control protocol only: transactional `REQ/REP` lock-step.
- Per simulation tick `seq`:
  - orchestrator sends `TICK(seq)` to every chip control socket,
  - each chip executes exactly one modeled tick and replies `DONE(seq)`,
  - orchestrator verifies `chip_id` and `seq` for every reply before moving to the next tick.
- Shutdown sequence:
  - orchestrator sends `STOP(seq=ticks)` to every chip,
  - each chip replies `DONE(seq=ticks)`,
  - each chip pushes one final `METRIC` message.

## Current Scope
- Runtime routing model is `1-in/1-out` per chip.
- Inter-chip data transport is reliable pull/response per link (`REQ/REP`) with per-tick `seq` validation.
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
- Optional minimal packet tracing:
  - per-chip binary files under `traces/<run_id>/chip_<id>.tracebin`,
  - fixed 24-byte rows (`tick`, `event_type`, `fifo_occupancy`, `packet_word`),
  - run manifest at `traces/<run_id>/manifest.json`.

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
