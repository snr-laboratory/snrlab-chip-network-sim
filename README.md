# RTLswarm: A massively parallelized chip simulator

This project aims to develop a deterministic, scalable simulation architecture for modeling the behavior of a network of ASIC chips. In this framework, each chip is represented as an independent software process in which the digital backend is specified entirely by RTL, while analog components in mixed-signal designs are simulated in software and coupled to the RTL-defined digital logic. A network can be composed of arbitrarily many chips which are coordinated by a central simulation orchestrator operating in a global lock-step where data is transmitted between chip processes via socket-based inter-process communication. The objective is to reproduce the essential routing, data flow, register configuration, data generation, arbitration, and timing behavior of a networked chip system while leveraging the independent nature of each chip process for scalability.

AI tools, particularly Codex, have played a central role in the development of this project, with the overall simulation architecture having been largely constructed with the assistance of AI. This included generating and organizing code across multiple languages (C++, Verilog, and Python), as well as structuring a nontrivial, multi-component codebase.

Explore the [verification scenario gallery](https://www.snr-lab.org/snrlab-chip-network-sim/scenarios/),
including the
[v3c 10x10 unconfigured-network startup playback](https://www.snr-lab.org/snrlab-chip-network-sim/scenarios/v3c-10x10-unconfigured-network-startup/)
and the
[v3c 15x15 two-track charge-deposition playback](https://www.snr-lab.org/snrlab-chip-network-sim/scenarios/v3c-15x15-two-track-charge-deposition/).

## Getting started

RTLswarm is distributed as a research framework rather than with a bundled RTL
design. Users provide their own compatible RTL tree and install the external
NNG and Verilator dependencies locally.

Start with the documentation index in
[`chip_network_sim/doc/`](chip_network_sim/doc/README.md). It leads through:

1. installing the prerequisites and preparing RTL for Verilator;
2. integrating an RTL tree with the simulator build;
3. launching and validating scenarios; and
4. viewing generated playback data.

The simulator sources and build definition are under
[`chip_network_sim/`](chip_network_sim/README.md).
