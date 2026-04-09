# Visualizer Status

## Purpose

The current web-based visualizer under [`packet_transmission`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission) is a browser playback tool for packet motion in `larpix_network_sim`.

It is now aimed at **live network simulation output**, not the toy bootstrap simulator.

The viewer is intended to show:
- a rectangular chip array
- enabled UART routing lanes on each chip
- packet motion across chip-to-chip links
- FPGA-to-source-chip configuration traffic
- long playback over many bitwise simulation ticks

## Current Browser App

Current files:
- [`index.html`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/index.html)
- [`style.css`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/style.css)
- [`main.js`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/main.js)

Current viewer behavior:
- renders the chip grid on a full-window canvas
- draws chip-to-chip UART lanes as directional outgoing arrows
- draws packet motion over the links using sparse packet spans
- supports play/pause, step, step back, reset, scrubber, and speed control
- allows chip selection by click
- draws a small `FPGA` box below the source chip
- lights the FPGA upward arrow while FPGA configuration traffic is being transmitted

The viewer currently plays a **sparse live-playback JSON** rather than a toy `ticks[]` demo format.

## Current Live Playback Format

The browser app now expects playback JSON of the form:
- `name`
- `rows`
- `cols`
- `source`
- `total_ticks`
- `initial_chips`
- `chip_updates`
- `packet_spans`
- `fpga_spans`

The important idea is:
- the visualizer is still stepped by **individual simulation ticks**
- but the file is **sparse**, so it does not store full board state for every tick
- instead it stores:
  - initial chip state once
  - chip-state changes only when they occur
  - packet spans with `start_tick` and `end_tick`

That makes it suitable for live runs that may contain thousands of bitwise ticks.

## File Flow

The current end-to-end file flow for the live `3x5` bootstrap visualization is:

1. Bootstrap protocol reference
- [`bootstrap_id_protocol_sim.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/bootstrap_id_protocol_sim.py)
- This is the toy reference for the bootstrap routing and chip-ID assignment logic.

2. Startup schedule generation
- [`generate_bootstrap_chip_id_readback_json.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/generate_bootstrap_chip_id_readback_json.py)
- Generates the live startup JSON schedule for arbitrary `rows`, `cols`, and source `s`.

3. Startup schedule used by the live run
- [`startup_3x5_bootstrap_chip_ids.json`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/config/startup_3x5_bootstrap_chip_ids.json)
- This is the `3x5`, `s=0` startup configuration sequence.

4. Startup schedule compilation into UART frames
- [`compile_startup_json.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/compile_startup_json.py)
- Converts the startup JSON into packet words and UART bitstreams for the FPGA controller.

5. Live network runtime
- [`run_3x5_bootstrap_id_startup.sh`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/run_3x5_bootstrap_id_startup.sh)
- Launches the live network run using:
  - [`orchestrator_larpix.c`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/orchestrator_larpix.c)
  - [`chip_larpix.cpp`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/chip_larpix.cpp)
  - [`larpix_cosim_backend.cpp`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/larpix_cosim_backend.cpp)
  - [`fpga_larpix.cpp`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/fpga_larpix.cpp)

6. Live run output
- [`run.log`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_3x5_bootstrap_id_smoke/run.log)
- This log contains the live FPGA transmit events and received readback packets.

7. Conversion from live run output to browser playback JSON
- [`convert_live_bootstrap_log_to_playback.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/convert_live_bootstrap_log_to_playback.py)
- This script reads:
  - the startup JSON schedule
  - the live `run.log`
- and writes a sparse visualization playback file.

8. Browser playback file
- [`live_bootstrap_3x5.json`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/data/live_bootstrap_3x5.json)
- This is the file the browser visualizer currently loads by default.

9. Browser playback
- [`index.html`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/index.html)
- [`main.js`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/main.js)
- [`style.css`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/style.css)

So the effective flow is:

- toy protocol logic
- startup schedule JSON
- compiled UART startup schedule
- live network run
- `run.log`
- playback converter
- browser playback JSON
- visualizer canvas app

## Current Live Example

The browser app is currently wired to the live `3x5` bootstrap/readback example:
- `rows = 3`
- `cols = 5`
- `s = 0`

The live network run that feeds the visualizer produced:
- `expected_frame_count = 62`
- `observed_transmitted_frame_count = 62`
- `verified_readbacks = 0,254,2,3,4,5,10,6,11,7,12,8,13,9,14,1`

This corresponds to the immediate-readback bootstrap test, where every chip-ID reassignment is followed by a readback confirmation before the sequence proceeds.

## How To View The Visualizer

From the repo root:

```bash
python3 -m http.server 8000
```

Then open:

```text
http://localhost:8000/larpix_network_sim/visualizers/packet_transmission/
```

By default, the page now attempts to load:
- [`live_bootstrap_3x5.json`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/data/live_bootstrap_3x5.json)

A different playback JSON can also be loaded through the file input in the HUD.

## Current Limitations

The current visualizer is useful, but still early.

Known limitations:
- packet classification is still approximate for some spans
- packet hover/selection details are minimal
- there is no converter yet for general event-data runs beyond the current bootstrap flow
- there is no direct live socket connection; playback is offline from JSON
- the renderer does not yet display raw UART bit values explicitly, only packet spans reconstructed from the live run
- there is no timeline event list or packet search yet

## Current Status Summary

The visualizer is now past the toy-demo stage.

It currently supports:
- browser playback of a **real live-network run**
- tick-by-tick stepping over a run with more than ten thousand ticks
- chip state updates derived from the live bootstrap process
- FPGA visualization at the source chip
- packet motion reconstructed from the live `3x5` bootstrap/readback run

The next likely work items are:
- improve packet labeling and packet detail popups
- generalize the converter for more live run types
- add support for event-packet playback from analog/cosim tests
- add better filtering and timeline navigation for long runs
