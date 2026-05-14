# 2x2 Single-Packet Transfer Report (BR -> TR, all 4 chips)

- Config: `config/network_2x2_single_packet_br_to_tr_all4.json`
- Trace run: `traces/single_packet_2x2_br_to_tr_all4/run_1772821598_2723310`
- FIFO depth: `2`
- Ticks simulated: `11` (generation tick + 10 additional ticks)
- Generated packet word: `0x000300000044b65a`
- Route traversed: `3 -> 2 -> 0 -> 1`

## Packet Event Timeline

| Tick | Chip | Event | FIFO Occupancy |
| ---: | ---: | --- | ---: |
| 0 | 3 | `GEN_LOCAL` | 0 |
| 0 | 3 | `ENQ_LOCAL_OK` | 1 |
| 1 | 3 | `DEQ_OUT` | 0 |
| 1 | 2 | `ENQ_NEIGH_OK` | 1 |
| 2 | 2 | `DEQ_OUT` | 0 |
| 2 | 0 | `ENQ_NEIGH_OK` | 1 |
| 3 | 0 | `DEQ_OUT` | 0 |
| 3 | 1 | `ENQ_NEIGH_OK` | 1 |
| 4 | 1 | `DEQ_OUT` | 0 |

## Inter-Chip Transfer Ticks

| Link | Sender `DEQ_OUT` Tick | Receiver `ENQ_NEIGH_OK` Tick | Delta (ticks) |
| --- | ---: | ---: | ---: |
| `3 -> 2` | 1 | 1 | 0 |
| `2 -> 0` | 2 | 2 | 0 |
| `0 -> 1` | 3 | 3 | 0 |
