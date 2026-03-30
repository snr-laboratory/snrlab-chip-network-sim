# Digital Core Event Flow

This note summarizes how [`digital_core.sv`](./src/digital_core.sv) turns channel activity into outgoing packets, and how packet formatting changes along the way.

## Top-Level Flow

The event path through the digital core is:

1. A per-channel [`channel_ctrl`](./src/channel_ctrl.sv) decides whether a hit/trigger should create an event.
2. The channel formats a 63-bit event payload and writes it into its local channel FIFO.
3. [`event_router`](./src/event_router.sv) arbitrates across the 64 local FIFOs, selects one event, and adds the parity bit to form a 64-bit packet.
4. [`external_interface`](./src/external_interface.sv) hands local event packets and protocol packets to [`hydra_ctrl`](./src/hydra_ctrl.sv).
5. Hydra arbitrates between local event traffic and protocol/readback traffic, writes the winner into the shared Hydra FIFO, then transmits FIFO entries on the enabled downstream UART links.

So local data is buffered twice:

- once in the per-channel local FIFO inside `channel_ctrl`
- once in the shared Hydra FIFO inside `hydra_ctrl`

## Channel-Level Trigger Behavior

Each [`channel_ctrl`](./src/channel_ctrl.sv) can start an event from four trigger sources:

- natural trigger: `channel_enabled & hit & ~channel_mask`
- external trigger: `external_trigger & ~external_trigger_mask`
- cross trigger: `cross_trigger & ~cross_trigger_mask`
- periodic trigger: `periodic_trigger & ~periodic_trigger_mask`

The 2-bit trigger encoding is:

- `00`: natural
- `01`: external
- `10`: cross
- `11`: periodic

Once triggered, the controller:

1. captures the trigger type
2. asserts `sample`
3. waits for the ADC/sample timing conditions
4. builds a packet payload
5. writes that payload into the local FIFO

Special behaviors implemented in `channel_ctrl` include:

- optional burst readout via `adc_burst_length`
- CDS mode, including a CDS reset packet path
- dynamic reset thresholding
- min-delta-ADC gating
- optional local FIFO diagnostics insertion
- optional 2-bit event tally insertion

## Local Channel Event Packet Format

The local event payload built in [`channel_ctrl.sv`](./src/channel_ctrl.sv) is 63 bits wide. The parity bit is not added here.

Field layout of `channel_event` / `input_events[i]`:

- `[1:0]`: packet type = `2'b01` (data packet)
- `[9:2]`: `chip_id`
- `[15:10]`: `channel_id`
- `[43:16]`: 28-bit timestamp
- `[55:46]`: 10-bit ADC value
- `[57:56]`: trigger type
- `[58]`: local FIFO half flag
- `[59]`: local FIFO full flag
- `[61:60]`: optional 2-bit event tally when enabled
- `[62]`: downstream flag, forced to `1`

If local FIFO diagnostics are enabled, bits `[31:28]` are overwritten with the local FIFO count.

## Event Router Behavior

[`event_router`](./src/event_router.sv) receives:

- `input_events[64]`
- `local_fifo_empty[64]`
- `ready_for_event`

It performs round-robin arbitration using a token. If the token points at an empty FIFO, it wraps and picks the first available channel with data.

When a channel is selected:

- `read_local_fifo_n` is pulsed low for that channel
- `event_valid` is asserted
- `event_data` is formed as:

```systemverilog
{~^input_events[i], input_events[i]}
```

So `event_router` converts the 63-bit local payload into the final 64-bit event packet by prepending the parity bit.

## External Interface Split

[`external_interface`](./src/external_interface.sv) ties together three blocks:

- `uart`: physical RX/TX datapaths on the 4 serial links
- [`comms_ctrl`](./src/comms_ctrl.sv): config/readback/statistics packet handling
- [`hydra_ctrl`](./src/hydra_ctrl.sv): packet routing, arbitration, Hydra FIFO, and transmission

The practical split is:

- local events come from `event_router`
- incoming config packets come from RX UARTs
- `comms_ctrl` either consumes packets locally or builds a reply/forwarded packet
- `hydra_ctrl` merges local events and protocol packets into the shared transmit path

## Incoming Packet Decode in comms_ctrl

[`comms_ctrl`](./src/comms_ctrl.sv) decodes the incoming 64-bit `rx_data` as:

- `[1:0]`: `pkt_type`
- `[9:2]`: destination chip ID
- `[17:10]`: register address
- `[25:18]`: register payload
- `[57:26]`: magic number
- `[61:58]`: stats selector
- `[63]`: parity

Its packet handling behavior is:

- malformed packet: dropped
- `CONFIG_WRITE_OP`: write the addressed config register
- `CONFIG_READ_OP` addressed to this chip: read config register and build a reply packet
- other valid traffic: forward through Hydra

It also tracks statistics such as local data packet count, config read/write counts, dropped packets, total packets, and Hydra FIFO high-water mark.

## Config Read Reply Packet Format

For a config read targeted to this chip, [`comms_ctrl`](./src/comms_ctrl.sv) builds a 63-bit reply payload and then recomputes parity.

Current construction in `LOAD_FIFO` is:

- `[62]`: downstream flag = `1`
- `[61:26]`: copied from the received request (`rcvd_pkt[61:26]`)
- `[25:10]`: either stats payload or `{regmap_read_data, original_reg_addr}`
- `[9:2]`: source chip ID = this chip's `chip_id`
- `[1:0]`: packet type = `CONFIG_READ_OP`

Then `pkt_data` becomes either:

- `{~^read_pkt, read_pkt}` if the packet is for this chip
- or the original `rx_data` if it is not

So a config-read reply keeps most of the original request structure, swaps in this chip as the source, and inserts either the register value or the selected statistics payload.

## Forwarded Packet Behavior

In [`comms_ctrl`](./src/comms_ctrl.sv), a packet is forwarded rather than rebuilt when any of these hold:

- destination chip ID is not this chip
- destination chip ID is the global ID
- packet type is `DATA_OP`

In that case:

- `read_pkt <= rx_data`
- `pkt_valid` is asserted
- Hydra will enqueue and transmit that packet unchanged

So forwarded packets retain their original layout.

## Hydra Arbitration and Shared FIFO

[`hydra_ctrl`](./src/hydra_ctrl.sv) has two arbitration points.

### RX-side arbitration

Across the 4 UART RX ports, Hydra uses a round-robin token to choose one non-empty enabled UART at a time.

After capture, the packet is either:

- sent upstream immediately if it is not for this chip and is not already marked downstream
- or handed to `comms_ctrl` for local processing

### TX-side arbitration

Hydra instantiates [`priority_fifo_arbiter`](./src/priority_fifo_arbiter.sv) to choose between:

- local event traffic: `event_valid`, `event_data`
- protocol traffic: `pkt_valid`, `pkt_data`

The selected packet is written into the shared Hydra FIFO (`fifo_latch`).

Hydra exposes back-pressure signals:

- `ready_for_event`: event path may present another local event
- `ready_for_pkt`: protocol path may present another config/readback/forwarded packet

When the enabled downstream UARTs are idle, Hydra reads the next packet from the FIFO and broadcasts it onto all enabled downstream PISO links.

## FIFO Diagnostics Packet Modification

If `enable_fifo_diagnostics` is high, Hydra modifies local event packets before putting them into the shared FIFO using `embed_fc_in_pkt(...)` in [`hydra_ctrl.sv`](./src/hydra_ctrl.sv).

Its intent is:

- keep the upper packet bits unchanged
- replace the normal event counter/timestamp field area with the current Hydra FIFO occupancy
- recompute parity afterward

The function currently constructs:

- upper bits from `raw_pkt[WIDTH-1:44]`
- embedded `fifo_counter`
- lower bits from `raw_pkt[31:0]`
- new parity bit as `~^payload`

So in FIFO-diagnostics mode, the normal event packet no longer preserves the original timestamp field exactly; part of that space is repurposed to carry Hydra FIFO occupancy.

## End-to-End Summary

A local hit becomes an outgoing packet like this:

1. `channel_ctrl` detects a valid trigger and captures ADC/timestamp context.
2. `channel_ctrl` writes a 63-bit local event payload into its local FIFO.
3. `event_router` selects one ready channel and adds parity, producing a 64-bit event packet.
4. `hydra_ctrl` arbitrates that event against any protocol packet from `comms_ctrl`.
5. The winner is written into the shared Hydra FIFO.
6. When downstream UARTs are available, Hydra transmits the packet on all enabled downstream outputs.

In parallel, incoming UART packets may be:

- consumed locally as config writes
- turned into config read replies or stats replies
- or forwarded unchanged through the same Hydra FIFO transmit path
