# Repository Guidelines

## Purpose
This repository implements an inter-chip digital network simulator.
Each chip entity is represented by a software runtime plus optional RTL-backed behavior (Verilator), and all chip entities are coordinated by the **Simulation Orchestrator**.

The design goal is deterministic, clocked, process-level simulation of a directional on-chip/off-chip network.

## Language and Implementation Guidance
- Prefer C99/C11 for core runtime and protocol logic.
- Do not discount C++ when necessary (for example Verilator integration and practical runtime glue in `chip_rtl`).
- Prefer struct-oriented design and explicit data flow over heavy abstraction.

## Functional Model
- Launch an `m x n` chip grid as parallel processes.
- Each chip has nearest-neighbor semantics; current runtime connectivity contract is `1-in/1-out` per chip.
- Routes are static for a run and defined at startup.
- Each chip:
  - pulls data from one configured upstream chip (or none),
  - forwards toward one configured downstream chip (or none),
  - generates sporadic local traffic,
  - arbitrates local-vs-neighbor ingress into a bounded FIFO.
- Tie-break rule is fixed: local-generated packet enqueues before neighbor packet when both are present in one tick.
- Full FIFO behavior is fixed: drop incoming packet and count drops.

## Why This Architecture Is Valid
- Process-per-chip + global tick gives deterministic digital-style execution while remaining scalable.
- `-input <chip_id>` and `-out <chip_id>` are logically sufficient in the current forwarding model.
- Reliable per-link request/reply data exchange avoids silent transport loss in the simulation data plane.
- Transactional control (`TICK`/`DONE`) provides strict lock-step and clear failure boundaries.

## Runtime Communication Contracts
### Control Plane (strict lock-step)
- Transport: `REQ/REP` between orchestrator and each chip.
- Per tick `seq`:
  1. Orchestrator sends `TICK(seq)` to all chips.
  2. Each chip executes exactly one modeled step.
  3. Each chip replies `DONE(seq)`.
  4. Orchestrator validates `(type, chip_id, seq)` for all chips before advancing.
- Shutdown: orchestrator sends `STOP(seq=ticks)` and requires `DONE(seq=ticks)` from all chips.

### Data Plane (reliable per-link)
- Downstream chip sends `DATA_PULL(seq)` to upstream chip.
- Upstream chip replies `DATA_REPLY(seq, has_packet, packet?)`.
- Sequence checks are mandatory for correctness.

## Frozen Interfaces
- CLI chip connectivity model: `-id`, `-input`, `-out`.
- Route schema: `routes[]` entries are `{id, input_id, out_id, gen_ppm?}`.
- Edge conventions:
  - `input_id = -1`: no upstream source.
  - `out_id = -1`: no downstream sink.
- FIFO ingress and overflow semantics are fixed as above.

## Backends
- `build/chip`: software FIFO path.
- `build/chip_rtl`: Verilated RTL FIFO/router path.
- Both backends must satisfy the same routing/FIFO invariants under identical config+seed.

## Trace (Minimal Binary)
Tracing is optional and enabled only when orchestrator receives `-trace_dir`.

Output layout:
- `traces/<run_id>/manifest.json`
- `traces/<run_id>/chip_<id>.tracebin`

Row schema (`24` bytes):
- `tick (u64)`
- `event_type (u16)`
- `reserved0 (u16)`
- `fifo_occupancy (u32)`
- `packet_word (u64)` at struct tail

Event set:
- `GEN_LOCAL`
- `ENQ_LOCAL_OK`
- `ENQ_LOCAL_DROP_FULL`
- `ENQ_NEIGH_OK`
- `ENQ_NEIGH_DROP_FULL`
- `DEQ_OUT`

## Validation Gates
- Determinism: same config + seed yields repeatable traces/metrics.
- Routing correctness: nearest-neighbor constraints and explicit map consistency hold.
- Lock-step correctness: exactly one valid `DONE(seq)` per chip per tick.
- FIFO correctness: ordering, local-first tie-break, and drop accounting.
- Backend parity: `build/chip` and `build/chip_rtl` satisfy shared invariants.
- Failure handling: orchestrator exits with clear diagnostics on timeout/protocol mismatch.

## Active Work Process
1. Keep protocol and CLI contracts stable unless a coordinated migration is explicitly planned.
2. Implement changes in both backends (or document intentional divergence).
3. Add/refresh deterministic checks and run build/tests.
4. Update docs (`README.md`, `doc/architecture.md`, `BENCHMARKS.md`, trace docs) whenever behavior/claims change.

## Definition of Done
- No regression in message contracts, route schema, or CLI behavior.
- `build/orchestrator`, `build/chip`, and `build/chip_rtl` compile and run.
- Touched behavior is validated and documented.
- Reproduction commands/configs for new results are committed or documented.

## Key Commands
- Build:
  - `cmake -S . -B build`
  - `cmake --build build -j`
- Test:
  - `ctest --test-dir build --output-on-failure`
- Config-driven run:
  - `python3 scripts/run_from_config.py -cfg config/network_3x4_snake_to_top_left.json`
- Trace reconstruction:
  - `python3 scripts/reconstruct_trace.py -run traces/<run_id> --top 20`
  - `python3 scripts/reconstruct_trace.py -run traces/<run_id> --plot-mode chip-lanes --plot-packets <packet_word> --plot-out <file>`
