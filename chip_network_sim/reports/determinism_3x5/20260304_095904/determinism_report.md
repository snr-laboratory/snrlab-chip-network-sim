# Determinism Test Report (3x5 Snake BR->TL)

- Config: `/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/config/network_3x5_determinism_snake_br_to_tl.json`
- Runs: 1
- Deterministic behavior check (`delivered_tx + total_drops + per_chip_drops`): **PASS**
- Full output check (including `cycles_per_sec`): **PASS**

## Per-run Results

| Run | Delivered Packets (tx) | Total Drops | Cycles/sec | Per-chip Drops (chip_id:count) | Behavior Match vs Run1 | Full Match vs Run1 |
| --- | ---: | ---: | ---: | --- | --- | --- |
| 1 | 261827 | 0 | 2316.508 | `0:0,1:0,2:0,3:0,4:0,5:0,6:0,7:0,8:0,9:0,10:0,11:0,12:0,13:0,14:0` | yes | yes |
