# Current RTL Routing Configurability

## Summary

In the current LArPix digital-core RTL, routing is only configurable to a limited extent.

A configuration packet does **not** program a full routing table in the network-simulator sense. Instead, the current RTL exposes a small set of configuration registers that control which UART lanes are enabled for receive, upstream transmit, and downstream transmit.

So the current RTL supports **lane-enable-style routing control**, not a general per-destination or per-edge routing-table model.

## How Configuration Packets Work

In the current RTL, a configuration write packet carries exactly one register write.

From `larpix_v3b/src/comms_ctrl.sv`, the relevant packet fields are:
- bits `[1:0]`   = packet type
- bits `[9:2]`   = destination chip ID
- bits `[17:10]` = register address
- bits `[25:18]` = register data byte
- bits `[57:26]` = magic number
- bit  `[63]`    = parity

So each `CONFIG_WRITE` packet writes **one byte to one config register**.

## Routing-Related Registers In The Current RTL

The routing-related configuration currently exposed by the digital core is primarily:

- `ENABLE_PISO_UP = 124`
- `ENABLE_PISO_DOWN = 125`
- `ENABLE_POSI = 126`

These register addresses are defined in:
- `larpix_v3b/src/larpix_constants.sv`

These registers are mapped in `digital_core.sv` to:
- `enable_piso_upstream = config_bits[ENABLE_PISO_UP][3:0]`
- `enable_piso_downstream = config_bits[ENABLE_PISO_DOWN][3:0]`
- `enable_posi = config_bits[ENABLE_POSI][3:0]`

So each of these is effectively a 4-bit lane mask.

A concrete example using `ENABLE_PISO_UP`:

- `ENABLE_PISO_UP = 124` means register address `124` in the 256-byte config register file
- a configuration write packet can write one byte to that register
- if that packet writes data `0x0B`, then the register becomes:
  - `config_bits[124] = 8'b0000_1011`
- the RTL then interprets the low 4 bits as:
  - `enable_piso_upstream = config_bits[ENABLE_PISO_UP][3:0] = 4'b1011`

So in that example, upstream PISO lanes `0`, `1`, and `3` are enabled, while lane `2` is disabled.

## What These Bits Actually Control

From `hydra_ctrl.sv`, these masks control:

- which RX UARTs are enabled:
  - `rx_enable = enable_posi`
- which TX UARTs are enabled overall:
  - `tx_enable = enable_piso_upstream | enable_piso_downstream`
- which UARTs are used when forwarding upstream packets:
  - `ld_tx_data_uart <= enable_piso_upstream`
- which UARTs are used when sending downstream packets:
  - `ld_tx_data_uart <= enable_piso_downstream`

So the current configurable routing behavior is essentially:
- enable or disable specific RX lanes
- enable or disable specific upstream TX lanes
- enable or disable specific downstream TX lanes

## Important Limitation

This is **not** a full routing table.

The current RTL does **not** expose configuration registers for things like:
- per-destination routing decisions
- edge-specific route selection based on packet destination chip
- a programmable mapping from logical network directions to physical lanes
- multi-hop route tables
- a shadow-vs-active routing bank

In other words, the RTL currently does **not** let you configure statements like:
- "packets for chip 17 should go east"
- "config readbacks should leave on west but event packets should leave on south"
- "north is lane 2 on this chip but lane 0 on another chip"

Those ideas are beyond the current register-programmable routing capability.

## Broadcast Behavior In The Current RTL

Another important detail is that Hydra does not currently choose a single TX lane for a packet in a given direction.

Instead, it broadcasts onto **all enabled lanes** for that direction.

So for downstream transmission, the current RTL does:
- load the same packet into all `tx_data_uart[i]`
- assert `ld_tx_data_uart` on all lanes enabled by `enable_piso_downstream`

Likewise for upstream forwarding, Hydra uses all lanes enabled by `enable_piso_upstream`.

So even the current "routing" behavior is best described as:
- directional lane masking
- plus broadcast on enabled lanes

not single-edge packet routing.

## Practical Consequence For `larpix_network_sim`

If `larpix_network_sim` wants startup configuration packets to program routing using the current LArPix RTL as-is, then those packets can only directly configure:
- `ENABLE_PISO_UP`
- `ENABLE_PISO_DOWN`
- `ENABLE_POSI`

That is enough to control which UART lanes participate in RX, upstream TX, and downstream TX.

It is **not** enough to implement a richer network routing model entirely inside the current RTL.

So if the network simulator needs more expressive routing behavior, one of the following will be required:

1. Additional RTL configuration registers
- new register fields to encode richer routing decisions inside the chip RTL

2. Runtime-side routing policy
- keep the current RTL lane-enable behavior
- implement the higher-level routing policy in the outer `larpix_network_sim` runtime

3. A hybrid approach
- use current RTL lane-enable bits where possible
- add a small amount of new RTL state for explicit edge-selection behavior

## Bottom Line

The current RTL makes routing configurable only to the extent of:
- enabling/disabling RX lanes
- enabling/disabling upstream TX lanes
- enabling/disabling downstream TX lanes

That is the exact extent of routing configurability exposed by the present digital core RTL.
