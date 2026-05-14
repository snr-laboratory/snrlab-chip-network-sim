# msg_rtl Design Notes

This note is the implementation-oriented specification for the next `msg_rtl` redesign.

It covers:

- the final intended `MSG_OP` packet contents
- the split between `msg_generator` and `msg_logic`
- the congestion-broadcast and downstream-lane-selection behavior

## Overview

The intent is to use `MSG_OP` as a lightweight congestion-broadcast packet exchanged between neighboring chips.

High-level behavior:

- `msg_generator` creates locally generated `MSG_OP`
- `msg_logic` receives and handles neighbor-generated `MSG_OP`
- only locally generated `MSG_OP` are eligible for transmission
- neighbor-received `MSG_OP` are not retransmitted
- generated `MSG_OP` are broadcast on all four TX lanes
- received `MSG_OP` are used to maintain remembered neighbor congestion state and to influence downstream-lane selection

## Final `MSG_OP` Packet Format

`MSG_OP` remains identified by the normal 2-bit packet type field.

Final on-wire width:

- `7` bits total

Bit layout:

- `[6]`: parity
- `[5:4]`: TX-lane tag
- `[3:2]`: shared-FIFO occupancy state
- `[1:0]`: `MSG_OP` packet type

TX-lane tag encoding:

- `00`: north
- `01`: east
- `10`: south
- `11`: west

Shared-FIFO occupancy encoding:

- `00`: shared FIFO occupancy `<= 25%`
- `01`: shared FIFO occupancy `> 25%` and `<= 50%`
- `10`: shared FIFO occupancy `> 50%` and `<= 90%`
- `11`: shared FIFO occupancy `> 90%`

For the current shared Hydra FIFO depth of `64`, that maps to:

- `00`: `0..16`
- `01`: `17..32`
- `10`: `33..57`
- `11`: `58..64`

Explicit exclusions from the new `MSG_OP` format:

- no origin chip ID field
- no downstream bit
- no extra payload beyond lane tag and FIFO-state field

## Block Responsibilities

The current monolithic message behavior should be split into two RTL blocks:

- `msg_generator`
- `msg_logic`

### `msg_generator`

`msg_generator` is responsible for:

- monitoring the local chip's shared Hydra FIFO occupancy state
- encoding that occupancy into the 2-bit `MSG_OP` FIFO-state field
- generating locally originated `MSG_OP`
- forwarding locally generated `MSG_OP` to `hydra_ctrl` for tagging and transmission

`msg_generator` is not responsible for:

- remembering neighbor state
- modifying downstream-lane policy directly
- retransmitting neighbor-received `MSG_OP`

### `msg_logic`

`msg_logic` is responsible for:

- receiving `MSG_OP` that arrived from neighboring chips
- decoding their FIFO-state field and TX-lane tag
- interpreting the sender TX-lane tag as the corresponding opposite RX lane on the current chip
- storing remembered neighbor-state information per RX lane
- issuing requests to adjust downstream lane-enable register state

`msg_logic` does only:

- receive `MSG_OP`
- decode/store neighbor state
- request downstream register updates

It does not:

- generate new `MSG_OP`
- retransmit received `MSG_OP`

## `msg_generator` Enable Control

Msg generation is configuration-controlled.

Register choice:

- use an unused bit in register `DMONITOR0` (address `114`) as the msg-generation enable control
- specifically use `config_bits[114][5]`

Register semantics:

- write `1` to bit `DMONITOR0[5]` to enable `MSG_OP` generation
- write `0` to bit `DMONITOR0[5]` to disable `MSG_OP` generation
- existing `DMONITOR0[4:0]` semantics remain unchanged
- `DMONITOR0[7:6]` remain ignored/reserved for this feature

Reset/startup default:

- `DMONITOR0[5]` defaults to `0`
- therefore msg generation is disabled by default

## `msg_generator` Trigger Rule

`msg_generator` is event-driven, not probabilistic.

It should generate and transmit a new local `MSG_OP` when:

- the chip's encoded 2-bit shared-FIFO occupancy state changes relative to the last transmitted state
- or msg generation is enabled by config after previously being disabled

Examples:

- `00 -> 01`: generate and transmit
- `01 -> 10`: generate and transmit
- `10 -> 11`: generate and transmit
- `11 -> 10`: generate and transmit
- `10 -> 00`: generate and transmit
- `msg_generation_enable: 0 -> 1`: generate and transmit current state

This enable edge acts as an initial advertisement, so neighbors can learn the chip's current congestion state even if that state is already `00`.

## `MSG_OP` Transmission Rules

Locally generated `MSG_OP` should be broadcast across all four TX lanes:

- north
- east
- south
- west

This broadcast ignores the normal downstream TX-enable mask.

`msg_generator` does not need to know the chip's lane configuration.

Instead:

- `msg_generator` only hands the local `MSG_OP` to `hydra_ctrl`
- `hydra_ctrl` stamps the TX-lane tag at transmit time
- `hydra_ctrl` performs lane-specific transmission

If a single local `MSG_OP` is sent on multiple lanes in the same cycle, each transmitted copy should carry the tag corresponding to its own TX lane.

Parity must be recomputed after lane-tag stamping.

Hydra implementation note:

- `hydra_ctrl` may use a one-cycle source-select signal to choose the generated `MSG_OP` for launch
- but it must keep all four UARTs clock-enabled until every lane launched for that local `MSG_OP` has gone idle
- this hold behavior must be separate from the source-select signal so later shared-FIFO traffic is not misclassified as `MSG_OP`

Generated `MSG_OP` transmit priority:

- a pending locally generated `MSG_OP` should take priority over shared-FIFO traffic
- therefore `hydra_ctrl` should prefer transmitting pending local `MSG_OP` before transmitting data packets or other packet types from the shared FIFO

Generated `MSG_OP` buffering policy:

- the generated-msg holding structure should be `1` deep
- there is no value in preserving older unsent generated `MSG_OP` if a newer local congestion advertisement is available
- if a new local `MSG_OP` is generated while an older unsent generated `MSG_OP` is still pending, the newer one should replace the older one

Design note:

- this means only the newest local congestion advertisement is retained for transmission
- intermediate occupancy transitions may be overwritten before transmission if the local state changes quickly

## TX-Tag / RX-Lane Interpretation Rule

When a chip receives a `MSG_OP`, it interprets the packet's TX-lane tag as implying the corresponding opposite RX lane on the receiving chip.

Directional mapping:

- sender TX `N` -> receiver RX `S`
- sender TX `E` -> receiver RX `W`
- sender TX `S` -> receiver RX `N`
- sender TX `W` -> receiver RX `E`

This is the receive-side interpretation used by `msg_logic`.

## Neighbor-State Memory

`msg_logic` maintains per-RX-lane remembered neighbor state.

There should be one remembered state entry for each RX lane:

- RX `N`
- RX `E`
- RX `S`
- RX `W`

Each entry should contain:

- the most recent received `MSG_OP` for that lane, or at minimum the needed decoded fields
- the chip's global timestamp value captured when that `MSG_OP` was stored
- a valid bit indicating whether that lane has ever received a usable `MSG_OP`

Interpretation:

## Local Visualizer

Current local playback for the 3x3 center-charge probe:

`http://localhost:8000/larpix_network_sim/visualizers/packet_transmission/index.html?playback=../../../build/larpix_3x3_msg_center_charge_probe/live_event_3x3_msg_center_charge_probe.json&v=5`

- remembered state is the chip's current view of that neighbor's congestion
- the stored timestamp is used for tie-breaking by recency

Freshness policy for the first version:

- remembered neighbor `MSG_OP` state does not time out
- once valid, it remains usable until overwritten by a newer `MSG_OP` on that lane

## Downstream Disable / Reselect Policy

If `msg_logic` receives a `MSG_OP` whose FIFO-state field is `11`:

- and that packet arrived on a direction which is currently enabled for downstream TX
- then `msg_logic` should request that downstream TX direction be disabled

After that disable:

- if at least one downstream TX lane still remains enabled, do nothing else
- if no downstream TX lane remains enabled, attempt to select a new downstream TX direction

### Reselect Rule

To choose a new downstream direction:

- inspect the remembered neighbor FIFO state for all four directions
- exclude any direction already enabled for upstream TX
- exclude any direction whose remembered state is invalid
- choose the direction with the lowest remembered FIFO occupancy state

Tie-break rule:

- if multiple candidate directions have the same lowest FIFO occupancy state
- choose the direction with the most recent stored timestamp

### Fallback Rule

If no valid new downstream direction can be selected:

- make no change to the current downstream lane selection

### Startup Policy

At startup:

- a chip keeps its normal configured downstream lane state
- remembered neighbor-state entries are invalid until a `MSG_OP` is received on that RX lane
- downstream reselection only uses valid remembered neighbor entries

So if there is not enough neighbor information yet:

- the chip leaves downstream selection unchanged

### Lane Re-enable Policy

A previously disabled downstream direction becomes eligible again when its most recent remembered `MSG_OP` satisfies the normal downstream-selection criteria:

- lowest remembered FIFO occupancy state
- tie-broken by most recent stored timestamp

Lane disable is therefore not permanent.

## Register-Update Control Path

Lane enable/disable policy remains register-driven.

That means:

- `msg_logic` does not directly modify `hydra_ctrl`
- `msg_logic` requests changes to downstream lane-enable register state
- `hydra_ctrl` continues to consume the resulting config-derived lane-enable signals without redesign

So:

- lane policy ownership remains in register state
- `hydra_ctrl` remains a consumer of register state

## Control Precedence

If an external config write arrives in the same cycle as a register adjustment request caused by `msg_logic`:

- the external config write takes precedence

This means explicit configuration traffic overrides autonomous internal control updates on collision.

## Simultaneous RX Arrivals

If two neighbor `MSG_OP` packets arrive in the same cycle on different RX lanes:

- existing `hydra_ctrl` one-hot RX-lane selection behavior determines which lane is serviced first
- only one RX lane is processed at a time
- the other lane remains pending for a later cycle

No extra `msg_logic` arbitration is required for that case beyond current `hydra_ctrl` behavior.

## RTL Files Likely To Change

The main files likely to be touched are:

- `larpix_network_sim/msg_rtl/src/larpix_constants.sv`
- `larpix_network_sim/msg_rtl/src/uart_rx.sv`
- `larpix_network_sim/msg_rtl/src/uart_tx.sv`
- `larpix_network_sim/msg_rtl/src/comms_ctrl.sv`
- `larpix_network_sim/msg_rtl/src/msg_logic.sv`
- `larpix_network_sim/msg_rtl/src/hydra_ctrl.sv`
- `larpix_network_sim/msg_rtl/src/external_interface.sv`
- `larpix_network_sim/msg_rtl/src/digital_core.sv`

Additional likely new file:

- `larpix_network_sim/msg_rtl/src/msg_generator.sv`

## Implementation Readiness

This document is intended to be sufficient to implement the first congestion-broadcast version of `msg_rtl`.
