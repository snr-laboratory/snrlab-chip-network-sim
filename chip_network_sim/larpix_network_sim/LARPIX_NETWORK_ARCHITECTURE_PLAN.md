# LArPix Network Architecture Plan

## Goal

Adapt the existing `chip_network_sim` NNG-socket network architecture so it can support a LArPix-oriented RTL/cosimulation backend in which each chip can communicate with up to four neighboring chips on its edges instead of only one upstream chip and one downstream chip.

The main objective is to preserve the parts of the simulator that are already working well:
- process-per-chip execution
- orchestrator-controlled lock-step ticking
- deterministic simulation sequencing
- shared software and RTL backend expectations

while replacing the current `1-in/1-out` data-plane model with a `4-edge` nearest-neighbor communication model.

## What Should Stay The Same

The following architectural pieces should remain unchanged or as close to unchanged as possible:

- The orchestrator remains the global owner of simulation time.
- Control uses the same strict transactional barrier model:
  - orchestrator sends `TICK(seq)`
  - each chip executes exactly one simulated tick
  - each chip replies `DONE(seq)`
- The simulation still runs one operating-system process per chip.
- NNG remains the transport library for inter-process communication.
- The software backend and RTL/cosim backend should still satisfy the same top-level runtime contract from the orchestrator's point of view.

This is important because the control-plane design is already strong: it gives deterministic execution, clear error boundaries, and easy reasoning about correctness.

## What Must Change

The current runtime contract is built around exactly one input and one output per chip:
- `-input <chip_id>`
- `-out <chip_id>`

That model is too restrictive for a LArPix-style chip network. A LArPix-oriented chip model needs to interact with up to four directional neighbors:
- north
- east
- south
- west

So the architecture change should focus on replacing the current single-link data plane with a per-edge data plane.

## Recommended New Data-Plane Model

Each chip should own up to four directional links.

### Per-chip outputs

Each chip should expose one output service per edge:
- `north_out`
- `east_out`
- `south_out`
- `west_out`

### Per-chip inputs

Each chip should also be able to pull from up to four input edges:
- `north_in`
- `east_in`
- `south_in`
- `west_in`

### NNG transport model

The simplest transport model is still `REQ/REP`, but now it should be per edge instead of per chip:
- one `REP` socket per output edge
- one `REQ` socket per input edge

This preserves the strong properties of the current transport approach:
- reliable request/reply transfer
- explicit tick sequencing
- deterministic per-link behavior
- no silent packet loss inside the transport layer

## New Connectivity Model

The old connectivity model is:
- one `input_id`
- one `out_id`

The new model should describe up to four edge connections.

### Suggested runtime CLI

The simplest explicit CLI version is:
- `-north_in <chip_id|-1>`
- `-east_in <chip_id|-1>`
- `-south_in <chip_id|-1>`
- `-west_in <chip_id|-1>`
- `-north_out <chip_id|-1>`
- `-east_out <chip_id|-1>`
- `-south_out <chip_id|-1>`
- `-west_out <chip_id|-1>`

This is verbose, but it is direct and easy to validate in C/C++ code.

### Suggested JSON schema

The current route entry schema is:

```json
{ "id": 7, "input_id": 6, "out_id": 3 }
```

The new route entry should become something like:

```json
{
  "id": 7,
  "inputs": {
    "north": 3,
    "east": 8,
    "south": 11,
    "west": 6
  },
  "outputs": {
    "north": 3,
    "east": 8,
    "south": 11,
    "west": 6
  }
}
```

This format is a better fit for directional network modeling and for a future LArPix backend.

## Recommended Protocol Changes

The protocol defined in `include/chipsim/protocol.h` currently identifies the peer chip and tick sequence, but not the edge involved in a data pull/reply.

A 4-edge architecture should add edge identity to the data messages.

### Suggested edge enum

```c
typedef enum {
    CHIPSIM_EDGE_NORTH = 0,
    CHIPSIM_EDGE_EAST  = 1,
    CHIPSIM_EDGE_SOUTH = 2,
    CHIPSIM_EDGE_WEST  = 3,
} chipsim_edge_t;
```

### Suggested `DATA_PULL` extension

```c
typedef struct {
    uint8_t  type;
    uint8_t  edge;
    uint8_t  reserved0[2];
    uint32_t requester_id;
    uint64_t seq;
} chipsim_data_pull_msg_t;
```

### Suggested `DATA_REPLY` extension

```c
typedef struct {
    uint8_t          type;
    uint8_t          has_packet;
    uint8_t          edge;
    uint8_t          reserved0;
    uint32_t         responder_id;
    uint64_t         seq;
    chipsim_packet_t packet;
} chipsim_data_reply_msg_t;
```

This gives the runtime enough information to validate not only:
- who sent the reply
- which tick it belongs to

but also:
- which directional link it belongs to

## Suggested Endpoint Layout

The current code uses one data endpoint per chip. The new design should use one data endpoint per chip edge.

A simple deterministic mapping is:
- `port = data_port_base + chip_id * 4 + edge_id`

where:
- `edge_id = 0` for north
- `edge_id = 1` for east
- `edge_id = 2` for south
- `edge_id = 3` for west

This gives each chip four stable edge-specific service URLs and avoids string-heavy endpoint construction.

## Tick Execution Under The New Model

## Software backend

For a software chip backend, one tick should look like:

1. Receive `TICK(seq)` from orchestrator.
2. Publish zero or one output packet for each output edge for tick `seq`.
3. Pull from every configured input edge for tick `seq`.
4. Generate local traffic if applicable.
5. Apply deterministic ingress arbitration across:
   - local packet(s)
   - north input
   - east input
   - south input
   - west input
6. Enqueue accepted packets into local FIFO(s).
7. Dequeue/service the forwarding logic for future output publication.
8. Reply `DONE(seq)`.

This software path remains useful as a simple reference backend, but it is not the intended source of local traffic for the LArPix network mode.

## RTL/cosim backend

For the LArPix-oriented RTL/cosim backend, local traffic should come from the LArPix chip model itself rather than from a synthetic `gen_ppm` packet generator.

The intended local-traffic source is:
- a software analog frontend model that accepts injected charge inputs
- the existing LArPix digital core running in Verilator/cosimulation
- the chip's own packet-generation logic inside the digital core and associated communication path

In other words, local traffic generation for `larpix_network_sim` should work like this:

1. The chip runtime receives `TICK(seq)` from the orchestrator.
2. The runtime provides one or more per-channel charge inputs to the software analog frontend model.
3. The software analog frontend converts those charge inputs into the digital-facing signals expected by the LArPix digital core, such as discriminator hits and ADC completion/data behavior.
4. The Verilated LArPix digital core consumes those frontend signals.
5. The digital core generates packets internally when appropriate.
6. Those locally generated packets become the chip's candidate output traffic for the network edges.
7. The runtime publishes those packets onto the enabled directional output links.
8. The runtime also pulls packets from the four neighbor input edges and feeds them into the chip backend on the next tick.

Under this model, local traffic is not just random packet generation. It includes the actual packet classes created by the LArPix chip logic, including:
- event/data packets originating from injected charge activity
- configuration readback packets
- status packets
- any other locally generated control or monitoring packets produced by the chip backend

This is the key architectural distinction for `larpix_network_sim`:
- the outer network runtime is responsible for deterministic ticking and inter-chip transport
- the LArPix cosim backend is responsible for deciding when local packets exist and what type of packets they are

This is where the architecture becomes adaptable to the LArPix work:
- the runtime handles NNG transport and lock-step sequencing
- the backend adapter handles the chip-specific directional interface and local packet creation

## Backend Abstraction Recommendation

The current runtime is strongly tied to the FIFO router backend. That is workable for the current design but not ideal for a LArPix migration.

The cleaner long-term structure is to separate:
- transport and orchestration plumbing
- chip backend behavior

A reasonable direction is a backend interface along these lines:

```c
struct chipsim_backend_vtbl {
    int  (*tick)(void *ctx, const chipsim_tick_inputs_t *in, chipsim_tick_outputs_t *out);
    void (*destroy)(void *ctx);
};
```

For `larpix_network_sim`, the important decision is that backend tick inputs and outputs should operate at the **serial-bit level**, not at the completed-packet level.

That follows directly from the timing model already chosen in this plan:
- one simulation tick = one chip clock cycle / one UART bit-time
- inter-chip communication is serialized on `piso` / `posi`

So the backend boundary should eventually look more like:

```c
typedef struct {
    uint64_t seq;
    bool edge_rx_bit_valid[4];
    uint8_t edge_rx_bit[4];
    double charge_in[64];
} chipsim_tick_inputs_t;

typedef struct {
    bool edge_tx_bit_valid[4];
    uint8_t edge_tx_bit[4];
} chipsim_tick_outputs_t;
```

The backend may still maintain internal packet FIFOs and word-level packet state, but the runtime-facing interface should be serial-bit-based so that the network timing model remains faithful to the LArPix UART links.

Then:
- the current software FIFO implementation becomes one backend
- the current `chip_fifo_router.sv` Verilated wrapper becomes another backend
- a future LArPix RTL/cosim backend becomes a third backend

This keeps the transport layer generic while making the backend replaceable.

## How This Relates To LArPix

The current RTL under `rtl/chip_fifo_router.sv` is a 2-input, 1-output FIFO router. That is useful as a simple backend but it is not the right abstraction for a LArPix-oriented network chip.

For a LArPix backend, the runtime should eventually support:
- four neighbor-facing inputs
- four neighbor-facing outputs
- chip-local event generation
- packet routing decisions inside the chip backend
- directional enable and forwarding behavior driven by the RTL/cosim model

This means the LArPix backend should not be forced into the existing single-input/single-output route contract.

## File-Level Impact

### `src/`

#### `src/chip.c`

This file currently assumes:
- one input chip
- one output chip
- one `REQ` data socket
- one `REP` data service

It will need to be extended or refactored so it can:
- hold four input neighbor IDs
- hold four output neighbor IDs
- own up to four `REQ` sockets
- own up to four `REP` sockets
- publish per-edge outgoing packets
- pull per-edge incoming packets
- arbitrate across four neighbor sources instead of one

#### `src/chip_rtl.cpp`

This file needs the same transport changes as `src/chip.c`, but with a second layer of work:
- it must map four directional neighbor packets into the backend model
- it must extract up to four directional outputs from the backend model

This is the most important runtime-side adaptation point for integrating a future LArPix RTL/cosim backend.

#### `src/orchestrator.c`

This file currently validates a `1-in/1-out` route graph.

It will need to change so that it can:
- parse directional route definitions
- validate per-edge nearest-neighbor consistency
- ensure reciprocal edge mappings are correct where required
- pass the expanded directional connectivity to each chip process at launch

The lock-step control protocol itself should remain unchanged.

### `rtl/`

#### `rtl/chip_fifo_router.sv`

This RTL should be treated as the legacy/simple backend, not as the foundation for the LArPix network model.

It may still be useful for:
- software-vs-RTL parity tests
- basic FIFO/router experiments
- regression preservation

But the LArPix path should use a separate backend adapter rather than trying to mutate this module into a four-edge network chip.

### `scripts/`

#### `scripts/run_from_config.py`

This launcher currently understands the old `{id,input_id,out_id}` schema.

It will need to evolve so it can:
- parse directional `inputs` and `outputs`
- parse startup configuration and stimulus sections
- generate the expanded chip CLI arguments
- preserve deterministic launch behavior
- optionally support migration from old configs if backward compatibility is desired

In addition, `larpix_network_sim` should have a helper script dedicated to building startup configuration packets, including variable routing bits for each chip. That helper should take the intended topology / routing description and emit the configuration packet sequence needed to program the chips at startup.

### `doc/`

#### `doc/architecture.md`

This document currently describes a `1-in/1-out` network.

It will need a new version of the architecture description covering:
- four-edge connectivity
- per-edge `REQ/REP` data transport
- directional route validation
- backend abstraction and LArPix adaptation

### `AGENTS.md`

`AGENTS.md` currently treats the `1-in/1-out` model as frozen.

So before implementation begins, there should be an explicit migration note or revision that records:
- the current architecture is valid for the existing simulator backend
- the new LArPix-oriented network mode is a planned architectural extension
- the extension is intentionally changing the frozen connectivity model

## Recommended Migration Strategy

The safest approach is not to replace the old architecture immediately. Instead, add a new version alongside it.

### Suggested path

1. Keep the current `1-in/1-out` simulator working.
2. Introduce a new `4-edge` route schema and protocol extension.
3. Add new chip binaries for the new architecture, for example:
   - `build/chip4`
   - `build/chip_rtl4`
   - or `build/chip_larpix`
4. Add launcher support for the new directional configuration format.
5. Add documentation describing both the old and new models during migration.
6. Only retire the old route model after the new one is validated.

This is especially important because the current repository contracts explicitly call out the old model as stable.

## Summary

The right architectural evolution is:
- keep the existing orchestrator lock-step control plane
- replace the current single-link data plane with a four-edge data plane
- add edge identity to the data protocol
- refactor the chip runtime around per-edge sockets
- introduce a backend abstraction layer
- treat the current FIFO-router RTL path as legacy/simple backend support
- build the LArPix path as a separate, directional backend

This gives the simulator a clean migration path from the current `1-in/1-out` digital network model to a `4-neighbor` architecture that is compatible with the LArPix RTL/cosim work.


## External Charge Injection Model

For `larpix_network_sim`, local event generation should not be driven only by an internal packet generator. It should also accept explicit external charge inputs into the software analog frontend for every chip and every channel.

This should be treated as a first-class simulation input.

### Required capability

Each chip should support charge injection on every analog channel as an external input.

That means the network configuration must be able to describe:
- which chip receives the injected charge
- which channel on that chip receives the injected charge
- the charge magnitude applied to that channel
- optionally, how that charge varies over time in clock cycles

### Basic static per-channel injection

The simplest form is a per-chip, per-channel scalar charge input.

Conceptually:
- chip `c`
- channel `k`
- injected charge `q`

This allows different channels on different chips to receive different fixed charge values.

A natural representation is a 2D array indexed by:
- chip id
- channel id

For example, conceptually:

```text
charge_injection[chip_id][channel_id] = charge_value
```

This is useful for:
- static per-channel calibration studies
- chip-to-chip nonuniformity studies
- controlled sparse stimulus patterns across a network

### Time-varying waveform injection

The more general form is a waveform input over time.

In that case, each chip/channel pair should be able to accept a charge waveform indexed by clock cycle.

Conceptually:

```text
charge_injection[chip_id][channel_id][tick] = charge_value
```

or equivalently as a per-channel list of `(tick, charge)` samples.

This enables:
- pulses of different widths or amplitudes
- multi-cycle analog stimulus on one channel
- different waveform shapes on different channels and chips
- replay of precomputed charge traces

### Recommended semantics

The cleanest runtime model is:
- at the beginning of each simulated tick, the chip runtime looks up the configured charge input for each local channel at that tick
- those charge values are passed into the software analog frontend model for that chip
- the analog frontend updates its per-channel state
- the Verilated digital core sees the resulting `hit`, `done`, and `dout` behavior
- the digital core then generates event packets, readback packets, and status packets as appropriate

Under this model, the charge waveform is an external stimulus to the chip, not an internal transport packet.

### Recommended configuration representation

The routing configuration and the analog stimulus configuration should be separate.

The route map should describe chip-to-chip connectivity.
The stimulus section should describe charge input.

A reasonable JSON structure would be:

```json
{
  "stimulus": {
    "charge": [
      {
        "chip_id": 5,
        "channel": 12,
        "tick": 100,
        "charge": -5.0e-15
      },
      {
        "chip_id": 5,
        "channel": 12,
        "tick": 101,
        "charge": -2.5e-15
      },
      {
        "chip_id": 9,
        "channel": 31,
        "tick": 250,
        "charge": -8.0e-15
      }
    ]
  }
}
```

This sparse event-list form is usually better than storing a dense 3D tensor for long runs.

If a dense form is needed for analysis or generated input files, it can still conceptually represent:

```text
charge_injection[chip_id][channel_id][tick]
```

but the runtime should probably load it into a sparse internal representation.

### Startup configuration requirement

`larpix_network_sim` should require a startup configuration phase before normal network traffic begins.

This means:
- every chip must receive configuration packets at startup
- those packets are part of the simulation definition, not an optional manual test step
- the startup configuration should program the chip into the intended network mode before charge-driven event traffic is injected

For the LArPix network mode, this startup configuration must also carry routing-related configuration. In other words, routing should not exist only as an outer runtime concept; the chip configuration packets should contain the routing bits that tell the chip how to forward traffic on its directional links.

So the simulation startup sequence should conceptually be:
1. reset all chips
2. inject startup configuration packets into the network or directly into the configured control path
3. allow the chips to apply that configuration
4. begin normal charge stimulus and packet traffic

This also implies that `larpix_network_sim` needs a helper script that can build startup configuration packets with variable routing bits, so that network topology and chip-local routing state are programmed consistently from the same simulation setup.

### Why this belongs in the architecture

This is not just a testbench convenience feature. For `larpix_network_sim`, explicit charge injection is the mechanism by which the network receives physically meaningful local stimulus.

It is the input that causes the LArPix cosim backend to generate local traffic.

So for the LArPix mode, the true local-input chain is:
- external charge stimulus
- software analog frontend
- Verilated digital core
- locally generated packet traffic
- directional network transmission to neighbors

### Tick meaning for network simulation

For `larpix_network_sim`, one simulation tick should represent one chip clock cycle, which is also the serial bit-time used by the UART link logic in the current LArPix RTL.

This timing choice is important. The simulator should **not** treat one tick as one full 64-bit packet transfer on a link.

Instead, the intended model is:
- internal packet formation inside the chip may happen on full-width packet words
- internal FIFOs may store and move full 64-bit packet words in parallel
- but inter-chip communication on `piso` / `posi` is serial
- so one transmitted packet occupies the link for multiple ticks

In the current UART RTL, one 64-bit packet takes approximately:
- 1 start bit
- 64 data bits
- 1 stop bit

So one packet occupies about `66` ticks on a serial link.

This leads to an important architectural distinction:
- **inside the chip**, packet movement may be word-parallel
- **between chips**, packet movement is serial and must consume many ticks

That means the network runtime should model:
- packet creation latency inside the backend
- FIFO movement inside the backend
- serial link occupancy and serial receive latency between chips

This is the right choice for LArPix fidelity, because otherwise a packet-atomic tick model would erase real link serialization effects such as:
- transmission latency
- line occupancy
- contention timing
- neighbor receive delay

### Practical implication for implementation

The chip runtime should eventually accept a per-tick charge-stimulus object in addition to neighbor packet inputs.

Conceptually, a backend tick input should include both:
- neighbor packets from north/east/south/west
- local analog charge inputs for channels `0..63`

Something in this direction:

```c
typedef struct {
    bool have_neighbor[4];
    chipsim_packet_t neighbor_packet[4];
    double charge_in[64];
} chipsim_tick_inputs_t;
```

For a waveform-driven run, `charge_in[ch]` is simply the charge value for that channel at the current tick.

This should be part of the planned `larpix_network_sim` architecture from the beginning.
