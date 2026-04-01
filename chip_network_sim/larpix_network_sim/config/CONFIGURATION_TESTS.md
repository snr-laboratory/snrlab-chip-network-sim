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
