.PHONY: all sim ver ver_fallback lint

DUT       := sipo_msb_gate
TOP       := sipo_msb_gate_tb
OBJ_DIR   := obj_dir
VTOP_BIN  := $(OBJ_DIR)/V$(TOP)
VERI_FLAGS:= --sv --assert --trace -Wall --top-module $(TOP)

all: sim ver

sim: $(TOP).v $(DUT).v
	iverilog -g2005 -o sim $^
	vvp sim

# Verilator build with fallback manual link if archive/link step fails
ver: $(TOP).v $(DUT).v
	@set -e; \
	verilator $(VERI_FLAGS) $^ --binary || { \
	  echo "[Make] Verilator --binary failed; attempting manual link fallback"; \
	  $(MAKE) ver_fallback; \
	}; \
	$(VTOP_BIN)

# Manual link fallback: link generated objects directly if the Verilator archive step fails
ver_fallback:
	@set -e; \
	if [ ! -f $(OBJ_DIR)/V$(TOP)__ALL.o ]; then \
	  echo "[Make] Missing $(OBJ_DIR)/V$(TOP)__ALL.o; cannot fallback"; exit 2; \
	fi; \
	g++ -o $(VTOP_BIN) \
	  $(OBJ_DIR)/verilated.o \
	  $(OBJ_DIR)/verilated_vcd_c.o \
	  $(OBJ_DIR)/verilated_timing.o \
	  $(OBJ_DIR)/verilated_threads.o \
	  $(OBJ_DIR)/V$(TOP)__ALL.o \
	  -std=gnu++20 -pthread -lpthread

lint: $(TOP).v $(DUT).v
	verilator $(VERI_FLAGS) --timing --lint-only $^
