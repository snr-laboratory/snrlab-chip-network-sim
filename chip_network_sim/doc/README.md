# Documentation Guide

This directory contains top-level documentation for the public-facing LArPix simulator.

## Main Documents
- `architecture.md`: top-level architecture and runtime model for the LArPix simulator.
- `../larpix_network_sim/config/WORKFLOW.md`: practical run workflow and artifact layout.
- `../larpix_network_sim/config/CONFIGURATION_TESTS.md`: startup/configuration test flows.
- `Doxyfile`: API documentation configuration.

## Build Outputs
- `build/architecture.html`
- `build/doxygen/html/index.html`

## Build Commands
- `make html`
- `make doxygen`
- `make pdf`
- `make clean`

## Notes
- The retired legacy packet/FIFO simulator is intentionally no longer documented here.
- Mermaid diagrams are loaded via `mermaid-header.html`.
