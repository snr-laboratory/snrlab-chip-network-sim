# Internal Packet Relay Latency In The Live LArPix Visualizer

This note explains the per-chip delay that appears in the browser visualizer between:

- a packet finishing its incoming hop into a chip, and
- the same packet beginning its outgoing hop from that chip.

The concrete example used here is the `3x5` chip-14 injection scenario, where one representative event packet shows:

- chip `14` `tx_packet` complete at `seq=9881`
- chip `9` `rx_packet` complete at `seq=9881`
- chip `9` `tx_packet` complete at `seq=9959`

So the relay chip contributes:

- `9959 - 9881 = 78` ticks from receive-complete to transmit-complete

A UART frame in this framework is `66` ticks (`64` payload bits plus start/stop framing) from:

- [convert_live_trace_to_playback.py](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/convert_live_trace_to_playback.py:21)
- [compile_startup_json.py](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/compile_startup_json.py:65)

That leaves an internal relay overhead of about:

- `78 - 66 = 12` ticks

## Important Distinction

Two parts contribute to what the browser shows:

1. Real in-chip relay latency: about `12` ticks in this example.
2. Visualizer span rendering: the outgoing moving dot starts at
   `tx_complete_tick - FRAME_BITS + 1`, not at `tx_complete_tick`.

The visualizer packet span logic is in:

- [convert_live_trace_to_playback.py](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/convert_live_trace_to_playback.py:239)

So the browser gap is not purely cosmetic. It is showing a real relay pipeline before the next UART transmission begins.

## Trace Points Used

The live runtime emits `rx_packet` and `tx_packet` trace events in [chip_larpix.cpp](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/chip_larpix.cpp:1141):

- published outgoing bits are decoded first, and a completed UART word produces `tx_packet`
- incoming bits are then pulled from neighbors and decoded, and a completed UART word produces `rx_packet`
- only after that does the backend `tick(...)` run

This means the runtime trace reflects completed UART frames at chip boundaries, while the internal relay work happens in the backend tick that follows.

## Tick-By-Tick Relay Timeline

The table below is the best current cycle-by-cycle interpretation of the `~12` internal ticks. The existence of these stages is directly supported by the RTL. The exact one-tick boundaries inside the chain are an inference from the measured trace timing and the state machines.

| Relative tick | What is happening | RTL component | Evidence |
| --- | --- | --- | --- |
| `T` | Incoming UART frame completes on the selected RX lane; runtime emits `rx_packet` for the chip. | Runtime wrapper around RTL | [chip_larpix.cpp](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/chip_larpix.cpp:1164) |
| `T+0` | `hydra_ctrl` is still in `IDLE`, sees `uart_has_data`, and captures the selected lane word into `rx_data`. | `hydra_ctrl` RX path | [hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/hydra_ctrl.sv:154), [hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/hydra_ctrl.sv:197) |
| `T+1` | State advances to `RX_CAPTURE`; the chosen UART lane is unloaded with `uld_rx_data_uart <= sel_onehot`. | `hydra_ctrl` | [hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/hydra_ctrl.sv:157), [hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/hydra_ctrl.sv:208) |
| `T+2` | State advances to `RX_PROCESS`; `hydra_ctrl` asserts `rx_data_flag` when `comms_ctrl` is not busy. | `hydra_ctrl` to `comms_ctrl` handoff | [hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/hydra_ctrl.sv:166), [hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/hydra_ctrl.sv:222) |
| `T+3` | `comms_ctrl` in `IDLE` consumes `rx_data`, increments packet stats, captures `rcvd_pkt`, and selects `LOAD_FIFO` for a data/pass-through packet. | `comms_ctrl` | [comms_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/comms_ctrl.sv:142), [comms_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/comms_ctrl.sv:188) |
| `T+4` | `comms_ctrl` is in `LOAD_FIFO`; it drives `read_pkt <= rx_data` for data traffic and pulses `pkt_valid`. | `comms_ctrl` output staging | [comms_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/comms_ctrl.sv:158), [comms_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/comms_ctrl.sv:209), [comms_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/comms_ctrl.sv:227) |
| `T+5` | `priority_fifo_arbiter` grants `pkt_valid` over event traffic and writes the packet into the Hydra shared FIFO. | `priority_fifo_arbiter` | [priority_fifo_arbiter.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/priority_fifo_arbiter.sv:29) |
| `T+6` | `hydra_ctrl` returns to `IDLE`, now sees `!fifo_empty`, and schedules `TX_GET_FIFO`. | `hydra_ctrl` TX path entry | [hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/hydra_ctrl.sv:154) |
| `T+7` | In `TX_GET_FIFO`, if no downstream UART is busy, `hydra_ctrl` pulses `fifo_read_n <= 0`. | `hydra_ctrl` shared FIFO read stage | [hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/hydra_ctrl.sv:172), [hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/hydra_ctrl.sv:229) |
| `T+8` | State advances to `TX_SEND`; `hydra_ctrl` copies `fifo_rd_data` to `tx_data_uart[i]` and asserts `ld_tx_data_uart <= enable_piso_downstream`. | `hydra_ctrl` TX launch staging | [hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/hydra_ctrl.sv:174), [hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/hydra_ctrl.sv:236) |
| `T+9` | `uart_tx` latches `tx_data` and asserts `tx_busy`. | `uart_tx` register load | [uart_tx.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/uart_tx.sv:53) |
| `T+10` | `uart_tx` begins frame emission with the start bit. | `uart_tx` serialization | [uart_tx.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/uart_tx.sv:63) |
| `T+11` onward | Data bits shift out over the next `66` tick frame. | `uart_tx` | [uart_tx.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/larpix_v3b_rtl/src/uart_tx.sv:64) |

## Why The Visualizer Dot Starts Later

The visualizer does not draw the next packet dot at `tx_complete_tick`. It reconstructs the whole outgoing frame using:

- `start_tick = tx_complete_tick - FRAME_BITS + 1`
- `end_tick = rx_complete_tick + 1`

from [convert_live_trace_to_playback.py](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/convert_live_trace_to_playback.py:239).

So the browser gap corresponds to the period between:

- the prior hop finishing at the destination, and
- the first bit of the next hop beginning to leave that destination chip

That is exactly the internal relay latency described above.

## Bottom Line

For the `3x5` example packet:

- `66` ticks are spent serializing the outgoing frame
- about `12` ticks are spent relaying the packet through the chip internally

Those internal ticks are dominated by:

- RX-lane arbitration and unload in `hydra_ctrl`
- handoff to `comms_ctrl`
- write into the Hydra shared FIFO
- read back out of the Hydra shared FIFO
- launch into `uart_tx`

So the visualizer's apparent `~13` tick pause is a real consequence of the current RTL relay pipeline, not just a drawing choice.
