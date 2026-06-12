# Lane Mapping Update

This note records the framework changes required after confirming that the RTL lane-to-bit mapping is different for `POSI` and `PISO`.

## Correct Mapping

The simulator should continue to use the canonical framework direction names:

- `north`
- `east`
- `south`
- `west`

But the RTL port bit ordering is:

### `POSI`

- `POSI0 = north`
- `POSI1 = west`
- `POSI2 = south`
- `POSI3 = east`

### `PISO`

- `PISO0 = west`
- `PISO1 = south`
- `PISO2 = east`
- `PISO3 = north`

## Why This Change Was Needed

The framework had been assuming one shared bit ordering for:

- simulator edge indices
- `dut_.posi`
- `dut_.piso`
- `dut_.tx_enable`
- lane-mask register values such as `ENABLE_PISO_UP` and `ENABLE_PISO_DOWN`

That assumption was wrong.

The result was that:

- RX traffic presented to the RTL could arrive on the wrong physical lane
- TX traffic sampled from the RTL could be attributed to the wrong direction
- startup and preload masks could enable the wrong downstream or upstream lanes
- playback reconstruction and visualizer lane rendering could show the wrong routing state

## Design Decision

The framework keeps its canonical direction model:

- `north`
- `east`
- `south`
- `west`

and applies remapping only at the RTL boundary and in any code that interprets raw lane-mask bits.

This avoids rewriting the rest of the simulator around RTL-specific bit positions.

## Core Backend Change

The most important fix is in:

- [sim_core/src/larpix_cosim_backend.cpp](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/sim_core/src/larpix_cosim_backend.cpp)

Two separate maps are now used.

### Framework edge -> `POSI` bit

- `north -> 0`
- `east -> 3`
- `south -> 2`
- `west -> 1`

This is used when driving incoming serial bits into `dut_.posi`.

### Framework edge <- `PISO` bit

- `north <- 3`
- `east <- 2`
- `south <- 1`
- `west <- 0`

This is used when sampling `dut_.piso` and `dut_.tx_enable`.

Without this split, live cosimulation is directionally incorrect.

## Lane-Mask Interpretation Change

The `ENABLE_PISO_UP` and `ENABLE_PISO_DOWN` masks follow the RTL `PISO` bit order, not the old framework assumption.

That means:

- `north = 0x08`
- `east = 0x04`
- `south = 0x02`
- `west = 0x01`

The old assumption had been:

- `north = 0x01`
- `east = 0x02`
- `south = 0x04`
- `west = 0x08`

## Files Updated

### Live cosimulation boundary

- [sim_core/src/larpix_cosim_backend.cpp](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/sim_core/src/larpix_cosim_backend.cpp)

This is the required fix for correct live chip I/O.

### Bootstrap / preload mask generation

- [sim_core/tools/generate_bootstrap_chip_id_readback_json.py](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/sim_core/tools/generate_bootstrap_chip_id_readback_json.py)
- [sim_core/tools/generate_bootstrap_preconfigured_event_init_json.py](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/sim_core/tools/generate_bootstrap_preconfigured_event_init_json.py)

The bootstrap helper now writes `ENABLE_PISO_*` using the corrected `PISO` bit ordering.

### Single-chip startup/readback config

- [sim_core/config/startup_1chip_event_source.json](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/sim_core/config/startup_1chip_event_source.json)
- [sim_core/config/startup_1chip_full_reg_readback.json](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/sim_core/config/startup_1chip_full_reg_readback.json)
- [sim_core/tools/generate_1chip_full_reg_readback_json.py](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/sim_core/tools/generate_1chip_full_reg_readback_json.py)

For a single-chip source connected on the south side, enabling south TX now means writing `0x02`, not `0x04`.

### Playback reconstruction

- [sim_core/visualizers/packet_transmission/convert_live_trace_to_playback.py](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/sim_core/visualizers/packet_transmission/convert_live_trace_to_playback.py)

This converter now interprets `up_mask` and `down_mask` using the corrected `PISO` bit ordering when reconstructing reachable neighbors and lane labels.

### Web visualizer

- [sim_core/visualizers/packet_transmission/main.js](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/sim_core/visualizers/packet_transmission/main.js)

The visualizer now uses two separate mappings:

- one for playback lane masks derived from `PISO`
- one for internal Hydra RX/debug masks derived from `POSI`

This matters because the internal chip-view debug masks and the network-view routing masks do not share the same bit order anymore.

## Practical Rule For Other Repos Or Branches

If another version of this framework still assumes one common lane ordering, it must be patched in at least two places:

1. the live RTL boundary
2. every place that interprets raw lane-mask bits

In practice, check:

- the Verilator backend or other cosim wrapper
- bootstrap/startup JSON generators
- preload/init JSON generators
- playback conversion tools
- visualizer lane rendering
- internal debug viewers that decode Hydra one-hot masks

## What Does Not Need To Change

The framework’s canonical direction enum can stay as-is.

For example, code that talks about:

- `north`
- `east`
- `south`
- `west`

at the network level does not need to be renamed or reordered, as long as the RTL-facing bit remaps are correct.

## Validation Performed

Two live maintained scenario checks were used after the update.

### Single-chip event startup

- `run_1chip_event_startup.sh`

This passed after changing the south-lane startup write to `0x02`.

### 3x5 bootstrap CHIP_ID assignment

- `run_3x5_bootstrap_id_startup.sh`

This passed after regenerating the startup schedule with the corrected `ENABLE_PISO_*` masks.

## Short Summary

The important lesson is:

- `POSI` and `PISO` do not share the same bit order

So the framework must not use one universal lane-bit map.

It needs:

- a `POSI` input mapping
- a `PISO` output mapping
- a consistent `PISO` mask interpretation for startup, preload, playback, and visualization
