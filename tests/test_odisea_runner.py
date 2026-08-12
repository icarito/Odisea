from pathlib import Path

import pytest

import os
import re
import selectors
import signal
import subprocess
import sys
import time


class RunnerError(Exception):
    pass


def _strip_ansi(line: str) -> str:
    return re.sub(r"\x1b\[[0-9;]*m", "", line).rstrip()


def _stream_process(
    cmd,
    file_hint: Path | None = None,
    filter_visualserver: bool = False,
    env: dict[str, str] | None = None,
    timeout_sec: float | None = None,
):
    process_env = os.environ.copy()
    if env:
        process_env.update(env)
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        universal_newlines=True,
        start_new_session=True,
        env=process_env,
    )

    captured_failed_asserts = []
    detected_log_path: Path | None = None
    assert_markers = (
        "ASSERT FAILED",
        "Assertion failed",
        "ASSERT_FAIL",
        "ASSERT_SIGNAL FAILED",
        "ASSERT_NO_HAND_CLIPPING failed",
        "[OYS ASSERT] FAILED",
        "OYS ASSERT FAILED",
    )

    def _consume_line(raw_line: str):
        nonlocal detected_log_path
        clean = _strip_ansi(raw_line)
        if not clean:
            return

        print(clean)

        if any(marker in clean for marker in assert_markers):
            captured_failed_asserts.append(clean)

        if "Output guardado en:" in clean or "Output completo en:" in clean:
            maybe_path = clean.split(":", 1)[-1].strip()
            if maybe_path:
                p = Path(maybe_path)
                detected_log_path = p if p.is_absolute() else Path.cwd() / p

        if os.environ.get("GITHUB_ACTIONS") == "true" and file_hint is not None:
            if "[ERROR]" in clean:
                print(f"::error file={file_hint}::{clean}")
            elif "[WARNING]" in clean:
                print(f"::warning file={file_hint}::{clean}")

    sel = selectors.DefaultSelector()
    if proc.stdout is not None:
        sel.register(proc.stdout, selectors.EVENT_READ)

    deadline = time.monotonic() + timeout_sec if timeout_sec and timeout_sec > 0 else None
    timed_out = False
    while proc.poll() is None:
        if deadline is not None and time.monotonic() >= deadline:
            timed_out = True
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait(timeout=5)
            break

        events = sel.select(timeout=0.2)
        if not events:
            continue

        line = proc.stdout.readline()
        if not line:
            continue

        if filter_visualserver and (
            "VisualServer attempted to free a NULL RID" in line
            or "at: free (servers/visual/visual_server_raster.cpp" in line
            or 'Condition "!track_pp" is true' in line
            or "at: _process_graph (scene/animation/animation_tree.cpp" in line
        ):
            continue

        _consume_line(line)

    # Drain remaining buffered output.
    if proc.stdout is not None:
        for line in proc.stdout:
            _consume_line(line)

    if timed_out:
        timeout_message = f"TIMEOUT: command exceeded {timeout_sec:.0f}s: {' '.join(cmd)}"
        print(timeout_message)
        captured_failed_asserts.append(timeout_message)
        return 124, captured_failed_asserts, detected_log_path

    return proc.poll(), captured_failed_asserts, detected_log_path


def _extract_assert_failures_from_log(log_path: Path | None):
    if log_path is None or not log_path.exists():
        return []
    patterns = (
        "ASSERT FAILED",
        "Assertion failed",
        "ASSERT_FAIL",
        "ASSERT_SIGNAL FAILED",
        "ASSERT_NO_HAND_CLIPPING failed",
        "[OYS ASSERT] FAILED",
        "OYS ASSERT FAILED",
    )
    results = []
    for line in log_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        clean = _strip_ansi(line)
        if any(marker in clean for marker in patterns):
            results.append(clean)
    return results


_BENIGN_ENGINE_NOISE = (
    "VisualServer attempted to free a NULL RID",
    "at: free (servers/visual/visual_server_raster.cpp",
    'Condition "!track_pp" is true',
    "at: _process_graph (scene/animation/animation_tree.cpp",
)


def _is_benign_noise(line: str) -> bool:
    return any(pattern in line for pattern in _BENIGN_ENGINE_NOISE)


def _tail_log_excerpt(log_path: Path | None, max_lines: int = 80) -> str:
    if log_path is None or not log_path.exists():
        return ""
    lines = log_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    if not lines:
        return ""
    excerpt = [_strip_ansi(line) for line in lines[-max_lines:]]
    return "\n".join(line for line in excerpt if line and not _is_benign_noise(line))


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


# Manual perf-debugging scripts, not replay-determinism tests: no LEVEL/SCENE,
# no expected final state, meant to be run by hand with --oys to eyeball FPS
# output. Collecting them here made CI hang on debug_perf.oys until its
# 180s per-test timeout, every run, flooding the log with millions of
# AnimationTree "couldn't resolve track" lines and blowing the job's
# 45-minute budget.
_NON_DETERMINISM_OYS_STEMS = {"debug_perf", "perf_test", "perf_ab_test"}


def _collect_determinism_oys_cases(repo_root: Path, include_determinism: bool):
    if not include_determinism:
        return []
    test_dir = repo_root / "core_v2" / "tests"
    return [
        path.stem
        for path in sorted(test_dir.glob("*.oys"))
        if path.stem not in _NON_DETERMINISM_OYS_STEMS
    ]


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


def _truthy_env(value: str | None) -> bool:
    if value is None:
        return False
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _test_timeout_sec() -> float | None:
    value = os.environ.get("ODISEA_TEST_TIMEOUT_SEC")
    if value is None:
        if os.environ.get("GITHUB_ACTIONS") == "true" or os.environ.get("CI") == "true":
            return 180.0
        return None
    try:
        parsed = float(value)
    except ValueError:
        return 180.0
    return parsed if parsed > 0 else None


def _cli_option_value(option_name: str) -> str | None:
    prefix = f"{option_name}="
    argv = sys.argv[1:]
    for index, arg in enumerate(argv):
        if arg.startswith(prefix):
            return arg.split("=", 1)[1]
        if arg == option_name and index + 1 < len(argv):
            return argv[index + 1]
    return None


def _cli_flag_present(flag_name: str) -> bool:
    return flag_name in sys.argv[1:]


def _selected_runner_hint() -> str:
    # Prefer explicit environment value; fallback to CLI/default.
    env_runner = os.environ.get("ODISEA_RUNNER")
    if env_runner in {"gdunit", "raw-oys"}:
        return env_runner
    cli_runner = _cli_option_value("--odisea-runner")
    if cli_runner in {"gdunit", "raw-oys"}:
        return cli_runner
    return "gdunit"


def _include_determinism_hint() -> bool:
    # Enabled by default; can be disabled with ODISEA_INCLUDE_DETERMINISM=0.
    env_value = os.environ.get("ODISEA_INCLUDE_DETERMINISM")
    if env_value is not None:
        return _truthy_env(env_value)
    return True


def _run_gdunit_suite(suite_path: Path, selected_runner: str, repo_root: Path, odisea_debug: bool):
    if selected_runner != "gdunit":
        pytest.skip("gdunit runner not selected")

    rel_suite = suite_path.relative_to(repo_root)
    cmd = ["./runtest.sh"]
    if odisea_debug:
        cmd += ["--show", "--debug"]
    cmd += ["-a", str(rel_suite)]
    print(f"[INFO] Executing: {' '.join(cmd)}")

    returncode, captured_failed_asserts, log_path = _stream_process(
        cmd,
        file_hint=rel_suite,
        filter_visualserver=True,
        env={"ODISEA_SKIP_PREFLIGHT": "1"},
        timeout_sec=_test_timeout_sec(),
    )
    if returncode != 0:
        failures = captured_failed_asserts + _extract_assert_failures_from_log(log_path)
        deduped = list(dict.fromkeys(failures))
        message = f"runtest.sh failed for {rel_suite} (return code {returncode})."
        if deduped:
            message += "\nAsserts detectados:\n" + "\n".join(deduped)
        else:
            excerpt = _tail_log_excerpt(log_path)
            if excerpt:
                message += f"\nTail de log ({log_path}):\n{excerpt}"
        pytest.fail(message, pytrace=False)


def _run_determinism_case(oys_name: str, selected_runner: str, odisea_debug: bool):
    if selected_runner != "gdunit":
        pytest.skip("gdunit runner not selected")

    cmd = ["./runtest.sh"]
    if odisea_debug:
        cmd += ["--show", "--debug"]
    run_full_determinism = _truthy_env(os.environ.get("ODISEA_FULL_DETERMINISM"))
    if not run_full_determinism:
        # Default profile: run OYS pass 1 only, skip JSON verification pass.
        cmd += ["--nodet"]
    cmd += ["--oys", oys_name]
    print(f"[INFO] Executing: {' '.join(cmd)}")

    returncode, captured_failed_asserts, log_path = _stream_process(
        cmd,
        env={"ODISEA_SKIP_PREFLIGHT": "1"},
        timeout_sec=_test_timeout_sec(),
    )
    if returncode != 0:
        failures = captured_failed_asserts + _extract_assert_failures_from_log(log_path)
        deduped = list(dict.fromkeys(failures))
        message = f"runtest.sh failed for OYS case '{oys_name}' (return code {returncode})."
        if deduped:
            message += "\nAsserts detectados:\n" + "\n".join(deduped)
        else:
            excerpt = _tail_log_excerpt(log_path)
            if excerpt:
                message += f"\nTail de log ({log_path}):\n{excerpt}"
        pytest.fail(message, pytrace=False)


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
    oys_auto_run = "res://%s" % rel_file.as_posix()
    print(f"[INFO] Executing: {' '.join(cmd)}")

    returncode, failed_asserts, _log_path = _stream_process(
        cmd,
        file_hint=rel_file,
        filter_visualserver=True,
        env={"OYS_AUTO_RUN": oys_auto_run},
        timeout_sec=_test_timeout_sec(),
    )
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

    rel_id = _safe_id(str(suite_path.relative_to(repo_root)))
    test_name = f"test_gd__{rel_id}"
    _test.__name__ = test_name
    _test.__qualname__ = test_name
    # Prefer paired OYS DSL file for editor navigation; fallback to suite source.
    paired_oys = suite_path.with_suffix(".oys")
    _test._oys_source = paired_oys if paired_oys.exists() else suite_path
    return _test


def _make_determinism_test(oys_name: str, repo_root: Path):
    @pytest.mark.odisea_gdunit
    @pytest.mark.odisea_determinism
    def _test(selected_runner: str, odisea_debug: bool):
        _run_determinism_case(oys_name, selected_runner, odisea_debug)

    test_name = f"test_det__{_safe_id(oys_name)}"
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

    rel_file = test_file.relative_to(_REPO_ROOT)
    test_name = f"test_raw__{_safe_id(str(rel_file))}"
    _test.__name__ = test_name
    _test.__qualname__ = test_name
    _test._oys_source = test_file
    return _test


_REPO_ROOT = Path(__file__).resolve().parents[1]
_RUNNER_HINT = _selected_runner_hint()
_INCLUDE_DETERMINISM = _include_determinism_hint()

if _RUNNER_HINT == "raw-oys":
    for _test_file in _collect_raw_oys_files(_REPO_ROOT):
        _id = _safe_id(str(_test_file.relative_to(_REPO_ROOT)))
        globals()[f"test_raw__{_id}"] = _make_raw_oys_test(_test_file)
else:
    for _suite_path in _collect_gdunit_suites(_REPO_ROOT):
        _id = _safe_id(str(_suite_path.relative_to(_REPO_ROOT)))
        globals()[f"test_gd__{_id}"] = _make_gdunit_test(_suite_path, _REPO_ROOT)

    for _oys_name in _collect_determinism_oys_cases(_REPO_ROOT, _INCLUDE_DETERMINISM):
        _id = _safe_id(_oys_name)
        globals()[f"test_det__{_id}"] = _make_determinism_test(_oys_name, _REPO_ROOT)
