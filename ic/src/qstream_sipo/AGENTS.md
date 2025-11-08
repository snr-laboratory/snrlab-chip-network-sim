# AGENTS.md — MSB-Gated SIPO with Timestamp (Event-Driven Holdoff)

## 1) Scope and intent

This document encodes design intent, invariants, and build/verification steps for the module and testbench in this repository.  It is written so autonomous agents can modify, lint, test, and extend the code without losing behavioral guarantees.

Artifacts referenced: `sipo_msb_gate.v`, `sipo_msb_gate_tb.v`.

## 2) External contract

**Module:** `sipo_msb_gate`

**Parameters**

- `WORD_W` (int, default 16): data word width in bits.  Must be ≥ 2.
- `TS_W` (int, default 64): timestamp counter width in bits.

**Ports**

- `CLK` (in): rising-edge clock.
- `RST` (in): active-high synchronous reset.
- `DIN` (in): serial input bit, sampled each `CLK`.
- `DOUT[WORD_W-1:0]` (out): latched parallel word.
- `TS[TS_W-1:0]` (out): timestamp captured with `DOUT`.
- `VALID` (out): one-cycle strobe when `DOUT` and `TS` update.

**Bit ordering** LSB-first shifting.  `DIN` enters bit 0 and shifts toward MSB each cycle.  The post-shift MSB is the decision bit.

## 3) Behavior specification

**Event-driven latch with holdoff (non-overlapping).**  There is no fixed windowing.  The design always shifts and increments the timestamp, and evaluates the post-shift MSB each cycle.  When allowed (no holdoff active) and `MSB(sh_next)==1`, the module latches `DOUT←sh_next`, `TS←ctr_next`, and asserts `VALID` for one cycle.  After any `VALID`, a post-capture holdoff of exactly `WORD_W-1` cycles is imposed to prevent recapturing from the same mid-word `1`.  When holdoff expires, evaluation is again enabled on every cycle until the next `MSB(sh_next)==1` event.

**Timestamp.**  `TS` is a free-running counter incremented every `CLK`.  On latch, `TS` captures the cycle index associated with the decision (post-increment, aligned with `sh_next`).

**Throughput upper bound.**  Maximum emission rate equals one word per `WORD_W` clocks due to holdoff.

```
\text{throughput}_{\max} = \frac{1}{\text{WORD\_W}}\ \text{words per clock}.
```

**Reset semantics.**  Synchronous.  On `RST=1`, shift register, outputs, counter, and holdoff are cleared.  After reset deasserts, the first capture occurs on the first cycle where `MSB(sh_next)==1` (i.e., when a fresh `1` reaches the MSB).  There is no fixed boundary after reset.

## 4) Non-requirements and limits

- This is **not** an information-theoretic compressor.  It is a rate-reduction gate that suppresses windows with `MSB=0`.  Without additional framing and metadata, the original bitstream is not uniquely recoverable.
- No backpressure or `READY` handshaking.  `VALID` is a pulse only.  Downstream must sample on `VALID`=1 or add buffering.

## 5) Micro-architecture

- **Shift register** `sh[WORD_W-1:0]` receives `DIN` into bit 0 each `CLK`.
- **Holdoff counter** `holdoff` suppresses new captures for `WORD_W-1` cycles after `VALID`.  When `holdoff==0`, captures are allowed on any cycle.
- **Free-running counter** `ctr[TS_W-1:0]` increments each `CLK` and is captured as `TS` on latch.
- **Outputs** `DOUT/TS/VALID` update only when a capture occurs (`MSB(sh_next)==1` and `holdoff==0`).

## 6) Verification and properties

**Testbench strategy.**  `sipo_msb_gate_tb.v` provides:

- Mixed deterministic and pseudo-random stimulus.  No sampling gaps.  One bit per `CLK`.
- Expected firing condition computed each cycle as `(holdoff_g==0) && MSB(sh_next)`; checks occur after a small `#1` delta to observe nonblocking updates.
- For non-SV simulators: portable checks remain under `ifndef SYNTHESIS` inside the RTL.

**SVA policy.**

- Under Verilator (`VERILATOR` defined), SVA are enabled in both RTL and TB.  RTL assertions compare **current outputs** to **previous-cycle expected** registers to avoid race conditions with NBA.
- Under Icarus Verilog, SVA are not compiled.  `$error`/`$display` checks remain active under `ifndef SYNTHESIS`.

**Key invariants expressed to agents**

- `VALID` may assert only when `holdoff==0` and `MSB(sh_next)==1`.
- When `VALID==1`, `DOUT==sh_next` and `TS==ctr_next` for that cycle.
- After any `VALID`, the next possible `VALID` is at least `WORD_W` clocks later (holdoff enforcement).  In a run of `1`s, emissions occur every `WORD_W` clocks.

## 7) Toolchain matrix and build recipes

**Defines and guards**

- `VERILATOR`: automatically defined by Verilator.  Enables SVA and uses `$error` instead of `$display/$stop` in checks.
- `SYNTHESIS`: assumed defined by synthesis.  Excludes all debug checks.
- `NO_DUMP`: if defined, disables waveform dump init blocks in TB.

**Verilator (preferred for SVA)**

- Compile: `verilator --sv --assert --trace -Wall --top-module sipo_msb_gate_tb sipo_msb_gate_tb.v sipo_msb_gate.v --binary`
- Run: `./obj_dir/Vsipo_msb_gate_tb`
- Waves: `--trace` creates VCD.  Use `--trace-fst` and change `$dumpfile` to `.fst` if desired.

**Icarus Verilog**

- Compile: `iverilog -g2005 -o sim sipo_msb_gate_tb.v sipo_msb_gate.v`
- Run: `vvp sim`
- Waves: VCD emitted by default unless `NO_DUMP` is defined.

**Lint policy**

- Use of `/* verilator lint_off/on ... */` is limited and justified.  Currently only `UNUSEDSIGNAL` on internal shift mirrors and `WIDTHTRUNC` on `$random` in TB when used as a single bit.

## 8) Logging and waveform dumping

The TB writes VCD under Icarus and FST or VCD under Verilator, guarded by `ifndef NO_DUMP`.  Scope is the entire TB top for quick navigation.

## 9) Edge cases covered

- Long runs of `1`s: emits every `WORD_W` clocks due to holdoff.  No overlap.
- Long runs of `0`s: no emissions.  Counter and holdoff continue.  No missed events.
- After reset: first capture occurs when a fresh `1` reaches MSB; no fixed boundary.

## 10) Extension roadmap (agents may implement)

- Add `READY` to create a `VALID/READY` handshake with optional skid buffer.
- Parameterize endianness and decision bit (choose MSB vs LSB, pre- vs post-shift).
- Emit a per-window diagnostic word containing zero-count or population count for richer zero-suppression.
- (Removed) `INIT_PHASE`.  First capture comes from data (fresh `1` to MSB), not a fixed boundary.
- Make timestamp capture selectable: pre- or post-increment, or external timebase input.
- Add optional synchronous clear for the timestamp counter separate from `RST`.
- Provide a formal verification harness (SymbiYosys) with assumptions on `CLK`/`RST` and assertions matching the invariants above.

## 11) How to direct agents (prompts and checks)

**Design Agent**

- If adding handshake: introduce `READY` input.  On `VALID&&READY`, accept the transfer and apply holdoff (`WORD_W-1`).  Provide `BUSY` only if buffering is added.  Ensure no sample loss.
- If changing decision bit: rename `msb_next` to `dec_next`.  Maintain the event-driven holdoff rule.

**Verification Agent**

- Maintain the TB’s expected fire condition `(holdoff_g==0) && MSB(sh_next)`.  When adding features, extend the scoreboard.
- For SVA, keep RTL comparisons against previous-cycle expected registers or use `|=>` appropriately.

**Lint/CI Agent**

- Enforce `-Wall` under Verilator and fail on new warnings unless explicitly suppressed with a comment justifying the suppression.
- Keep Icarus path free of SVA and vendor pragmas beyond benign `$dump*`.

**Docs Agent**

- Preserve Doxygen blocks.  Update parameter and port descriptions on any interface change.  Keep two-space sentence separation.

## 12) Session changelog (traceability)

- Initial SIPO with MSB gating and timestamp.  LSB-first shifting.  No `VALID`.
- Added explicit one-cycle `VALID` output.  Introduced parameter rename `N → WORD_W` for clarity.
- Switched to **event-driven** evaluation with post-capture holdoff (no fixed windows).  Implemented `holdoff` counter.
- Added doxygen headers, clarified external contract, and documented reset and timing.
- Introduced Verilator-only SVA under `ifdef VERILATOR`.  Adjusted to avoid NBA races by comparing against previous-cycle expected registers.
- Added portable runtime checks under `ifndef SYNTHESIS` using `$error` and `$display/$stop` for Verilator/Icarus.
- Integrated waveform dumping.  Added `NO_DUMP` guard.  Cleaned warnings: replaced initial nonblocking assigns in TB, handled `$random` width, and minimized lint suppressions.
- Fixed TB naming to `sipo_msb_gate_tb.v` and module `sipo_msb_gate_tb`.  Resolved mispaired `end` and delta-cycle ordering issues.

## 13) Acceptance criteria

- Builds and runs cleanly under Verilator with `--sv --assert --trace -Wall` with no errors and no unsuppressed warnings.  SVA must pass.
- Builds and runs under Icarus Verilog with `-g2005` with no errors.  TB must self-check and finish.
- Emission only when allowed and `MSB(sh_next)==1`.  Non-overlap enforced by holdoff.  Timestamp captured on the correct cycle.  Continuous ingestion of `DIN` without gaps.

---

This file is authoritative for agents acting on this repository.  Update it whenever behavior or interfaces change.  Keep the two-space sentence style to ease diffs and consistency.
