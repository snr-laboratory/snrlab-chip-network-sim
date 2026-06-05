# Architecture PDF Profile

This repository uses a dedicated Pandoc defaults profile for print-quality architecture PDFs:

- Defaults file: `doc/pandoc-pdf.yaml`
- Source document: `doc/architecture.md`
- Output artifact: `doc/build/architecture.pdf`

## Build Commands
From `doc/`:

```bash
make pdf
```

Direct invocation:

```bash
pandoc --defaults pandoc-pdf.yaml architecture.md -o build/architecture.pdf
```

## Prerequisites
- `pandoc` must be installed.
- A PDF engine must be available; this profile uses `xelatex`.
- On Debian/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y texlive-xetex
```

## Profile Goals
- Printable `letter` page setup with readable margins.
- Numbered sections and deep table of contents.
- Consistent syntax highlighting.
- Clickable links in the PDF.
