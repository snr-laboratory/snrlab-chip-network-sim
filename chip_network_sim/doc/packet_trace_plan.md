# Packet Trace Plan (Minimal Binary)

## Goal
Track packet lifecycle with minimal runtime overhead and minimal disk footprint.
Trace metadata stays outside packet payload.

## Storage Model
- One append-only binary file per chip per run.
- No in-place updates.
- Little-endian encoding.
- Fixed-size row format for fast sequential IO.

Directory layout:
- `traces/<run_id>/manifest.json`
- `traces/<run_id>/chip_<id>.tracebin`

## File Header
Use a small fixed header with:
- magic (`"CTRACE01"`),
- version (`v1`),
- `record_size`,
- `chip_id`,
- reserved bytes.

## Record Schema (v1)
The v1 row is 24 bytes:

```c
typedef struct {
    uint64_t tick;
    uint16_t event_type;
    uint16_t reserved0;
    uint32_t fifo_occupancy;
    uint64_t packet_word; // keep at tail for future extension
} chipsim_trace_row_v1_t;
```

Rules:
- `packet_word` remains the last field.
- `tick` is global simulation tick.
- `fifo_occupancy` is occupancy after the event.

## Event Types
Required v1 events:
- `GEN_LOCAL`
- `ENQ_LOCAL_OK`
- `ENQ_LOCAL_DROP_FULL`
- `ENQ_NEIGH_OK`
- `ENQ_NEIGH_DROP_FULL`
- `DEQ_OUT`

## Write/Order Rules
- Single writer queue per chip.
- Runtime threads emit to queue; one writer serializes to file.
- File order is authoritative local order for equal tick values.

## Reconstruction
Offline tool flow:
1. Load manifest and all chip trace files.
2. Merge rows by `(tick, chip_id, local_file_order)`.
3. Reconstruct packet timelines using `packet_word`.
4. Compute hop count, sink/reachability, and drop points.

## Validation
- Deterministic run with same config/seed yields identical traces.
- Local-first FIFO tie-break is observable in same-tick events.
- Drop counters in metrics match `*_DROP_FULL` event counts.
