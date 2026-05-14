#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-$ROOT_DIR/config/network_3x5_determinism_snake_br_to_tl.json}"
RUNS="${RUNS:-15}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"

if [[ ! -f "$CONFIG" ]]; then
  echo "error: config file not found: $CONFIG" >&2
  exit 1
fi

if [[ ! -x "$ROOT_DIR/build/orchestrator" ]]; then
  echo "error: missing executable: $ROOT_DIR/build/orchestrator" >&2
  echo "build first: cmake -S . -B build && cmake --build build -j" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="$ROOT_DIR/reports/determinism_3x5/$STAMP"
LOG_DIR="$OUT_DIR/logs"
mkdir -p "$LOG_DIR"

RESULTS_TSV="$OUT_DIR/results.tsv"
REPORT_MD="$OUT_DIR/determinism_report.md"

printf "run\tdelivered_tx\ttotal_drops\tcycles_per_sec\tper_chip_drops\ttrace_run_dir\n" > "$RESULTS_TSV"

echo "running determinism test: runs=$RUNS"
echo "config=$CONFIG"
echo "output_dir=$OUT_DIR"

for i in $(seq 1 "$RUNS"); do
  ATTEMPT=1
  while true; do
    LOG_FILE="$LOG_DIR/run_${i}_attempt_${ATTEMPT}.log"
    echo "[$i/$RUNS] launching simulation (attempt $ATTEMPT/$MAX_ATTEMPTS)..."
    RUN_OK=1
    if ! (
      cd "$ROOT_DIR"
      python3 scripts/run_from_config.py -cfg "$CONFIG"
    ) >"$LOG_FILE" 2>&1; then
      RUN_OK=0
    fi

    METRICS_LINE="$(grep -E "^metrics: " "$LOG_FILE" | tail -n 1 || true)"
    BENCH_LINE="$(grep -E "^benchmark: ticks=.*cycles_per_sec=" "$LOG_FILE" | tail -n 1 || true)"
    TRACE_LINE="$(grep -E "^orchestrator: trace_run_id=.* trace_dir=" "$LOG_FILE" | tail -n 1 || true)"

    if [[ "$RUN_OK" -eq 0 || -z "$METRICS_LINE" || -z "$BENCH_LINE" || -z "$TRACE_LINE" ]]; then
      if [[ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]]; then
        echo "error: run $i failed after $MAX_ATTEMPTS attempts" >&2
        echo "see log: $LOG_FILE" >&2
        exit 1
      fi
      ATTEMPT=$((ATTEMPT + 1))
      continue
    fi

    TX="$(sed -E 's/.*tx=([0-9]+).*/\1/' <<<"$METRICS_LINE")"
    TOTAL_DROPS="$(sed -E 's/.*drops=([0-9]+).*/\1/' <<<"$METRICS_LINE")"
    CYCLES_PER_SEC="$(sed -E 's/.*cycles_per_sec=([0-9.]+).*/\1/' <<<"$BENCH_LINE")"
    TRACE_RUN_DIR="$(sed -E 's/.*trace_dir=([^ ]+).*/\1/' <<<"$TRACE_LINE")"

    mapfile -t DROP_PARSE < <(
    python3 - "$TRACE_RUN_DIR" <<'PY'
import json
import struct
import sys
from pathlib import Path

ROW_STRUCT = struct.Struct("<QHHIQ")
HEADER_SIZE = 64
ROW_SIZE = 24
DROP_EVENTS = {3, 5}

run_dir = Path(sys.argv[1])
manifest_path = run_dir / "manifest.json"
if not manifest_path.exists():
    raise SystemExit(f"missing manifest: {manifest_path}")

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
chips = sorted(manifest.get("chips", []), key=lambda c: int(c["id"]))

parts = []
drop_sum = 0

for chip in chips:
    chip_id = int(chip["id"])
    trace_path = run_dir / str(chip["file"])
    data = trace_path.read_bytes()
    payload = data[HEADER_SIZE:]
    if len(payload) % ROW_SIZE != 0:
        raise SystemExit(f"corrupt trace rows in {trace_path}")

    chip_drop = 0
    for off in range(0, len(payload), ROW_SIZE):
        _tick, ev, _reserved0, _occ, _packet_word = ROW_STRUCT.unpack_from(payload, off)
        if ev in DROP_EVENTS:
            chip_drop += 1

    parts.append(f"{chip_id}:{chip_drop}")
    drop_sum += chip_drop

print(",".join(parts))
print(drop_sum)
PY
    )

    PER_CHIP_DROPS="${DROP_PARSE[0]}"
    TRACE_DROP_SUM="${DROP_PARSE[1]}"
    if [[ "$TRACE_DROP_SUM" != "$TOTAL_DROPS" ]]; then
      if [[ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]]; then
        echo "error: run $i drops mismatch after $MAX_ATTEMPTS attempts: metrics=$TOTAL_DROPS trace=$TRACE_DROP_SUM" >&2
        echo "see log: $LOG_FILE" >&2
        exit 1
      fi
      ATTEMPT=$((ATTEMPT + 1))
      continue
    fi

    printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
      "$i" "$TX" "$TOTAL_DROPS" "$CYCLES_PER_SEC" "$PER_CHIP_DROPS" "$TRACE_RUN_DIR" >> "$RESULTS_TSV"
    break
  done
done

python3 - "$RESULTS_TSV" "$REPORT_MD" "$RUNS" "$CONFIG" <<'PY'
import csv
import sys
from pathlib import Path

results_tsv = Path(sys.argv[1])
report_md = Path(sys.argv[2])
expected_runs = int(sys.argv[3])
config_path = sys.argv[4]

rows = []
with results_tsv.open("r", encoding="utf-8") as f:
    reader = csv.DictReader(f, delimiter="\t")
    rows = list(reader)

if len(rows) != expected_runs:
    raise SystemExit(f"expected {expected_runs} rows, found {len(rows)}")

base = rows[0]
base_behavior = (base["delivered_tx"], base["total_drops"], base["per_chip_drops"])
base_full = (base["delivered_tx"], base["total_drops"], base["per_chip_drops"], base["cycles_per_sec"])

behavior_identical = True
full_identical = True

for r in rows:
    current_behavior = (r["delivered_tx"], r["total_drops"], r["per_chip_drops"])
    current_full = (r["delivered_tx"], r["total_drops"], r["per_chip_drops"], r["cycles_per_sec"])
    if current_behavior != base_behavior:
        behavior_identical = False
    if current_full != base_full:
        full_identical = False

lines = []
lines.append("# Determinism Test Report (3x5 Snake BR->TL)")
lines.append("")
lines.append(f"- Config: `{config_path}`")
lines.append(f"- Runs: {expected_runs}")
lines.append(f"- Deterministic behavior check (`delivered_tx + total_drops + per_chip_drops`): **{'PASS' if behavior_identical else 'FAIL'}**")
lines.append(f"- Full output check (including `cycles_per_sec`): **{'PASS' if full_identical else 'FAIL'}**")
lines.append("")
lines.append("## Per-run Results")
lines.append("")
lines.append("| Run | Delivered Packets (tx) | Total Drops | Cycles/sec | Per-chip Drops (chip_id:count) | Behavior Match vs Run1 | Full Match vs Run1 |")
lines.append("| --- | ---: | ---: | ---: | --- | --- | --- |")

for r in rows:
    behavior_match = "yes" if (r["delivered_tx"], r["total_drops"], r["per_chip_drops"]) == base_behavior else "no"
    full_match = "yes" if (r["delivered_tx"], r["total_drops"], r["per_chip_drops"], r["cycles_per_sec"]) == base_full else "no"
    lines.append(
        "| {run} | {tx} | {drops} | {cps} | `{per_chip}` | {bmatch} | {fmatch} |".format(
            run=r["run"],
            tx=r["delivered_tx"],
            drops=r["total_drops"],
            cps=r["cycles_per_sec"],
            per_chip=r["per_chip_drops"],
            bmatch=behavior_match,
            fmatch=full_match,
        )
    )

report_md.parent.mkdir(parents=True, exist_ok=True)
report_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(report_md)
PY

echo "done"
echo "results_tsv=$RESULTS_TSV"
echo "report=$REPORT_MD"
