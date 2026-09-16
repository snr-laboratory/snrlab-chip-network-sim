# Internal Inspection Mode

This mode explains how RTLswarm can inspect selected internal RTL signals
without adding debug ports or simulator-specific annotations to the supplied
RTL.

Internal inspection is optional. First make the RTL build and run through the
normal integration flow; then add visibility only for signals needed by a
debug scenario or analysis output.

## 1. Simulator-Owned Visibility

Verilator accepts control files with the `.vlt` extension. RTLswarm keeps this
visibility configuration on the simulator side, separate from the RTL source
tree.

The repository provides a simulator-side example at:

```text
sim_core/config/example_debug_public.vlt
```

Copy it to a design-specific filename under `sim_core/config/` before editing
it. The example is intentionally not enabled by default because its fictional
module and signal names do not describe a real design. Keeping these files
under `chip_network_sim/` makes the ownership clear: they are part of the
simulator integration, not part of the synthesizable design.

Because users provide their own RTL, they also provide the module and signal
names entered in this file. RTLswarm cannot preselect a universal set of
internal signals for every design.

## 2. Selecting Signals In The `.vlt` File

A Verilator control file begins with `` `verilator_config``. The provided
[`example_debug_public.vlt`](../sim_core/config/example_debug_public.vlt) shows
the complete minimal structure. Use
`public_flat_rd` rules to expose internal state for read-only simulator access:

```text
`verilator_config

// Read-only state used by simulator-side debug capture.
public_flat_rd -module "<module_name>" -var "<signal_name>"
public_flat_rd -module "<another_module_name>" -var "<another_signal_name>"
```

Replace the placeholders with module and variable names from the supplied RTL.
Each rule selects matching instances of that module and makes the named
variable visible in the generated Verilated C++ model.

Prefer read-only exposure for inspection. The simulator should observe these
signals, not drive them or change the RTL's behavior.

## 3. Passing The Control File To Verilator

The `.vlt` file must be included in the Verilator command used to build the
chip executable. In `CMakeLists.txt`, each `add_larpix_chip_target(...)` call
has a final argument for its simulator-side control file. Pass the
design-specific path in that target definition:

```cmake
add_larpix_chip_target(
  chip_myrtl_build
  chip_myrtl
  MYRTL_MDIR
  MYRTL_BIN
  "${MYRTL_RTL_DIR}"
  "${MYRTL_SOURCES}"
  "${CMAKE_SOURCE_DIR}/sim_core/config/myrtl_debug_public.vlt"
)
```

The existing calls use an empty final argument (`""`) when they do not need
internal inspection. CMake verifies any nonempty path, passes the file to
Verilator, and treats it as a build dependency so changes regenerate the chip
model.

Do not attach the example unchanged. First replace its fictional module and
signal names with hierarchy from the supplied RTL.

The control file is part of the target definition, so it is used automatically
whenever that chip target is built. Different RTL targets can select different
`.vlt` files without additional configure-time flags.

## 4. Reading Exposed State In The Simulator

After Verilator rebuilds the model, it emits C++ members for the selected
signals. Their generated names reflect the RTL instance hierarchy and the
Verilator version.

Inspect the generated headers under the target's `build/verilated_*` directory
to find the exact member names. The RTL-specific cosimulation backend can then
read those members during a simulation tick and copy their values into debug
records, CSV rows, trace events, or scenario metrics.

This keeps the responsibilities separate:

- the `.vlt` file chooses which internal RTL state is visible;
- the cosimulation backend samples the generated C++ members; and
- the scenario or analysis tooling decides how to record and present them.

## 5. Typical Workflow

1. Build and run the RTL without optional internal inspection.
2. Identify the internal state needed to answer a specific debug question.
3. Copy the example `.vlt` file and replace its fictional hierarchy names.
4. Put that file's path in the corresponding CMake chip-target definition.
5. Rebuild the Verilated chip model.
6. Inspect the generated headers and add backend sampling for the exposed
   members.
7. Record the values only in scenarios that need the additional visibility.

## 6. Inspection Outputs

Once the backend samples the exposed state, scenarios may produce optional
artifacts such as:

- internal-state CSV files;
- occupancy or utilization histories;
- trace events;
- run-summary metrics; and
- scenario-specific analysis JSON.

These are debug products, not requirements of the basic RTLswarm interface.

## 7. Practical Limits

- Module and variable names in the `.vlt` file must match the supplied RTL.
- Hierarchical generated C++ names may change when RTL hierarchy or Verilator
  versions change.
- Adding or removing `.vlt` rules requires rebuilding the Verilated model.
- Expose only the signals needed for a specific inspection task; large public
  signal sets increase generated-model complexity and couple the backend more
  tightly to one RTL hierarchy.
- Keep functional inputs and outputs in the normal top-level RTL contract.
  Internal inspection should not become a second functional interface.

## Summary

RTLswarm exposes optional internal state through a simulator-owned `.vlt`
control file. Verilator turns the selected read-only signals into generated C++
members, and the cosimulation backend samples those members for debug and
analysis outputs. This provides internal visibility without changing the
supplied synthesizable RTL.
