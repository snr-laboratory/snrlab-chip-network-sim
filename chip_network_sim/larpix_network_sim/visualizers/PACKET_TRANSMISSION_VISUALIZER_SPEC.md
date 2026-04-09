# Packet Transmission Visualizer

## Goal

Build a browser-based visualizer for `larpix_network_sim` that is inspired by the interaction model and presentation style of [nifty-routing-board-game](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/nifty-routing-board-game/README.md).

The current implementation target is not a full packet-hop debugger. It is a state viewer for the RTL-backed digital core during live network playback.

The visualizer should make it easy to see:
- where each chip is located in the `rows x cols` network
- which UART lanes are enabled on each chip
- when the FPGA is transmitting configuration traffic into the source chip
- when a config write is applied and changes a chip's visible state
- how chip IDs and lane enables evolve during bootstrap

## Reference App Features To Reuse

From [nifty-routing-board-game](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/nifty-routing-board-game/README.md):
- full-window canvas rendering
- a compact fixed HUD in the top-left corner
- step / step-back / run / pause controls
- turn-by-turn discrete movement
- strong visual emphasis on board state rather than menus
- keyboard-first control flow
- lightweight static-web-app deployment model

## Current Scope

### Primary Goal

The first solid version should visualize playback of an already-generated live simulation run.

It should:
- load a playback JSON produced from a live `larpix_network_sim` run
- render a rectangular chip grid
- show FPGA transmit activity at the source chip south edge
- show chip-local state changes tick by tick
- allow pause, play, single-step forward, and single-step backward

### Secondary Goal

Internal packet spans may still be shown, but they are not the primary signal the viewer is built around right now.

### Out Of Scope For Now

- editing routing in the visualizer
- launching the simulator directly from the browser
- live socket connection into a running simulation
- analog waveform plotting
- RTL waveform viewing
- exact per-hop semantic tracing for every packet copy inside the network

## Visual Model

### Board Layout

- One rectangular board cell per chip.
- Grid orientation matches simulation conventions:
  - `x` increases to the right
  - `y=0` is the bottom row
  - larger `y` values appear higher on the board
- Each chip cell should display at least:
  - chip ID
  - enabled upstream TX mask as colored arrows
  - enabled downstream TX mask as colored arrows

### Edge / Lane Display

Each chip cell should indicate the four directional UART lanes:
- north
- east
- south
- west

Lane styling should distinguish:
- lane disabled
- lane enabled in `ENABLE_PISO_UP`
- lane enabled in `ENABLE_PISO_DOWN`

Recommended visual encoding:
- muted gray for disabled
- blue for upstream-enabled
- orange for downstream-enabled
- chip highlight when a config write is applied on the current tick

### FPGA Display

The visualizer should render a small FPGA/controller box below the source chip.

It should:
- be labeled `FPGA`
- have an upward arrow into the source chip
- light that arrow while the FPGA is actively sending a configuration frame

### Chip-State Display

The most important visual event is a chip-local configuration update.

Interpretation rule:
- a lane arrow changes color when the corresponding config write is applied in that chip
- a chip ID label changes when the `CHIP_ID` register write is applied
- this is intentionally different from trying to show every intermediate packet hop inside the network

## Control Model

Required controls:
- `Space`: play / pause
- `S`: step forward one tick
- `Z`: step backward one tick
- `R`: reset to tick 0
- scrubber / timeline slider
- speed selector for autoplay

## HUD

A compact HUD should remain visible in the top-left corner.

It should show:
- current file / scenario name
- current tick
- total ticks
- FPGA transmit activity when active
- selected chip details
- applied config-register update when one occurs on the current tick

## Data Input

The visualizer should be driven by a precomputed JSON input tailored for playback.

Current playback JSON contains at least:
- board dimensions: `rows`, `cols`
- source chip location
- initial chip state
- chip-local updates over time
- FPGA transmit spans
- optional packet spans

A representative shape is:

```json
{
  "rows": 3,
  "cols": 5,
  "source": {"x": 0, "y": 0},
  "initial_chips": [
    {
      "x": 0,
      "y": 0,
      "chip_id": 1,
      "up_mask": 0,
      "down_mask": 4
    }
  ],
  "chip_updates": [
    {
      "tick": 151,
      "x": 0,
      "y": 0,
      "event": "config_applied",
      "register_addr": 122,
      "register_data": 0,
      "chip_id": 0,
      "label": "bottom-row source assignment"
    }
  ],
  "fpga_spans": [
    {
      "start_tick": 85,
      "end_tick": 151,
      "packet_type": "config_write",
      "packet_word": "0x822541391c01e806",
      "label": "bottom-row source assignment"
    }
  ]
}
```

## Data Preparation Pipeline

Expected file flow:
- `larpix_network_sim` live run
- startup JSON and run log
- converter script
- visualization-ready playback JSON
- browser visualizer playback

A separate helper script is expected for this conversion.

## Rendering Requirements

- Must work well on desktop browser first.
- Must handle long runs with thousands of ticks.
- Must remain readable for small and medium networks.
- Should prefer clean 2D rendering over unnecessary effects.

A canvas-based renderer similar to the routing-board reference is preferred.

## Styling Direction

The visual style should resemble a debugging board / routing panel rather than a polished dashboard.

Recommended direction:
- dark background
- bright lane overlays
- monospaced labels
- minimal but readable HUD
- obvious state changes when config writes are applied

## Current Priority

The current priority is:
- robust state playback from live bootstrap runs
- accurate lane and chip-ID updates over time
- clear FPGA injection visualization

More detailed packet-hop tracing can come later once the chip-state timeline is solid.
