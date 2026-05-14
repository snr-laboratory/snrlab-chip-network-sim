This live-network simulation was for a 3x5 network of LArPix chips where Chip 14 had its natural trigger mode enabled and an identical charge (sufficient to meet the CSA threshold) was injected into each of the 64 channel inputs. The following plots show the occupancy of both the channel-local FIFOs and the shared chip FIFO on Chip 14.  

## Occupancy Plots

#### Full occupancy plot:

![Full occupancy plot](./figures/chip14_occupancy.png)

#### Why Didn't The Chip FIFO Immediately Overrun?

After the charge-injection timing was corrected so that all configuration writes had completed before injection, all `64` channels on chip `14` did generate local data packets. The observed result was:

- all `64` channels locally generated packets
- all `64` channels were later observed at the FPGA
- the chip-level FIFO reached a peak occupancy of `63`

The peak is `63` instead of `64` because Hydra begins draining the shared chip FIFO while channel-local FIFOs are still feeding it. In the RTL, a simultaneous FIFO write and FIFO read leaves the shared FIFO occupancy counter unchanged, rather than increasing by one.

So the result is consistent with:

- `64` channels generating packets
- one packet already being dequeued by Hydra while the remaining `63` are still queued


#### Filling chip FIFO:

![Zoomed occupancy plot](./figures/chip14_occupancy_zoom.png)

The charge injection into the channels occurs at tick=9800. By about 8 ticks later, all 64 channels have generated a data packet which has entered the local (channel-level) FIFO, setting its occupany to one. The RTL defines a round-robin arbiter for pulling data packets from the local FIFO into the chip FIFO. The process begins from Channel 0 where you see the local FIFO occupancy go back down to zero and the chip FIFO occupancy increase by one. This process repeats, during which on each clock tick a packet is removed from a local FIFO and placed in the chip FIFO, with the occupancy of the chip FIFO increasing by one on each clock tick. 


#### Why Is There A Brief Flat Region Around Tick 9813?

The short plateau near tick `9813` is also explained by overlapping shared-FIFO enqueue and dequeue activity.

Around that region:

- active channel-local FIFO count continues to fall by one packet per tick
- chip FIFO occupancy goes `3 -> 3 -> 4`

That means channel packets are still leaving local FIFOs, but on tick `9813` Hydra also dequeues a packet from the chip FIFO in the same cycle. The net chip FIFO occupancy therefore stays constant for one tick.

This is a real RTL timing effect, not a plotting artifact.

#### Chip FIFO emptying (ticks 1350 to 14300):

![Mid-range occupancy plot](./figures/chip14_occupancy_zoom_mid.png)

Every 69 ticks, a packet exits the chip FIFO and enters the Hydra TX data path and then into the selected UART transmitter. This plot shows on what tick the packet exits the FIFO (which is not the tick on which it exits the chip). It takes about 69 ticks to pull the following data packet out of the chip FIFO for data transmission because the packets are transmitted serially. They also have 1 start bit (0) and 1 stop bit (1). Additionally, it takes about 3 ticks for te Hydra to (1) change its state from `IDLE` to `TX_GET_FIFO` (2) perform the FIFO read (3) load the packet into the UART TX block. This accounts for the 69 ticks between dequeuing of the chip FIFO. 

