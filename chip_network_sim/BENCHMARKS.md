# Benchmarks

## 3x4 RTL Snake Benchmark (Sync Mode Comparison)
Date: 2026-02-26
Topology/config: `config/network_3x4_snake_to_top_left.json`
Backend: `build/chip_rtl` (Verilated RTL FIFO)
Workload: `300,000` ticks (10x longer than prior 30,000-tick run), identical routing and per-chip `gen_ppm`.

### Results
| Sync mode                       | Tick loop sec | Cycles/sec | Tick send sec | Tick wait sec | Wait % | Ack barriers | Local generated |  Drops | FIFO peak |
|---------------------------------|--------------:|-----------:|--------------:|--------------:|-------:|-------------:|----------------:|-------:|----------:|
| `barrier_ack`                   |     73.880528 |   4060.610 |     46.585271 |     27.262118 | 36.90% |       300000 |          429648 | 128494 |        32 |
| `windowed_ack` (`ack_window=8`) |     43.610595 |   6879.062 |     25.818285 |     17.771133 | 40.75% |        37500 |          429648 | 127773 |        32 |
| `pubsub_only`                   |     24.831436 |  12081.460 |     24.814768 |      0.000000 |  0.00% |            0 |          288836 |  84191 |        32 |

### Derived comparisons
- `windowed_ack` vs `barrier_ack`: `+69.4%` cycles/sec.
- `pubsub_only` vs `barrier_ack`: `+197.5%` cycles/sec.
- `pubsub_only` vs `windowed_ack`: `+75.6%` cycles/sec.

### Findings
1. Global per-tick barrier synchronization is the main throughput limiter for deterministic lockstep.
2. Windowed barriers preserve most synchronization guarantees while significantly reducing orchestration cost.
3. `pubsub_only` is fastest, but it is not behaviorally equivalent: fewer ticks are effectively processed by chips (`local generated` drops from `429,648` to `288,836`), so it trades correctness/fidelity for speed.
4. FIFO saturation remains high across modes (`fifo_peak=32` in all runs), indicating workload pressure is sufficient to exercise drop behavior.

### Notes
- `cycles/sec` is measured inside orchestrator as `ticks / tick_loop_sec`.
- External timing (`/usr/bin/time`) was also captured per run and was consistent with internal instrumentation.

## Reproduce
1. Build binaries:
```bash
cmake -S . -B build
cmake --build build -j
```

2. Generate 300k-tick benchmark configs from the base `3x4` snake config:
```bash
python3 - <<'PY'
import json
from pathlib import Path

src = Path("config/network_3x4_snake_to_top_left.json")
base = json.loads(src.read_text())
base["runtime"]["ticks"] = 300000
base["runtime"]["chip_bin"] = "./build/chip_rtl"

targets = [
    ("barrier_ack", 4, Path("/tmp/network_3x4_bench10x_barrier_ack.json")),
    ("windowed_ack", 8, Path("/tmp/network_3x4_bench10x_windowed_ack.json")),
    ("pubsub_only", 4, Path("/tmp/network_3x4_bench10x_pubsub_only.json")),
]

for mode, win, dst in targets:
    cfg = json.loads(json.dumps(base))
    cfg["runtime"]["sync_mode"] = mode
    cfg["runtime"]["ack_window"] = win
    dst.write_text(json.dumps(cfg, indent=2) + "\n")
    print(dst)
PY
```

3. Run the three benchmark modes:
```bash
/usr/bin/time -f "ELAPSED_SEC=%e USER_SEC=%U SYS_SEC=%S CPU_PCT=%P MAXRSS_KB=%M" \
  python3 scripts/run_from_config.py -cfg /tmp/network_3x4_bench10x_barrier_ack.json

/usr/bin/time -f "ELAPSED_SEC=%e USER_SEC=%U SYS_SEC=%S CPU_PCT=%P MAXRSS_KB=%M" \
  python3 scripts/run_from_config.py -cfg /tmp/network_3x4_bench10x_windowed_ack.json

/usr/bin/time -f "ELAPSED_SEC=%e USER_SEC=%U SYS_SEC=%S CPU_PCT=%P MAXRSS_KB=%M" \
  python3 scripts/run_from_config.py -cfg /tmp/network_3x4_bench10x_pubsub_only.json
```
