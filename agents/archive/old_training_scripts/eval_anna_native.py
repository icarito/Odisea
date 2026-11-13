#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Evaluate ANNA RL agent natively in Godot using ONNX.",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog=(
            "Quick start:\n"
            "  python agents/eval_anna_native.py --watch\n"
            "    Opens window (if display is available), auto-picks the latest .onnx model,\n"
            "    runs forever, and evaluates natively.\n\n"
            "  python agents/eval_anna_native.py --scene TestScene_RL_2\n"
            "    Evaluates natively using TestScene_RL_2.\n\n"
            "  python agents/eval_anna_native.py --headless\n"
            "    Short headless evaluation.\n"
        ),
    )
    parser.add_argument("--model", default="", help="Path to model .onnx. If omitted, auto-select latest best model.")
    parser.add_argument("--scene", default="TestScene_RL", help="Scene name/path (e.g. TestScene_RL, TestScene_RL_2).")
    
    view_group = parser.add_mutually_exclusive_group()
    view_group.add_argument("--render", dest="render", action="store_true", help="Launch Godot with a window.")
    view_group.add_argument("--headless", dest="render", action="store_false", help="Run without window.")
    parser.set_defaults(render=None)
    
    parser.add_argument("--watch", action="store_true", help="Run continuously. Restarts Godot if it crashes.")
    return parser.parse_args()


def _pick_default_model(repo_root: Path) -> Path | None:
    candidates = []
    patterns = [
        "core_v2/trained_models/*_best*.onnx",
        "core_v2/trained_models/*.onnx",
        "agents/models/*.onnx",
    ]
    for pat in patterns:
        candidates.extend(sorted(repo_root.glob(pat), key=lambda p: p.stat().st_mtime, reverse=True))

    seen = set()
    for p in candidates:
        rp = str(p.resolve())
        if rp in seen:
            continue
        seen.add(rp)
        if p.exists() and p.suffix == ".onnx":
            return p
    return None


def _resolve_scene_arg(scene_arg: str, project_root: str) -> str:
    def _normalize_res(rel_path: str) -> str:
        rel = rel_path.lstrip("./").replace("\\", "/")
        return "res://" + rel

    def _exists_rel(rel_path: str) -> bool:
        rel = rel_path.lstrip("./")
        return os.path.exists(os.path.join(project_root, rel))

    raw = str(scene_arg).strip()
    if not raw:
        return raw

    attempts = []
    candidates = []

    if raw.startswith("res://"):
        rel = raw[len("res://"):].lstrip("/")
        candidates.append(rel)
    elif os.path.isabs(raw):
        if os.path.exists(raw):
            try:
                rel = os.path.relpath(raw, project_root)
                if not rel.startswith(".."):
                    return _normalize_res(rel)
            except Exception:
                pass
            return raw
        attempts.append(raw)
        raise RuntimeError(f"[eval_native] Scene path does not exist: {raw}")
    else:
        candidates.append(raw.lstrip("./"))

    expanded = []
    for c in candidates:
        c = c.strip()
        if not c:
            continue
        expanded.append(c)
        if not c.endswith(".tscn"):
            expanded.append(c + ".tscn")
        if "/" not in c and "\\" not in c:
            expanded.append("core_v2/tests/" + c)
            expanded.append("scenes/" + c)
            if not c.endswith(".tscn"):
                expanded.append("core_v2/tests/" + c + ".tscn")
                expanded.append("scenes/" + c + ".tscn")

    seen = set()
    for rel in expanded:
        if rel in seen:
            continue
        seen.add(rel)
        attempts.append(rel)
        if _exists_rel(rel):
            return _normalize_res(rel)

    raise RuntimeError(
        f"[eval_native] Could not resolve scene '{raw}'. Tried: {', '.join(attempts[:10])}"
    )


def main() -> int:
    args = _parse_args()
    if args.render is None:
        args.render = bool(args.watch and (os.environ.get("DISPLAY") or os.name == "nt"))

    repo_root = Path(__file__).resolve().parents[1]

    if str(args.model).strip():
        model_path = (repo_root / args.model).resolve()
    else:
        picked = _pick_default_model(repo_root)
        if picked is None:
            print("[eval_native] model not provided and no default .onnx model found")
            return 2
        model_path = picked.resolve()
        print(f"[eval_native] auto model: {model_path}")
        
    if not model_path.exists():
        print(f"[eval_native] model not found: {model_path}")
        return 2

    try:
        scene_path = _resolve_scene_arg(args.scene, str(repo_root))
    except RuntimeError as e:
        print(e)
        return 1

    godot_bin = os.environ.get("ANNA_GODOT_BIN", "godot3-mono-bin")
    cmd = [godot_bin, "--path", "."]
    
    if not args.render:
        cmd.append("--no-window")
        
    cmd.append(scene_path)
    
    env = os.environ.copy()
    env["ANNA_ENABLED"] = "1"
    env["ANNA_RL_MODE"] = "1"
    env["ANNA_RL_EXIT_ON_DISCONNECT"] = "0"
    env["ANNA_ONNX_MODEL"] = str(model_path)
    
    # Auto-seed the Godot Mono binding for the native DLL
    import shutil
    for config in ["Debug", "Release"]:
        mono_path = repo_root / f".mono/temp/bin/{config}"
        mono_path.mkdir(parents=True, exist_ok=True)
        try:
            shutil.copy2(repo_root / "libonnxruntime.so", mono_path / "libonnxruntime.so")
        except FileNotFoundError:
            pass

    # Expose local libonnxruntime.so to Mono
    current_ld = env.get("LD_PRELOAD", "")
    env["LD_PRELOAD"] = f"{repo_root}/libonnxruntime.so:{current_ld}" if current_ld else f"{repo_root}/libonnxruntime.so"

    # We want native Godot mono. Ensure proper fallback to local physics rate.
    if not args.render:
        env.setdefault("ANNA_RL_TARGET_FPS", "2000")
        env.setdefault("ANNA_RL_PHYSICS_FPS", "2000")
        env.setdefault("ANNA_RL_PHYSICS_FPS_CAP", "2000")
        env.setdefault("ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME", "64")
    else:
        render_fps = env.get("ANNA_RL_RENDER_PHYSICS_FPS", "60").strip() or "60"
        env.setdefault("ANNA_RL_TARGET_FPS", render_fps)
        env.setdefault("ANNA_RL_PHYSICS_FPS", render_fps)
        env.setdefault("ANNA_RL_PHYSICS_FPS_CAP", render_fps)
        env.setdefault("ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME", "8")
        
    env.setdefault("ANNA_RL_DISABLE_CPU_SLEEP", "1")
    
    print(f"[eval_native] Launching Godot natively: {' '.join(cmd)}")
    print(f"[eval_native] Using ONNX model: {model_path}")
    print(f"[eval_native] Scene: {scene_path}")
    
    try:
        while True:
            proc = subprocess.Popen(cmd, env=env, cwd=str(repo_root))
            proc.wait()
            
            if not args.watch:
                break
                
            print(f"[eval_native] Godot exited with code {proc.returncode}. Restarting in 2 seconds (--watch)...")
            time.sleep(2)
            
    except KeyboardInterrupt:
        print("[eval_native] Interrupted by user (Ctrl+C). Exiting.")
        if 'proc' in locals() and proc.poll() is None:
            proc.terminate()
            
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
