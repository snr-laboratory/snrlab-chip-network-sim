# LArPix Verification Scenario Playbacks

This file records only scenarios whose investigation and visualizer playback
have reached an acceptable state. The published files are immutable run
artifacts; replace them only when an accepted scenario is deliberately
superseded.

The [scenario gallery](https://www.snr-lab.org/snrlab-chip-network-sim/scenarios/)
is the public entry point for all accepted playbacks.

## v3c 2x2 Packet-Loss Probe

Inject 64 packets each from chips 1 and 2, route both streams through chip 0,
and inspect the North/East UART RX paths, Hydra arbitration, shared FIFO, and
South UART TX. All 128 generated packets reached the FPGA in the recorded run.

- Stable page:
  [2x2 Packet-Loss Probe](https://www.snr-lab.org/snrlab-chip-network-sim/scenarios/v3c-2x2-packet-loss-probe/)
- Published playback:
  [`live_event_2x2_packet_loss_probe.json`](../docs/playback/v3c_2x2_packet_loss_probe/live_event_2x2_packet_loss_probe.json)
- Required debug sidecar:
  [`chip0_rx_debug.csv`](../docs/playback/v3c_2x2_packet_loss_probe/chip0_rx_debug.csv)

The playback references the adjacent `chip0_rx_debug.csv`; both files must
remain together.

## v3c 3x3 Convergent Packet-Loss and Read-Contention Probe

Inject all 64 channels of chips 3, 5, and 7 simultaneously so three 64-packet
streams converge on chip 4. While chip 4 receives and forwards data traffic,
send four configuration-read requests to chip 7. All 192 data packets and all
four valid read replies reached the FPGA.

The routing overrides are:

| Chip | Upstream TX | Downstream TX |
|---:|---|---|
| 3 | North only | East only |
| 4 | North only | South only |
| 5 | North only | West only |
| 7 | South only | South only |

Configuration reads begin at ticks 1100, 1200, 1300, and 1400 for chip 7
registers 122 (`CHIP_ID`), 124 (`ENABLE_PISO_UP`), 125
(`ENABLE_PISO_DOWN`), and 64 (`GLOBAL_THRESH`).

- Stable page:
  [3x3 Convergent Traffic and Read Contention](https://www.snr-lab.org/snrlab-chip-network-sim/scenarios/v3c-3x3-convergent-packet-loss-read-contention/)
- Published playback:
  [`live_event_3x3_convergent_packet_loss_probe.json`](../docs/playback/v3c_3x3_convergent_packet_loss_read_contention/live_event_3x3_convergent_packet_loss_probe.json)
- Required chip-4 debug sidecar:
  [`chip4_rx_debug.csv`](../docs/playback/v3c_3x3_convergent_packet_loss_read_contention/chip4_rx_debug.csv)
- Required chip-0 debug sidecar:
  [`chip0_rx_debug.csv`](../docs/playback/v3c_3x3_convergent_packet_loss_read_contention/chip0_rx_debug.csv)

The playback references both adjacent debug CSV files; all three files must
remain together.

## v3c 10x10 Unconfigured-Network Startup

Instantiate 100 v3c chips without register preconfiguration and exercise the
complete network bootstrap process. The accepted schedule contains 445
configuration writes and no reads. Writes are spaced 75 ticks start-to-start.
The temporary ID 254 assigned to chip `(1,0)` was successfully remapped to ID
1 at tick 33457, and every scheduled write had a matching destination trace.

- Stable page:
  [10x10 Unconfigured-Network Startup](https://www.snr-lab.org/snrlab-chip-network-sim/scenarios/v3c-10x10-unconfigured-network-startup/)
- Published playback:
  [`live_bootstrap_10x10.json`](../docs/playback/v3c_10x10_unconfigured_network_startup/live_bootstrap_10x10.json)

The playback has no required chip-debug sidecar.

## v3c 15x15 Two-Track Charge Deposition

Exercise event generation and convergent packet transport in a preconfigured
15x15 v3c network. Two staggered tracks inject channels 0 through 15 on 13
chips, with consecutive chips separated by 500 ticks. All 208 generated
packets reached the FPGA exactly once; the final packet arrived at tick 16252.

The first track uses chip IDs 48, 64, 80, 96, 112, 113, 129, and 145. The
second track uses chip IDs 183, 184, 169, 155, and 141.

- Stable page:
  [15x15 Two-Track Charge Deposition](https://www.snr-lab.org/snrlab-chip-network-sim/scenarios/v3c-15x15-two-track-charge-deposition/)
- Published playback:
  [`live_event_15x15_staggered_multichip.json`](../docs/playback/v3c_15x15_two_track_charge_deposition/live_event_15x15_staggered_multichip.json)
- Selected-chip FIFO occupancy plot:
  [`selected_chip_fifo_occupancy_ticks_1000_18000.png`](../docs/playback/v3c_15x15_two_track_charge_deposition/selected_chip_fifo_occupancy_ticks_1000_18000.png)

The playback has no required chip-debug sidecar.
