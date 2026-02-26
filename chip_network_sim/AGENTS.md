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
- `config/`: Grid dimensions, chip IDs, static routes, FIFO depth, random seed, runtime limits.
- `protocol/`: Message schemas (`PACKET`, `TICK`, `DONE`, `METRIC`) and serialization.
- `chip/rtl/`: Verilated core wrapper (C99 interface), reset/tick/input/output shims.
- `chip/runtime/`: nng sockets, local sporadic generator, FIFO adapter, step execution.
- `orchestrator/`: Topology compiler, process launcher, tick barrier, failure handling.
- `metrics/`: Aggregation and reporting (throughput, latency, queue occupancy, drops, stalls).
- `tests/`: Unit, integration, deterministic replay, and scale smoke tests.

## Revised Work Breakdown
1. **Contracts first**: freeze packet bit layout (`N/A/B/C`), CLI/config schema, and tick protocol with sequence numbers.
2. **Core primitives**: implement FIFO and packet codec with unit tests for ordering, full/empty, overflow behavior.
3. **RTL FIFO first**: implement FIFO/router RTL (two inputs, one output, local-first arbitration) and compile it with Verilator.
4. **Single-chip runtime variants**: keep software `chip` path and add `chip_rtl` runtime that drives the verilated FIFO model.
5. **Orchestrator sync modes**: implement launch control for `barrier_ack`, `pubsub_only`, and `windowed_ack` with timeout + abort policy.
6. **Topology wiring**: compile `m x n` routes into chip startup args and endpoint map.
7. **Traffic model**: add sporadic local generation with deterministic RNG seed control.
8. **Metrics pipeline**: collect per-tick and end-of-run stats; emit machine-readable report.
9. **Scale and hardening**: run increasing grid sizes, profile bottlenecks, and tune transport settings.

## Validation Methods
- **Protocol checks**: reject malformed packet width/field mappings at startup.
- **Determinism test**: identical seed + config must produce identical packet traces and metrics.
- **Routing correctness**: golden tests on small grids (`2x2`, `3x3`) with known expected paths.
- **Sync correctness**:
  - `barrier_ack`: all chips report `DONE(seq)` exactly once per tick.
  - `windowed_ack`: all chips report `DONE(seq)` exactly once per configured window.
  - `pubsub_only`: no `DONE` requirement; monitor drift/stall counters.
- **FIFO correctness**: verify no reorder, local-first ingress priority, and overflow counter behavior.
- **RTL parity**: compare `chip` vs `chip_rtl` runs on same seed/config; enforce matching packet-trace invariants.
- **Verilator build gate**: CI/local build must produce runnable `chip_rtl` artifact before integration tests.
- **Fault handling**: kill one chip process and verify orchestrator detects and exits with clear diagnostics.
- **Performance gate**: for each target grid size, record ticks/sec, CPU, memory, drop/stall rates.

## Implementation Notes
- Prefer nng request/reply or pair channels for `TICK/DONE`; use pub/sub primarily for data fanout.
- Keep command examples explicit, e.g.:
  - `./chip -id 5 -input 2 -out 8 -cfg chip_5.json -sync barrier_ack`
  - `./build/orchestrator -rows 4 -cols 4 -ticks 200 -sync barrier_ack -chip_bin ./build/chip_rtl`
  - `./orchestrator -cfg network_8x8.json`

## Decision-Complete Execution Plan
Locked design decisions:
- Runtime connectivity is `1-in/1-out`; `-input <chipID>` is sufficient for each chip.
- FIFO ingress arbitration is deterministic: local-generated data enters before neighbor data when both are present in the same cycle.
- Sync mode is launch-selectable and must support `barrier_ack`, `pubsub_only`, and `windowed_ack`.

1. Freeze contracts: packet bit layout (`N/A/B/C`), `chip`/`orchestrator` CLI, config schema, and sync-mode options.
2. Build core primitives: packet codec and FIFO (C99), including local-first ingress arbitration and drop counters.
3. Implement RTL FIFO/router and compile with Verilator to produce `chip_rtl`.
4. Implement `chip` (software FIFO) and `chip_rtl` (verilated FIFO) runtime variants under shared protocol/CLI.
5. Implement orchestrator launch/topology compiler for `m x n` grids under `1-in/1-out` routing.
6. Implement clock-sync modes:
   - `barrier_ack`: strict per-tick `TICK(seq)` -> `DONE(id, seq)` barrier.
   - `pubsub_only`: broadcast tick without per-tick wait.
   - `windowed_ack`: barrier every `N` ticks.
7. Add metrics and diagnostics: throughput, latency, FIFO occupancy, drops, stalls, timeout/fault events.
8. Validate with deterministic seeds and golden traces (`2x2`, `3x3`, then larger scale), including `chip` vs `chip_rtl` parity checks.

## Validation Gate Criteria
- Same config + seed gives identical traces/metrics in `barrier_ack` and `windowed_ack`.
- FIFO guarantees preserved: no reorder, correct drop-on-full accounting, local-first tie-break.
- Verilator artifact exists and runs: `build/chip_rtl`.
- Routing correctness on fixed topologies with known expected packet paths.
- Sync invariants met per selected mode; dead/stalled chip detected and reported clearly.
