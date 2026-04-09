# Visualizer Status

## Purpose

The current web-based visualizer under [packet_transmission](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission) is a browser playback tool for `larpix_network_sim` live runs.

Its current role is to show the RTL-backed digital-core state over time during a live network run.

Primary things shown now:
- FPGA transmit activity into the source chip from the south.
- `CHIP_ID` changes when a config write is applied.
- `ENABLE_PISO_UP` lane state on each chip.
- `ENABLE_PISO_DOWN` lane state on each chip.

Internal packet motion is still present in the playback data, but it is now secondary to the chip-state timeline.

## Current Browser App

Current files:
- [index.html](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/index.html)
- [style.css](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/style.css)
- [main.js](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/main.js)

Current viewer behavior:
- renders the chip grid on a full-window canvas
- draws chip UART lanes as outgoing arrows
- colors lane arrows from the current chip state: blue for `ENABLE_PISO_UP`, orange for `ENABLE_PISO_DOWN`
- shows chip IDs in the top-left of each chip
- draws an `FPGA` box below the source chip
- lights the FPGA upward arrow while the FPGA is transmitting
- highlights a chip when a config write is applied at that tick
- shows the applied register and data in the HUD/selection text
- supports play/pause, step, step back, reset, scrubber, and speed control

## Current Playback Model

The browser app expects a sparse playback JSON with:
- `name`
- `rows`
- `cols`
- `source`
- `total_ticks`
- `initial_chips`
- `chip_updates`
- `packet_spans`
- `fpga_spans`

Interpretation:
- `initial_chips` sets the starting RTL-visible configuration state.
- `chip_updates` are the primary events for the visualizer.
  - these represent config writes being applied in a chip
  - they update `chip_id`, `up_mask`, or `down_mask`
- `fpga_spans` show when the FPGA is actively transmitting a frame.
- `packet_spans` are still available, but they are not the main signal the viewer is built around right now.

## File Flow

The current end-to-end file flow for the live `3x5` bootstrap visualization is:

1. Bootstrap protocol reference
- [bootstrap_id_protocol_sim.py](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/bootstrap_id_protocol_sim.py)
- This is the toy reference for the bootstrap routing and chip-ID assignment logic.

2. Startup schedule generation
- [generate_bootstrap_chip_id_readback_json.py](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/generate_bootstrap_chip_id_readback_json.py)
- Generates the live startup JSON schedule for arbitrary `rows`, `cols`, and source `s`.

3. Startup schedule used by the live run
- [startup_3x5_bootstrap_chip_ids.json](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/config/startup_3x5_bootstrap_chip_ids.json)

4. Startup schedule compilation into UART frames
- [compile_startup_json.py](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/compile_startup_json.py)

5. Live network runtime
- [run_3x5_bootstrap_id_startup.sh](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/run_3x5_bootstrap_id_startup.sh)
- Launches the live network run using:
  - [orchestrator_larpix.c](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/orchestrator_larpix.c)
  - [chip_larpix.cpp](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/chip_larpix.cpp)
  - [larpix_cosim_backend.cpp](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/larpix_cosim_backend.cpp)
  - [fpga_larpix.cpp](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/fpga_larpix.cpp)

6. Live run output
- [run.log](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_3x5_bootstrap_id_smoke/run.log)
- This contains the FPGA transmit events and received readback packets for the live run.

7. Conversion into browser playback JSON
- [convert_live_bootstrap_log_to_playback.py](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/convert_live_bootstrap_log_to_playback.py)
- This reads:
  - the startup JSON schedule
  - the live `run.log`
- and writes a sparse playback file focused on chip-state changes plus FPGA transmission spans.

8. Browser playback file
- [live_bootstrap_3x5.json](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/data/live_bootstrap_3x5.json)

9. Browser playback
- [index.html](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/index.html)
- [main.js](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/main.js)
- [style.css](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/style.css)

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

## How To View

From the repo root:

```bash
python3 -m http.server 8000
```

Then open:

```text
http://localhost:8000/larpix_network_sim/visualizers/packet_transmission/
```

By default, the page loads:
- [live_bootstrap_3x5.json](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/visualizers/packet_transmission/data/live_bootstrap_3x5.json)

## Current Limitations

Known limitations:
- internal packet spans are still approximate and are not the main model
- the converter infers state application timing from the startup schedule and FPGA log, not from a dedicated chip-local trace stream
- there is no general converter yet for analog/event-data runs
- there is no direct live socket connection; playback remains offline from JSON
- the HUD is still minimal for long runs

## Current Status Summary

The visualizer is now in a usable first state for live bootstrap runs.

It currently supports:
- browser playback of a real live-network run
- tick-by-tick stepping over a run with thousands of ticks
- FPGA transmit visualization at the source chip
- chip-state visualization based on applied config writes
- lane-state and chip-ID changes over time during bootstrap

The next likely work items are:
- extract chip-local config-application events directly from the runtime instead of inferring them
- add a clearer per-tick event list in the HUD
- support additional live scenarios beyond bootstrap/readback
- optionally reintroduce more detailed internal packet motion once the state timeline is solid
