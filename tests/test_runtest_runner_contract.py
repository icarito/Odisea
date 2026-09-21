"""Contrato del runner local: backend Server headless, igual que CI.

Estos tests no lanzan Godot real. Verifican que `runtest.sh` resuelva siempre el
driver Server (`--headless --no-window`) por defecto, que `--show` sea la unica via
grafica, y que el sharding del job core (`--shards N`) cubra cada suite exactamente
una vez, en procesos frescos secuenciales. El rescue (`ODISEA_RETRY_ISOLATED=1`)
solo verde a el gate cuando la suite flaker pasa aislada. Un run local con X11
oculto (`--no-window` solo) cambia el driver de ventana/input y el mouse virtual y
Box3D pueden dar resultados distintos a CI; por eso se blinda aca.
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
RUNTEST = REPO_ROOT / "runtest.sh"
SUITE_TARGET = "./core_v2/tests/test_gravity_modes.gd"
CORE_TARGET = "./core_v2/tests/"



def _resolve_commands(*args: str, display: str = ":99") -> list[str]:
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
    return lines


def _resolve_command(*args: str, display: str = ":99") -> str:
    return _resolve_commands(*args, display=display)[-1]


def _expected_core_suites() -> list[str]:
    return sorted(
        "./" + str(p.relative_to(REPO_ROOT))
        for p in (REPO_ROOT / "core_v2" / "tests").rglob("*.gd")
        if "GdUnitTestSuite" in p.read_text(encoding="utf-8", errors="ignore")
    )


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


def test_ci_profile_is_sharded_gdunit():
    cmds = _resolve_commands("--ci")
    # El job core de CI corre shards secuenciales en procesos frescos (--ci lo espeja)
    # y sigue SIENDO gdunit: el delegate pytest es otro registro (~una corrida por suite).
    assert len(cmds) >= 2, f"--ci debe imprimir un comando por shard, salio: {cmds}"
    for cmd in cmds:
        assert "--headless" in cmd
        assert "-c" in cmd
        assert "pytest" not in cmd
        assert "core_v2/tests/" in cmd  # -a por suite explicita, no el directorio crudo


def test_sharded_print_command_covers_every_suite_once():
    cmds = _resolve_commands("--shards", "4", "--runner", "gdunit", "-a", CORE_TARGET)
    assert len(cmds) == 4
    actual: list[str] = []
    for cmd in cmds:
        assert "GdUnitCmdTool.gd" in cmd
        paths = re.findall(r"-a (\./core_v2/tests/[^ ]+\.gd)", cmd)
        assert paths, f"shard sin suites explicitas: {cmd}"
        actual.extend(paths)
    assert sorted(actual) == _expected_core_suites()  # cobertura exacta, sin duplicados


def _write_stub_godot(tmp_path: Path, *, first_fails: bool, always_fails: bool) -> Path:
    """Stub de Godot: imprime tests y falla segun la politica pedida.

    Reglas: promedia contando invocaciones en `counter`. Con always_fails=True
    siempre sale 100 imprimiendo el fallo de suite_ficticia. Si no, la PRIMERA
    invocacion falla (100 + linea FAILED de test_ringhub_wakeup) y el resto sale 0.
    """
    stub = tmp_path / "stub-godot"
    stub.write_text(
        "#!/usr/bin/env bash\n"
        "this_dir=\"$(dirname \"$0\")\"\n"
        "counter=\"$this_dir/counter\"\n"
        "n=1\n"
        "if [ -f \"$counter\" ]; then n=$(($(cat \"$counter\") + 1)); fi\n"
        "echo \"$n\" > \"$counter\"\n"
        "for a in \"$@\"; do echo \"$a\" >> \"$this_dir/args.log\"; done\n"
        + (
            "echo '\\tRun Test: res://core_v2/tests/test_ringhub_wakeup.gd > test_opening_cryo_pod_does_not_move_pilot :FAILED 8s 235ms'\n"
            "exit 100\n"
            if always_fails
            else (
                "if [ \"$n\" -le 1 ]; then\n"
                "  echo '\\tRun Test: res://core_v2/tests/test_ringhub_wakeup.gd > test_opening_cryo_pod_does_not_move_pilot :FAILED 8s 235ms'\n"
                "  exit 100\n"
                "fi\n"
                "exit 0\n"
                if first_fails
                else "exit 0\n"
            )
        )
    )
    stub.chmod(0o755)
    return stub


def _run_stubbed_sharded_run(tmp_path: Path, stub: Path, shards: str = "4") -> tuple[int, str]:
    env = os.environ.copy()
    env.update(
        {
            "GODOT_BIN": str(stub),
            "DISPLAY": ":99",
            "ODISEA_SKIP_PREFLIGHT": "1",
            "ODISEA_RUN_DETERMINISM": "0",
            "ODISEA_RETRY_ISOLATED": "1",
        }
    )
    result = subprocess.run(
        ["bash", str(RUNTEST), "--runner", "gdunit", "--shards", shards, "-a", CORE_TARGET],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        env=env,
        timeout=120,
    )
    stdout = result.stdout + result.stderr
    print(stdout)
    return result.returncode, stdout


def test_sharded_run_covers_every_suite_once(tmp_path):
    """End-to-end contra el stub: cada suite se pasa a Godot exactamente una vez."""
    stub = _write_stub_godot(tmp_path, first_fails=False, always_fails=False)
    rc, stdout = _run_stubbed_sharded_run(tmp_path, stub, shards="4")
    assert rc == 0, f"run sharded con stub exito esperado, rc={rc}"
    invoked: list[str] = []
    for line in (tmp_path / "args.log").read_text().splitlines():
        if line.startswith("./core_v2/tests/") and line.endswith(".gd"):
            invoked.append(line)
    assert sorted(invoked) == _expected_core_suites()


def test_sharded_rescue_retries_failed_suite_isolated_and_greens_gate(tmp_path):
    """Flake de corrida larga: la suite falla en shard pero pasa aislada -> gate verde + warning."""
    stub = _write_stub_godot(tmp_path, first_fails=True, always_fails=False)
    rc, stdout = _run_stubbed_sharded_run(tmp_path, stub, shards="4")
    assert "::warning::Gate rescatado por reintentos aislados" in stdout
    assert "Reintento aislado" in stdout
    assert rc == 0, f"rescue debe verdear el gate, rc={rc}"
    # La suite flaker se re-corre exactamente con -a <suite> (aislada, proceso fresco).
    retry_invocations = stdout.count("Reintento aislado: res://core_v2/tests/test_ringhub_wakeup.gd")
    assert retry_invocations == 1


def test_sharded_rescue_keeps_gate_red_on_real_failure(tmp_path):
    """Fallo real: la suite sigue fallando aislada -> el gate queda rojo."""
    stub = _write_stub_godot(tmp_path, first_fails=False, always_fails=True)
    rc, stdout = _run_stubbed_sharded_run(tmp_path, stub, shards="4")
    assert rc == 100, f"un fallo real no debe rescatarse, rc={rc}"
    assert "sigue fallando aislada" in stdout
    assert "::warning::Gate rescatado" not in stdout


def test_no_display_bifurcation_in_source():
    text = RUNTEST.read_text(encoding="utf-8")
    # El default debe ser literalmente Server headless.
    assert 'HEADLESS="--headless --no-window"' in text
    # No debe existir un default grafico que dependa de un display.
    assert not re.search(r'HEADLESS\s*=\s*"--no-window"', text)
    assert not re.search(r'\[\s*-n\s+"\$\{?DISPLAY', text)
    # --headless sobre el editor X11 de Godot 3 no lo convierte en platform=server.
    assert "ODISEA_GODOT_FLAVOR=headless" in text
