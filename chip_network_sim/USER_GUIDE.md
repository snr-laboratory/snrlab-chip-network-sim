# User Guide

This guide covers the recommended way to run the simulator with a single JSON run configuration.

## Where To Work
Create and edit your run configuration JSON under:
- `chip_network_sim/larpix_network_sim/config/`

A good starting point is:
- `chip_network_sim/larpix_network_sim/config/example_run_config_1chip_event.json`

Run the wrapper from the repository root:
- `chip_network_sim/`

That means your working directory should be the directory that contains `README.md`, `CMakeLists.txt`, and `larpix_network_sim/`.

## 1. Build The Simulator
The RTL and `nng` are external inputs supplied by the user.

From `chip_network_sim/`:
```bash
cmake -S . -B build \
  -DNNG_ROOT=/path/to/nng \
  -DLARPIX_RTL_DIR=/path/to/larpix_rtl/src
cmake --build build -j
```

## 2. Create A Run Config
Place your config JSON in:
- `larpix_network_sim/config/`

Example:
- `larpix_network_sim/config/my_run.json`

The config describes:
- network size and runtime
- startup mode
- charge injection stimulus
- output locations
- optional build inputs and binary paths

Supported `startup.mode` values are:
- `bootstrap_chip_id_readback`
- `bootstrap_chip_id`
- `enable_trigger_injected_channels`
- `manual`

If you use `bootstrap_chip_id` or `bootstrap_chip_id_readback`, you can also set:
- `"append_enable_injected_channels": true`

That appends the channel-enable writes implied by `stimulus.charges` so the injected channels are ready to trigger.

## 3. Prepare Derived Inputs
From `chip_network_sim/`, run:
```bash
python3 larpix_network_sim/scripts/run_from_config.py \
  -cfg larpix_network_sim/config/my_run.json \
  --prepare-only
```

This generates the derived files for the run, including:
- `startup.source.json`
- `startup.compiled.json`
- `stimulus.json`

These are written under the `outputs.work_dir` directory from your config.

## 4. Launch The Simulation
From `chip_network_sim/`, run:
```bash
python3 larpix_network_sim/scripts/run_from_config.py \
  -cfg larpix_network_sim/config/my_run.json
```

The wrapper will:
1. interpret the startup mode
2. generate or reuse the startup schedule
3. compile startup frames for `fpga_larpix`
4. write the stimulus file
5. optionally build if your config enables it
6. launch `orchestrator_larpix`

## Recommended Workflow
- Put user-authored run configs in `larpix_network_sim/config/`
- Run the wrapper from the repo root `chip_network_sim/`
- Start from `example_run_config_1chip_event.json` and copy it to a new file for each run
- Use `--prepare-only` first if you want to inspect generated startup and stimulus files before launching
