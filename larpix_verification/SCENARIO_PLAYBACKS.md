# LArPix Verification Scenario Playbacks

This file records only scenarios whose investigation and visualizer playback
have reached an acceptable state. Add new scenarios only when they are
explicitly selected for this list.

All scenario runners, playback data, sidecars, schedules, summaries, and plots
are stored under [`verification_scenarios/`](verification_scenarios/). The
`docs/` directory contains only the GitHub Pages visualizer and lightweight
stable-page wrappers.

## v3c 2x2 Packet-Loss Probe

Purpose: inject 64 packets each from chips 1 and 2, route both streams through
chip 0, and inspect the North/East UART RX paths, Hydra arbitration, shared
FIFO, and South UART TX. All 128 generated packets reached the FPGA in the
recorded run.

- RTL: `v3c`
- Scenario runner:
  [`run_2x2_packet_loss_probe.sh`](verification_scenarios/v3c_2x2_packet_loss_probe/run_2x2_packet_loss_probe.sh)
- Playback JSON:
  [`live_event_2x2_packet_loss_probe.json`](verification_scenarios/v3c_2x2_packet_loss_probe/live_event_2x2_packet_loss_probe.json)
- Required chip-debug sidecar:
  [`chip0_rx_debug.csv`](verification_scenarios/v3c_2x2_packet_loss_probe/chip0_rx_debug.csv)
- Stable visualizer page:
  [2x2 Packet-Loss Probe](https://www.snr-lab.org/snrlab-chip-network-sim/scenarios/v3c-2x2-packet-loss-probe/)

The playback JSON references the adjacent `chip0_rx_debug.csv`. Both files
must be retained and published together.

## v3c 3x3 Convergent Packet-Loss and Read-Contention Probe

Purpose: inject all 64 channels of chips 3, 5, and 7 simultaneously so three
64-packet streams converge on chip 4. While chip 4 is receiving and forwarding
the data traffic, send four configuration-read requests to chip 7. This
exercises chip 4's upstream request forwarding concurrently with its
downstream data handling.

The routing overrides are:

| Chip | Upstream TX | Downstream TX |
|---:|---|---|
| 3 | North only | East only |
| 4 | North only | South only |
| 5 | North only | West only |
| 7 | South only | South only |

Configuration reads begin at ticks 1100, 1200, 1300, and 1400 for chip 7
registers 122 (`CHIP_ID`), 124 (`ENABLE_PISO_UP`), 125
(`ENABLE_PISO_DOWN`), and 64 (`GLOBAL_THRESH`). All four valid replies reached
the FPGA. All 192 generated data packets also reached the FPGA with no loss or
duplicate arrivals.

- RTL: `v3c`
- Scenario runner:
  [`run_3x3_convergent_packet_loss_probe.sh`](verification_scenarios/v3c_3x3_convergent_packet_loss_read_contention/run_3x3_convergent_packet_loss_probe.sh)
- Playback JSON:
  [`live_event_3x3_convergent_packet_loss_probe.json`](verification_scenarios/v3c_3x3_convergent_packet_loss_read_contention/live_event_3x3_convergent_packet_loss_probe.json)
- Required chip-4 debug sidecar:
  [`chip4_rx_debug.csv`](verification_scenarios/v3c_3x3_convergent_packet_loss_read_contention/chip4_rx_debug.csv)
- Required chip-0 debug sidecar:
  [`chip0_rx_debug.csv`](verification_scenarios/v3c_3x3_convergent_packet_loss_read_contention/chip0_rx_debug.csv)
- Packet-loss and routing summary:
  [`packet_loss_summary.json`](verification_scenarios/v3c_3x3_convergent_packet_loss_read_contention/packet_loss_summary.json)
- Compiled configuration-read schedule:
  [`startup_3x3_convergent_packet_loss_probe.compiled.json`](verification_scenarios/v3c_3x3_convergent_packet_loss_read_contention/startup_3x3_convergent_packet_loss_probe.compiled.json)
- Stable visualizer page:
  [3x3 Convergent Traffic and Read Contention](https://www.snr-lab.org/snrlab-chip-network-sim/scenarios/v3c-3x3-convergent-packet-loss-read-contention/)

The playback JSON references both adjacent debug CSV files. The playback,
`chip4_rx_debug.csv`, and `chip0_rx_debug.csv` must be retained and published
together.

## v3c 10x10 Unconfigured-Network Startup

Purpose: instantiate 100 v3c chips without register preconfiguration and
exercise the complete network bootstrap process. The RTL reset state gives
every chip ID 1 with upstream and downstream TX lanes disabled. The startup
schedule progressively assigns IDs 0 through 99 and configures the lane masks
needed to reach every chip.

The accepted schedule contains 445 configuration writes and no configuration
reads. Writes are spaced 75 ticks start-to-start, safely above the observed
68-tick forwarding service interval. The temporary ID 254 assigned to chip
`(1,0)` was successfully remapped to ID 1 at tick 33457. Every scheduled write
had a matching destination trace.

- RTL: `v3c`
- Scenario runner:
  [`run_10x10_bootstrap_startup_v3c.sh`](verification_scenarios/v3c_10x10_unconfigured_network_startup/run_10x10_bootstrap_startup_v3c.sh)
- Playback JSON:
  [`live_bootstrap_10x10.json`](verification_scenarios/v3c_10x10_unconfigured_network_startup/live_bootstrap_10x10.json)
- Bootstrap summary:
  [`bootstrap_summary.json`](verification_scenarios/v3c_10x10_unconfigured_network_startup/bootstrap_summary.json)
- Compiled startup schedule:
  [`startup_10x10_bootstrap.compiled.json`](verification_scenarios/v3c_10x10_unconfigured_network_startup/startup_10x10_bootstrap.compiled.json)
- Stable visualizer page:
  [10x10 Unconfigured-Network Startup](https://www.snr-lab.org/snrlab-chip-network-sim/scenarios/v3c-10x10-unconfigured-network-startup/)

The playback has no required chip-debug sidecar.

## v3c 15x15 Two-Track Charge Deposition

Purpose: exercise event generation and convergent packet transport in a
preconfigured 15x15 v3c network. Two staggered charge-deposition tracks inject
all channels 0 through 15 on 13 chips. Consecutive chips on each track are
separated by 500 ticks.

The first track uses chip IDs 48, 64, 80, 96, 112, 113, 129, and 145. The
second track uses chip IDs 183, 184, 169, 155, and 141. The accepted run lasts
16500 ticks, providing a 12000-tick drain after the final injection at tick
4500. All 208 generated packets reached the FPGA exactly once; the final
packet arrived at tick 16252.

- RTL: `v3c`
- Scenario runner:
  [`run_15x15_event_staggered_multichip.sh`](verification_scenarios/v3c_15x15_two_track_charge_deposition/run_15x15_event_staggered_multichip.sh)
- Playback JSON:
  [`live_event_15x15_staggered_multichip.json`](verification_scenarios/v3c_15x15_two_track_charge_deposition/live_event_15x15_staggered_multichip.json)
- Preconfigured register state:
  [`init_15x15_event_staggered_multichip_preconfigured.json`](verification_scenarios/v3c_15x15_two_track_charge_deposition/init_15x15_event_staggered_multichip_preconfigured.json)
- Charge-injection stimulus:
  [`stimulus_15x15_event_staggered_multichip.json`](verification_scenarios/v3c_15x15_two_track_charge_deposition/stimulus_15x15_event_staggered_multichip.json)
- Selected-chip FIFO occupancy plot:
  [`selected_chip_fifo_occupancy_ticks_1000_18000.png`](verification_scenarios/v3c_15x15_two_track_charge_deposition/selected_chip_fifo_occupancy_ticks_1000_18000.png)
- FIFO occupancy plotting script:
  [`plot_15x15_selected_fifo_occupancy.py`](verification_scenarios/v3c_15x15_two_track_charge_deposition/plot_15x15_selected_fifo_occupancy.py)
- Stable visualizer page:
  [15x15 Two-Track Charge Deposition](https://www.snr-lab.org/snrlab-chip-network-sim/scenarios/v3c-15x15-two-track-charge-deposition/)

The playback and FIFO occupancy plot have no required chip-debug sidecars.
