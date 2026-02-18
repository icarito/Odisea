from pathlib import Path

import pytest

import hashlib
import os
import re
import selectors
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
        start_new_session=True,
    )

    captured_failed_asserts = []

    sel = selectors.DefaultSelector()
    if proc.stdout is not None:
        sel.register(proc.stdout, selectors.EVENT_READ)

    while proc.poll() is None:
        events = sel.select(timeout=0.2)
        if not events:
            continue

        line = proc.stdout.readline()
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

    # Drain remaining buffered output.
    if proc.stdout is not None:
        for line in proc.stdout:
            clean = _strip_ansi(line)
            if clean:
                print(clean)

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
    include_determinism_raw = os.environ.get("ODISEA_INCLUDE_DETERMINISM")
    include_determinism = True if include_determinism_raw is None else include_determinism_raw.strip().lower() in {"1", "true", "yes", "on"}
    if not include_determinism:
        return []
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


def _safe_id(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]+", "_", value).strip("_")


def _stable_suffix(value: str) -> str:
    return hashlib.sha1(value.encode("utf-8")).hexdigest()[:8]


def _run_gdunit_suite(suite_path: Path, selected_runner: str, repo_root: Path, odisea_debug: bool):
    if selected_runner != "gdunit":
        pytest.skip("gdunit runner not selected")

    rel_suite = suite_path.relative_to(repo_root)
    cmd = ["./runtest.sh"]
    if odisea_debug:
        cmd += ["--show", "--debug"]
    cmd += ["-a", str(rel_suite)]
    print(f"[INFO] Executing: {' '.join(cmd)}")

    returncode, _ = _stream_process(cmd, file_hint=rel_suite)
    if returncode != 0:
        raise RunnerError(f"runtest.sh failed for {rel_suite} with return code {returncode}.")


def _run_determinism_case(
    oys_name: str, selected_runner: str, odisea_debug: bool, odisea_editor: bool
):
    if selected_runner != "gdunit":
        pytest.skip("gdunit runner not selected")

    cmd = ["./runtest.sh"]
    if odisea_debug:
        cmd += ["--show", "--debug"]
    if odisea_editor:
        # Editor profile: run OYS pass 1 only to avoid heavy determinism second pass.
        cmd += ["--nodet"]
    cmd += ["--oys", oys_name]
    print(f"[INFO] Executing: {' '.join(cmd)}")

    returncode, _ = _stream_process(cmd)
    if returncode != 0:
        raise RunnerError(f"runtest.sh failed for OYS case '{oys_name}' with return code {returncode}.")


def _run_raw_oys_file(test_file: Path, selected_runner: str, repo_root: Path, odisea_debug: bool):
    if selected_runner != "raw-oys":
        pytest.skip("raw-oys runner not selected")

    godot_bin = "godot3-bin"
    if not _has_executable(godot_bin):
        godot_bin = "godot"

    rel_file = test_file.relative_to(repo_root)
    cmd = [godot_bin]
    if not odisea_debug:
        cmd += ["--headless", "--no-window", "--audio-driver", "Dummy"]
    cmd += ["-s", "tests/debug_runner.gd", "--test-file", str(rel_file)]
    print(f"[INFO] Executing: {' '.join(cmd)}")

    returncode, failed_asserts = _stream_process(cmd, file_hint=rel_file, filter_visualserver=True)
    if returncode == 1:
        message = "Test failed with return code 1. Check logs for [ERROR]."
        if failed_asserts:
            message += "\nCaptured Failures:\n" + "\n".join(failed_asserts)
        pytest.fail(message, pytrace=False)
    if returncode != 0:
        raise RunnerError(f"Godot Engine Crash: test crashed/error with return code {returncode}.")


def _make_gdunit_test(suite_path: Path, repo_root: Path):
    @pytest.mark.odisea_gdunit
    def _test(selected_runner: str, repo_root: Path, odisea_debug: bool):
        _run_gdunit_suite(suite_path, selected_runner, repo_root, odisea_debug)

    test_name = f"test_gd__{_safe_id(suite_path.name)}__{_stable_suffix(str(suite_path))}"
    _test.__name__ = test_name
    _test.__qualname__ = test_name
    # Prefer paired OYS DSL file for editor navigation; fallback to suite source.
    paired_oys = suite_path.with_suffix(".oys")
    _test._oys_source = paired_oys if paired_oys.exists() else suite_path
    return _test


def _make_determinism_test(oys_name: str, repo_root: Path):
    @pytest.mark.odisea_gdunit
    @pytest.mark.odisea_determinism
    def _test(selected_runner: str, odisea_debug: bool, odisea_editor: bool):
        _run_determinism_case(oys_name, selected_runner, odisea_debug, odisea_editor)

    test_name = f"test_det__{_safe_id(oys_name)}__{_stable_suffix(oys_name)}"
    _test.__name__ = test_name
    _test.__qualname__ = test_name
    _test._oys_source = repo_root / "core_v2" / "tests" / f"{oys_name}.oys"
    return _test


def _make_raw_oys_test(test_file: Path):
    marks = [pytest.mark.odisea_raw_oys]
    if "stress" in test_file.parts:
        marks.append(pytest.mark.odisea_stress)

    def _test(selected_runner: str, repo_root: Path, odisea_debug: bool):
        _run_raw_oys_file(test_file, selected_runner, repo_root, odisea_debug)

    for mark in marks:
        _test = mark(_test)

    test_name = f"test_raw__{_safe_id(test_file.name)}__{_stable_suffix(str(test_file))}"
    _test.__name__ = test_name
    _test.__qualname__ = test_name
    _test._oys_source = test_file
    return _test


_REPO_ROOT = Path(__file__).resolve().parents[1]

for _suite_path in _collect_gdunit_suites(_REPO_ROOT):
    globals()[f"test_gd__{_safe_id(_suite_path.name)}__{_stable_suffix(str(_suite_path))}"] = _make_gdunit_test(_suite_path, _REPO_ROOT)

for _oys_name in _collect_determinism_oys_cases(_REPO_ROOT):
    globals()[f"test_det__{_safe_id(_oys_name)}__{_stable_suffix(_oys_name)}"] = _make_determinism_test(_oys_name, _REPO_ROOT)

for _test_file in _collect_raw_oys_files(_REPO_ROOT):
    globals()[f"test_raw__{_safe_id(_test_file.name)}__{_stable_suffix(str(_test_file))}"] = _make_raw_oys_test(_test_file)
