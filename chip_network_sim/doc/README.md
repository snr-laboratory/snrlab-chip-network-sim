# Documentation Guide

This directory contains architecture and API documentation inputs and build configs.

## Main Documents
- `architecture.md`: system architecture, message model, sync/tick behavior, and backend design.
- `packet_trace_plan.md`: packet-level tracing design (binary schema, event model, reconstruction flow).
- `../scripts/reconstruct_trace.py`: offline parser/reconstructor for `tracebin` runs.
- `../BENCHMARKS.md`: benchmark results and reproduction commands.
- `Doxyfile`: Doxygen configuration for code-level API docs.

## Build Outputs
- `build/architecture.html`: rendered architecture document (Pandoc + Mermaid).
- `build/doxygen/html/index.html`: Doxygen site entry point.

## Build Commands
- `make html`: generate `build/architecture.html`.
- `make doxygen`: generate API docs under `build/doxygen/html`.
- `make pdf`: generate `build/architecture.pdf` (requires `xelatex`).
- `make clean`: remove generated docs under `build/`.

## Tooling Notes
- Mermaid diagrams are loaded via `mermaid-header.html` and rendered from fenced `mermaid` blocks in `architecture.md`.
- `Makefile` tracks `pandoc.yaml`, `pandoc.css`, and `mermaid-header.html` as HTML build dependencies to avoid stale output.
