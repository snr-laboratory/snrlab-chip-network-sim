# Chip-ID Bootstrap Script Plan

## Goal

Create a script that generates the sequence of LArPix configuration-write operations needed to assign unique chip IDs to all chips in an `n x m` rectangular array.

The purpose of this script is **only** chip-ID assignment during bring-up. It is not yet the full runtime-routing or stimulus compiler.

Because the current RTL starts all chips with the same default chip ID, this script must generate many configuration writes in a carefully ordered sequence so that IDs can be assigned one chip at a time without ambiguity.

## Why This Script Is Needed

From the current RTL behavior:
- all chips start with the same default `CHIP_ID`
- a single configuration write packet changes only one 8-bit configuration register
- a packet addressed to chip ID `1` is not uniquely targeted if multiple reachable chips still have chip ID `1`
- TX lanes are disabled by default, so bring-up must explicitly enable temporary forwarding paths

That means chip-ID assignment cannot be a single packet or a single global operation.
It must be a staged packet sequence.

## Scope

This script should:
- accept a rectangular chip-array size `rows x cols`
- assume one designated source chip is directly reachable from the FPGA / external controller
- generate the ordered packet sequence needed to assign unique chip IDs to every chip
- use temporary lane-enable writes as needed during bring-up
- guarantee that at each step only one reachable chip still responds to the default target chip ID

This script should not yet:
- generate final runtime-routing configuration
- generate charge stimulus input
- generate normal operational config writes unrelated to chip-ID assignment

## Core Assumption

The bring-up method is a directional hop-by-hop bootstrap.

At a high level:
1. configure the source chip directly
2. give the source chip a unique non-default ID
3. enable exactly one TX direction toward the next target chip
4. send a config write addressed to the default chip ID so only that one reachable target chip receives it
5. change that target chip's ID to a new unique value
6. repeat until all chips have unique IDs

This only works if the bootstrap path is controlled so that exactly one still-default-ID chip is reachable at each step.

### Bidirectional TX rule after every reassignment

The bootstrap protocol must now be treated as **bidirectional**, not purely forward-going.

After every successful `CHIP_ID` reassignment, the next lane-enable write for the newly assigned chip must enable **two** TX directions:
- the forward TX lane already required by the original protocol, pointing toward the next chip whose ID will be reassigned
- the reverse TX lane pointing back toward the chip from which the reassignment packet just arrived

So each newly assigned chip must preserve both:
- forward progress of the bootstrap path
- reverse reachability for immediate readback and later return traffic

Concrete example:
- chip `2` sends a reassignment packet that changes a neighboring chip from `chip_id = 1` to `chip_id = 3`
- the subsequent lane-enable write for chip `3` must open:
  - `lane1` if that is the forward direction to the next chip to be assigned, and
  - `lane3` for the reverse direction back toward chip `2`
- under the agreed lane convention, that means the write data should be `0x0A` (`lane1 | lane3`)

This new rule updates the earlier one-direction-at-a-time description. From this point onward, whenever the protocol says to "enable the TX lane toward the next chip," it should be interpreted as:
- enable the forward lane toward the next chip, and
- also enable the reverse lane back toward the predecessor chip that delivered the reassignment

The source chip is the only exception at the very beginning of bootstrap, because before the first reassignment there is no predecessor chip inside the network. Once a chip has been reached through the network, however, both lanes must be enabled after its reassignment.

### First bootstrap rule

Let the directly reachable source chip have desired final chip ID `s`.

Placement constraint:
- the source chip must lie on the bottom row of the array
- that means `y = 0`
- its column may be anywhere in the row: `x = 0 .. m-1`

At startup, that source chip still has the RTL default `chip_id = 1`.

Therefore, the **first configuration packet** in the entire bring-up sequence must be:
- a `CONFIG_WRITE` packet addressed to `chip_id = 1`
- writing register `CHIP_ID = 122`
- with data byte equal to the desired source-chip ID `s`

So the first bootstrap action is simply:
- change the directly reachable source chip from default chip ID `1` to chip ID `s`

This works because, at the beginning of bring-up, the source chip is the only chip directly reachable from the FPGA / external controller even though all chips share the same default chip ID.

After that first write succeeds, the source chip no longer responds as chip ID `1` and can be used as the unique first configured forwarder for the rest of the bootstrap sequence.

### Second bootstrap rule

After the source chip has been assigned chip ID `s`, the next bootstrap action is to open only its eastward TX path so the bootstrap can proceed along the bottom row.

Using the fixed lane convention:
- `lane1 = east`

So the next configuration write should be:
- destination chip ID = `s`
- register address = `ENABLE_PISO_UP = 124`
- register data = `0x02`

That value enables only `lane1`, which is the east TX lane under the agreed convention.

This step should be performed **except** when the source chip is already at the last column of the row, that is:
- `s = m - 1`

In that boundary case, there is no chip directly east of the source chip, so the east-lane-enable step is skipped.

This rule assumes that the bootstrap configuration traffic is being propagated using the upstream TX mask. 

### Third bootstrap rule

Once chip `s` has been assigned its unique ID and only the east TX lane is open, the next bootstrap action is to assign a unique ID to the chip directly east of `s`.

The required configuration write should be:
- injected into chip `s` from the controller / source side
- addressed to destination chip ID `1`
- writing register `CHIP_ID = 122`
- with data byte `s + 1`

The intended effect is:
- chip `s` does not consume the packet locally, because its ID is now `s`, not `1`
- the packet is forwarded through the only enabled TX lane, which is `lane1 = east`
- the chip directly east of `s` is the only reachable chip still responding to default chip ID `1`
- that chip accepts the write and changes its chip ID from `1` to `s + 1`

This step depends on the bootstrap-path invariant remaining true:
- exactly one still-default-ID chip is reachable through the currently enabled lane configuration

Under that condition, the chip directly east of the source becomes the next uniquely configured chip in the bottom-row bootstrap sequence.

### Repeated eastward bootstrap along the bottom row

The same two-step pattern should then be repeated for each remaining chip to the east along the bottom row.

For each already-configured bottom-row chip with chip ID `k`, where `k` runs from `s + 1` up to `m - 2`, do the following:

1. Enable only the east TX lane on chip `k`.
- send a `CONFIG_WRITE` addressed to chip ID `k`
- write register `ENABLE_PISO_UP = 124`
- write data `0x02` so only `lane1 = east` is enabled for upstream TX

2. Assign the chip directly east of `k` its new chip ID `k + 1`.
- send a `CONFIG_WRITE` into chip `k` from the controller / already-configured path
- set the destination chip ID field to `1`
- write register `CHIP_ID = 122`
- write data byte `k + 1`

3. Enable the readback TX lane on chip `k+1`
- send a `CONFIG_WRITE` addressed to chip ID `k+1` 
- write a register `ENABLE_PISO_DOWN = 125`
- write data `0x08` so only `lane3 = west` is enabled for downstream TX


The intended effect is that chip `k` forwards the packet only upstream eastward, and the one still-default-ID chip reachable in that direction changes from chip ID `1` to chip ID `k + 1`.

This repeated process continues until the eastmost chip in the bottom row has been assigned. Under the current numbering convention being described, that means continuing until chip ID `m - 1` has been set.

So the bottom-row eastward bootstrap establishes the sequence of chip IDs:
- `s` for the source chip
- `s + 1`, `s + 2`, ..., `m - 1` for the chips to its east

This rule assumes that the intended bottom-row chip IDs correspond to the x-coordinate progression from the source chip toward the east edge.

### Repeated westward bootstrap along the bottom row

After the chips to the east of the source have been assigned, the same idea should be applied to the chips to the west of the source.

Using the fixed lane convention:
- `lane3 = west`

The westward bootstrap begins by reconfiguring chip `s` so that only its west TX lane is enabled.

1. Open only the west upstream TX lane on chip `s`.
- send a `CONFIG_WRITE` addressed to chip ID `s`
- write register `ENABLE_PISO_UP = 124`
- write data `0x08` so only `lane3 = west` is enabled for upstream TX

2. Assign the chip directly west of `s` the chip ID `s - 1`.
- send a `CONFIG_WRITE` addressed to destination chip ID `1`
- write register `CHIP_ID = 122`
- write data byte `s - 1`

Under the bootstrap-path invariant, that packet is forwarded only westward and the one still-default-ID chip reachable in that direction changes from chip ID `1` to chip ID `s - 1`.

The same two-step pattern is then repeated for each already-configured chip to the west:

For each chip with chip ID `k`, where `k` runs from `s - 1` down to `1`, do the following:

1. Enable only the west upstream TX lane on chip `k`.
- send a `CONFIG_WRITE` addressed to chip ID `k`
- write register `ENABLE_PISO_UP = 124`
- write data `0x08`

2. Assign the chip directly west of `k` the chip ID `k - 1`.
- send a `CONFIG_WRITE` addressed to destination chip ID `1`
- write register `CHIP_ID = 122`
- write data byte `k - 1`

3. Enable only the east downstream (readback) TX lane on chip `k-1`. 
- send a `CONFIG_WRITE` addressed to chip ID `k-1`
- write register `ENABLE_PISO_DOWN = 125`
- write data `0x02` to enable the east TX lane for downstream TX



This process continues until chip ID `0` has been assigned.

Under the current numbering convention, chip ID `0` is the **leftmost** chip in the bottom row.


### Special bottom-row override for chip ID `1`

The bootstrap protocol uses destination chip ID `1` as the temporary target for still-unassigned chips. That creates a hazard if, during bottom-row construction, one of the newly assigned permanent chip IDs is also `1`.

So during first-row construction, apply this special-case override:
- if the natural assignment for the chip immediately east of `s` would be `s + 1 = 1`, assign that chip ID `99` instead
- if the natural assignment for the chip immediately west of `s` would be `s - 1 = 1`, assign that chip ID `99` instead

More generally, during the bottom-row bootstrap phase, any step that would permanently assign chip ID `1` should override that assignment to chip ID `99`.

The purpose of this override is to preserve `chip_id = 1` as the temporary bootstrap target used for as-yet-unassigned chips, while preventing an already-configured chip from continuing to capture packets addressed to `1`.

This means the bottom row may temporarily contain chip ID `99` instead of chip ID `1` during bootstrap. A later post-bootstrap cleanup/remap step can restore the intended final row-major chip ID if required.

### Northward bootstrap along the leftmost column

After the bottom row has been assigned, the next stage is to bootstrap upward along the leftmost column, beginning from chip `0`.

Using the fixed lane convention:
- `lane0 = north`

The sequence is:

1. Reconfigure chip `0` so that its north upstream TX lane is now also enabled.
- send a `CONFIG_WRITE` addressed to chip ID `0`
- write register `ENABLE_PISO_UP = 124`
- write data `0x01` 

2. Assign the chip directly north of chip `0` the chip ID `m`.
- send a `CONFIG_WRITE` addressed to destination chip ID `1`
- write register `CHIP_ID = 122`
- write data byte `m`

3. Reconfigure chip `m` so that its north upstream TX lane is enabled.
- send a `CONFIG_WRITE` addressed to chip ID `m`
- write register `ENABLE_PISO_UP = 124`
- write data `0x01`

4. Reconfigure chip `m` so that its south downstream (readback) TX lane is enabled. 
- send a `CONFIG_WRITE` addressed to chip ID `m` 
- write register `ENABLE_PISO_DOWN = 125`
- write data `0x04` to enable the south TX lane 

5. Assign the chip directly north of chip `m` the chip ID `2m`.
- send a `CONFIG_WRITE` addressed to destination chip ID `1`
- write register `CHIP_ID = 122`
- write data byte `2m`

This pattern repeats up the leftmost column:
- configure the current column chip to north-only upstream TX
- send a `CONFIG_WRITE` addressed to chip ID `1`
- configure the current column chip to south-only downstream TX
- assign the directly north neighbor the next row-major column-0 ID

So the assigned chip IDs in the leftmost column become:
- `0`, `m`, `2m`, `3m`, ... , `m * (n - 1)`

This process continues until chip ID `m * (n - 1)` has been assigned, which is the topmost chip in the leftmost column under the current row-major numbering convention.

Note: these chip-ID changes are still carried by `CONFIG_WRITE` packets. They are not data packets in the RTL packet-type sense.

### Northward bootstrap along the second column

A similar pattern should then be applied to the second column, beginning from bottom-row chip `1`.

The sequence for the second column is:

1. Reconfigure chip `1` so that it enables north while retaining previously enabled upstream TX lane.
- send a `CONFIG_WRITE` addressed to chip ID `1`
- write register `ENABLE_PISO_UP = 124`
- write data which is a bitwise OR with the existing data in that register with the north TX lane `0x01`
- e.g. if chip `1` previously had `ENABLE_PISO_UP` with data `0x08` (westward upstream flow) then this step would write `0x08 | 0x01 = 0x09` to register `124`

2. Assign the chip directly north of chip `1` the chip ID `m + 1`.
- send a `CONFIG_WRITE` addressed to destination chip ID `1`
- write register `CHIP_ID = 122`
- write data byte `m + 1`

3. Reconfigure chip `m + 1` so that its north upstream TX lane is enabled.
- send a `CONFIG_WRITE` addressed to chip ID `m + 1`
- write register `ENABLE_PISO_UP = 124`
- write data `0x01`

4. Reconfigure chip `m + 1` so that its south downstream TX lane is enabled. 
- send a `CONFIG_WRITE` addressed to chip ID `m + 1`
- write a register `ENABLE_PISO_DOWN = 125`
- write data `0x04`

5. Assign the chip directly north of chip `m + 1` the chip ID `2m + 1`.
- send a `CONFIG_WRITE` addressed to destination chip ID `1`
- write register `CHIP_ID = 122`
- write data byte `2m + 1`

This pattern repeats up the second column:
- configure the current chip in column `x = 1` to have only north upstream TX, except for the bottom-row chip `1`, which keeps previously enabled upstream TX lanes as described above
- send a `CONFIG_WRITE` addressed to chip ID `1`
- configure the current chip to enable a south downstream TX lane (for readback)
- assign the directly north neighbor the next row-major ID for column `1`

So the assigned chip IDs in the second column become:
- `1`, `m + 1`, `2m + 1`, `3m + 1`, ... , `m * (n - 1) + 1`

This process continues until chip ID `m * (n - 1) + 1` has been assigned.

### General column-by-column continuation rule

After the second-column procedure is established, the same northward column bootstrap pattern should continue across the remaining bottom-row starting chips until the protocol reaches chip `s`, and then continue further until the starting chip is `m - 1`, the rightmost chip in the bottom row.

For a general bottom-row starting chip `c`, the bottom-row preparation must now be stated explicitly in terms of whether the chip lies west or east of the source chip `s`.

Case 1: `c < s`
- chip `c` lies to the west of the source chip
- from the earlier bottom-row bootstrap, chip `c` already has a west-facing upstream TX lane enabled
- before bootstrapping the column above chip `c`, do a bitwise-OR write to `ENABLE_PISO_UP = 124` which also enables `lane0 = north`
- in other words, retain the already-enabled west upstream lane and add the north upstream lane
- then send the `CHIP_ID` reassignment packet addressed to chip ID `1` so that the chip directly north of `c` is assigned chip ID `m + c`

Case 2: `c > s`
- chip `c` lies to the east of the source chip
- from the earlier bottom-row bootstrap, chip `c` already has an east-facing upstream TX lane enabled
- before bootstrapping the column above chip `c`, do a bitwise-OR write to `ENABLE_PISO_UP = 124` which also enables `lane0 = north`
- in other words, retain the already-enabled east upstream lane and add the north upstream lane
- then send the `CHIP_ID` reassignment packet addressed to chip ID `1` so that the chip directly north of `c` is assigned chip ID `m + c`

Case 3: `c = s`
- this is the special source-chip case described separately below
- chip `s` must preserve the horizontal bootstrap lanes needed on the bottom row while also enabling north upstream and keeping south downstream enabled

After the bottom-row chip for column `c` has been prepared in one of the above ways:

1. Use chip `c` to assign the chip directly north of it the row-major chip ID `m + c`.

2. Configure the newly assigned chip with a south downstream TX lane for readback.

3. Then continue upward in that column using north-only propagation from the newly assigned chips, so the assigned IDs become:
- `c`, `m + c`, `2m + c`, `3m + c`, ... , `m * (n - 1) + c`

This repeats column by column until the entire array has been assigned unique chip IDs.

### Special case at chip `s`

When the protocol reaches the bottom-row source chip `s`, there is an added condition before assigning the chip directly north of `s`.

At that point, chip `s` must have the following upstream TX lanes enabled simultaneously:
- `lane0 = north`
- `lane1 = east`
- `lane3 = west`
- unless s=0 or m-1 (end of row) in which it will have either `lane1 = east` OR `lane3 = west` enabled

And chip `s` must have the following downstream TX lane enabled: 
- `lane2 = south` 

So before creating the column above chip `s`, chip `s` should be configured with an upstream TX mask that enables:
- north
- east
- west

Using the fixed lane convention, that mask is:
- `lane0 + lane1 + lane3 = 4'b1011 = 0x0B`

That special case reflects the fact that chip `s` is the central bootstrap source for both the leftward and rightward bottom-row paths and also needs to support northward propagation into its own column.

### Completion condition

The full chip-ID bootstrap protocol is complete only when every chip in the `n x m` array has been assigned its row-major chip ID.

Under the intended numbering convention, the assigned IDs should span:
- `0` through `n * m - 1`

So the completion condition is:
- every chip ID in the set `0, 1, 2, ..., n * m - 1` has been assigned exactly once

At the end of this protocol, the entire rectangular array has unique chip IDs and is ready for the next bring-up phase.

## Inputs To The Script

The script should take at least:
- `rows`
- `cols`
- `source_chip`
- `source_edge_policy` or a fixed assumption for initial outward directions
- optionally, the order in which chips should be assigned IDs

A reasonable initial interface is:

```text
bootstrap_ids.py --rows 4 --cols 4 --source-chip 0
```

A later extension could allow:
- custom traversal order
- custom initial source direction
- custom assigned ID numbering

## Output Of The Script

The script should produce a machine-readable ordered list of bootstrap operations.

Each operation should describe:
- which chip is expected to process the configuration packet
- which register is being written
- what byte value is being written
- why the write is needed
- what the expected reachable target is after the write

A useful JSON-like output format would be:

```json
{
  "bootstrap_steps": [
    {
      "step": 0,
      "chip_context": 0,
      "target_chip_id": 1,
      "register": 122,
      "data": 0,
      "meaning": "assign source chip ID = 0"
    }
  ]
}
```

The script may also optionally emit the corresponding packet words using the UART helper.

## Fixed Lane-To-Edge Convention

For the remainder of the bootstrap protocol and related helper scripts, the lane mapping convention is fixed as:

- `lane0` = `north`
- `lane1` = `east`
- `lane2` = `south`
- `lane3` = `west`

This convention applies to both:
- TX lane masks
- RX lane masks

So any 4-bit lane-enable value should be interpreted using that ordering.

Examples:
- enabling only the north lane means enabling `lane0`
- enabling only the west lane means enabling `lane3`
- a mask of `4'b0010` means east only
- a mask of `4'b1001` means west and north

This convention should be used consistently in:
- bootstrap packet-generation logic
- runtime routing descriptions
- helper scripts
- documentation for `larpix_network_sim`

## Register-Write Interpretation Rule

Unless a protocol step explicitly says to **enable only** a specific TX lane or lane set, the word **enable** should be interpreted as a read-modify-write operation on the existing register contents.

That means:
- if the step writes `ENABLE_PISO_UP = 124`, then enabling a lane means bitwise-OR the requested lane bit into the chip's current `ENABLE_PISO_UP` value
- if the step writes `ENABLE_PISO_DOWN = 125`, then enabling a lane means bitwise-OR the requested lane bit into the chip's current `ENABLE_PISO_DOWN` value

So the default interpretation of a lane-enable step is:
- `new_register_value = old_register_value | lane_mask`

This rule is needed because many bootstrap steps must preserve previously enabled lanes while adding one new direction for continued propagation or readback.

Examples:
- if a chip already has `ENABLE_PISO_UP = 0x08` and a later step says to enable the north upstream lane, the write should use `0x08 | 0x01 = 0x09`
- if a chip already has `ENABLE_PISO_DOWN = 0x04` and a later step says to enable the west downstream lane, the write should use `0x04 | 0x08 = 0x0C`

Only when a protocol step explicitly says to **enable only** a specific lane should the write replace the old register value rather than OR-ing into it.

## Registers Needed During Bootstrap

Based on the current RTL, the bootstrap process will likely need to write at least:

- `CHIP_ID = 122`
- `ENABLE_PISO_UP = 124`
- `ENABLE_PISO_DOWN = 125`
- `ENABLE_POSI = 126`

These are sufficient for:
- assigning unique chip IDs
- opening and closing temporary forwarding paths
- ensuring RX/TX lane participation during bootstrap

## Required Behavioral Rules

The script must obey these rules:

1. The source chip must be assigned a unique chip ID first.
- Otherwise it will still consume packets addressed to the default chip ID.

2. Only one upstream direction facing a chip with `chip_ID=1` should be opened when targeting the next unassigned chip.
- This keeps only one new default-ID chip reachable.

3. The script must not allow multiple still-default-ID chips to become reachable at the same time.
- That would make the next `CHIP_ID` write ambiguous.

4. Lane-enable writes used only for bootstrap should be treated as temporary state.
- The script should make clear which writes are for bring-up only.

5. The script should define a deterministic traversal order.
- Example options:
  - row-major flood
  - snake order
  - breadth-first from the source chip

## Recommended Initial Traversal Strategy

A simple initial strategy is a deterministic spanning-tree walk from the source chip.

The script should:
- define a parent-child bootstrap tree over the `rows x cols` array
- only use already-configured chips as forwarders
- assign exactly one new child chip at a time

This is safer than trying to open multiple fronts simultaneously.

A breadth-first tree is a reasonable default because it keeps hop distance small and makes the bring-up sequence easier to reason about.

## Packet-Level Model

Each configuration write packet should be described by:
- destination chip ID
- register address
- register data byte

The script should be able to generate many such writes in order.

Examples of bootstrap actions:
- assign source chip ID from default `1` to unique ID `0`
- enable only one TX lane on the source chip
- assign the next chip from default `1` to unique ID `2`
- disable or reconfigure temporary lane masks before continuing

## What Must Be Decided Before Implementation

Before writing the script, these decisions should be fixed:

1. What traversal order should be the default?
- breadth-first
- row-major
- snake
- custom explicit order

2. What chip-ID numbering scheme should be used?
- row-major IDs
- breadth-first assignment IDs
- preserve an external desired ID map

3. How are physical directions mapped to UART lanes?
- lane-to-edge mapping must be fixed or provided as input

4. What temporary lane-mask convention is used during bootstrap?
- the script must know which register values correspond to opening north/east/south/west

5. Does the source chip always receive out-of-band direct configuration from the FPGA?
- this is assumed for now, but should be made explicit

## Recommended Next Step

After this design note, the next implementation step should be a script that:
- constructs a traversal tree for an `n x m` array
- emits the ordered chip-ID assignment steps
- emits the corresponding configuration write packet words using `larpix_network_sim/scripts/larpix_uart.py`

That script should initially solve only the chip-ID bootstrap problem.
Full routing configuration can be added afterward as a separate layer.

### Source chip south-lane rule

The source chip must always keep `lane2` south downstream enabled throughout the bootstrap procedure so that a return path to the FPGA/controller exists for later network tests. In the toy simulator this means any TX-mask write delivered to the source chip is automatically augmented with `lane2`.
