#!/usr/bin/env bash
set -euo pipefail

# Pass criteria for gate_clk_tb.sv:
# 1. With both gates disabled initially, gated_pos must be 0 and gated_neg must be 1.
# 2. While disabled, the positive-edge gate must propagate zero rising edges.
# 3. While disabled, the negative-edge gate must propagate zero falling edges.
# 4. Enabling the positive-edge gate while CLK is low must allow the next rising edge through.
# 5. Disabling the positive-edge gate while CLK is high must let the current pulse finish but block future rising edges.
# 6. A short enable glitch on the positive-edge gate while CLK is high must not create a pulse.
# 7. Enabling the negative-edge gate while CLK is high must allow the next falling edge through.
# 8. Disabling the negative-edge gate while CLK is low must let the current low phase finish but block future falling edges.
# 9. A short enable glitch on the negative-edge gate while CLK is low must not create a falling edge.
# All checks above must pass. Any failed check triggers $fatal(1), so the test only prints PASS if every condition is met.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verilator_bin="${VERILATOR_BIN:-/home/lxusers/y/ymei/OpenICEDA/bin/verilator}"
build_dir="${BUILD_DIR:-$repo_root/build/verilated_gate_tb_clang}"
clang_bin="${CXX_BIN:-clang++}"
link_bin="${LINK_BIN:-$clang_bin}"

sv_sources=(
  "$repo_root/larpix_v3b/src/gate_posedge_clk.sv"
  "$repo_root/larpix_v3b/src/gate_negedge_clk.sv"
  "$repo_root/larpix_v3b/testbench/unit_tests/gate_clk_tb.sv"
)

echo "Using Verilator: $verilator_bin"
echo "Using C++ compiler: $clang_bin"
echo "Build directory: $build_dir"

if [[ ! -x "$verilator_bin" ]]; then
  echo "error: Verilator binary not found or not executable: $verilator_bin" >&2
  exit 1
fi

if ! command -v "$clang_bin" >/dev/null 2>&1; then
  echo "error: C++ compiler not found on PATH: $clang_bin" >&2
  exit 1
fi

mkdir -p "$build_dir"

# Generate the Verilator build files. The built-in --binary step may still try to
# use g++, so allow that phase to fail as long as the makefile is emitted.
set +e
"$verilator_bin" \
  --binary \
  --sv \
  --timing \
  -Wall \
  -Wno-fatal \
  -Mdir "$build_dir" \
  -CFLAGS "-std=c++20" \
  "${sv_sources[@]}" \
  --top-module gate_clk_tb
verilator_status=$?
set -e

if [[ ! -f "$build_dir/Vgate_clk_tb.mk" ]]; then
  echo "error: Verilator did not generate $build_dir/Vgate_clk_tb.mk" >&2
  exit ${verilator_status:-1}
fi

make -C "$build_dir" -f Vgate_clk_tb.mk CXX="$clang_bin" LINK="$link_bin"
"$build_dir/Vgate_clk_tb"
