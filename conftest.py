import os
import re
import subprocess
import sys
from pathlib import Path

import pytest


def pytest_addoption(parser):
    parser.addoption(
        "--odisea-runner",
        action="store",
        default=os.environ.get("ODISEA_RUNNER", "gdunit"),
        choices=["gdunit", "raw-oys"],
        help=(
            "Runner mode: 'gdunit' (default, mirrors runtest.sh by executing "
            "GdUnit .gd suites) or 'raw-oys' (.oys/.json via debug_runner)."
        ),
    )
    parser.addoption(
        "--odisea-debug",
        action="store_true",
        default=False,
        help="Debug mode for Odisea runner: run tests with visible window (non-headless).",
    )


def _is_debugger_attached() -> bool:
    gettrace = getattr(sys, "gettrace", None)
    if gettrace is None:
        return False
    return gettrace() is not None


def _odisea_debug_enabled(config) -> bool:
    if os.environ.get("ODISEA_DEBUG", "").lower() in {"1", "true", "yes", "on"}:
        return True
    if bool(config.getoption("--odisea-debug")):
        return True
    # --pdb / IDE debug session should behave as non-headless automatically.
    if bool(getattr(config.option, "usepdb", False)):
        return True
    if _is_debugger_attached():
        return True
    # VSCode/PyDev debug adapters often expose these env vars even without --pdb.
    if any(
        key in os.environ
        for key in (
            "DEBUGPY_LAUNCHER_PORT",
            "PYDEVD_LOAD_VALUES_ASYNC",
            "PYDEVD_USE_FRAME_EVAL",
            "PYCHARM_HOSTED",
        )
    ):
        return True
    return False


def pytest_configure(config):
    debug_enabled = _odisea_debug_enabled(config)

    # Auto-enable xdist when available unless the user explicitly set a worker value.
    if (
        config.pluginmanager.hasplugin("xdist")
        and hasattr(config.option, "numprocesses")
    ):
        if debug_enabled:
            # Debug sessions work best in a single local process.
            config.option.numprocesses = 0
        elif config.option.numprocesses is None:
            config.option.numprocesses = "auto"


def _is_github_actions() -> bool:
    return os.environ.get("GITHUB_ACTIONS") == "true"


def _gha_escape(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def pytest_collection_modifyitems(config, items):
    runner = config.getoption("--odisea-runner")
    deselected = []
    selected = []
    for item in items:
        is_gdunit = "odisea_gdunit" in item.keywords
        is_raw_oys = "odisea_raw_oys" in item.keywords

        if is_gdunit and runner != "gdunit":
            deselected.append(item)
            continue
        if is_raw_oys and runner != "raw-oys":
            deselected.append(item)
            continue
        selected.append(item)

    if deselected:
        config.hook.pytest_deselected(items=deselected)
        items[:] = selected


def pytest_runtest_logreport(report):
    if not _is_github_actions():
        return
    if report.when != "call":
        return
    if not (report.failed or report.skipped):
        return

    path, line_no, _ = report.location
    title = "Pytest Failure" if report.failed else "Pytest Skipped"
    level = "error" if report.failed else "notice"
    details = getattr(report, "longreprtext", "") or report.outcome
    message = _gha_escape(details.splitlines()[0][:400])
    nodeid = _gha_escape(report.nodeid)
    print(
        f"::{level} file={path},line={line_no + 1},title={title}::{nodeid} | {message}"
    )


@pytest.fixture(scope="session")
def repo_root() -> Path:
    return Path(__file__).resolve().parent


@pytest.fixture(scope="session")
def selected_runner(pytestconfig) -> str:
    return pytestconfig.getoption("--odisea-runner")


@pytest.fixture(scope="session")
def odisea_debug(pytestconfig) -> bool:
    return _odisea_debug_enabled(pytestconfig)


class RunnerError(Exception):
    pass


def strip_ansi(line: str) -> str:
    return re.sub(r"\x1b\[[0-9;]*m", "", line).rstrip()


def stream_process(cmd, file_hint: Path | None = None, filter_visualserver: bool = False):
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

        clean = strip_ansi(line)
        print(clean)

        if "ASSERT FAILED" in clean or "Assertion failed" in clean:
            captured_failed_asserts.append(clean)

        if _is_github_actions() and file_hint is not None:
            if "[ERROR]" in clean:
                print(f"::error file={file_hint}::{clean}")
            elif "[WARNING]" in clean:
                print(f"::warning file={file_hint}::{clean}")

    return proc.poll(), captured_failed_asserts


def has_executable(program: str) -> bool:
    if os.path.sep in program:
        return os.path.isfile(program) and os.access(program, os.X_OK)

    for entry in os.environ.get("PATH", "").split(os.pathsep):
        if not entry:
            continue
        candidate = os.path.join(entry, program)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return True
    return False


def pytest_terminal_summary(terminalreporter, exitstatus, config):
    if not os.environ.get("GITHUB_STEP_SUMMARY"):
        return

    summary_file = os.environ["GITHUB_STEP_SUMMARY"]
    runner = config.getoption("--odisea-runner")

    with open(summary_file, "a", encoding="utf-8") as f:
        f.write(f"## Pytest Results ({runner})\n")
        f.write(f"**Exit Status:** {exitstatus}\n\n")

        stats = terminalreporter.stats
        passed = len(stats.get("passed", []))
        failed = len(stats.get("failed", []))
        errors = len(stats.get("error", []))
        skipped = len(stats.get("skipped", []))
        deselected = len(stats.get("deselected", []))
        total_executed = passed + failed + errors + skipped

        f.write("| Status | Count |\n")
        f.write("| :--- | :--- |\n")
        f.write(f"| Passed | {passed} |\n")
        f.write(f"| Failed | {failed} |\n")
        f.write(f"| Errors | {errors} |\n")
        f.write(f"| Skipped | {skipped} |\n")
        f.write(f"| Deselected | {deselected} |\n\n")
        f.write(f"**Executed tests:** {total_executed}\n\n")

        if failed > 0 or errors > 0:
            f.write("### Failures & Errors\n")
            for rep in stats.get("failed", []):
                f.write(f"- FAILED: `{rep.nodeid}`\n")
            for rep in stats.get("error", []):
                f.write(f"- ERROR: `{rep.nodeid}`\n")

        if skipped > 0:
            reasons = {}
            for rep in stats.get("skipped", []):
                reason = "unknown"
                if isinstance(rep.longrepr, tuple) and len(rep.longrepr) >= 3:
                    reason = str(rep.longrepr[2]).strip()
                elif hasattr(rep, "longreprtext"):
                    reason = rep.longreprtext.splitlines()[-1].strip()
                reasons[reason] = reasons.get(reason, 0) + 1

            f.write("\n### Skip Reasons\n")
            for reason, count in sorted(reasons.items(), key=lambda entry: entry[1], reverse=True):
                f.write(f"- {count}x {reason}\n")
