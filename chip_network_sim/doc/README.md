# Documentation Order

There are four documents outlining how to get started with using this simulation framework. They go through the steps of (1) downloading required prerequisites, (2) integrating a user's unique RTL design into the simulation framework, (3) running a simulation, and (4) optionality for enabling internal state visibility for futher investigation of chip/network behavior. 

# 1. Prerequisite Mode

Start with:

- `prerequisite_mode.md`

This document explains how to prepare the machine and RTL for the framework:

- install `nng`
- install Verilator
- make the RTL compatible with functional Verilator cosimulation

## 2. Integrate RTL Mode

Next read:

- `integrate_rtl_mode.md`

This document explains how to take a LArPix-like RTL tree and turn it into a simulator-launchable chip executable:

- place the RTL in the repo
- register the RTL variant in `CMakeLists.txt`
- build the chip target
- validate that the chip executable launches correctly

## 3. Launch Scenario Mode

After the chip executable is working, read:

- `launch_scenario_mode.md`

This document explains how to run live simulations:

- run an existing maintained scenario script
- understand the scenario artifacts
- write a new scenario runner script

## 4. Internal Inspection Mode

Finally read:

- `internal_inspection_mode.md`

This document covers optional deeper observability and debug features:

- extra internal RTL visibility
- optional analysis outputs
- inspection-oriented adjustments that are not required for basic functional cosimulation

## Recommended Path

For a new user, the intended reading order is:

1. `prerequisite_mode.md`
2. `integrate_rtl_mode.md`
3. `launch_scenario_mode.md`
4. `internal_inspection_mode.md`
