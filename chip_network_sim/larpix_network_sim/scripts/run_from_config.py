#!/usr/bin/env python3
"""Generate startup/stimulus inputs from one JSON config and optionally run the simulation."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from compile_startup_json import FRAME_BITS, check_overlaps, compile_frame, compile_readback_phase
from generate_bootstrap_chip_id_readback_json import Builder as BootstrapReadbackBuilder
from generate_bootstrap_startup_json import BootstrapStartupBuilder

CSA_ENABLE_BASE = 66
ENABLE_TRIG_MODES_REG = 128
CHANNEL_MASK_BASE = 131


def strip_json_line_comments(text: str) -> str:
    lines: list[str] = []
    for line in text.splitlines():
        if line.lstrip().startswith("//"):
            continue
        lines.append(line)
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")


def load_json_with_comments(path: Path) -> dict[str, Any]:
    return json.loads(strip_json_line_comments(path.read_text()))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def resolve_repo_path(repo_root: Path, value: str | Path) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return repo_root / path


def get_required(mapping: dict[str, Any], key: str) -> Any:
    if key not in mapping:
        raise ValueError(f"missing required field '{key}'")
    return mapping[key]


def runtime_to_chip_id_map(cfg: dict[str, Any]) -> dict[int, int]:
    out: dict[int, int] = {}
    raw = cfg.get("runtime_to_chip_id")
    if raw is None:
        return out
    if not isinstance(raw, dict):
        raise ValueError("startup.runtime_to_chip_id must be an object")
    for key, value in raw.items():
        out[int(key)] = int(value)
    return out


def generate_enable_injected_channel_frames(
    startup_cfg: dict[str, Any],
    stimulus_cfg: dict[str, Any] | None,
    tick_start: int,
    tick_step: int,
) -> list[dict[str, Any]]:
    if stimulus_cfg is None:
        raise ValueError("startup mode requires a stimulus.charges list")

    charges = stimulus_cfg.get("charges")
    if not isinstance(charges, list) or not charges:
        raise ValueError("stimulus.charges must be a non-empty list")

    chip_map = runtime_to_chip_id_map(startup_cfg)
    per_runtime: dict[int, set[int]] = {}
    for entry in charges:
        if not isinstance(entry, dict):
            raise ValueError("stimulus charge entries must be objects")
        runtime_id = int(get_required(entry, "runtime_id"))
        channel = int(get_required(entry, "channel"))
        if channel < 0 or channel >= 64:
            raise ValueError(f"stimulus channel out of range: {channel}")
        per_runtime.setdefault(runtime_id, set()).add(channel)

    frames: list[dict[str, Any]] = []
    tick = tick_start
    disable_trigger_veto = bool(startup_cfg.get("disable_trigger_veto", True))

    for runtime_id in sorted(per_runtime):
        chip_id = chip_map.get(runtime_id, runtime_id)
        csa_bytes = [0] * 8
        mask_bytes = [0xFF] * 8
        for channel in sorted(per_runtime[runtime_id]):
            byte_idx = channel // 8
            bit_idx = channel % 8
            csa_bytes[byte_idx] |= 1 << bit_idx
            mask_bytes[byte_idx] &= ~(1 << bit_idx)

        for byte_idx, value in enumerate(csa_bytes):
            if value == 0:
                continue
            frames.append(
                {
                    "tick_start": tick,
                    "type": "write",
                    "chip_id": chip_id,
                    "register_addr": CSA_ENABLE_BASE + byte_idx,
                    "register_data": value,
                    "label": f"enable injected channels byte {byte_idx} on chip {chip_id}",
                }
            )
            tick += tick_step

        for byte_idx, value in enumerate(mask_bytes):
            if value == 0xFF:
                continue
            frames.append(
                {
                    "tick_start": tick,
                    "type": "write",
                    "chip_id": chip_id,
                    "register_addr": CHANNEL_MASK_BASE + byte_idx,
                    "register_data": value,
                    "label": f"unmask injected channels byte {byte_idx} on chip {chip_id}",
                }
            )
            tick += tick_step

        if disable_trigger_veto:
            frames.append(
                {
                    "tick_start": tick,
                    "type": "write",
                    "chip_id": chip_id,
                    "register_addr": ENABLE_TRIG_MODES_REG,
                    "register_data": 0,
                    "label": f"disable trigger veto modes on chip {chip_id}",
                }
            )
            tick += tick_step

    return frames


def build_startup_source(
    cfg: dict[str, Any],
    rows: int,
    cols: int,
    source_x: int,
    stimulus_cfg: dict[str, Any] | None,
) -> dict[str, Any] | None:
    startup_cfg = cfg.get("startup")
    if startup_cfg is None:
        return None
    if not isinstance(startup_cfg, dict):
        raise ValueError("startup must be an object")

    mode = startup_cfg.get("mode", "manual")
    tick_start = int(startup_cfg.get("tick_start", 20))
    tick_step = int(startup_cfg.get("tick_step", 120))

    frames: list[dict[str, Any]]
    if mode == "manual":
        raw_frames = startup_cfg.get("frames", [])
        if not isinstance(raw_frames, list):
            raise ValueError("startup.frames must be a list when startup.mode is manual")
        frames = [dict(frame) for frame in raw_frames]
    elif mode == "bootstrap_chip_id_readback":
        builder = BootstrapReadbackBuilder(cols, rows, source_x, tick_start=tick_start, tick_step=tick_step)
        frames = [
            {
                "tick_start": f.tick_start,
                "type": f.type,
                "chip_id": f.chip_id,
                "register_addr": f.register_addr,
                **({"register_data": f.register_data} if f.register_data is not None else {}),
                **({"wait_for_chip_id_reply": f.wait_for_chip_id_reply} if f.wait_for_chip_id_reply is not None else {}),
                "label": f.label,
            }
            for f in builder.build()
        ]
    elif mode == "bootstrap_chip_id":
        builder = BootstrapStartupBuilder(cols, rows, source_x, tick_start=tick_start, tick_step=tick_step)
        frames = [
            {
                "tick_start": f.tick_start,
                "type": f.type,
                "chip_id": f.chip_id,
                "register_addr": f.register_addr,
                "register_data": f.register_data,
                "label": f.label,
            }
            for f in builder.build()
        ]
    elif mode in ("enable_trigger_injected_channels", "enable_injected_channels"):
        frames = generate_enable_injected_channel_frames(startup_cfg, stimulus_cfg, tick_start, tick_step)
    else:
        raise ValueError(f"unsupported startup.mode '{mode}'")

    if startup_cfg.get("append_enable_injected_channels"):
        next_tick = tick_start
        if frames:
            next_tick = max(int(frame["tick_start"]) for frame in frames) + tick_step
        frames.extend(generate_enable_injected_channel_frames(startup_cfg, stimulus_cfg, next_tick, tick_step))

    out: dict[str, Any] = {"frames": frames}
    if "readback_phase" in startup_cfg:
        out["readback_phase"] = startup_cfg["readback_phase"]
    return out


def compile_startup_source(raw: dict[str, Any]) -> dict[str, Any]:
    frames_in = raw.get("frames", [])
    if not isinstance(frames_in, list):
        raise ValueError("startup source must contain a list field 'frames'")
    compiled_frames = [compile_frame(frame) for frame in frames_in]
    compiled_readback = compile_readback_phase(raw.get("readback_phase"))
    check_overlaps(compiled_frames)
    out: dict[str, Any] = {
        "frame_bits": FRAME_BITS,
        "frames": sorted(compiled_frames, key=lambda f: int(f["tick_start"])),
    }
    if compiled_readback is not None:
        out["readback_phase"] = compiled_readback
    return out


def run_command(cmd: list[str], *, cwd: Path) -> None:
    print(" ".join(cmd))
    subprocess.run(cmd, cwd=str(cwd), check=True)


def maybe_build(repo_root: Path, build_dir: Path, build_cfg: dict[str, Any] | None) -> None:
    if build_cfg is None or not bool(build_cfg.get("enabled", False)):
        return

    nng_root = build_cfg.get("nng_root") or os.environ.get("NNG_ROOT")
    rtl_dir = build_cfg.get("larpix_rtl_dir") or os.environ.get("LARPIX_RTL_DIR")
    if not nng_root:
        raise ValueError("build.nng_root or NNG_ROOT must be set when build.enabled is true")
    if not rtl_dir:
        raise ValueError("build.larpix_rtl_dir or LARPIX_RTL_DIR must be set when build.enabled is true")

    configure_cmd = [
        "cmake",
        "-S",
        str(repo_root),
        "-B",
        str(build_dir),
        f"-DNNG_ROOT={nng_root}",
        f"-DLARPIX_RTL_DIR={rtl_dir}",
    ]
    build_cmd = [
        "cmake",
        "--build",
        str(build_dir),
        "--target",
        "fpga_larpix",
        "orchestrator_larpix",
        "trace_collector_larpix",
        "chip_larpix_build",
        "-j",
    ]
    run_command(configure_cmd, cwd=repo_root)
    run_command(build_cmd, cwd=repo_root)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the LArPix network simulator from one JSON config")
    parser.add_argument("-cfg", "--config", required=True, help="Path to unified run config JSON")
    parser.add_argument("--prepare-only", action="store_true", help="Generate derived inputs but do not launch orchestrator")
    args = parser.parse_args()

    repo_root = THIS_DIR.parents[1]
    cfg_path = Path(args.config).resolve()
    cfg = load_json_with_comments(cfg_path)

    network = cfg.get("network")
    if not isinstance(network, dict):
        raise ValueError("network must be an object")
    rows = int(get_required(network, "rows"))
    cols = int(get_required(network, "cols"))
    ticks = int(get_required(network, "ticks"))
    source = network.get("source", {})
    if not isinstance(source, dict):
        raise ValueError("network.source must be an object")
    source_x = int(get_required(source, "x"))
    source_y = int(source.get("y", 0))

    runtime_cfg = cfg.get("runtime", {})
    if not isinstance(runtime_cfg, dict):
        raise ValueError("runtime must be an object")
    outputs_cfg = cfg.get("outputs", {})
    if not isinstance(outputs_cfg, dict):
        raise ValueError("outputs must be an object")
    build_cfg = cfg.get("build")
    if build_cfg is not None and not isinstance(build_cfg, dict):
        raise ValueError("build must be an object")

    build_dir = resolve_repo_path(repo_root, build_cfg.get("build_dir", "build")) if build_cfg else repo_root / "build"
    work_dir = resolve_repo_path(repo_root, outputs_cfg.get("work_dir", f"/tmp/chip_network_sim_runs/{cfg_path.stem}"))
    work_dir.mkdir(parents=True, exist_ok=True)

    stimulus_cfg = cfg.get("stimulus")
    if stimulus_cfg is not None and not isinstance(stimulus_cfg, dict):
        raise ValueError("stimulus must be an object")

    maybe_build(repo_root, build_dir, build_cfg)

    startup_source = build_startup_source(cfg, rows, cols, source_x, stimulus_cfg)
    startup_source_path = work_dir / "startup.source.json"
    startup_compiled_path = work_dir / "startup.compiled.json"
    if startup_source is not None:
        write_json(startup_source_path, startup_source)
        write_json(startup_compiled_path, compile_startup_source(startup_source))

    stimulus_path = work_dir / "stimulus.json"
    if stimulus_cfg is not None:
        write_json(stimulus_path, stimulus_cfg)

    orchestrator_bin = resolve_repo_path(repo_root, runtime_cfg.get("orchestrator_bin", build_dir / "orchestrator_larpix"))
    chip_bin = resolve_repo_path(repo_root, runtime_cfg.get("chip_bin", build_dir / "chip_larpix"))
    fpga_bin = resolve_repo_path(repo_root, runtime_cfg.get("fpga_bin", build_dir / "fpga_larpix"))
    trace_collector_bin = runtime_cfg.get("trace_collector_bin")

    cmd = [
        str(orchestrator_bin),
        "-rows",
        str(rows),
        "-cols",
        str(cols),
        "-ticks",
        str(ticks),
        "-source_x",
        str(source_x),
        "-source_y",
        str(source_y),
        "-chip_bin",
        str(chip_bin),
        "-fpga_bin",
        str(fpga_bin),
    ]

    if "backend" in runtime_cfg:
        cmd.extend(["-backend", str(runtime_cfg["backend"])])
    if "seed" in runtime_cfg:
        cmd.extend(["-seed", str(int(runtime_cfg["seed"]))])
    if "startup_ms" in runtime_cfg:
        cmd.extend(["-startup_ms", str(int(runtime_cfg["startup_ms"]))])
    if "ack_timeout_ms" in runtime_cfg:
        cmd.extend(["-ack_timeout_ms", str(int(runtime_cfg["ack_timeout_ms"]))])
    if "base_uri" in runtime_cfg:
        cmd.extend(["-base_uri", str(runtime_cfg["base_uri"])])
    if trace_collector_bin is not None:
        cmd.extend(["-trace_collector_bin", str(trace_collector_bin)])

    if startup_source is not None:
        cmd.extend(["-startup_json", str(startup_compiled_path)])
    if stimulus_cfg is not None:
        cmd.extend(["-stimulus_json", str(stimulus_path)])

    if "trace_out" in outputs_cfg:
        cmd.extend(["-trace_out", str(resolve_repo_path(repo_root, outputs_cfg["trace_out"]))])
    if "occupancy_csv" in outputs_cfg:
        cmd.extend(["-occupancy_csv", str(resolve_repo_path(repo_root, outputs_cfg["occupancy_csv"]))])
    if "occupancy_runtime_id" in outputs_cfg:
        cmd.extend(["-occupancy_runtime_id", str(int(outputs_cfg["occupancy_runtime_id"]))])
    if "occupancy_tick_start" in outputs_cfg:
        cmd.extend(["-occupancy_tick_start", str(int(outputs_cfg["occupancy_tick_start"]))])

    print(f"work_dir={work_dir}")
    if startup_source is not None:
        print(f"startup_source={startup_source_path}")
        print(f"startup_compiled={startup_compiled_path}")
    if stimulus_cfg is not None:
        print(f"stimulus_path={stimulus_path}")

    if args.prepare_only:
        return 0

    run_command(cmd, cwd=repo_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
