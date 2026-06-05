#Simulation Framework for Chip Networks: Update

### Introduction

This work presents an update on a simulation framework designed for networks of readout chips. The framework is intended to model an m×n network of chips together with a source chip connected to an FPGA for data collection. The goal is to provide a scalable environment in which many chips can be simulated together while preserving detailed digital behavior at the chip level.

The framework is motivated by the need to study communication, routing, and buffering behavior in large chip networks without losing clock-level and bit-level detail. It is especially relevant for detector readout systems in which network behavior and chip implementation are tightly coupled.


### Program Description

The simulation program models the behavior of a two-dimensional network of readout chips, together with a source chip that interfaces with an FPGA for data collection. Each chip operates as an independent hardware simulation. Rather than treating the network as a single monolithic testbench, the framework distributes the simulation across separate processes, allowing the network to scale without linearly increasing runtime.

Communication between chip processes and the central orchestrator is handled through the nanomsg-next-generation (nng) messaging library. This communication mechanism allows chips to run on different CPUs and in different processes while remaining synchronized in simulation time. The orchestrator maintains a global clock and advances the network by exchanging clock-tick messages with the chip processes. In this sense, the system behaves as a distributed synchronous hardware simulator. The orchestrator provides the global timing reference, the chip processes behave as hardware modules, and the nng socket connections act as communication links between those modules.

At the chip level, the simulation begins from RTL. The RTL is compiled by Verilator into a C++ model, which is then repeatedly evaluated on each simulation clock tick. This allows the digital behavior of the chip to remain tied directly to the RTL description rather than being replaced by a more abstract behavioral model.

The framework is the same as the toy model presented on March 9th but with some expansion of sockets to accommodate 4 edge communication. 

### Socket Communication Architecture Update

The framework relies on explicit socket communication between the orchestrator and chip processes and between neighboring chips. The state information collector gathers simulation outputs for later analysis and visualization, while request/reply and push/pull socket patterns coordinate the movement of clock ticks, data requests, and state data.

This communication structure is central to the framework’s scalability. Because each chip is its own simulated unit, sockets provide a clean way to propagate timing, route messages, and collect data without forcing all logic into one simulation process. This is especially important for eventually studying detector-scale networks, where the number of chip instances becomes too large for a conventional monolithic RTL simulation approach.

The main framework update involved instantiating both input and output REQ/REP socket pairs for each of the four chip edges. Previously, chips only communicated with two chips which were explicitly defined as either upstream or downstream, meaning a chip only needed one input REQ/REP socket pair on the edge facing the upstream chip and one output REQ/REP socket pair on the edge facing the downstream chip. In this version, the edges which face upstream versus downstream chips/data paths are defined via the RTL and configuration registers within the chip, requiring each chip edge to have the ability to be both an input and output socket pair. 

### LArPix v3b Digital Core as a Test Case

As the first non-trivial test of this framework, the LArPix v3b digital core was used as the input RTL to the simulator. Only minimal changes were required to the overall framework. The primary modifications were:

additional mechanisms for collecting chip state information, and
additional nng sockets to enable communication between chip processes in all four directions.

This is significant because it shows that the framework is not tightly bound to a toy model or to one specific communication scheme. Instead, it can be extended to support a more realistic chip architecture with modest structural changes. The framework therefore becomes a useful intermediate environment between high-level routing studies and true hardware deployment, because routing choices must eventually be realized through the chip’s actual communication interfaces and packet behavior.


### 3×5 LArPix Network Case: Chip ID Assignment

A first network-level study was performed on a 3×5 LArPix array. In the startup configuration (defined in the RTL), all chips begin with:

chip_id = 1
all four RX lanes enabled
no TX lanes enabled.

From this initial state, a schedule of configuration write packets is generated and sent by the FPGA into the source chip. The configuration proceeds by cycling through a repeating pattern:

enable the downstream TX lane,
assign a chip ID,
enable the upstream TX lane.

This demonstrates how the framework can model the actual packet-driven configuration of a chip network rather than assuming that all chip settings are externally assigned in an idealized way. The configuration process itself becomes part of the simulation and can therefore be studied as a network behavior.


### 3×5 LArPix Network Case: Charge Injection

A second study on the same 3×5 array examines data generation from charge injection. In this case, the disable masks are removed from all channels in Chip 14, and natural triggering is enabled. A charge of −5×10
−15 is then injected into each of the 64 channels of that chip. The simulation then follows the resulting data packets as they are generated and begin to leave Chip 14. FIFO occupancy is monitored as part of the analysis.

This case shows how the framework can connect physical stimulus, channel-level activity, and network-level communication in one simulation environment. Rather than merely reporting that packets were produced, the simulation resolves the timing and buffering behavior through the actual digital architecture.

The charge injection into the channels occurs at simulation tick 9800. Within about eight ticks, all 64 channels have generated a data packet. Each of these packets first enters a local channel-level FIFO, causing the occupancy of each local FIFO to rise to one.

The RTL defines a round-robin arbiter that pulls data packets from the local FIFOs into the chip FIFO. The transfer begins from Channel 0. As packets are removed from their local FIFOs, local occupancy returns to zero while chip FIFO occupancy increases. This process repeats such that, on each clock tick, one packet is removed from a local FIFO and placed into the chip FIFO, and the chip FIFO occupancy rises by one on each clock tick.

This is a useful example of the kind of information the framework can reveal. The simulation does not only show that data is present; it reveals how arbitration and queueing operate cycle by cycle, making it possible to analyze the detailed timing of packet movement through the digital design.

#### FIFO Dequeuing into the Hydra TX Path

Once packets have entered the chip FIFO, they do not leave continuously every clock tick. Instead, the simulation shows that one packet exits the chip FIFO every 69 ticks and enters the Hydra TX data path and then the selected UART transmitter. The plotted quantity is the tick on which the packet exits the FIFO, not the tick on which it leaves the chip entirely.

This interval is rooted in the structure of the transmitted packet and the transmit path timing. Each data packet is 64 bits, and it is sent serially with the addition of one start bit and one stop bit, and roughly three additional ticks for the Hydra TX logic to:

change state from IDLE to TX_GET_FIFO,
perform the FIFO read, and
load the packet into the UART TX block.

Together, these effects account for the 69-tick interval between successive dequeues from the chip FIFO. This illustrates how the framework can connect FIFO behavior, control-state transitions, and serialized transmission timing into a single analysis.

### 15×15 LArPix Network Case

This larger case supports one of the main claims of the framework: it can scale to arrays far larger than those that are convenient to simulate in a traditional RTL testbench while still preserving bit- and clock-level digital behavior.

### Comparison to Existing Network Simulators

The framework was compared to two existing simulation tools: BookSim and FireSim. The purpose of the comparison is to clarify what design space this work addresses.

#### BookSim

BookSim is described as a cycle-accurate network simulator dedicated to studying network performance. It focuses on the movement of flow-control units (flits) rather than bits, and it is primarily concerned with information such as queueing, arbitration, bandwidth, latency, and congestion. In BookSim, the node is represented as an abstraction built from routers, buffers, and channels. It is therefore well suited to large-scale network studies with abstract node models.

#### FireSim

FireSim is described as a cycle-accurate FPGA-accelerated simulator for studying RTL-defined systems at scale. It focuses on system-level behavior, timing, and communication between simulated nodes. In this view, the link between nodes is modeled so that communication behavior is captured without bit-level information. FireSim is intended for cases where the simulated nodes are large RTL-defined computing blocks such as SoCs.

#### Position of the Present Framework

The present framework is designed for a different regime. The chip designs of interest are too large, and too inherently mixed-signal, to simulate as a large network within a conventional SystemVerilog testbench. At the same time, the individual chips are small enough that the simulation does not need to give up bit-level or clock-edge accuracy in order to study the network. The framework therefore fills a gap between abstract network simulators and large-node system simulators. It also opens the possibility of mixed-signal accuracy through Verilator-based co-simulation with charge input.

### Project Integration and Role in Design Studies

The framework is intended to support ongoing work on the optimization of topology and routing in chip networks. In this role, it acts as a bridge between high-level routing design studies and bit-level hardware behavior. In a LArPix-like system, routing or configuration designs may originate from broader network studies, but they must eventually be implemented through real packet transmissions and chip-level configuration behavior. This framework provides a way to validate those ideas closer to the hardware implementation stage and therefore move toward pre-fabrication verification.

In other words, the simulator is not only a tool for studying network behavior in the abstract. It is also a design-verification tool that can check whether routing concepts can actually be enacted through the chip’s digital architecture and communication paths.

### Next Steps

The framework already supports:

simulation network scaling,
RTL-accurate behavior,
integration with detector concepts, and
simple design parameter studies.

These applications highlight the combination of scalability and detailed digital fidelity that motivates the framework.

The next major directions identified are:

incorporation of SPICE simulation,
support for multiple neighboring chip routing, and
integration of existing RTL designs.

These directions aim to extend the framework further into mixed-signal simulation and more realistic chip-network studies.

#### SPICE/RTL Co-simulation

One of the backup slides presents SPICE/RTL co-simulation, indicating a path toward simulation in which an analog front end can be modeled alongside the RTL-defined digital architecture. This direction is especially important for detector readout systems, where analog charge response and digital packet generation are tightly connected. By combining SPICE with the existing Verilator-based flow, the framework could support simulations that begin with analog stimuli and continue through digital processing and network transmission.

This points toward a simulation chain that begins from charge input and ends with digital readout behavior. The accompanying plots suggest how analog input or front-end output could be visualized together with the block-level architecture of the chip unit.

This is a natural extension of the framework’s core purpose. It would allow the simulator to bridge not only chip-network design and digital routing studies, but also detector stimulus and full readout behavior.


