# Launch Scenario Mode

This document is for users working with LArPix-like RTL in this framework.

This mode assumes the user has already completed the earlier steps:

- the external prerequisites are installed
- the RTL has been integrated into the repo
- a chip executable has been built successfully

The purpose of this mode is to move from a built chip executable to an actual run:

- launch a live simulation through an existing scenario script
- inspect the resulting artifacts
- understand how to create a new scenario script

## 1. What This Mode Produces

At the end of this mode, the user should be able to:

- run one of the existing scenario scripts under `sim_core/scenarios/`
- collect run artifacts under `build/<scenario_name>__<chip_variant>/`
- optionally convert the run into playback JSON and open it in the visualizer
- create their own new scenario script that follows the same framework pattern

## 2. Scenario Scripts

In this repo, the maintained launch mechanism is the scenario script.

A scenario is a runnable shell script under:

- `sim_core/scenarios/`

that defines a concrete live-simulation workflow for a LArPix-like run.

Depending on the case, a scenario may:

- by default, build the required binaries
- generate startup JSON or init-register JSON
- generate a stimulus JSON
- launch `orchestrator_larpix`
- capture logs and trace artifacts under `build/<scenario_name>__<chip_variant>/`
- validate the observed results
- generate playback JSON for the visualizer

So when this document says “launch a simulation”, the default meaning is:

- choose a scenario script
- run that scenario script from the repo root

## 3. How To Run A Maintained Scenario

The most useful first live simulations are the single-chip smoke scenarios.

### Single-chip startup/readback scenario

Script:

- `sim_core/scenarios/run_1chip_fullreg_readback_startup.sh`

Purpose:

- bring up one chip
- inject startup configuration from the FPGA
- read back configuration registers
- verify the responses match the RTL defaults

### Single-chip analog/event scenario

Script:

- `sim_core/scenarios/run_1chip_event_startup.sh`

Purpose:

- bring up one chip
- configure it through startup packets, including setting `GLOBAL_THRESH = 0x0F`
  so the CSA threshold is explicitly programmed to about `0.60047 V`
- inject one charge pulse
- verify that a valid downstream data packet is received by the FPGA

These are the best first checks after a chip executable has been built.

### Where to run a scenario

Run scenario scripts from the repo root:

- `chip_network_sim/`

### Example: Run the `v3b` scenario

All maintained scenarios use the same launch interface:

- always set `CHIP_TARGET`
- always set `CHIP_BIN_NAME`
- omit `BUILD_BINARIES` to rebuild from scratch
- set `BUILD_BINARIES=0` to reuse binaries already present in `build/`

By default, the artifact directory name also includes a short chip-variant label derived from `CHIP_BIN_NAME`, such as:

- `v3b`
- `v3c`
- `v3b_v2`
- `msg`

So running the same scenario against different RTL variants keeps the outputs separate.

For an RTL variant called `v3b`, rebuild mode looks like:

```bash
CHIP_TARGET=chip_larpix_v3b_build \
CHIP_BIN_NAME=chip_larpix_v3b \
./sim_core/scenarios/run_1chip_event_startup.sh
```

Reuse-existing-binaries mode looks like:

```bash
BUILD_BINARIES=0 \
CHIP_TARGET=chip_larpix_v3b_build \
CHIP_BIN_NAME=chip_larpix_v3b \
./sim_core/scenarios/run_1chip_event_startup.sh
```

### Run a scenario with a different chip variant

For a LArPix-like RTL variant integrated into this framework, the expected naming pattern is:

```text
build/chip_larpix_<variant>
```

and the corresponding build target is expected to be:

```text
chip_larpix_<variant>_build
```

All of the maintained scenario scripts let the user override those names through environment variables.

For example, to run the 1-chip event scenario with `v3c`:

```bash
CHIP_TARGET=chip_larpix_v3c_build \
CHIP_BIN_NAME=chip_larpix_v3c \
./sim_core/scenarios/run_1chip_event_startup.sh
```

To reuse an already-built `v3c` binary:

```bash
BUILD_BINARIES=0 \
CHIP_TARGET=chip_larpix_v3c_build \
CHIP_BIN_NAME=chip_larpix_v3c \
./sim_core/scenarios/run_1chip_event_startup.sh
```

To run the 1-chip startup/readback scenario with `v3c`:

```bash
CHIP_TARGET=chip_larpix_v3c_build \
CHIP_BIN_NAME=chip_larpix_v3c \
./sim_core/scenarios/run_1chip_fullreg_readback_startup.sh
```

### What a maintained scenario does

The maintained scenario scripts typically:

- by default, configure and build the required binaries
- generate or compile startup/init inputs
- generate a stimulus JSON if needed
- launch `orchestrator_larpix`
- capture logs under `build/<scenario_name>__<chip_variant>/`
- validate the results automatically

### How to tell if the scenario succeeded

A maintained scenario is successful when:

- the script exits with code `0`
- it reaches its final validation step
- it prints its final `PASS` message

If the script exits nonzero, the scenario did not succeed.

## 4. Where Scenario Artifacts Go

Scenario scripts write artifacts under:

```text
build/<scenario_name>__<chip_variant>/
```

Examples:

- `build/larpix_1chip_event_smoke__v3b/`
- `build/larpix_1chip_event_smoke__v3c/`
- `build/larpix_2x2_msg_data_probe__msg/`

Artifacts include:

Input artifacts:

- `startup_*.json`
  Human-readable startup packet schedule describing configuration writes sent from the FPGA during the run.
- `startup_*.compiled.json`
  Compiled UART-frame form of the startup schedule used directly by the live runtime.
- `init_*.json`
  Human-readable preloaded register state applied directly to chips before tick `0` for preconfigured runs, rather than being compiled into FPGA UART traffic.
- `stimulus_*.json`
  Runtime stimulus description, such as charge injections or other scheduled chip-local activity.

Output artifacts:

- `run.log`
  Main textual log from the live run, including FPGA transmit and receive activity.
- `trace.jsonl`
  Line-by-line structured event trace emitted live by the running chip processes.
- playback JSON
  Browser-facing replay file built from the run inputs plus the raw live outputs.

For `trace.jsonl`, the important point is that it is generated live during the simulation run.

- each `chip_larpix` process connects to `trace_collector_larpix` over `NNG`
- during the run, each chip sends structured trace events as things happen
- `trace_collector_larpix` writes those events one JSON object per line into `trace.jsonl`

So `trace.jsonl` is not postprocessed from `run.log`. It comes directly from live chip state and chip-emitted events during the live simulation.

Optional analysis and debug artifacts are not part of the minimal scenario contract. Those are described in:

- `doc/internal_inspection_mode.md`

## 5. Visualizer After A Scenario Run

If a scenario produced playback JSON, the local visualizer entry point is:

- `sim_core/visualizers/packet_transmission/index.html`

The local URL pattern is:

```text
http://localhost:8000/sim_core/visualizers/packet_transmission/?playback=/build/<scenario_name>__<chip_variant>/<playback_file>.json
```

Many scenario scripts print a `visualizer_url_hint=...` line when they finish.

## 6. How To Write Your Own Scenario Runner

The easiest way to create a new scenario is to copy the closest existing script in `sim_core/scenarios/` and modify it for the new run.

The important mental model is that a runner script in this framework does two jobs:

- it prepares the exact input files the live run will consume
- it launches and validates the live simulation

A runner is therefore partly:

- a file-preparation script

and partly:

- a simulation-launch script

When this document says that a runner “generates” an input file, that can mean any of the following:

- call a helper script that writes the file
- copy and rewrite an existing source file into the scenario work directory
- emit a new JSON file directly from the runner

The key point is that the runner prepares the final per-run input files under `build/<scenario_name>__<chip_variant>/`, then passes those prepared files into `orchestrator_larpix`.

A scenario runner in this framework should do five things.

### 1. Define the scenario inputs and output paths

At the top of the script, define:

- `repo_root`
- `build_dir`
- `work_dir`
- input JSON paths such as `startup_in`, `stimulus_json`, or `init_json`
- output artifact paths such as `run.log`, `trace.jsonl`, and `playback_json`

This gives the scenario one dedicated artifact directory under `build/`.

### 2. Build the binaries the scenario needs

Every scenario should explicitly build the executables it depends on.

Typical pattern:

```bash
build_binaries="${BUILD_BINARIES:-1}"

if [[ "$build_binaries" == "1" ]]; then
  cmake -S "$repo_root" -B "$build_dir"
  cmake --build "$build_dir" --target fpga_larpix trace_collector_larpix orchestrator_larpix "$chip_target" -j
fi
```

If a runner supports binary reuse, it should also check that the required executables already exist before launch.

The scenario should not assume the correct binaries already exist.

### 3. Prepare the runtime inputs

A scenario should produce all of the runtime inputs it needs.

The two common patterns are:

- `startup_json`
  - generate or select a startup JSON
  - compile it with `sim_core/tools/compile_startup_json.py`

- `init_regs_json`
  - generate a preloaded register-state JSON for tick `0`

A scenario may also generate or rewrite a `stimulus_json` so the charge injection happens after configuration is complete.

### 4. Compute the tick budget and launch `orchestrator_larpix`

A scenario needs to choose:

- the network shape with `-rows` and `-cols`
- the source location with `-source_x` and `-source_y`
- the runtime length with `-ticks`
- the chip executable with `-chip_bin`
- the FPGA executable with `-fpga_bin`
- whether the run uses `-startup_json` or `-init_regs_json`
- whether the run uses `-stimulus_json`
- any optional trace outputs

A good pattern is to compute `ticks` from the last startup frame or last stimulus event plus a safety margin.

### 5. Validate the result

A scenario runner should always check whether the intended behavior occurred.

Typical validations include:

- the FPGA received at least one packet
- a packet decoded to the expected `chip_id` or `channel_id`
- configuration readback matched the RTL defaults
- occupancy CSV output exists and contains rows
- playback JSON was generated

This validation step is what makes the script a scenario runner rather than just a launcher.

## 7. Recommended Authoring Process

When writing a new scenario runner:

1. copy the closest existing script from `sim_core/scenarios/`
2. rename the scenario-specific `work_dir` and output filenames
3. replace the startup/init/stimulus preparation logic
4. replace the `orchestrator_larpix` arguments for the new network shape
5. replace the validation block so it checks the intended result of the new run

Good starting templates are:

- `sim_core/scenarios/run_1chip_event_startup.sh`
- `sim_core/scenarios/run_1chip_fullreg_readback_startup.sh`
- `sim_core/scenarios/run_3x5_bootstrap_id_startup.sh`
- `sim_core/scenarios/run_3x5_event_top_right.sh`
- `sim_core/scenarios/run_15x15_event_staggered_multichip.sh`

## Summary

This mode has two tasks:

1. run an existing scenario script from the repo root
2. create a new scenario runner by copying an existing scenario and changing its inputs, launch arguments, and validation logic

## Scenario Catalog

The currently maintained scenario runners are:

### Single-chip smoke scenarios

- `sim_core/scenarios/run_1chip_event_startup.sh`
  Instantiates a `1x1` LArPix network with source chip `(0,0)`.
  Uses a startup packet file plus a single-channel analog charge-injection stimulus file.
  Pass condition: the FPGA receives a valid downstream event-data packet from chip `1`, channel `0`.
- `sim_core/scenarios/run_1chip_fullreg_readback_startup.sh`
  Instantiates a `1x1` LArPix network with source chip `(0,0)`.
  Generates a startup packet file containing one south-TX enable write followed by full register readback requests; no analog stimulus file is used.
  Pass condition: every returned config-read reply matches the expected RTL startup-default register value.

### Bootstrap configuration scenario

- `sim_core/scenarios/run_3x5_bootstrap_id_startup.sh`
  Instantiates a `3x5` LArPix network with source chip `(0,0)`.
  Uses a generated startup packet file containing bootstrap `CHIP_ID` writes, lane-enable writes, and immediate `CHIP_ID` readbacks; no analog stimulus file is used.
  Pass condition: the returned `CHIP_ID` readback sequence matches the expected bootstrap traversal and a bootstrap playback JSON is produced.

### Preconfigured event scenarios

- `sim_core/scenarios/run_15x15_event_staggered_multichip.sh`
  Instantiates a `15x15` LArPix network with source chip `(0,0)`.
  Uses a preconfigured `init_*.json` file and a generated staggered analog charge-injection stimulus file; no runtime startup packet file is used.
  Pass condition: the FPGA receives downstream data packets from the injected chips across both staggered injection waves.
- `sim_core/scenarios/run_15x15_event_staggered_multichip_source_8_6.sh`
  Instantiates a `15x15` LArPix network with source chip `(8,6)`.
  Uses a preconfigured `init_*.json` file and a generated staggered analog charge-injection stimulus file; no runtime startup packet file is used.
  Pass condition: the FPGA receives downstream data packets from the injected chips for the off-corner source configuration.
- `sim_core/scenarios/run_3x5_event_top_right.sh`
  Instantiates a `3x5` LArPix network with source chip `(0,0)` and targets the top-right chip `(4,2)`, final chip ID `14`.
  Uses a generated startup packet file and a generated all-channel analog charge-injection stimulus file.
  Pass condition: the FPGA receives at least one valid downstream event-data packet from chip `14`.

### Packet-loss scenario

- `sim_core/scenarios/run_2x2_packet_loss_probe.sh`
  Instantiates a `2x2` LArPix network with source chip `(0,0)` and simultaneous event injection on runtimes `1` and `2`.
  Uses a preconfigured `init_*.json` file and a generated analog charge-injection stimulus file.
  Pass condition: the run completes and produces the packet-loss probe artifacts needed to compare chip-generated traffic against FPGA-received traffic on the two return lanes.

### Message-RTL scenarios

- `sim_core/scenarios/run_2x2_msg_data_probe.sh`
  Instantiates a `2x2` `msg_rtl` network with internal message generation enabled and analog charge injection on runtime `2`.
  Uses a preconfigured `init_*.json` file and a generated analog charge-injection stimulus file.
  Pass condition: the run completes and produces mixed message/data traffic artifacts showing event-data packets interacting with message packets in the same network.
- `sim_core/scenarios/run_6x6_msg_rerouting_second_wave_probe.sh`
  Instantiates a `6x6` `msg_rtl` network with message generation pre-enabled on all chips.
  Uses a preconfigured `init_*.json` file and a generated two-wave analog charge-injection stimulus file; no runtime startup packet file is used.
  Pass condition: the run completes and produces the second-wave rerouting playback and summary artifacts for visual inspection of network-wide message rerouting.
