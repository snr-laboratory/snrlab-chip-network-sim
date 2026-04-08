# Configuration Tests

## Single-Chip Startup Register Readback

This first configuration test checks that a single `chip_larpix` instance comes up with the expected RTL startup register values and can return configuration readback packets to the FPGA controller.

The flow is:

1. [`generate_1chip_full_reg_readback_json.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/generate_1chip_full_reg_readback_json.py)
   creates the startup configuration description:
   [`startup_1chip_full_reg_readback.json`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/config/startup_1chip_full_reg_readback.json)

2. [`compile_startup_json.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/compile_startup_json.py)
   converts that startup JSON into a compiled schedule of UART packet bitstreams for the FPGA controller to send.

3. [`fpga_larpix.cpp`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/fpga_larpix.cpp)
   reads the compiled startup schedule and transmits the UART bits into the chip over the south-edge connection.

4. [`run_larpix_1chip_readback_smoke.sh`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/run_larpix_1chip_readback_smoke.sh)
   runs the full 1-chip test and checks that the returned configuration readback packets match the startup defaults defined in the mirrored RTL files.

In the current version of the test, the FPGA first enables south TX on the chip so replies can return to the controller, then reads back every explicit startup-default register described by the RTL default-assignment file, excluding register `125` because that register is intentionally modified first for the test.

## 3x5 Bootstrap Chip-ID Assignment Plus Readback Test

This network bootstrap test runs a live `3`-row by `5`-column LArPix network with source chip `(0,0)` and uses the corrected toy bootstrap protocol as the reference schedule. After every `CHIP_ID` reassignment, the FPGA immediately issues a `CHIP_ID` read and waits for the matching readback reply before allowing the next bootstrap step to proceed.

File flow:
- [`bootstrap_id_protocol_sim.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/bootstrap_id_protocol_sim.py) is the toy reference model for the bootstrap protocol and the expected final chip/mask state.
- [`generate_bootstrap_chip_id_readback_json.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/generate_bootstrap_chip_id_readback_json.py) mirrors that toy protocol and generates the live startup JSON schedule for arbitrary network size and source chip. Run with flags `python3 generate_bootsrap_chip_id_readback_json.py --rows <ROWS> --cols <COLS> --s <SOURCE_X_ON_BOTTOM_ROW> --out <OUTPUT_JSON_FILEPATH>`.
- [`startup_3x5_bootstrap_chip_ids.json`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/config/startup_3x5_bootstrap_chip_ids.json) is the generated startup sequence for a rows=3 cols=5 s=0 network containing the distributed `CHIP_ID` writes, `ENABLE_PISO_UP` / `ENABLE_PISO_DOWN` writes, and immediate `CHIP_ID` reads. This file was generated from the generate.py script.
- [`compile_startup_json.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/compile_startup_json.py) converts that startup JSON into UART packet words and bitstreams, preserving the per-read wait metadata for the FPGA controller.
- [`fpga_larpix.cpp`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/fpga_larpix.cpp) sends the compiled startup frames into the source chip south edge and pauses after each `CHIP_ID` read until the matching reply is received.
- [`run_3x5_bootstrap_id_startup.sh`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/run_3x5_bootstrap_id_startup.sh) regenerates the startup JSON, compiles it, launches the live network, and checks the returned readbacks for the 3x5 example case.

Observed passing result:
- `verified_readbacks=0,254,2,3,4,5,10,6,11,7,12,8,13,9,14,1`

This ordering reflects the actual bootstrap traversal and includes the temporary placeholder ID `254` on the bottom row before the final cleanup remap `254 -> 1`.

The live network is expected to emulate the following final toy-model state from [`bootstrap_id_protocol_sim.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/bootstrap_id_protocol_sim.py) for `rows=3`, `cols=5`, `s=0`:

```text
After Full Protocol Completed
+--------------------+--------------------+--------------------+--------------------+--------------------+
|     10@U0000/D0100 |     11@U0000/D0100 |     12@U0000/D0100 |     13@U0000/D0100 |     14@U0000/D0100 |
+--------------------+--------------------+--------------------+--------------------+--------------------+
|      5@U0001/D0100 |      6@U0001/D0100 |      7@U0001/D0100 |      8@U0001/D0100 |      9@U0001/D0100 |
+--------------------+--------------------+--------------------+--------------------+--------------------+
|      0@U0011/D0100 |      1@U0011/D1000 |      2@U0011/D1000 |      3@U0011/D1000 |      4@U0001/D1000 |
+--------------------+--------------------+--------------------+--------------------+--------------------+
  x=0   x=1   x=2   x=3   x=4
  top row is y=2
  bottom row is y=0
  cell format = chip_id@Uupstreammask/Ddownstreammask
```

### Running The 3x5 Test Manually

The runner script automates generation, build, compilation, launch, and log checking. The equivalent manual command flow is:

1. Generate the startup JSON:
```bash
python3 larpix_network_sim/scripts/generate_bootstrap_chip_id_readback_json.py \
  --rows 3 \
  --cols 5 \
  --s 0 \
  --out larpix_network_sim/config/startup_3x5_bootstrap_chip_ids.json
```

2. Configure and build the required binaries:
```bash
cmake -S . -B build
cmake --build build --target fpga_larpix orchestrator_larpix chip_larpix_build -j
```

3. Compile the startup JSON into UART packet words and bitstreams:
```bash
mkdir -p build/larpix_3x5_bootstrap_id_smoke
python3 larpix_network_sim/scripts/compile_startup_json.py \
  larpix_network_sim/config/startup_3x5_bootstrap_chip_ids.json \
  build/larpix_3x5_bootstrap_id_smoke/startup_3x5_bootstrap_chip_ids.compiled.json
```

4. Launch the live network:
```bash
build/orchestrator_larpix \
  -rows 3 \
  -cols 5 \
  -ticks 30000 \
  -source_x 0 \
  -source_y 0 \
  -chip_bin build/chip_larpix \
  -fpga_bin build/fpga_larpix \
  -startup_json build/larpix_3x5_bootstrap_id_smoke/startup_3x5_bootstrap_chip_ids.compiled.json
```

To capture the same log used by the runner:
```bash
build/orchestrator_larpix \
  -rows 3 \
  -cols 5 \
  -ticks 30000 \
  -source_x 0 \
  -source_y 0 \
  -chip_bin build/chip_larpix \
  -fpga_bin build/fpga_larpix \
  -startup_json build/larpix_3x5_bootstrap_id_smoke/startup_3x5_bootstrap_chip_ids.compiled.json \
  > build/larpix_3x5_bootstrap_id_smoke/run.log 2>&1
```

At that point, the remaining runner-script work is log validation: checking the transmitted-frame count and the returned `CHIP_ID` readback packets.

## Single-Chip Analog/Cosim Event Test

This single-chip event test verifies that the `chip_larpix` runtime can use startup configuration writes from the FPGA to prepare the real analog-plus-Verilated-digital-core backend for a natural hit, then return a downstream data packet to the FPGA after a local charge injection.

File flow:
- [`startup_1chip_event_source.json`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/config/startup_1chip_event_source.json) describes the required startup configuration writes: enable south TX, enable channel 0, unmask channel 0, and disable trigger-veto behavior.
- [`compile_startup_json.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/compile_startup_json.py) converts that startup JSON into a compiled UART frame schedule for the FPGA controller.
- [`stimulus_1chip_event_source.json`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/config/stimulus_1chip_event_source.json) provides the local charge injection applied by `chip_larpix` to channel 0 after configuration is complete.
- [`fpga_larpix.cpp`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/fpga_larpix.cpp) sends the compiled UART bits into the chip over the south edge and logs any received packet words coming back.
- [`run_1chip_event_startup.sh`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/run_1chip_event_startup.sh) builds the binaries, compiles the startup JSON, runs the one-chip network, and checks that the FPGA receives a valid downstream data packet from chip 1, channel 0.

Observed passing result:
- `chip_id=1`
- `channel_id=0`
- `adc=355`
- `downstream=1`
- `trigger_type=0`
