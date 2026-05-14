# 1x2 Local-Priority Packet-Loss Test Report

- Config: `/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/config/network_1x2_priority_loss_test.json`
- Trace run: `traces/priority_loss_1x2/run_1772650434_2818623`
- Run log: `/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/reports/priority_loss_1x2/latest_run.log`

## Test Setup

- Topology: chip `0 -> 1`, with chip `1` as downstream sink (`out_id=-1`)
- Grid: `1x2` chips
- `gen_ppm`: `1,000,000` for both chips (generate every tick)
- `fifo_depth`: `2`
- `ticks`: `2000`

## Run-Level Metrics (orchestrator)

- delivered packets (`tx`): 1999
- received packets (`rx`): 1999
- locally generated packets (`local`): 4000
- total drops (`drops`): 1998
- fifo peak occupancy (`fifo_peak`): 2
- cycles/sec: 5220.575

## Packet Loss by Chip (from trace events)

| Chip | Local Enq OK | Neighbor Enq OK | Local Drops | Neighbor Drops | Total Drops | DEQ_OUT |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 2000 | 0 | 0 | 0 | 0 | 1999 |
| 1 | 2000 | 1 | 0 | 1998 | 1998 | 1999 |

## Sink Output Provenance (chip 1, DEQ_OUT events)

- Total sink output packets: 1999
- From chip 1 local traffic (`src_id=1`): 1998
- From chip 0 pass-through traffic (`src_id=0`): 1
- `src_id=0` packet `timestamp` values: `0`
- From other sources: 0

## Finding vs Expectation

- Result: PARTIAL/FAIL for the strict expectation.
- Observation: sink output includes at least one pass-through packet from chip 0.
- Interpretation: local-first priority does not block neighbor packets when capacity is available; with depth=2, one neighbor packet can still enter and later dequeue.
