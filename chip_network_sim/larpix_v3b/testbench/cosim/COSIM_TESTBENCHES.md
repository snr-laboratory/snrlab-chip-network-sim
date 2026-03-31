# Co-simulation Testbenches

This directory contains the C++ co-simulation harnesses used to verify the `larpix_v3b` software-analog / Verilated-digital flow.

These harnesses all use the same basic split:
- the analog side is modeled in C++ by [`analog_core_model.cpp`](../../cpp/analog_core_model.cpp)
- the digital side is the Verilated RTL from [`digital_core.sv`](../../src/digital_core.sv)
- the harness drives the DUT, checks internal behavior, and reports `PASS` only if all required checks succeed

## Testbenches

### 1. `digital_core_cosim_harness.cpp`
Path:
- [`digital_core_cosim_harness.cpp`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_v3b/testbench/cosim/digital_core_cosim_harness.cpp)

Purpose:
- inject analog charge into one channel, or optionally all channels
- verify that the software analog model produces `hit`, `done`, and `dout`
- verify that the digital core converts that activity into a local event packet
- verify that the event enters Hydra and launches toward TX

What it proves:
- the software analog model interfaces correctly to the current `digital_core`
- local event generation works end-to-end
- Hydra/TX launch works for generated event packets

Primary runner:
- [`run_digital_core_cosim_charge_test.sh`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/scripts/run_digital_core_cosim_charge_test.sh)

### 2. `digital_core_cosim_order_tb.cpp`
Path:
- [`digital_core_cosim_order_tb.cpp`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_v3b/testbench/cosim/digital_core_cosim_order_tb.cpp)

Purpose:
- inject `-5e-15` C into channels `32-63`
- inject `-5e-15` C into channels `0-31` after a programmed delay
- verify the first-seen event order observed from the digital core event path

Current configured behavior:
- the harness currently uses a `120`-cycle gap between the two injections
- with that delay, the expected observed order is:
  - `32,33,...,63,0,1,...,31`

What it proves:
- the co-simulation can test ordering behavior, not just packet existence
- the current RTL drains the first half before the second half when enough spacing is provided
- the event path and Hydra launch still work under multi-channel stimulus

Primary runner:
- [`run_digital_core_cosim_order_test.sh`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/scripts/run_digital_core_cosim_order_test.sh)

### 3. `digital_core_cosim_config_tb.cpp`
Path:
- [`digital_core_cosim_config_tb.cpp`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/larpix_v3b/testbench/cosim/digital_core_cosim_config_tb.cpp)

Purpose:
- drive real serialized configuration packets into `posi[0]`
- exercise the true RTL configuration path:
  - `posi -> uart_rx -> hydra_ctrl -> comms_ctrl -> config_regfile`
- verify configuration readback replies launched from Hydra into UART0
- verify UART0 actually begins transmitting those replies on `piso[0]`

What it proves:
- config write behavior works through the real serial interface
- config read behavior works through the real serial interface
- mapped outputs such as `tx_enable` and `threshold_global` respond correctly to config writes
- Hydra launches the readback reply packets toward TX

Primary runner:
- [`run_digital_core_cosim_config_test.sh`](/home/lxusers/k/kalindigosine/snrlab-ic-q-pix-v1/chip_network_sim/scripts/run_digital_core_cosim_config_test.sh)

## Re-Verilation Note

In general, if the digital-core RTL is stable and neither the RTL nor the harness source has changed, it is not necessary to re-run Verilator every time. An already generated C++ model and executable can be reused directly.

However, the current early-stage runner scripts in this repository are written for convenience and reproducibility, and they do re-Verilate the RTL and rebuild the executable each time they run.

So:
- re-Verilation is not fundamentally required for every execution
- but the current `run_*.sh` scripts do perform it by design
