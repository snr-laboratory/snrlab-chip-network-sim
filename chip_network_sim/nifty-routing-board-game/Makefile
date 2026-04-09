CLANG   ?= clang
TARGET  ?= wasm32
WASM     = main.wasm
INC      = game.h
SRC      = app_wasm.c game.c
RL_CC   ?= clang-mp-19
RL_CFLAGS ?= -std=c11 -O2
RL_DEMO  = rl_demo
RL_SRC   = rl_demo.c game.c

all: $(WASM)

$(WASM): $(SRC) $(INC) Makefile
	$(CLANG) --target=$(TARGET) -O3 -nostdlib -ffreestanding -fno-builtin \
	  -fuse-ld=lld \
	  -Wl,--no-entry \
	  -Wl,--export=init -Wl,--export=frame -Wl,--export=set_viewport \
	  -Wl,--export=set_game_config \
	  -Wl,--export=set_routing_pattern \
	  -Wl,--export=on_pointer -Wl,--export=on_key \
	  -Wl,--export-memory \
	  -Wl,--initial-memory=2097152 -Wl,--max-memory=16777216 \
	  -Wl,--export-table \
	  -Wl,--allow-undefined \
	  -o $(WASM) $(SRC)

.PHONY: clean
clean:
	rm -f $(WASM) $(RL_DEMO)

$(RL_DEMO): $(RL_SRC) $(INC) Makefile
	$(RL_CC) $(RL_CFLAGS) -o $(RL_DEMO) $(RL_SRC)
