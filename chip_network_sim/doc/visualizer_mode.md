# Visualizer Mode

This document explains how to launch the web-based visualizer and point it at a playback JSON produced by a scenario run.

This mode assumes the user has already:

- completed the prerequisite steps
- integrated RTL and built a chip executable
- run a scenario that produced a playback JSON

## 1. What Visualizer Mode Produces

At the end of this mode, the user should be able to:

- serve the repo locally in a browser
- open the packet-transmission visualizer
- load a specific scenario playback JSON
- understand which run artifacts are required for playback

## 2. Visualizer Entry Point

The local browser entry point is:

- `sim_core/visualizers/packet_transmission/index.html`

This visualizer accepts a `playback` query parameter pointing at a playback JSON file.

## 3. What Playback JSON Is

The visualizer does not read `run.log` or `trace.jsonl` directly.

Instead, it reads a derived playback JSON that reconstructs the run timeline using:

- scenario input artifacts such as `startup_*.json`, `startup_*.compiled.json`, or `init_*.json`
- raw run outputs such as `run.log` and `trace.jsonl`
- a conversion step that builds the browser-facing playback JSON

Typical playback files look like:

- `live_event_3x5_chip14.json`
- `live_event_2x2_packet_loss_probe.json`
- `live_bootstrap_3x5_chip_ids.json`

## 4. Where Playback Files Live

Scenario playback files are written under:

```text
build/<scenario_name>__<chip_variant>/
```

Examples:

- `build/larpix_1chip_event_smoke__v3b/`
- `build/larpix_3x5_event_top_right__v3b/`
- `build/larpix_2x2_msg_data_probe__msg/`

The visualizer should be pointed at the playback JSON inside that directory.

## 5. Serve The Repo Locally

The visualizer must be opened through a local web server, not as a raw `file://` path.

From the repo root, a simple option is:

```bash
python3 -m http.server 8000
```

Then open:

```text
http://localhost:8000/
```

## 6. Local URL Pattern

The standard local visualizer URL pattern is:

```text
http://localhost:8000/sim_core/visualizers/packet_transmission/?playback=/build/<scenario_name>__<chip_variant>/<playback_file>.json
```

Examples:

- `http://localhost:8000/sim_core/visualizers/packet_transmission/?playback=/build/larpix_3x5_event_top_right__v3b/live_event_3x5_chip14.json`
- `http://localhost:8000/sim_core/visualizers/packet_transmission/?playback=/build/larpix_3x5_bootstrap_id_smoke__v3b/live_bootstrap_3x5_chip_ids.json`

## 7. Scenario-Specific Examples

For the maintained `v3b` scenarios, the local links follow the same pattern.

Examples:

- `15x15` double-track:
  `http://localhost:8000/sim_core/visualizers/packet_transmission/?playback=/build/larpix_15x15_event_staggered_multichip__v3b/live_event_15x15_staggered_multichip.json`

- `3x5` bootstrap CHIP_ID procedure:
  `http://localhost:8000/sim_core/visualizers/packet_transmission/?playback=/build/larpix_3x5_bootstrap_id_smoke__v3b/live_bootstrap_3x5_chip_ids.json`

- `3x5` top-right charge injection:
  `http://localhost:8000/sim_core/visualizers/packet_transmission/?playback=/build/larpix_3x5_event_top_right__v3b/live_event_3x5_chip14.json`

- `2x2` packet-loss probe:
  `http://localhost:8000/sim_core/visualizers/packet_transmission/?playback=/build/larpix_2x2_packet_loss_probe__v3b/live_event_2x2_packet_loss_probe.json`

## 8. How Playback JSON Gets Produced

All maintained playback-producing scenarios use:

- `sim_core/visualizers/packet_transmission/convert_live_trace_to_playback.py`

This converts:

- `run.log`
- `trace.jsonl`
- `startup_*.json` or `init_*.json`

into a browser playback JSON.

This includes the bootstrap CHIP_ID configuration scenario. Its configuration traffic still comes from `startup_*.json`, but the playback is reconstructed from the live chip trace using the same converter as the other maintained scenarios.

## 9. What To Check If The Visualizer Fails To Load

If the browser says the playback failed to load, check:

- the local web server is running
- the `playback` URL path matches the actual file under `build/...`
- the scenario run actually generated the playback JSON
- the playback file is non-empty

Useful checks:

```bash
ls -l build/<scenario_name>__<chip_variant>/
```

and:

```bash
test -s build/<scenario_name>__<chip_variant>/<playback_file>.json && echo ok
```

If the playback file is missing, rerun the scenario first.

## 10. Scope Boundary

This document is only about opening and using the browser visualizer.

It does not cover:

- how to build RTL into a chip executable
- how to write a scenario runner
- optional deeper debug and analysis artifacts

Those are covered in:

- `integrate_rtl_mode.md`
- `launch_scenario_mode.md`
- `internal_inspection_mode.md`
