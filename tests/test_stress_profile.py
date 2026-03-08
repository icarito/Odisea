from pathlib import Path
import os
import subprocess

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
STRESS_OYS = REPO_ROOT / "core_v2" / "tests" / "stress" / "run_stress.oys"


@pytest.mark.odisea_stress
def test_stress__run_stress_oys():
    godot_bin = "godot3-bin"
    if os.path.sep in godot_bin:
        pass
    elif not any(
        (Path(entry) / godot_bin).is_file() and os.access(Path(entry) / godot_bin, os.X_OK)
        for entry in os.environ.get("PATH", "").split(os.pathsep)
        if entry
    ):
        godot_bin = "godot"

    cmd = [
        godot_bin,
        "--headless",
        "--no-window",
        "--audio-driver",
        "Dummy",
    ]
    env = os.environ.copy()
    env["OYS_AUTO_RUN"] = "res://core_v2/tests/stress/run_stress.oys"
    completed = subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        env=env,
    )
    if completed.returncode != 0:
        pytest.fail(
            "Stress profile failed.\n"
            f"Command: {' '.join(cmd)}\n"
            f"Exit: {completed.returncode}\n"
            f"STDOUT:\n{completed.stdout}\n"
            f"STDERR:\n{completed.stderr}",
            pytrace=False,
        )


# VSCode test navigation hint: jump to the source OYS file from this profile test.
test_stress__run_stress_oys._oys_source = STRESS_OYS
