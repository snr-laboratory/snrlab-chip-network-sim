# Integrate RTL Mode

This mode is for a user who has an RTL source tree and wants to make it launchable by the simulator.

## 1. Purpose

The goal of "Integrate RTL" is to turn a specific RTL variant into a simulator-compatible backend.

The deliverable of this mode is a simulator-launchable chip executable.

At the end of this mode, the user should have:

- an RTL tree placed in the repository in the expected location
- a CMake target for that RTL variant
- a built chip binary under `build/`
- a minimal proof that the simulator runtime can launch that binary

## 2. Simulator-RTL Contract

Before editing build files, the user needs to understand what this framework expects from the RTL.

In the current simulator structure:

- the simulator assumes a LArPix-like RTL contract rather than an arbitrary generic digital block
- the active RTL-backed flow uses Verilator with top module `digital_core`
- the runtime boundary is implemented through the active `sim_core` wrappers, not by directly running RTL on its own

The important practical implication is that a new RTL tree must match the expectations encoded in the build and cosimulation code, i.e. be "LArPix-like". Future publications of this framework will detail where to edit files to allow for more generic RTL inputs.

In practice, the current RTL contract includes these concrete requirements:

- the top module must be named `digital_core`
- the RTL tree must be organized as a source directory that can be enumerated explicitly in `CMakeLists.txt`
- the RTL tree is expected to provide the LArPix-style source set used by the current build flow, including files such as `digital_core.sv`, `comms_ctrl.sv`, `hydra_ctrl.sv`, `external_interface.sv`, `config_regfile.sv`, `uart.sv`, `uart_rx.sv`, and `uart_tx.sv`
- if message-generation logic is present, the build can also include `msg_logic.sv` and `msg_generator.sv`
- the RTL must work with the simulator’s Verilator-based cosimulation wrapper rather than as a standalone simulator project; in practice this means the wrapper must be able to instantiate `Vdigital_core` and drive the top-level signals it currently uses, including `clk`, `reset_n`, `runtime_id`, `preload_done`, `posi`, `external_trigger`, `hit`, `done`, and `dout[]`
- the RTL must be compatible with the runtime-facing interface implemented by `sim_core/src/larpix_cosim_backend.cpp`; in practice this means:
  - four serial edge inputs are driven into the RTL one bit per tick through `posi`, with idle/un-driven lines treated as logic `1`
  - four serial edge outputs are sampled from the RTL through `piso` and `tx_enable`
  - one simulation tick corresponds to one wrapped clock step of the RTL
  - the analog frontend model supplies per-channel activity for `64` channels and drives the RTL through `hit`, `done`, and `dout[]`
  - the wrapper expects to be able to set `runtime_id` on the DUT before use
  - the wrapper expects to be able to preload configuration registers by writing `digital_core__DOT__config_bits[...]` after the RTL’s config-reset window clears, then asserting `preload_done`
- the RTL must follow the clock/reset behavior expected by the active chip runtime and cosim wrapper
- if the simulation flow uses register preloads, the RTL must support the register initialization path used by the current backend integration

The most relevant integration points are:

- `CMakeLists.txt`
- `sim_core/src/chip_larpix.cpp`
- `sim_core/src/larpix_cosim_backend.cpp`
- `sim_core/include/larpixsim/backend.h`

Those files define what the simulator believes the chip backend is, how it is built, and how it is driven at runtime.

## 3. Prerequisites

Before attempting to build a new RTL variant, the machine needs the external toolchain prerequisites in place.

For installation details, see:

- `doc/prerequisite_mode.md`

The active build assumes:

- local `nng` headers under `nng/include`
- local `nng` shared library at `nng/build/libnng.so`
- `verilator` available to CMake
- a working C/C++ toolchain

If those external prerequisites are not in place, integration work should stop and the environment should be fixed first.

## 4. Place Your RTL Tree

Place your RTL tree under the `rtl/` directory. This RTL should already be Verilator-compatible as outlined in the `doc/prerequisite_mode.md`. Examples of RTL variants in the directory look like:

- `rtl/v3b/`
- `rtl/v3b_v2/`
- `rtl/v3c/`
- `rtl/v3c2/`
- `rtl/msg_rtl/`

So a new RTL integration should follow that same pattern and live under a new subdirectory in `rtl/`.

## 5. Register The RTL Variant In CMake

Once the RTL tree exists, it needs to be wired into the build system.

This means:

- defining where the RTL tree lives in `CMakeLists.txt`
- enumerating the expected SystemVerilog source files for that variant
- adding a dedicated Verilator-backed chip build target
- defining the final output binary name

In the current `CMakeLists.txt`, the user should look at four specific regions:

### Define the RTL tree location

This is the block where the repo defines the source-directory variables for the supported RTL trees.

Look at:

- `CMakeLists.txt`, around the `set(LARPIX_RTL_..._DIR ...)` entries

This is where a new variant-specific source root should be added. In the current file, that block looks like:

```cmake
set(LARPIX_RTL_V1_DIR ${CMAKE_SOURCE_DIR}/rtl/v3b/src)
set(LARPIX_RTL_V2_DIR ${CMAKE_SOURCE_DIR}/rtl/v3b_v2/src)
set(LARPIX_RTL_V3C_DIR ${CMAKE_SOURCE_DIR}/rtl/v3c/src)
set(LARPIX_RTL_V3C2_DIR ${CMAKE_SOURCE_DIR}/rtl/v3c2/src)
set(LARPIX_RTL_MSG_DIR ${CMAKE_SOURCE_DIR}/rtl/msg_rtl/src)
```

### Enumerate the source files for the variant

This is the helper function that builds the SystemVerilog source list for a LArPix-like `digital_core` RTL tree.

Look at:

- `CMakeLists.txt`, inside `function(set_larpix_digital_core_sv_sources ...)`

That block is where the expected RTL filenames are enumerated. If the new RTL variant uses the same file naming scheme, the user may only need to add a new call to the helper. If it uses a different source layout, this function is one of the places that may need editing.

The current enumeration block looks like:

```cmake
function(set_larpix_digital_core_sv_sources out_var rtl_dir)
  set(_sources
    ${rtl_dir}/async2sync.sv
    ${rtl_dir}/channel_ctrl.sv
    ${rtl_dir}/comms_ctrl.sv
    ${rtl_dir}/config_regfile.sv
    ${rtl_dir}/digital_core.sv
    ${rtl_dir}/digital_monitor.sv
    ${rtl_dir}/event_router.sv
    ${rtl_dir}/external_interface.sv
    ${rtl_dir}/fifo_latch.sv
    ${rtl_dir}/gate_negedge_clk.sv
    ${rtl_dir}/gate_posedge_clk.sv
    ${rtl_dir}/hydra_ctrl.sv
    ${rtl_dir}/periodic_pulser.sv
    ${rtl_dir}/priority_fifo_arbiter.sv
    ${rtl_dir}/reset_sync.sv
    ${rtl_dir}/sar_adc_cdc.sv
    ${rtl_dir}/timestamp_gen.sv
    ${rtl_dir}/uart.sv
    ${rtl_dir}/uart_rx.sv
    ${rtl_dir}/uart_tx.sv
  )
```

### Define the final output binary name

This happens inside the Verilator-backed chip-target helper.

Look at:

- `CMakeLists.txt`, inside `function(add_larpix_chip_target target_name output_name ...)`

In that function:

- `output_name` determines the final chip executable name
- `_bin` becomes `${CMAKE_BINARY_DIR}/${output_name}`
- the Verilator command uses `-o ${output_name}`

So if the user wants the final binary to be named `chip_larpix_<variant>`, this is the function that enforces that naming.

### Add the dedicated Verilator-backed chip build target

This is the block where concrete chip targets are instantiated for each supported RTL variant.

Look at:

- `CMakeLists.txt`, at the `add_larpix_chip_target(...)` calls

That is where the user adds one more line for the new RTL variant. The current block looks like:

```cmake
add_larpix_chip_target(chip_larpix_v3b_build chip_larpix_v3b LARPIX_CHIP_MDIR LARPIX_CHIP_BIN "${LARPIX_RTL_V1_DIR}" "${LARPIX_DIGITAL_CORE_SV_SOURCES}")
add_larpix_chip_target(chip_larpix_v3b_v2_build chip_larpix_v3b_v2 LARPIX_CHIP_V2_MDIR LARPIX_CHIP_V2_BIN "${LARPIX_RTL_V2_DIR}" "${LARPIX_DIGITAL_CORE_SV_SOURCES_V2}")
add_larpix_chip_target(chip_larpix_v3c_build chip_larpix_v3c LARPIX_CHIP_V3C_MDIR LARPIX_CHIP_V3C_BIN "${LARPIX_RTL_V3C_DIR}" "${LARPIX_DIGITAL_CORE_SV_SOURCES_V3C}")
add_larpix_chip_target(chip_larpix_v3c2_build chip_larpix_v3c2 LARPIX_CHIP_V3C2_MDIR LARPIX_CHIP_V3C2_BIN "${LARPIX_RTL_V3C2_DIR}" "${LARPIX_DIGITAL_CORE_SV_SOURCES_V3C2}")
add_larpix_chip_target(chip_larpix_msg_rtl_build chip_larpix_msg_rtl LARPIX_CHIP_MSG_MDIR LARPIX_CHIP_MSG_BIN "${LARPIX_RTL_MSG_DIR}" "${LARPIX_DIGITAL_CORE_SV_SOURCES_MSG}")
```

In the current repo, existing examples are the active targets:

- `chip_larpix_v3b_build`
- `chip_larpix_v3b_v2_build`
- `chip_larpix_v3c_build`
- `chip_larpix_v3c2_build`
- `chip_larpix_msg_rtl_build`

The user should create a new target that follows the same pattern so that the integration is explicit and reproducible.

A typical naming pattern is:

- build target: `chip_larpix_<variant>_build`
- output binary: `build/chip_larpix_<variant>`

The target should produce a binary with a stable name under `build/`, for example:

```text
build/chip_larpix_<variant>
```

This framework allows for using the same CMakeLists.txt for multiple RTL variants for protoyping and comparison of different RTL versions.
 
## 6. Build And Validate The Chip Binary

The first success criterion is narrow: can the new backend be built.

After editing `CMakeLists.txt`, build the new chip target from the repo root with:

```bash
cmake -S . -B build
cmake --build build --target chip_larpix_<variant>_build -j
```

For example, if the new variant is named `myrtl`:

```bash
cmake -S . -B build
cmake --build build --target chip_larpix_myrtl_build -j
```

If the target was registered correctly, this should produce:

```text
build/chip_larpix_<variant>
```

The initial validation questions are:

- does CMake configure successfully
- does Verilator compile the RTL tree
- does the expected chip binary appear in `build/`

The simplest concrete success check at this stage is that a binary with the expected name exists, for example:

```text
build/chip_larpix_<variant>
```

You can check that directly with:

```bash
ls -l build/chip_larpix_<variant>
```

At this stage, the user is not yet proving that a large scenario works. They are only proving that the framework can compile the RTL into a backend executable.

After the binary is produced, the next validation layer is runtime launch:

- can the chip process start
- can the backend be created successfully
- can the simulator runtime talk to it without immediate failure
- if needed, do register preload paths still work

The simplest sanity check is to invoke the binary directly:

```bash
./build/chip_larpix_<variant>
```

For the current `chip_larpix_<variant>` runtime, invoking the binary without required arguments should print its usage message rather than crashing. That confirms the executable was built and can start on the machine.

If you want a slightly stronger launch check before moving to full scenario runs, use:

```bash
timeout 2s ./build/chip_larpix_<variant> -id 0
```

The practical success condition here is that the runtime can launch the chip binary without an immediate backend creation, startup, or dynamic-link failure.

This is the point where integration becomes operational rather than just syntactic.

## 7. Hand-Off To "Run Simulations"

The "Integrate RTL" (this mode) is complete when:

- the new RTL variant has a named build target
- the build target compiles cleanly
- the chip executable exists under `build/`
- the simulator runtime can launch it
- the user knows which chip binary name to use in the next workflow

After that, the user should leave this guide and move to the scenario-running workflow.

That second mode will cover:

- choosing or creating a scenario
- generating init/startup/stimulus inputs
- launching the orchestrator and chip processes
- collecting run artifacts
- generating playback JSON
- opening the visualizer or publishing a stable playback link


## Summary

This seven-step mode is focused on achieving a successful chip build:

1. Purpose
2. Simulator-RTL contract
3. Prerequisites
4. Place your RTL tree
5. Register the RTL variant in CMake
6. Build and validate the chip binary
7. Hand-off to "Run Simulations"
