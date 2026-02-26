# Repository Guidelines

## Purpose
This directory implements an inter-chip digital network simulator.
Each simulated chip is represented by:
- a Python wrapper, and
- C/C++ generated from RTL via Verilator.

Use the term **Simulation Orchestrator** for the top-level launcher.

- We use ZeroMQ (preferably its successor nng) to do communication.
- Verilator, python, C compilers are available and directly callable from the environment.
- When C/C++ is used, we strongly prefer pure C99/C11 instead of C++.  Use struct {} based "objects" extensively.

## Functional Requirements
- Launch an `m x n` grid of chip entities for concurrent simulation.
- Each chip has up to 4 nearest neighbors: north, south, east, west.
- Data links are directional (one-way per configured route).
- Route direction is statically configured at simulation start.
- Each chip forwards data it receives according to route configuration.
- Each chip also generates its own sporadic data stream.
- Every data unit carries chip identity metadata (at least source chip ID).
- Each chip includes a local FIFO buffer for incoming/outgoing flow control.
- For explicit per-chip routing maps, use:
  - `input_id = -1` for chips with no upstream neighbor input (edge/source node).
  - `out_id = -1` for chips with no downstream neighbor target (edge/sink node).
  - `gen_ppm` may be attached per route entry to override local generation rate for that chip.

### RTL implemented chip behavior
- Data format: each data word (N-bit wide) contains A-bit wide chip ID, B-bit wide time stamp, and C-bit wide payload
- RTL shall implement two input ports and one output port.  All ports should be N-bit wide.
  - One port is for neighbor's data coming in, another port is for locally generated data to enter, the output port will push data to the next chip.
- The central structure is a FIFO.  Additional logic shall push data from both input ports into the FIFO without data loss.
- The entire chip (and the entire chip array) runs on a single clock.  There's no clock domain crossing anywhere.

### Python and C/C++ wrap around RTL for single chip entity
- Python and C/C++ wrapper shall prepare single chip simulation launch in an easy manner.
- For instance, if I run `./chip -id 5 -input 2`, it should launch a single chip simulation designating its own chip id to be 5, and expect data input from chip id 2
- Each chip shall publish output data via nng.  It shall take data published by another chip specified by `-input` through nng subscription.
- Clock advancement shall be orchestrated by subscribing to the orchestrator's published clock message.
- Local data generation shall be implemented in software domain, sporadically, and randomly.  It is fed into one of the RTL input ports.

### Orchestrator
- Orchestrator is responsible for generating a series of launch commands using the pattern `./chip -id 5 -input 2`, and generate correct arguments to establish desired network connectivity.
- We use ZeroMQ (preferably its successor nng) to do communication.
- Orchestrator shall publish clock message so all parallel-running chip instances advance in sync.
- Orchestrator collects metrics.

## Validity Assessment
- The process-per-chip model and single global clock are valid for deterministic digital simulation.
- RTL with two inputs and one output is valid for this design: one neighbor input plus one local input, with one configured outgoing direction.
- `-input <chipID>` is sufficient for runtime connectivity because each chip has exactly one upstream source in this model.
- Clock synchronization must support three launch-selectable modes: `barrier_ack`, `pubsub_only`, and `windowed_ack`.
- "No data loss" is interpreted as no unintended software loss; finite FIFO overflow behavior must be explicit (`drop incoming + count`).

## Proposed Architecture
- `config/`: Grid dimensions, chip IDs, static routes, FIFO depth, random seed, runtime limits. Support both global route mode and explicit per-chip route map.
- `protocol/`: Message schemas (`PACKET`, `TICK`, `DONE`, `METRIC`) and serialization.
- `chip/rtl/`: Verilated core wrapper (C99 interface), reset/tick/input/output shims.
- `chip/runtime/`: nng sockets, local sporadic generator, FIFO adapter, step execution.
- `orchestrator/`: Topology compiler, process launcher, tick barrier, failure handling.
- `metrics/`: Aggregation and reporting (throughput, latency, queue occupancy, drops, stalls).
- `tests/`: Unit, integration, deterministic replay, and scale smoke tests.

## Frozen Interfaces
- Connectivity model is `1-in/1-out` per chip: `-input <chipID>` plus `-out <chipID>`.
- Config route schema is `routes[]` with `{id, input_id, out_id, gen_ppm?}`.
- Edge conventions are fixed:
  - `input_id = -1`: no upstream source.
  - `out_id = -1`: no downstream sink target.
- Supported sync modes are fixed: `barrier_ack`, `windowed_ack`, `pubsub_only`.
- FIFO ingress tie-break is fixed: local-generated data is enqueued before neighbor data when both arrive in the same tick.
- FIFO full behavior is fixed: drop incoming data and count drops.

## Execution Plan
1. Freeze contracts: packet bit layout (`N/A/B/C`), CLI options, config schema, and tick sequence protocol.
2. Build primitives: packet codec and C FIFO with tests for ordering, overflow, and counters.
3. Implement RTL FIFO/router (2-input, 1-output, local-first arbitration), Verilate, and produce `build/chip_rtl`.
4. Keep dual runtime variants:
   - `build/chip`: software FIFO path.
   - `build/chip_rtl`: Verilated RTL FIFO path.
5. Implement orchestrator topology compilation for `m x n` and explicit per-chip routes.
6. Implement sync modes with timeout/abort policy:
   - `barrier_ack`: strict per-tick `DONE`.
   - `windowed_ack`: barrier every `ack_window`.
   - `pubsub_only`: no per-tick `DONE`.
7. Add metrics and diagnostics: throughput, FIFO occupancy, drops, stalls, and timing breakdown.
8. Validate with deterministic seeds and golden route tests (`2x2`, `3x3`, then larger grids), including `chip` vs `chip_rtl` parity checks.

## Validation Gates
- Protocol checks: reject malformed packet width/field mappings at startup.
- Determinism: same config + seed must match traces/metrics in `barrier_ack` and `windowed_ack`.
- FIFO correctness: no reorder; local-first tie-break; drop-on-full accounting matches counters.
- Routing correctness: expected path traces on fixed small topologies.
- Sync correctness:
  - `barrier_ack`: one `DONE(seq)` per chip per tick.
  - `windowed_ack`: one `DONE(seq)` per chip at barrier ticks.
  - `pubsub_only`: no `DONE` dependency; monitor drift/stall counters.
- Backend parity: `build/chip` vs `build/chip_rtl` satisfy packet-trace invariants on same seeds.
- Build/runtime gate: Verilator artifact `build/chip_rtl` must exist and run.
- Fault handling: orchestrator detects dead/stalled chip and exits with clear diagnostics.
- Performance gate: record ticks/sec, CPU, memory, drop/stall rates for target grid sizes.

## Definition of Done
- Interface stability: changes do not break frozen CLI/config contracts (`routes[{id,input_id,out_id,gen_ppm?}]`, `-1` edge semantics, sync-mode names).
- Build success: `build/orchestrator`, `build/chip`, and when applicable `build/chip_rtl` compile and run.
- Correctness checks: touched behavior is covered by deterministic tests and relevant validation gates above.
- Metrics visibility: runs produce clear throughput/drop/FIFO statistics; sync-mode behavior is observable in logs.
- Documentation updates: `README.md`, `BENCHMARKS.md`, and `doc/architecture.md` are updated when behavior, interfaces, or performance claims change.
- Reproducibility: commands/configs needed to reproduce new results are committed or documented.

## Implementation Notes
- Prefer nng request/reply or pair channels for `TICK/DONE`; use pub/sub for data fanout.
- Keep launch commands explicit, e.g.:
  - `./chip -id 5 -input 2 -out 8 -cfg chip_5.json -sync barrier_ack`
  - `./build/orchestrator -rows 4 -cols 4 -ticks 200 -sync barrier_ack -chip_bin ./build/chip_rtl`
  - `python3 scripts/run_from_config.py -cfg config/network_3x4_snake_to_top_left.json`

## Chip ID Assignment
- IDs are row-major in the grid: `id = row * cols + col`.
- Example for `3x4`:
  - row 0: `0 1 2 3`
  - row 1: `4 5 6 7`
  - row 2: `8 9 10 11`
