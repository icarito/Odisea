from pathlib import Path

import pytest

import os
import re
import subprocess


class RunnerError(Exception):
    pass


def _strip_ansi(line: str) -> str:
    return re.sub(r"\x1b\[[0-9;]*m", "", line).rstrip()


def _stream_process(cmd, file_hint: Path | None = None, filter_visualserver: bool = False):
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        universal_newlines=True,
    )

    captured_failed_asserts = []

    while True:
        line = proc.stdout.readline()
        if not line and proc.poll() is not None:
            break
        if not line:
            continue

        if filter_visualserver and (
            "VisualServer attempted to free a NULL RID" in line
            or "at: free (servers/visual/visual_server_raster.cpp:69)" in line
        ):
            continue

        clean = _strip_ansi(line)
        print(clean)

        if "ASSERT FAILED" in clean or "Assertion failed" in clean:
            captured_failed_asserts.append(clean)

        if os.environ.get("GITHUB_ACTIONS") == "true" and file_hint is not None:
            if "[ERROR]" in clean:
                print(f"::error file={file_hint}::{clean}")
            elif "[WARNING]" in clean:
                print(f"::warning file={file_hint}::{clean}")

    return proc.poll(), captured_failed_asserts


def _has_executable(program: str) -> bool:
    if os.path.sep in program:
        return os.path.isfile(program) and os.access(program, os.X_OK)

    for entry in os.environ.get("PATH", "").split(os.pathsep):
        if not entry:
            continue
        candidate = os.path.join(entry, program)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return True
    return False


def _collect_gdunit_suites(repo_root: Path):
    test_dir = repo_root / "core_v2" / "tests"
    suites = []
    for path in sorted(test_dir.glob("*.gd")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        if "GdUnitTestSuite" in text:
            if path.name == "test_determinism_v2.gd":
                continue
            suites.append(path)
    return suites


def _collect_determinism_oys_cases(repo_root: Path):
    test_dir = repo_root / "core_v2" / "tests"
    return [path.stem for path in sorted(test_dir.glob("*.oys"))]


def _collect_raw_oys_files(repo_root: Path):
    files = []
    for base in (repo_root / "tests", repo_root / "core_v2" / "tests"):
        if not base.exists():
            continue
        oys_files = sorted(base.rglob("*.oys"))
        files.extend(oys_files)

        # Only include JSON replays when no matching OYS file is present.
        oys_keys = {(p.parent, p.stem) for p in oys_files}
        for json_path in sorted(base.rglob("*.json")):
            if (json_path.parent, json_path.stem) in oys_keys:
                continue
            files.append(json_path)
    return files


@pytest.mark.parametrize("suite_path", _collect_gdunit_suites(Path(__file__).resolve().parents[1]), ids=lambda p: p.name)
def test_gdunit_suite(suite_path: Path, selected_runner: str, repo_root: Path):
    if selected_runner != "gdunit":
        pytest.skip("gdunit runner not selected")

    rel_suite = suite_path.relative_to(repo_root)
    cmd = ["./runtest.sh", "-a", str(rel_suite)]
    print(f"[INFO] Executing: {' '.join(cmd)}")

    returncode, _ = _stream_process(cmd, file_hint=rel_suite)
    if returncode != 0:
        raise RunnerError(f"runtest.sh failed for {rel_suite} with return code {returncode}.")


@pytest.mark.parametrize("oys_name", _collect_determinism_oys_cases(Path(__file__).resolve().parents[1]))
def test_determinism_batched_case(oys_name: str, selected_runner: str):
    if selected_runner != "gdunit":
        pytest.skip("gdunit runner not selected")

    cmd = ["./runtest.sh", "--oys", oys_name]
    print(f"[INFO] Executing: {' '.join(cmd)}")

    returncode, _ = _stream_process(cmd)
    if returncode != 0:
        raise RunnerError(f"runtest.sh failed for OYS case '{oys_name}' with return code {returncode}.")


@pytest.mark.parametrize("test_file", _collect_raw_oys_files(Path(__file__).resolve().parents[1]), ids=lambda p: p.name)
def test_raw_oys_file(test_file: Path, selected_runner: str, repo_root: Path):
    if selected_runner != "raw-oys":
        pytest.skip("raw-oys runner not selected")

    godot_bin = "godot3-bin"
    if not _has_executable(godot_bin):
        godot_bin = "godot"

    rel_file = test_file.relative_to(repo_root)
    cmd = [
        godot_bin,
        "--headless",
        "--no-window",
        "-s",
        "tests/debug_runner.gd",
        "--test-file",
        str(rel_file),
    ]
    print(f"[INFO] Executing: {' '.join(cmd)}")

    returncode, failed_asserts = _stream_process(cmd, file_hint=rel_file, filter_visualserver=True)
    if returncode == 1:
        message = "Test failed with return code 1. Check logs for [ERROR]."
        if failed_asserts:
            message += "\nCaptured Failures:\n" + "\n".join(failed_asserts)
        pytest.fail(message, pytrace=False)
    if returncode != 0:
        raise RunnerError(f"Godot Engine Crash: test crashed/error with return code {returncode}.")
