# Packet Transmission Visualizer

## Goal

Build a browser-based visualizer for LArPix network packet motion that is inspired by the interaction model and presentation style of [`nifty-routing-board-game`]( /home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/nifty-routing-board-game/README.md ).

The visualizer should make it easy to see:
- where each chip is located in the `rows x cols` network
- which UART lanes are enabled on each chip
- which packets are moving between chips on each tick
- when packets are locally generated, forwarded, read back, or dropped
- how startup configuration traffic and later event/data traffic propagate through the network

This visualizer is intended as a debugging and demonstration tool for `larpix_network_sim`, not as a game.

## Reference App Features To Reuse

From [`nifty-routing-board-game`]( /home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/nifty-routing-board-game/README.md ) and its browser implementation:
- full-window canvas rendering
- a compact fixed HUD in the top-left corner
- step / step-back / run / pause controls
- turn-by-turn discrete movement
- strong visual emphasis on board state and object motion rather than menus
- keyboard-first control flow
- lightweight static-web-app deployment model (`index.html` + JS + optional WASM)

The LArPix visualizer should borrow that overall feel:
- the network grid should fill most of the screen
- the HUD should stay small and readable
- each simulation tick should correspond to one visual step
- packet movement should be visually obvious

## Scope

### Phase 1

The first version should visualize playback of an already-generated simulation trace or packet-motion log.

It does not need to run the simulation itself.

It should:
- load a trace/log file produced by `larpix_network_sim`
- render a rectangular chip grid
- animate packet movement tick by tick
- show chip-local state relevant to routing
- allow pause, play, single-step forward, and single-step backward

### Out Of Scope For Phase 1

- editing routing in the visualizer
- launching the simulator directly from the browser
- live socket connection into a running simulation
- analog waveform plotting
- RTL waveform viewing

## Visual Model

### Board Layout

- One rectangular board cell per chip.
- The grid orientation should match the simulation conventions:
  - `x` increases to the right
  - `y=0` is the bottom row
  - larger `y` values appear higher on the board
- A chip cell should display at least:
  - chip ID
  - `(x,y)` coordinate optionally in smaller text
  - enabled upstream TX mask
  - enabled downstream TX mask

### Edge / Lane Display

Each chip cell should visually indicate the four directional UART lanes:
- north
- east
- south
- west

The lane styling should distinguish:
- lane disabled
- lane enabled in `ENABLE_PISO_UP`
- lane enabled in `ENABLE_PISO_DOWN`
- optionally lane enabled in both, if that ever occurs in a trace

Recommended visual encoding:
- muted gray for disabled
- one distinct color for upstream-enabled
- one distinct color for downstream-enabled
- thicker stroke or glow when a packet is actively traversing that lane this tick

### Packet Display

Packets should be rendered as moving markers traveling from one chip center toward another across one edge during one tick.

Recommended behavior:
- during tick `t`, a packet moving from chip A to chip B should be drawn partway along the relevant edge
- on stepping to the next tick, it should appear at the destination chip or continue as another hop depending on the trace data
- different packet classes should be distinguishable:
  - config write
  - config read request
  - config read reply
  - event/data packet

Recommended encoding:
- different colors by packet type
- optional short labels on hover or selection
- packet trail fade for the last few ticks to show recent history

## Control Model

The control model should follow the routing-board app closely.

Required controls:
- `Space`: play / pause
- `S`: step forward one tick
- `Z`: step backward one tick
- `R`: reset to tick 0

Recommended additions:
- `[` and `]` or arrow keys to move backward/forward faster
- speed selector for autoplay
- tick scrubber / timeline slider
- packet-type visibility toggles

## HUD

A compact HUD should remain visible in the top-left corner.

It should show:
- current file / scenario name
- current tick
- total ticks
- play / pause state
- number of packets visible this tick
- selected chip or selected packet details
- key controls summary

Optional but useful:
- current network dimensions
- current source chip / FPGA attachment point
- running counts of packets by type

## Data Input

The visualizer should be driven by a precomputed JSON input tailored for playback.

The playback JSON should contain at least:
- board dimensions: `rows`, `cols`
- initial chip state
- per-tick events
- optional packet metadata

A likely schema shape is:

```json
{
  "rows": 3,
  "cols": 5,
  "chips": [
    {
      "x": 0,
      "y": 0,
      "chip_id": 0,
      "up_mask": 3,
      "down_mask": 4
    }
  ],
  "ticks": [
    {
      "tick": 85,
      "events": [
        {
          "type": "packet_move",
          "packet_type": "config_write",
          "src": [0, 0],
          "dst": [1, 0],
          "edge": "east",
          "packet_word": "0x822541391ffce806"
        }
      ]
    }
  ]
}
```

The actual schema can evolve, but it must support:
- deterministic replay
- per-tick chip-state updates
- per-tick packet motion
- packet details lookup

## Data Preparation Pipeline

The visualizer should not need to parse raw RTL or orchestrator logs directly.

Instead, the architecture should include a preprocessing step that converts simulation output into visualizer JSON.

Expected file flow:
- `larpix_network_sim` simulation run
- log / trace / packet activity output
- converter script
- visualization-ready JSON
- browser visualizer playback

A separate helper script should be expected for this conversion.

## Interaction Requirements

### Selection

Clicking a chip should show:
- chip ID
- coordinates
- current upstream/downstream masks
- packets sent/received on the current tick if available

Clicking a packet should show:
- packet type
- packet word
- source and destination chip
- tick index
- decoded fields if available

### Filters

The first version should ideally support toggling visibility for:
- config writes
- config reads
- config replies
- data packets

## Rendering Requirements

- Must work well on desktop browser first.
- Should handle at least medium networks like `10x10` smoothly in playback mode.
- Must remain readable for smaller networks like `1x1`, `2x2`, `3x5`.
- Should prefer clean 2D rendering over unnecessary 3D effects.

A canvas-based renderer similar to the routing-board reference is preferred.

## Styling Direction

The visual style should intentionally resemble a debugging board / routing panel rather than a polished consumer dashboard.

Recommended direction:
- dark background
- bright lane overlays
- clear packet colors
- monospaced small labels where appropriate
- minimal but readable HUD

The visualizer should feel close in spirit to the routing-board game:
- strong contrast
- obvious movement
- dense but legible board-centric presentation

## Technical Direction

The reference app uses:
- `index.html`
- `main.js`
- optional WASM/C rendering core

The LArPix visualizer can follow the same lightweight structure.

Recommended initial layout under `larpix_network_sim/visualizers/packet_transmission/`:
- `index.html`
- `main.js`
- `style.css` or inline styles
- optional `main.wasm` later if performance justifies it
- sample playback JSON files

For the first version, plain JS + canvas is likely sufficient.

## Validation Goals

The visualizer should be able to clearly demonstrate at least these scenarios:
- single-chip startup config read/write
- single-chip event packet generation after charge injection
- `3x5` chip-ID bootstrap assignment with immediate readbacks
- packet travel over multiple hops in a larger network

A good validation milestone is:
- load the `3x5` bootstrap playback
- visually confirm the same traversal order as the toy protocol
- visually confirm immediate readback after each reassignment

## Deliverables For The First Implementation

1. A markdown spec for the visualizer.
2. A playback JSON schema definition or example.
3. A converter script plan from simulation logs to playback JSON.
4. A minimal browser app that can:
- load a playback JSON file
- render the chip grid
- animate packet movement
- step forward/backward by tick
- show a compact HUD

## First Concrete Target

The first concrete visual demonstration should be:
- the `3x5` bootstrap chip-ID assignment test with source `s=0`
- showing all config writes and immediate CHIP_ID readbacks
- ending in the final board state documented by the toy simulator

That will provide a direct visual comparison between:
- the toy bootstrap protocol
- the live distributed network behavior

and will establish the visualizer as a real debugging tool for packet routing correctness.
