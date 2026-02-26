# Benchmarks

## Post-migration Benchmarks (Reliable Inter-chip Data)
Date: 2026-02-26

These results were collected after inter-chip data moved to reliable per-link `REQ/REP` (`DATA_PULL`/`DATA_REPLY`).

| Topology | Backend | Ticks | Tick loop sec | Cycles/sec | Tick send sec | Tick wait sec | Wait % | Ack barriers |
|---------:|:-------:|------:|--------------:|-----------:|--------------:|--------------:|-------:|-------------:|
| `2x2` custom routes | `build/chip_rtl` | 5000 | 0.932326 | 5362.934 | 0.160052 | 0.771901 | 82.79% | 5000 |
| `2x2` custom routes | `build/chip` | 5000 | 0.786081 | 6360.670 | 0.160453 | 0.625263 | 79.54% | 5000 |
| `3x4` snake to top-left | `build/chip_rtl` | 10000 | 3.335390 | 2998.150 | 1.232961 | 2.101491 | 63.01% | 10000 |
| `3x4` snake to top-left | `build/chip` | 10000 | 3.281213 | 3047.654 | 1.234171 | 2.046102 | 62.36% | 10000 |
| `3x4` snake to top-left | `build/chip_rtl` | 300000 | 84.342902 | 3556.909 | 37.857442 | 46.454093 | 55.08% | 300000 |

Notes:
- Long-run (`300k`) post-migration sustained throughput on `3x4` RTL is `3556.909` cycles/sec.
- `chip` and `chip_rtl` backends are close on `3x4` (`~1.7%` difference at 10k ticks).
- Wait time remains a major component (`55-63%` on `3x4`), showing synchronization/data-transaction overhead.

## Historical Baseline (Pre Reliable Data Migration)
Date: 2026-02-26
Topology/config: `config/network_3x4_snake_to_top_left.json`
Backend: `build/chip_rtl` (Verilated RTL FIFO)
Workload: `300,000` ticks, transactional control (`REQ/REP`) with old best-effort inter-chip `PUB/SUB` data path.

| Tick loop sec | Cycles/sec | Tick send sec | Tick wait sec | Wait % | Ack barriers | Local generated | Drops | FIFO peak |
|--------------:|-----------:|--------------:|--------------:|-------:|-------------:|----------------:|------:|----------:|
|     64.153528 |   4676.282 |     47.898604 |     16.223025 | 25.29% |       300000 |          429648 | 128303 |        32 |

## Reproduce (Current Reliable Data Path)
1. Build binaries:
```bash
cmake -S . -B build
cmake --build build -j
```

2. Run measured configs:
```bash
python3 scripts/run_from_config.py -cfg /tmp/bench_post_2x2_rtl_5000.json
python3 scripts/run_from_config.py -cfg /tmp/bench_post_2x2_sw_5000.json
python3 scripts/run_from_config.py -cfg /tmp/bench_post_3x4_rtl_10000.json
python3 scripts/run_from_config.py -cfg /tmp/bench_post_3x4_sw_10000.json
python3 scripts/run_from_config.py -cfg /tmp/bench_post_3x4_rtl_300k.json
```

3. Example config generation:
```bash
python3 - <<'PY'
import json
from pathlib import Path

def emit(src, dst, ticks, chip_bin):
    cfg = json.loads(Path(src).read_text())
    cfg["runtime"]["ticks"] = ticks
    cfg["runtime"]["chip_bin"] = chip_bin
    Path(dst).write_text(json.dumps(cfg, indent=2) + "\\n")
    print(dst)

emit("config/network_2x2_custom_routes.json", "/tmp/bench_post_2x2_rtl_5000.json", 5000, "./build/chip_rtl")
emit("config/network_2x2_custom_routes.json", "/tmp/bench_post_2x2_sw_5000.json", 5000, "./build/chip")
emit("config/network_3x4_snake_to_top_left.json", "/tmp/bench_post_3x4_rtl_10000.json", 10000, "./build/chip_rtl")
emit("config/network_3x4_snake_to_top_left.json", "/tmp/bench_post_3x4_sw_10000.json", 10000, "./build/chip")
emit("config/network_3x4_snake_to_top_left.json", "/tmp/bench_post_3x4_rtl_300k.json", 300000, "./build/chip_rtl")
PY
```
