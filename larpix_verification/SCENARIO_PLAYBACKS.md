# LArPix Verification Scenario Playbacks

This file records only scenarios whose investigation and visualizer playback
have reached an acceptable state. Add new scenarios only when they are
explicitly selected for this list.

## v3c 2x2 Packet-Loss Probe

Purpose: inject 64 packets each from chips 1 and 2, route both streams through
chip 0, and inspect the North/East UART RX paths, Hydra arbitration, shared
FIFO, and South UART TX. All 128 generated packets reached the FPGA in the
recorded run.

- RTL: `v3c`
- Scenario runner:
  [`run_2x2_packet_loss_probe.sh`](../chip_network_sim/sim_core/scenarios/run_2x2_packet_loss_probe.sh)
- Playback JSON:
  [`live_event_2x2_packet_loss_probe.json`](../chip_network_sim/build/larpix_2x2_packet_loss_probe__v3c/live_event_2x2_packet_loss_probe.json)
- Required chip-debug sidecar:
  [`chip0_rx_debug.csv`](../chip_network_sim/build/larpix_2x2_packet_loss_probe__v3c/chip0_rx_debug.csv)
- Visualizer URL:
  `http://localhost:8000/sim_core/visualizers/packet_transmission/?asset_rev=chip-view-35&playback=/build/larpix_2x2_packet_loss_probe__v3c/live_event_2x2_packet_loss_probe.json`

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
  [`run_3x3_convergent_packet_loss_probe.sh`](../chip_network_sim/sim_core/scenarios/run_3x3_convergent_packet_loss_probe.sh)
- Playback JSON:
  [`live_event_3x3_convergent_packet_loss_probe.json`](../chip_network_sim/build/larpix_3x3_convergent_packet_loss_probe__v3c/live_event_3x3_convergent_packet_loss_probe.json)
- Required chip-4 debug sidecar:
  [`chip4_rx_debug.csv`](../chip_network_sim/build/larpix_3x3_convergent_packet_loss_probe__v3c/chip4_rx_debug.csv)
- Required chip-0 debug sidecar:
  [`chip0_rx_debug.csv`](../chip_network_sim/build/larpix_3x3_convergent_packet_loss_probe__v3c/chip0_rx_debug.csv)
- Packet-loss and routing summary:
  [`packet_loss_summary.json`](../chip_network_sim/build/larpix_3x3_convergent_packet_loss_probe__v3c/packet_loss_summary.json)
- Compiled configuration-read schedule:
  [`startup_3x3_convergent_packet_loss_probe.compiled.json`](../chip_network_sim/build/larpix_3x3_convergent_packet_loss_probe__v3c/startup_3x3_convergent_packet_loss_probe.compiled.json)
- Visualizer URL:
  `http://localhost:8000/sim_core/visualizers/packet_transmission/?asset_rev=chip-view-39&playback=/build/larpix_3x3_convergent_packet_loss_probe__v3c/live_event_3x3_convergent_packet_loss_probe.json`

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
  [`run_10x10_bootstrap_startup_v3c.sh`](../chip_network_sim/sim_core/scenarios/run_10x10_bootstrap_startup_v3c.sh)
- Playback JSON:
  [`live_bootstrap_10x10.json`](../chip_network_sim/build/larpix_10x10_bootstrap_startup__v3c/live_bootstrap_10x10.json)
- Bootstrap summary:
  [`bootstrap_summary.json`](../chip_network_sim/build/larpix_10x10_bootstrap_startup__v3c/bootstrap_summary.json)
- Compiled startup schedule:
  [`startup_10x10_bootstrap.compiled.json`](../chip_network_sim/build/larpix_10x10_bootstrap_startup__v3c/startup_10x10_bootstrap.compiled.json)
- Visualizer URL:
  `http://localhost:8000/sim_core/visualizers/packet_transmission/?asset_rev=chip-view-39&playback=/build/larpix_10x10_bootstrap_startup__v3c/live_bootstrap_10x10.json`

The playback has no required chip-debug sidecar.
