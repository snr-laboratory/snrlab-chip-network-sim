# Configuration Tests

## Single-Chip Startup Register Readback

This first configuration test checks that a single `chip_larpix` instance comes up with the expected RTL startup register values and can return configuration readback packets to the FPGA controller. The same framework now also supports parallel Verilated chip targets for the alternate `v2` RTL (`chip_larpix_v2`) and the `larpix_v3c` RTL (`chip_larpix_v3c`) through separate CMake targets.

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
- [`generate_bootstrap_chip_id_readback_json.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/generate_bootstrap_chip_id_readback_json.py) mirrors that toy protocol and generates the live startup JSON schedule for arbitrary network size and source chip. Run with flags `python3 generate_bootsrap_chip_id_readback_json.py --rows <ROWS> --cols <COLS> --s <SOURCE_X> --source-y <SOURCE_Y> --out <OUTPUT_JSON_FILEPATH>`; `--source-y` defaults to `0` so the old bottom-row usage still works unchanged.
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

This single-chip event test verifies that the `chip_larpix` runtime can use startup configuration writes from the FPGA to prepare the real analog-plus-Verilated-digital-core backend for a natural hit, then return a downstream data packet to the FPGA after a local charge injection. The mirrored RTL trees used by the framework now all share the same lowered `GLOBAL_THRESH` startup default so this smoke test remains portable across `chip_larpix`, `chip_larpix_v2`, and `chip_larpix_v3c`.

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


## 3x5 Remote Analog/Cosim Event And Occupancy Test

This live-network event test extends the single-chip analog check to a `3`-row by `5`-column network with source chip `(0,0)`. The startup sequence bootstraps `CHIP_ID` assignment across the network without the per-assignment confirmation reads, then configures the remote top-right chip `(4,2)` with final `chip_id=131` so that all `64` channels can emit natural event packets after simultaneous charge injection. The same live run also records FIFO occupancy directly from the RTL-backed chip runtime for chip `14`, including the shared chip FIFO and the local channel FIFO counters for channels `0..4`.

File flow:
- [`generate_bootstrap_event_startup_json.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/generate_bootstrap_event_startup_json.py) builds the startup schedule by reusing the bootstrap assignment logic from [`generate_bootstrap_chip_id_readback_json.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/generate_bootstrap_chip_id_readback_json.py), removing the bootstrap readbacks for this shorter event testbench, then appending the remote-chip configuration writes needed for the analog hit test on all `64` channels.
- [`startup_3x5_event_top_right.json`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/config/startup_3x5_event_top_right.json) is the generated startup sequence for the `3x5`, `s=0` case targeting chip `(4,2)`. It writes all eight `CSA_ENABLE` bytes to `0xFF`, all eight `CHANNEL_MASK` bytes to `0x00`, and `ENABLE_TRIG_MODES` to `0x00` on chip `14` after bootstrap is complete.
- [`compile_startup_json.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/compile_startup_json.py) converts that startup JSON into the compiled UART frame schedule for the FPGA controller.
- [`stimulus_3x5_event_top_right.json`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/config/stimulus_3x5_event_top_right.json) injects one charge pulse into all `64` channels of runtime `14` at tick `9000`.
- [`orchestrator_larpix.c`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/orchestrator_larpix.c) now accepts `-occupancy_csv`, `-occupancy_runtime_id`, and `-occupancy_tick_start` and forwards them only to the selected runtime.
- [`chip_larpix.cpp`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/chip_larpix.cpp) now writes `tick,chip_fifo,ch0_fifo,ch1_fifo,ch2_fifo,ch3_fifo,ch4_fifo` CSV rows beginning at the requested tick, using the live cosim backend FIFO counters.
- [`larpix_cosim_backend.cpp`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/larpix_cosim_backend.cpp) samples the shared chip FIFO occupancy and the channel FIFO occupancy for channels `0..4` on every tick.
- [`run_3x5_event_top_right.sh`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/run_3x5_event_top_right.sh) regenerates the startup JSON, compiles it, launches the live network with the shared stimulus JSON, requests occupancy logging for runtime `14` from the injection tick, generates a PNG occupancy plot, and checks that the FPGA receives downstream event packets from chip `14`.
- The live run writes:
  - occupancy CSV: [`chip14_occupancy.csv`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_3x5_event_top_right/chip14_occupancy.csv)
  - occupancy plot: [`chip14_occupancy.png`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_3x5_event_top_right/chip14_occupancy.png)

Observed passing result:
- `PASS: 3x5 LArPix analog/cosim remote all-channel occupancy test`
- `expected_frame_count=63`
- `observed_transmitted_frame_count=63`
- `occupancy_samples=7380`
- `peak_chip_fifo=8`
- `peak_ch0_fifo=1`
- `peak_ch4_fifo=1`
- `distinct_event_channels=14`
- `observed_event_channels=1,2,3,4,5,6,7,41,42,43,44,45,46,47`
- `first_matching_reply_packet=0x5058c80023260439`
- `first_matching_chip_id=14 channel_id=1 adc=355 downstream=1 trigger_type=0`


## 15x15 Remote Analog/Cosim Event Test For Chip 131

This live-network event test is now an official `rtl_preconfigured` configuration test for a `15`-row by `15`-column network with source chip `(0,0)` and `s=0`. Instead of spending runtime on the long chip-ID bootstrap packet schedule, the run derives the final `CHIP_ID`, `ENABLE_PISO_UP`, and `ENABLE_PISO_DOWN` state from that same bootstrap protocol logic and preloads those register values directly into each RTL-backed chip before tick `0`. The test then injects charge into all `64` channels of final `chip_id=131`. For `rows=15`, `cols=15`, `s=0`, chip `131` lands at coordinate `(11,8)` and runtime `131`.

File flow:
- [`generate_bootstrap_preconfigured_event_init_json.py`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/generate_bootstrap_preconfigured_event_init_json.py) derives the final steady-state register values from the existing bootstrap assignment logic, then appends the chip-131 event-enabling writes for all `64` channels.
- [`chip_larpix.cpp`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/chip_larpix.cpp) accepts `-init_regs_json`, preloads those register values into the backend before the first live tick, and now delays shutdown slightly after the terminal `DONE(STOP)` so successful runs do not report a false control-plane failure.
- [`larpix_cosim_backend.cpp`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/larpix_cosim_backend.cpp) waits for the RTL internal config-reset window to clear, then writes the preload values into the true Verilated RTL register file. The run still uses the real RTL design rather than a software-side register emulation.
- [`orchestrator_larpix.c`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/src/orchestrator_larpix.c) forwards `-init_regs_json` to every chip and still attaches the FPGA sink for preconfigured runs.
- [`run_15x15_event_chip131.sh`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_network_sim/scripts/run_15x15_event_chip131.sh) builds the binaries, regenerates the init JSON, generates the `64`-channel stimulus JSON for runtime `131`, runs the live network, records chip-131 occupancy, and converts the trace into a playback JSON for the web visualizer.
- The live run writes:
  - playback JSON: [`live_event_15x15_chip131.json`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_15x15_event_chip131/live_event_15x15_chip131.json)
  - occupancy CSV: [`chip131_occupancy.csv`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_15x15_event_chip131/chip131_occupancy.csv)
  - occupancy plot: [`chip131_occupancy.png`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/build/larpix_15x15_event_chip131/chip131_occupancy.png)

Observed passing result:
- `PASS: 15x15 LArPix rtl_preconfigured analog/cosim chip-131 event test`
- `rows=15`
- `cols=15`
- `source=(0,0)`
- `chip_id=131`
- `runtime_id=131`
- `injection_tick=1000`
- `channels_injected=64`
- `ack_timeout_ms=20000`
- `occupancy_samples=7000`
- `first_occupancy_tick=1000`
- `last_occupancy_tick=8000`
- `run completed without timeout`
- `run completed without STOP-handshake connection reset`

Manual run:
```bash
./larpix_network_sim/scripts/run_15x15_event_chip131.sh
```

Visualizer URL after the run:
```text
http://localhost:8000/larpix_network_sim/visualizers/packet_transmission/?playback=/build/larpix_15x15_event_chip131/live_event_15x15_chip131.json
```
