# Prerequisite Mode

In this framework, the two most important external prerequisites are:

- `nng`, the messaging library used by the simulator processes
- Verilator, the tool used to compile supported RTL into a C++-backed simulator executable

This document also includes the first compatibility edits that may be needed before an RTL tree can be used with Verilator in this framework.

## 1. What Prerequisite Mode Produces

At the end of this mode, the user should have:

- a working local `nng` checkout that can be built into `nng/build/libnng.so`
- a working Verilator installation available on `PATH`
- an RTL tree that has been checked for obvious Verilator incompatibilities

Only after that should the user move on to `integrate_rtl_mode.md`.

## 2. Getting NNG

Official upstream sources:

- GitHub repository: <https://github.com/nanomsg/nng>
- Documentation/manual: <https://nng.nanomsg.org/>

The active simulator expects `nng` to exist as a local checkout under:

```text
nng/
```

and expects the built shared library at:

```text
nng/build/libnng.so
```

### Recommended way to obtain NNG

Clone the upstream repository into the repo root:

```bash
git clone https://github.com/nanomsg/nng.git
```

This creates:

```text
chip_network_sim/
  nng/
```

### Recommended way to build NNG

NNG uses CMake. A standard local build is:

```bash
cd nng
mkdir -p build
cd build
cmake ..
cmake --build . -j
```

If you have `ninja` installed, that is also a good choice:

```bash
cd nng
mkdir -p build
cd build
cmake -G Ninja ..
ninja
```

### Success check for NNG

This mode is successful for `nng` when all of the following are true:

- `nng/include/nng/nng.h` exists
- `nng/build/libnng.so` exists
- the top-level simulator build can find both without editing paths

## 3. Getting Verilator

Official upstream sources:

- GitHub repository: <https://github.com/verilator/verilator>
- Official installation guide: <https://veripool.org/guide/latest/install.html>
- Project website: <https://verilator.org/>

### Recommended way to obtain Verilator

There are two reasonable paths.

#### Option A: install from your system package manager

This is the fastest way to get started, though it may not give the newest version.

For Ubuntu/Debian systems:

```bash
sudo apt-get install verilator
```

#### Option B: build Verilator from the upstream repository

This is the better choice if you need a newer release or want behavior closer to upstream documentation.

Typical source build flow:

```bash
git clone https://github.com/verilator/verilator
cd verilator
autoconf
./configure
make -j "$(nproc)"
sudo make install
```

The Verilator installation guide also lists the common prerequisite packages needed before the source build.

### Success check for Verilator

This mode is successful for Verilator when:

- `verilator --version` runs successfully
- `cmake` can discover `verilator`
- the simulator build can create the Verilated chip targets

## 4. Common System Packages

The exact package list depends on the OS, but in practice a Linux machine will usually need:

- `git`
- `cmake`
- `make`
- `g++` or `clang++`
- `autoconf`
- `flex`
- `bison`
- `perl`
- `python3`

If you build Verilator from source, check the current upstream Verilator installation guide for the exact prerequisites recommended for your platform.

## 5. Verilator Compatibility For RTL

Having Verilator installed is not enough by itself. The RTL also needs to be compatible with the way this framework uses Verilator.

At a high level, this means:

- the RTL must compile cleanly under Verilator
- the RTL must avoid dependencies on foundry-specific simulation libraries when running in the Verilator path
- the RTL must preserve the functional behavior needed for cosimulation even after those proprietary dependencies are removed

### General compatibility checks

Before integrating a new RTL tree, check for:

- direct instantiations of foundry-only cells
- `include` or library references that only exist in a proprietary simulator environment
- global include-guard patterns that interfere with the RTL’s existing `include` usage under Verilator

## 6. LArPix-Specific Verilator Compatibility Edit

For the LArPix-like RTL used in this repository, the functional-cosimulation compatibility edits are:

- modify the gate-edge files so they no longer depend on specific foundry clock-gate models in the Verilator path
- remove the global include guard pattern from `larpix_constants.sv` so each including module still receives its own localparams during Verilator compilation
- expose the framework-required `digital_core` top-level ports `runtime_id` and `preload_done`

The relevant files are:

- `gate_posedge_clk.sv`
- `gate_negedge_clk.sv`
- `larpix_constants.sv`
- `digital_core.sv`

In the active RTL trees, the gate-edge modules use a conditional `VERILATOR` path with a simple functional model, while keeping the foundry-cell instantiation for non-Verilator flows. The minimal standalone patch record for these required compatibility edits is:

- `doc/patches/verilator_rtl_compatibility_minimal.patch`

That patch is written relative to a generic RTL `src/` directory so it can be reused for any user RTL variant that follows this repo's normal layout.

The intended application pattern is:

```bash
cd rtl/<your_variant>
patch --dry-run -p0 < ../../doc/patches/verilator_rtl_compatibility_minimal.patch
patch -p0 < ../../doc/patches/verilator_rtl_compatibility_minimal.patch
```

In other words, the user applies the patch from inside their RTL variant directory, not from the repo root.

Instead of requiring cells such as:

- `CKLNQD8`
- `CKLHQD4`

the Verilator path should implement equivalent functional clock-gating behavior in portable RTL.

For `larpix_constants.sv`, the active pattern is:

- do not use a global include guard if the file is intended to be `include`d inside multiple modules
- allow each including module to receive its own copy of the localparams during Verilator compilation

For `digital_core.sv`, the active framework-compatible pattern is to expose these additional top-level inputs:

- `runtime_id`
- `preload_done`

These are required by the simulator/backend contract in this repository even if the RTL does not use them internally for chip logic.

During a live simulation:

- `runtime_id` is used by the framework as chip-instance identity plumbing so the backend can keep the launched chip process aligned with the simulator's runtime/chip numbering
- `preload_done` is used by the framework as the register-preload completion handshake for runs that use `init_regs_json`, so the backend can mark when direct RTL register preload has finished before normal execution proceeds

In the current LArPix RTL trees, these ports may be functionally unused inside `digital_core`, but they still need to exist on the top-level module so the Verilated model exposes them to the cosimulation backend.

These changes are the ones required to preserve functional cosimulation in the current Verilator flow.

Optional internal-signal exposure for richer debug and observability is documented separately in `internal_inspection_mode.md`.

## 7. Success Criteria Before Moving On

Do not move on to RTL integration until all of the following are true:

- `nng/include/nng/nng.h` exists
- `nng/build/libnng.so` exists
- `verilator --version` works
- the RTL no longer depends on foundry-specific gate-edge cell models in the Verilator path
- the RTL no longer relies on the problematic global include-guard pattern for `larpix_constants.sv`
- the RTL exposes the framework-required `digital_core` ports `runtime_id` and `preload_done`
- you understand which RTL files were modified for functional Verilator compatibility

After that, the next document should be `integrate_rtl_mode.md`.

## Summary

This prerequisite mode is focused on three things:

1. obtain and build `nng`
2. install Verilator
3. make the RTL portable enough for the framework’s Verilator-based functional cosimulation flow
