PANDOC      ?= pandoc
PDF_ENGINE  ?= xelatex
OUTDIR      ?= build
DOXYGEN     ?= doxygen
PDF_DEFAULTS ?= pandoc-pdf.yaml

SRCS       := architecture.md
HTML       := $(SRCS:%.md=$(OUTDIR)/%.html)
PDF        := $(SRCS:%.md=$(OUTDIR)/%.pdf)

.PHONY: all html pdf doxygen clean

all: html

html: $(HTML)

pdf: $(PDF)

doxygen:
	@command -v $(DOXYGEN) >/dev/null 2>&1 || (echo "Missing doxygen. Install system package 'doxygen' first."; exit 1)
	@mkdir -p $(OUTDIR)/doxygen
	cd .. && $(DOXYGEN) doc/Doxyfile

$(OUTDIR):
	mkdir -p $(OUTDIR)

$(OUTDIR)/%.html: %.md pandoc.yaml pandoc.css mermaid-header.html | $(OUTDIR)
	$(PANDOC) --defaults pandoc.yaml $< -o $@

$(OUTDIR)/%.pdf: %.md $(PDF_DEFAULTS) | $(OUTDIR)
	$(PANDOC) --defaults $(PDF_DEFAULTS) --pdf-engine=$(PDF_ENGINE) $< -o $@

clean:
	rm -rf $(OUTDIR)
