import os
import re
import subprocess
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


def pytest_configure(config):
    # Auto-enable xdist when available unless the user explicitly set a worker value.
    if (
        config.pluginmanager.hasplugin("xdist")
        and hasattr(config.option, "numprocesses")
        and config.option.numprocesses is None
    ):
        config.option.numprocesses = "auto"


@pytest.fixture(scope="session")
def repo_root() -> Path:
    return Path(__file__).resolve().parent


@pytest.fixture(scope="session")
def selected_runner(pytestconfig) -> str:
    return pytestconfig.getoption("--odisea-runner")


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

        if os.environ.get("GITHUB_ACTIONS") == "true" and file_hint is not None:
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

        f.write("| Status | Count |\n")
        f.write("| :--- | :--- |\n")
        f.write(f"| Passed | {passed} |\n")
        f.write(f"| Failed | {failed} |\n")
        f.write(f"| Errors | {errors} |\n")
        f.write(f"| Skipped | {skipped} |\n\n")

        if failed > 0 or errors > 0:
            f.write("### Failures & Errors\n")
            for rep in stats.get("failed", []):
                f.write(f"- FAILED: `{rep.nodeid}`\n")
            for rep in stats.get("error", []):
                f.write(f"- ERROR: `{rep.nodeid}`\n")
