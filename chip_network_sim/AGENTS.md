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
- Clock advancement shall be orchestrated by transactional control messages from the orchestrator (`TICK`/`STOP` request, `DONE` response).
- Local data generation shall be implemented in software domain, sporadically, and randomly.  It is fed into one of the RTL input ports.

### Orchestrator
- Orchestrator is responsible for generating a series of launch commands using the pattern `./chip -id 5 -input 2`, and generate correct arguments to establish desired network connectivity.
- We use ZeroMQ (preferably its successor nng) to do communication.
- Orchestrator shall send per-chip control requests so all parallel-running chip instances advance in lock step.
- Orchestrator collects metrics.

## Validity Assessment
- The process-per-chip model and single global clock are valid for deterministic digital simulation.
- RTL with two inputs and one output is valid for this design: one neighbor input plus one local input, with one configured outgoing direction.
- `-input <chipID>` is sufficient for runtime connectivity because each chip has exactly one upstream source in this model.
- Clock synchronization uses one fixed transactional lock-step protocol: `TICK(seq)` request and `DONE(seq)` response, plus `STOP(seq)` termination request.
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
- Control-plane lock-step handshake is fixed:
  - per tick: orchestrator sends `TICK(seq)` to each chip and waits for `DONE(seq)` from each chip.
  - shutdown: orchestrator sends `STOP(seq=ticks)` to each chip and waits for `DONE(seq=ticks)`.
- Data-plane handshake is fixed:
  - downstream chip sends `DATA_PULL(seq)` to upstream chip.
  - upstream chip replies `DATA_REPLY(seq, has_packet, packet?)`.
- FIFO ingress tie-break is fixed: local-generated data is enqueued before neighbor data when both arrive in the same tick.
- FIFO full behavior is fixed: drop incoming data and count drops.

## Lock-Step Logic (`TICK` / `STOP` / `DONE`)
- Transport: orchestrator opens one `REQ` control socket per chip; each chip listens with one `REP` socket.
- Tick transaction (`seq = 0..ticks-1`):
  1. Orchestrator builds `TICK(seq)`.
  2. Orchestrator sends `TICK(seq)` to all chips.
  3. Each chip executes exactly one modeled tick.
  4. Each chip responds `DONE(seq, chip_id, counters, fifo_occupancy)`.
  5. Orchestrator validates `type == DONE`, `chip_id`, and `seq` for every chip.
  6. Only after all `DONE(seq)` are accepted does orchestrator start `seq + 1`.
- Stop transaction:
  1. Orchestrator sends `STOP(seq=ticks)` to all chips.
  2. Each chip replies `DONE(seq=ticks)`.
  3. After all stop acks arrive, chips push final `METRIC`; orchestrator collects all metrics and exits.

## Reliability Direction
- Inter-chip data plane uses an acknowledged protocol.
- Preferred target: per-link `REQ/REP` with explicit `seq`/`tick` and `ACK`, plus duplicate suppression by sequence ID.
- Clock tick distribution should also use guaranteed delivery semantics.
- `DONE` reporting should be folded into reliable control handshake (or otherwise acknowledged/retried), not left as fire-and-forget.
- Goal: no silent message loss; any delivery failure must be detected and surfaced as an explicit simulation error.
- Status:
  - Implemented: control plane uses per-chip transactional `REQ/REP` (`TICK` request -> `DONE` response).
  - Implemented: inter-chip data plane uses per-link `REQ/REP` (`DATA_PULL(seq)` request -> `DATA_REPLY(seq)` response).

## Execution Plan
1. Add reliable transport contracts:
   - Data request/ack schema with sequence numbers.
   - Control request/ack schema for `TICK`/`DONE`/`STOP`.
   - Retry/timeout policy and duplicate handling rules.
2. Implement control-plane reliability first:
   - Keep per-chip reliable request/response for control ticks.
   - Keep `DONE` in response payload (no separate best-effort path).
3. Implement inter-chip data reliability with per-link `REQ/REP` and per-tick sequence validation.
4. Freeze remaining contracts: packet bit layout (`N/A/B/C`), CLI options, config schema.
5. Build primitives: packet codec and C FIFO with tests for ordering, overflow, and counters.
6. Implement RTL FIFO/router (2-input, 1-output, local-first arbitration), Verilate, and produce `build/chip_rtl`.
7. Keep dual runtime variants:
   - `build/chip`: software FIFO path.
   - `build/chip_rtl`: Verilated RTL FIFO path.
8. Implement orchestrator topology compilation for `m x n` and explicit per-chip routes.
9. Keep one control mode only: strict transactional lock-step (`TICK(seq)`/`DONE(seq)`, `STOP`/`DONE`) with timeout/abort policy.
10. Add metrics and diagnostics: throughput, FIFO occupancy, drops, stalls, retry counts, and timing breakdown.
11. Validate with deterministic seeds and golden route tests (`2x2`, `3x3`, then larger grids), including `chip` vs `chip_rtl` parity checks.

## Validation Gates
- Protocol checks: reject malformed packet width/field mappings at startup.
- Determinism: same config + seed must match traces/metrics in lock-step mode.
- FIFO correctness: no reorder; local-first tie-break; drop-on-full accounting matches counters.
- Routing correctness: expected path traces on fixed small topologies.
- Sync correctness:
  - exactly one `DONE(seq)` response per chip per `TICK(seq)`;
  - orchestrator never advances `seq` until all chips reply;
  - exactly one `DONE(seq=ticks)` response per chip for `STOP`.
- Reliable transport correctness:
  - no silent loss under normal operation;
  - duplicates tolerated and deduplicated by sequence ID;
  - timeout/retry behavior deterministic and bounded.
- Backend parity: `build/chip` vs `build/chip_rtl` satisfy packet-trace invariants on same seeds.
- Build/runtime gate: Verilator artifact `build/chip_rtl` must exist and run.
- Fault handling: orchestrator detects dead/stalled chip and exits with clear diagnostics.
- Performance gate: record ticks/sec, CPU, memory, drop/stall rates for target grid sizes.

## Definition of Done
- Interface stability: changes do not break frozen CLI/config contracts (`routes[{id,input_id,out_id,gen_ppm?}]`, `-1` edge semantics, lock-step control message schema).
- Build success: `build/orchestrator`, `build/chip`, and when applicable `build/chip_rtl` compile and run.
- Correctness checks: touched behavior is covered by deterministic tests and relevant validation gates above.
- Metrics visibility: runs produce clear throughput/drop/FIFO statistics; lock-step control behavior is observable in logs.
- Documentation updates: `README.md`, `BENCHMARKS.md`, and `doc/architecture.md` are updated when behavior, interfaces, or performance claims change.
- Reproducibility: commands/configs needed to reproduce new results are committed or documented.

## Implementation Notes
- Prefer acknowledged transport (`REQ/REP` or equivalent) for both control (`TICK/DONE/STOP`) and inter-chip data paths.
- Any optional pub/sub observer channel must be treated as telemetry only, not as the source of truth for correctness.
- Keep launch commands explicit, e.g.:
  - `./chip -id 5 -input 2 -out 8 -cfg chip_5.json`
  - `./build/orchestrator -rows 4 -cols 4 -ticks 200 -chip_bin ./build/chip_rtl`
  - `python3 scripts/run_from_config.py -cfg config/network_3x4_snake_to_top_left.json`

## Chip ID Assignment
- IDs are row-major in the grid: `id = row * cols + col`.
- Example for `3x4`:
  - row 0: `0 1 2 3`
  - row 1: `4 5 6 7`
  - row 2: `8 9 10 11`
