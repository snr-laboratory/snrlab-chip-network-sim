# Packet Loss At RX: `v3b` vs `v3b2`

## Summary

This note records the packet-loss investigation performed with the dedicated `2x2` chip network. During the simulation, all 64 channels on chips 1 and 2 were injected with cahrge, leadind to the formation of 128 unique packets within the network. Both chips simultaneously feed data packets into the source chip, chip 0, through RX lanes north and east.

The baseline `v1` result was:

- chip `0` receives all `64` packets from chip `2` on its `north` RX lane
- chip `0` receives all `64` packets from chip `1` on its `east` RX lane
- chip `0` forwards only `64` packets onward
- the FPGA sees only one source stream

The final `v2` result is now:

- chip `0` receives all `64` north packets and all `64` east packets
- chip `0` forwards all `128` packets onward
- the FPGA receives all `128` packets
- the shared FIFO drains completely by the end of the run

So the current conclusion is:

- the `v1` packet loss was real RTL behavior in the shared `Hydra -> comms_ctrl -> FIFO -> TX` path
- the `v2` RTL changes removed the forwarding-path mismatches seen in `v1`

## Tests Used

### Baseline `v1`

Runner script:

- [run_2x2_packet_loss_probe.sh](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/sim_core/scenarios/run_2x2_packet_loss_probe.sh)

Artifacts:

- [run.log](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_2x2_packet_loss_probe/run.log)
- [trace.jsonl](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_2x2_packet_loss_probe/trace.jsonl)
- [chip0_rx_debug.csv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_2x2_packet_loss_probe/chip0_rx_debug.csv)
- [packet_loss_summary.json](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_2x2_packet_loss_probe/packet_loss_summary.json)
- [live_event_2x2_packet_loss_probe.json](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_2x2_packet_loss_probe/live_event_2x2_packet_loss_probe.json)

### Modified `v2`

Runner script:

- [run_2x2_packet_loss_probe_v2.sh](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/sim_core/scenarios/run_2x2_packet_loss_probe_v2.sh)

Artifacts:

- [run.log](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_2x2_packet_loss_probe_v2/run.log)
- [trace.jsonl](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_2x2_packet_loss_probe_v2/trace.jsonl)
- [chip0_rx_debug.csv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_2x2_packet_loss_probe_v2/chip0_rx_debug.csv)
- [packet_loss_summary.json](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_2x2_packet_loss_probe_v2/packet_loss_summary.json)
- [live_event_2x2_packet_loss_probe_v2.json](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_2x2_packet_loss_probe_v2/live_event_2x2_packet_loss_probe_v2.json)

`v2` is the same `2x2` probe rerun against the alternate RTL tree in `rtl/v3b_v2/src/`. The primary RTL tree in `rtl/v3b/src/` remains the `v1` baseline.

## Probe Topology

```text
  y=1:  2  3
  y=0:  0  1
```

Where:

- chip `0` is the source chip and FPGA-facing sink path
- chip `1` injects all `64` channels at tick `1000`
- chip `2` injects all `64` channels at tick `1000`

This forces two simultaneous return streams into chip `0`:

- chip `2` -> chip `0` on chip `0`'s `north` RX lane
- chip `1` -> chip `0` on chip `0`'s `east` RX lane

## What Was Measured

The probe records:

1. Per-chip packet trace
- `rx_packet`
- `tx_packet`

2. FPGA receive log
- all packets printed by `fpga_larpix`

3. Per-tick chip-0 internal state sampled from the Verilated model
- Hydra FSM state and next state
- selected lane and unload mask
- live Hydra `rx_data`
- `comms_ctrl` `rcvd_pkt` and `read_pkt`
- per-lane `rx_empty`, `hold_valid`, `rx_data`, `hold_reg`
- Hydra FIFO state
  - `fifo_rd_data`
  - `read_pointer`
  - `write_pointer`
  - `fifo_counter`
  - `fifo_mem0`
  - `fifo_mem1`
  - `fifo_read_n`
  - internal `fifo_write_n`

## Baseline `v1` Results

### Packet counts

From the trace and FPGA log:

- chip `0` RX on `north`: `64` packets
- chip `0` RX on `east`: `64` packets
- chip `0` TX onward: `64` packets
- FPGA arrivals: chip `2` only

So the loss was not:

- chip `1` failing to generate data
- chip `1` failing to reach chip `0`

The loss was specifically that chip `0` did not forward both streams onward.

### RX hold-buffer status

From `chip0_rx_debug.csv`:

- `north_hold_valid` never asserts
- `east_hold_valid` never asserts

So the baseline `2x2` case was not explained by visible lane-local `hold_reg` overflow.

## `v1` Hydra Finding

The baseline `v1` debug rows show that Hydra can change the selected lane and unload that lane without updating the internal packet presented to `comms_ctrl`.

Hydra state encoding from [hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/rtl/v3b/src/hydra_ctrl.sv):

- `0` = `IDLE`
- `1` = `RX_CAPTURE`
- `2` = `RX_PROCESS`
- `3` = `TX_UPSTREAM`
- `4` = `TX_GET_FIFO`
- `5` = `TX_SEND`

Representative `v1` rows from [chip0_rx_debug.csv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_2x2_packet_loss_probe/chip0_rx_debug.csv):

|tick|hydra_state|hydra_next_state|hydra_sel_onehot|hydra_uld_rx_data_uart|hydra_rx_data_word|hydra_comms_rcvd_pkt|north_rx_data|east_rx_data|
|---|---|---|---|---|---|---|---|---|
|1082|0|1|0x1|0x0|0x0000000000000000|0x0000000000000000|0xd058c80003e80009|0xd058c80003e80005|
|1083|1|2|0x1|0x0|0xd058c80003e80009|0x0000000000000000|0xd058c80003e80009|0xd058c80003e80005|
|1084|2|1|0x1|0x1|0xd058c80003e80009|0x0000000000000000|0xd058c80003e80009|0xd058c80003e80005|
|1085|1|2|0x2|0x1|0xd058c80003e80009|0x0000000000000000|0xd058c80003e80009|0xd058c80003e80005|
|1086|2|1|0x2|0x2|0xd058c80003e80009|0xd058c80003e80009|0xd058c80003e80009|0xd058c80003e80005|
|1087|1|0|0x0|0x2|0xd058c80003e80009|0xd058c80003e80009|0xd058c80003e80009|0xd058c80003e80005|

Interpretation:

- both `north` and `east` completed packets are present
- Hydra first selects `north`
- Hydra then selects `east`
- the `east` lane is unloaded
- but `hydra_rx_data_word` and `hydra_comms_rcvd_pkt` remain the `north` packet

So in `v1`, the selected lane changes but the active Hydra/comms packet does not. That is the first confirmed control-path bug.

## Exact RTL Changes Between `v1` And `v2`

The final `v2` result depends on four distinct RTL changes. These are the changes between the baseline `v1` RTL used in the original `2x2` probe and the final `v2` RTL used in the successful rerun.

### Change 1: `hydra_ctrl.sv` `RX_PROCESS -> IDLE`

File:

- [hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/rtl/v3b/src/hydra_ctrl.sv)

`v1` behavior:

- after `RX_PROCESS`, if `comms_ctrl` was no longer busy and another RX lane still had data, Hydra could go directly to `RX_CAPTURE`
- this allowed Hydra to unload a newly selected lane while keeping stale `rx_data` from the previous lane

`v2` change:

- once `comms_ctrl` is no longer busy, Hydra always returns to `IDLE`
- `rx_data` still loads only in `IDLE`

Purpose:

- preserve the original packet-capture timing model
- force every newly serviced lane to refresh `rx_data` before `comms_ctrl` sees it

### Change 2: `comms_ctrl.sv` `LOAD_FIFO` uses `rcvd_pkt`

File:

- [comms_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/rtl/v3b/src/comms_ctrl.sv)

`v1` behavior:

- the pass-through/data branch in `LOAD_FIFO` used live `rx_data`
- if Hydra had already advanced live `rx_data`, `read_pkt` could refer to a different lane than `rcvd_pkt`

`v2` change:

- the pass-through/data branch in `LOAD_FIFO` now uses latched `rcvd_pkt`

Purpose:

- keep `read_pkt` transactionally tied to the packet originally captured at `rx_data_flag`
- eliminate the `rcvd_pkt != read_pkt` mismatch

### Change 3: `comms_ctrl.sv` `pkt_data` uses `read_pkt`

File:

- [comms_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/rtl/v3b/src/comms_ctrl.sv)

`v1` behavior:

- even after fixing `read_pkt`, the actual FIFO write data `pkt_data` still bypassed to live `rx_data` for nonlocal pass-through packets
- that meant `read_pkt` could be correct while FIFO memory still received the wrong lane's packet

`v2` change:

- `pkt_data` now always uses the packet assembled in `read_pkt`

Purpose:

- make the actual FIFO write word match the `comms_ctrl` transaction state
- eliminate the `read_pkt correct, fifo_mem wrong` mismatch

### Change 4: `hydra_ctrl.sv` TX scheduling no longer parks in `TX_GET_FIFO`

File:

- [hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/rtl/v3b/src/hydra_ctrl.sv)

`v1` behavior:

- Hydra could sit in `TX_GET_FIFO` for about one UART frame time while `uart_tx` was busy serializing a previous packet
- while parked there, Hydra was not available for new RX-side work

`v2` change:

- `IDLE` enters `TX_GET_FIFO` only when FIFO is non-empty and TX is free
- if TX is busy, Hydra falls back to `IDLE` rather than waiting in `TX_GET_FIFO`

Purpose:

- make TX launch opportunistic instead of blocking
- allow Hydra to keep servicing RX-side traffic while an older packet is already being serialized

## Current Interpretation

The investigation supports this interpretation.

### `v1`

The original `v1` loss came from real RTL control-path mismatches:

- Hydra could unload a lane without refreshing the packet seen by `comms_ctrl`
- `comms_ctrl` could mix live `rx_data` with latched `rcvd_pkt`
- the FIFO write path could still use live `rx_data` even after `read_pkt` had been corrected
- Hydra could also block itself for long periods in `TX_GET_FIFO`

### `v2`

The final `v2` changes corrected those issues for the `2x2` probe:

- every newly serviced lane now refreshes `rx_data` via a return to `IDLE`
- `read_pkt` is based on `rcvd_pkt`
- `pkt_data` is based on `read_pkt`
- TX launch no longer blocks RX servicing by parking in `TX_GET_FIFO`

With those changes, the `2x2` probe drains completely.

## Related Note

The incremental `v3c -> v3c2` edit series has been moved to:

- [packet_loss_at_rx_v3c_v3c2.md](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/doc/packet_loss_at_rx_v3c_v3c2.md)

## What This Investigation Rules Out

For this `2x2` probe, it rules out the simplest explanation that the original loss was just visible `hold_reg` overflow on a lane.

This test shows the original corruption happened even when:

- both streams fully arrived
- both lanes were unloaded
- `hold_valid` never asserted

So the original `v1` failures were deeper in the shared `Hydra / comms_ctrl / FIFO / TX` handoff path.

## Figure Notes

Add a figure showing the `2x2` packet-loss probe topology:

- chip `0` at bottom-left as source chip
- chip `1` feeding chip `0` from the east
- chip `2` feeding chip `0` from the north
- both chip `1` and chip `2` injecting `64` channels at tick `1000`

Add a figure showing the baseline `v1` symptom:

- both lanes receive `64` packets
- only one stream reaches the FPGA
- `hold_valid` never asserts

Add a figure showing the `v1` Hydra mismatch:

- selected lane changes from north to east
- `hydra_rx_data_word` stays north
- east is unloaded anyway

Add a figure showing the intermediate `v2` transaction mismatch:

- `rcvd_pkt` and `read_pkt` disagree before the `LOAD_FIFO` fix
- later `read_pkt` is correct but FIFO memory still receives the live `rx_data` packet before the `pkt_data` fix

Add a figure showing the final `v2` outcome:

- both streams fully forwarded
- FIFO backlog drains to zero with the longer tail
- FPGA receives all `128` packets
