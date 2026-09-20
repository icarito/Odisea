"""Contrato del runner local: backend Server headless, igual que CI.

Estos tests no lanzan Godot. Verifican que `runtest.sh` resuelva siempre el driver
Server (`--headless --no-window`) por defecto y que `--show` sea la unica via grafica.
Un run local con X11 oculto (`--no-window` solo) cambia el driver de ventana/input y
el mouse virtual y Box3D pueden dar resultados distintos a CI; por eso se blinda aca.
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
RUNTEST = REPO_ROOT / "runtest.sh"
SUITE_TARGET = "./core_v2/tests/test_gravity_modes.gd"


def _resolve_command(*args: str, display: str = ":99") -> str:
    env = os.environ.copy()
    env["GODOT_BIN"] = "stub-godot"
    env["DISPLAY"] = display
    result = subprocess.run(
        ["bash", str(RUNTEST), "--print-command", *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )
    assert result.returncode == 0, f"runtest.sh --print-command fallo:\n{result.stdout}\n{result.stderr}"
    lines = [
        line
        for line in (result.stdout + result.stderr).splitlines()
        if "GdUnitCmdTool.gd" in line
    ]
    assert lines, f"sin comando GdUnit en la salida:\n{result.stdout}\n{result.stderr}"
    return lines[-1]


def test_default_backend_is_server_headless_even_with_display():
    cmd = _resolve_command("-a", SUITE_TARGET)
    assert "--headless" in cmd
    assert "--no-window" in cmd


def test_show_is_the_only_graphical_path():
    cmd = _resolve_command("--show", "-a", SUITE_TARGET)
    assert "--headless" not in cmd


def test_oys_path_is_headless():
    cmd = _resolve_command("--oys", "test_salto_vertical")
    assert "--headless" in cmd
    assert "--no-window" in cmd


def test_ci_profile_forces_single_process_gdunit():
    cmd = _resolve_command("--ci")
    assert "--headless" in cmd
    assert "-a ./core_v2/tests/" in cmd
    # El delegate pytest arranca un Godot por suite: --ci debe quedarse en gdunit.
    assert "pytest" not in cmd


def test_no_display_bifurcation_in_source():
    text = RUNTEST.read_text(encoding="utf-8")
    # El default debe ser literalmente Server headless.
    assert 'HEADLESS="--headless --no-window"' in text
    # No debe existir un default grafico que dependa de un display.
    assert not re.search(r'HEADLESS\s*=\s*"--no-window"', text)
    assert not re.search(r'\[\s*-n\s+"\$\{?DISPLAY', text)
