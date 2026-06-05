# Pass-Through Packet Path In RTL

This note describes the RTL path for an incoming serial packet that is passing through a chip rather than being terminated there.

## Overview

An incoming serial packet enters on one RX UART lane, is converted to a parallel packet in the lane-local UART receiver, arbitrated by Hydra, and then either:

- goes directly to `TX_UPSTREAM` if it is an upstream pass-through packet, or
- goes through `comms_ctrl` and the shared Hydra FIFO if it is a downstream data pass-through packet

After that, it is loaded into a TX UART and serialized back out of the chip.

## Block Flow

1. `uart_rx` inside `uart`
   File: [rtl/v3b/src/uart_rx.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/rtl/v3b/src/uart_rx.sv)

   - Serial bits arrive on `rx_in`
   - The line is synchronized into `rx_sync`
   - Bits are captured into `shift_reg_next[bit_cnt]`
   - When the full word is complete, `packet_ready` is asserted
   - The completed parallel packet is committed into `rx_data` or `hold_reg`

   This is the serial-to-parallel conversion step.

2. `external_interface`
   File: [rtl/v3b/src/external_interface.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/rtl/v3b/src/external_interface.sv)

   - The four lane-local UART receivers expose:
     - `rx_data_uart[i]`
     - `rx_empty_uart[i]`
   - Those feed `hydra_ctrl`

   `external_interface` is the top-level wiring point that connects the UART lanes, Hydra controller, comms controller, and register file.

3. `hydra_ctrl` RX arbitration
   File: [rtl/v3b/src/hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/rtl/v3b/src/hydra_ctrl.sv)

   - `uart_has_data[i] = ~rx_empty_uart[i] & enable_posi[i]`
   - A single lane is chosen with `sel_onehot`
   - In `IDLE`, Hydra copies that selected lane's packet into the shared `rx_data` register
   - In `RX_CAPTURE`, Hydra unloads only that selected UART with `uld_rx_data_uart <= sel_onehot`

   States involved:
   - `IDLE`
   - `RX_CAPTURE`

   This is where multiple RX lanes are serialized into one chip-level receive path.

4. `hydra_ctrl` branch: direct upstream pass-through vs RX processing
   File: [rtl/v3b/src/hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/rtl/v3b/src/hydra_ctrl.sv)

   After `RX_CAPTURE`, Hydra decides what to do with the packet.

   If the packet:
   - is not for this chip, and
   - has `rx_data[62] == 0`

   then the state machine goes directly to `TX_UPSTREAM`.

   Otherwise it goes to `RX_PROCESS`.

   This creates two pass-through cases:
   - upstream pass-through packets: direct Hydra forwarding path
   - downstream data packets: processed through `comms_ctrl` and FIFO

## Upstream Pass-Through Path

For an upstream pass-through packet, the packet path is:

1. `uart_rx`
2. `external_interface`
3. `hydra_ctrl` arbitration
4. `hydra_ctrl` `TX_UPSTREAM`
5. `uart_tx`

In `TX_UPSTREAM`:
- Hydra copies `rx_data` into all `tx_data_uart[i]`
- It asserts `ld_tx_data_uart <= enable_piso_upstream` when those TX UARTs are free

Then the selected upstream TX UART(s) serialize the packet out.

This path bypasses `comms_ctrl` and the shared FIFO.

## Downstream Data Pass-Through Path

For a downstream data packet, the packet path is:

1. `uart_rx`
2. `external_interface`
3. `hydra_ctrl` arbitration
4. `hydra_ctrl` `RX_PROCESS`
5. `comms_ctrl`
6. `priority_fifo_arbiter` / shared Hydra FIFO
7. `hydra_ctrl` `TX_GET_FIFO`
8. `hydra_ctrl` `TX_SEND`
9. `uart_tx`

### `hydra_ctrl` `RX_PROCESS`

In `RX_PROCESS`:
- Hydra asserts `rx_data_flag` when `comms_ctrl` is ready
- This hands the packet to `comms_ctrl`

### `comms_ctrl`
File: [rtl/v3b/src/comms_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/rtl/v3b/src/comms_ctrl.sv)

`comms_ctrl` classifies the packet:
- config writes for this chip go to the register file
- config reads for this chip generate a reply
- non-local packets and data packets go to `LOAD_FIFO`

For a pass-through data packet:
- `pkt_valid` is asserted
- `pkt_data` is driven from the received packet
- the packet is handed to the shared FIFO path

### Shared Hydra FIFO
File: [rtl/v3b/src/priority_fifo_arbiter.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/rtl/v3b/src/priority_fifo_arbiter.sv)

The pass-through data packet is written into the shared FIFO.

This is the same chip-level shared path used for event traffic leaving the chip.

### `hydra_ctrl` transmit side
File: [rtl/v3b/src/hydra_ctrl.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/rtl/v3b/src/hydra_ctrl.sv)

After FIFO enqueue, Hydra transmits the packet via:
- `TX_GET_FIFO`
- `TX_SEND`

In `TX_GET_FIFO`:
- Hydra waits for downstream TX lanes to be free
- It asserts `fifo_read_n <= 0` to read the shared FIFO

In `TX_SEND`:
- Hydra copies `fifo_rd_data` into all `tx_data_uart[i]`
- It asserts `ld_tx_data_uart <= enable_piso_downstream`

### `uart_tx`
File: [rtl/v3b/src/uart_tx.sv](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/rtl/v3b/src/uart_tx.sv)

The parallel packet is serialized back into UART bits and driven out on `tx_out`.

## Summary

### Upstream pass-through packet

`rx_in`
-> `uart_rx`
-> `hydra_ctrl` arbitration
-> `TX_UPSTREAM`
-> `uart_tx`
-> `tx_out`

### Downstream data pass-through packet

`rx_in`
-> `uart_rx`
-> `hydra_ctrl` arbitration
-> `RX_PROCESS`
-> `comms_ctrl`
-> shared Hydra FIFO
-> `TX_GET_FIFO`
-> `TX_SEND`
-> `uart_tx`
-> `tx_out`

## Important implication

Downstream data pass-through packets pay extra relay latency because they do not go straight from RX to TX. They must pass through:
- `comms_ctrl`
- the shared FIFO
- the Hydra FIFO transmit states

That extra relay path is part of why sustained multi-lane convergence can overrun lane-local UART RX buffering before packets are drained.
