import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest


def _env_truthy(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


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
    parser.addoption(
        "--odisea-include-stress",
        action="store_true",
        default=False,
        help="Include odisea_stress tests in execution (they are skipped by default).",
    )
    parser.addoption(
        "--odisea-editor",
        action="store_true",
        default=False,
        help="Enable IDE-friendly behavior (stable discovery and single-process execution).",
    )
    parser.addoption(
        "--odisea-include-determinism",
        action="store_true",
        default=_env_truthy("ODISEA_INCLUDE_DETERMINISM", True),
        help="Include odisea_determinism tests (enabled by default; set ODISEA_INCLUDE_DETERMINISM=0 to disable).",
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
    # Debug adapters expose these env vars when an actual debug session is active.
    if any(
        key in os.environ
        for key in (
            "DEBUGPY_LAUNCHER_PORT",
            "VSCODE_DEBUGPY_ADAPTER_ENDPOINTS",
            "PYCHARM_HOSTED",
        )
    ):
        return True
    # Fallback: some debug sessions export generic DEBUGPY_/PYDEVD_ variables.
    if any(
        key.startswith("DEBUGPY_") or key.startswith("PYDEVD_")
        for key in os.environ
    ):
        return True
    return False


def pytest_configure(config):
    debug_enabled = _odisea_debug_enabled(config)
    editor_mode = bool(config.getoption("--odisea-editor"))
    editor_serial = os.environ.get("ODISEA_EDITOR_SERIAL", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }
    is_collect_only = bool(getattr(config.option, "collectonly", False))
    invocation_args = list(getattr(config.invocation_params, "args", ()))
    explicit_numprocesses = any(
        arg == "-n"
        or arg.startswith("-n")
        or arg.startswith("--numprocesses")
        for arg in invocation_args
    )

    # Propagate debug mode to subprocesses (runtest.sh, child pytest runs).
    if debug_enabled:
        os.environ["ODISEA_DEBUG"] = "1"

    # Propagate determinism collection mode to dynamic test discovery.
    # VSCode/editor can opt-in via --odisea-include-determinism.
    if os.environ.get("ODISEA_INCLUDE_DETERMINISM") is None:
        os.environ["ODISEA_INCLUDE_DETERMINISM"] = (
            "1" if bool(config.getoption("--odisea-include-determinism")) else "0"
        )

    # Auto-enable xdist when available. In debug we always force single process.
    if (
        config.pluginmanager.hasplugin("xdist")
        and hasattr(config.option, "numprocesses")
    ):
        if is_collect_only:
            # VSCode discovery is more stable without xdist workers.
            config.option.numprocesses = 0
        elif editor_mode and editor_serial:
            # Optional fallback when local machine cannot handle parallel Godot runs.
            config.option.numprocesses = 3
        elif debug_enabled:
            # Debug sessions must be single-process; xdist workers lose debug context.
            config.option.numprocesses = 0
        elif (not debug_enabled) and (not is_collect_only) and (not explicit_numprocesses):
            if _is_github_actions():
                config.option.numprocesses = "auto"
            else:
                config.option.numprocesses = 3


def _is_github_actions() -> bool:
    return os.environ.get("GITHUB_ACTIONS") == "true"


def _gha_escape(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def _is_direct_external_target_run(config) -> bool:
    args = [str(arg) for arg in getattr(config.invocation_params, "args", ())]
    return any(arg.endswith((".oys", ".gd")) for arg in args)


def _is_core_tests_target_run(config) -> bool:
    args = [str(arg).replace("\\", "/").rstrip("/") for arg in getattr(config.invocation_params, "args", ())]
    return any(arg.endswith("core_v2/tests") for arg in args)


def _to_oys_selector(target_path: Path, rootpath: Path) -> str:
    try:
        rel = target_path.relative_to(rootpath / "core_v2" / "tests")
    except ValueError:
        return target_path.stem
    return str(rel.with_suffix(""))


class OdiseaExternalTargetFile(pytest.File):
    def collect(self):
        target_path = Path(str(self.path))
        if target_path.suffix == ".oys":
            test_name = f"test_det__{target_path.stem}"
        else:
            test_name = f"test_gd__{target_path.stem}"
        item = OdiseaExternalTargetItem.from_parent(
            self,
            name=test_name,
            target_path=target_path,
        )
        item._oys_source = target_path
        return [item]


class OdiseaExternalTargetDirectory(pytest.Directory):
    def collect(self):
        rootpath = Path(self.config.rootpath)
        tests_root = rootpath / "core_v2" / "tests"
        include_stress = bool(self.config.getoption("--odisea-include-stress")) or os.environ.get(
            "ODISEA_INCLUDE_STRESS", ""
        ).strip().lower() in {"1", "true", "yes", "on"}

        items = []
        for target_path in sorted(tests_root.rglob("*")):
            if not target_path.is_file():
                continue
            if target_path.suffix not in {".oys", ".gd"}:
                continue
            if "stress" in target_path.parts and not include_stress:
                continue

            if target_path.suffix == ".gd":
                try:
                    text = target_path.read_text(encoding="utf-8", errors="ignore")
                except OSError:
                    continue
                if "GdUnitTestSuite" not in text:
                    continue
                if target_path.name == "test_determinism_v2.gd":
                    continue
                test_name = f"test_gd__{target_path.stem}"
            else:
                test_name = f"test_det__{target_path.stem}"

            item = OdiseaExternalTargetItem.from_parent(
                self,
                name=test_name,
                target_path=target_path,
            )
            item._oys_source = target_path
            item.add_marker(pytest.mark.odisea_gdunit)
            if "stress" in target_path.parts:
                item.add_marker(pytest.mark.odisea_stress)
            items.append(item)

        return items


class OdiseaExternalTargetItem(pytest.Item):
    def __init__(self, *, target_path: Path, **kwargs):
        super().__init__(**kwargs)
        self.target_path = target_path

    def runtest(self):
        selected_runner = self.config.getoption("--odisea-runner")
        if selected_runner != "gdunit":
            pytest.skip("gdunit runner not selected")

        rootpath = Path(self.config.rootpath)
        rel_target = self.target_path
        try:
            rel_target = self.target_path.relative_to(rootpath)
        except ValueError:
            pass

        cmd = ["./runtest.sh"]
        if _odisea_debug_enabled(self.config):
            cmd += ["--show", "--debug"]

        if self.target_path.suffix == ".oys":
            if bool(self.config.getoption("--odisea-editor")):
                cmd += ["--nodet"]
            cmd += ["--oys", _to_oys_selector(self.target_path, rootpath)]
            returncode, _ = stream_process(cmd, file_hint=Path(str(rel_target)))
            if returncode != 0:
                raise RunnerError(
                    f"runtest.sh failed for OYS case '{self.target_path}' with return code {returncode}."
                )
            return

        # .gd execution path
        cmd += ["-a", str(rel_target)]
        returncode, _ = stream_process(cmd, file_hint=Path(str(rel_target)))
        if returncode != 0:
            raise RunnerError(
                f"runtest.sh failed for GdUnit suite '{self.target_path}' with return code {returncode}."
            )

    def reportinfo(self):
        return self.target_path, 0, self.name


def pytest_collect_directory(path: Path, parent):
    config = parent.config
    if not bool(config.getoption("--odisea-editor")):
        return None
    if not _is_core_tests_target_run(config):
        return None
    root_tests = Path(config.rootpath) / "core_v2" / "tests"
    if Path(path) != root_tests:
        return None
    return OdiseaExternalTargetDirectory.from_parent(parent, path=path)


def pytest_collect_file(file_path: Path, parent):
    if file_path.suffix not in {".oys", ".gd"}:
        return None
    config = parent.config
    editor_native_collect = bool(config.getoption("--odisea-editor")) and _is_core_tests_target_run(config)
    if editor_native_collect:
        # Directory-level collector handles this mode to keep tests flat in IDE.
        return None
    if not (_is_direct_external_target_run(config) or editor_native_collect):
        return None
    rootpath = Path(config.rootpath)
    try:
        rel_path = file_path.relative_to(rootpath / "core_v2" / "tests")
    except ValueError:
        return None

    include_stress = bool(config.getoption("--odisea-include-stress")) or os.environ.get(
        "ODISEA_INCLUDE_STRESS", ""
    ).strip().lower() in {"1", "true", "yes", "on"}
    if "stress" in rel_path.parts and not include_stress:
        return None

    if file_path.suffix == ".gd":
        try:
            text = file_path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            return None
        if "GdUnitTestSuite" not in text:
            return None
        # Determinism replay suite is exposed as OYS entries in editor mode.
        if file_path.name == "test_determinism_v2.gd":
            return None

    return OdiseaExternalTargetFile.from_parent(parent, path=file_path)


# ============================================================================
# VSCode Test Explorer: Location remapping for OYS tests
# Tests in test_odisea_runner.py have _oys_source attribute pointing to .oys file
# ============================================================================

def pytest_collection_modifyitems(config, items):
    """Remap OYS test locations for VSCode IDE navigation."""
    runner = config.getoption("--odisea-runner")
    rootpath = Path(config.rootpath)
    editor_mode = bool(config.getoption("--odisea-editor"))
    include_stress = bool(config.getoption("--odisea-include-stress")) or os.environ.get(
        "ODISEA_INCLUDE_STRESS", ""
    ).strip().lower() in {"1", "true", "yes", "on"}
    include_determinism = bool(config.getoption("--odisea-include-determinism")) or os.environ.get(
        "ODISEA_RUN_DETERMINISM", ""
    ).strip().lower() in {"1", "true", "yes", "on"}

    deselected = []
    selected = []
    seen_source_tests: set[str] = set()
    for item in items:
        # Patch location for tests generated from OYS/GD sources to avoid
        # navigation to tests/test_odisea_runner.py in IDE explorers.
        source_path = getattr(item, "_oys_source", None)
        if source_path is None and hasattr(item, "obj") and item.obj is not None:
            source_path = getattr(item.obj, "_oys_source", None)
        if source_path is None and item.name.startswith("test_det__"):
            # Determinism tests are always derived from core_v2/tests/*.oys.
            oys_name = item.name.replace("test_det__", "", 1)
            source_path = rootpath / "core_v2" / "tests" / f"{oys_name}.oys"

        if source_path is not None:
            source_path = Path(source_path)
            try:
                rel_path = source_path.relative_to(rootpath)
            except ValueError:
                rel_path = source_path
            rel_path_str = str(rel_path).replace("\\", "/")
            mapped_location = (rel_path_str, 0, item.name)
            item.location = mapped_location
            item._location = mapped_location
            item._nodeid = f"{rel_path_str}::{item.name}"
            dedupe_key = item._nodeid
            if dedupe_key in seen_source_tests:
                deselected.append(item)
                continue
            seen_source_tests.add(dedupe_key)

        is_gdunit = "odisea_gdunit" in item.keywords
        is_raw_oys = "odisea_raw_oys" in item.keywords

        if is_gdunit and runner != "gdunit":
            deselected.append(item)
            continue
        if is_raw_oys and runner != "raw-oys":
            deselected.append(item)
            continue

        if "odisea_stress" in item.keywords and not include_stress:
            item.add_marker(
                pytest.mark.skip(reason="stress profile disabled by default (use --odisea-include-stress)")
            )
        if "odisea_determinism" in item.keywords and not include_determinism:
            reason = "determinism disabled by configuration (use --odisea-include-determinism or ODISEA_INCLUDE_DETERMINISM=1)"
            if editor_mode:
                reason = "determinism disabled in editor mode by configuration (use --odisea-include-determinism)"
            item.add_marker(
                pytest.mark.skip(reason=reason)
            )
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


@pytest.fixture(scope="session")
def odisea_editor(pytestconfig) -> bool:
    return bool(pytestconfig.getoption("--odisea-editor"))


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
    # In xdist, workers also execute hooks; only controller should write summary.
    if hasattr(config, "workerinput"):
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
        xfailed = len(stats.get("xfailed", []))
        xpassed = len(stats.get("xpassed", []))
        deselected = len(stats.get("deselected", []))
        total_executed = passed + failed + errors + skipped + xfailed + xpassed
        non_passed_total = failed + errors + skipped + xfailed + xpassed

        f.write("| Status | Count |\n")
        f.write("| :--- | :--- |\n")
        f.write(f"| Passed | {passed} |\n")
        f.write(f"| Failed | {failed} |\n")
        f.write(f"| Errors | {errors} |\n")
        f.write(f"| Skipped | {skipped} |\n")
        f.write(f"| XFailed | {xfailed} |\n")
        f.write(f"| XPassed | {xpassed} |\n")
        f.write(f"| Deselected | {deselected} |\n\n")
        f.write(f"**Executed tests:** {total_executed}\n\n")

        status_order = [
            ("error", "ERROR"),
            ("failed", "FAILED"),
            ("xpassed", "XPASSED"),
            ("skipped", "SKIPPED"),
            ("xfailed", "XFAILED"),
            ("passed", "PASSED"),
        ]
        status_icon = {
            "PASSED": "✅",
            "FAILED": "❌",
            "ERROR": "💥",
            "SKIPPED": "⏭️",
            "XFAILED": "🧪",
            "XPASSED": "⚠️",
        }
        status_rank = {
            "ERROR": 0,
            "FAILED": 1,
            "XPASSED": 2,
            "SKIPPED": 3,
            "XFAILED": 4,
            "PASSED": 5,
        }

        def _sanitize(text: str) -> str:
            return re.sub(r"\s+", " ", text).strip()

        def _display_test_name(nodeid: str) -> str:
            # Keep only the changing part: test id without full path and generated hash suffix.
            short = nodeid.split("::")[-1]
            short = re.sub(r"__[0-9a-f]{8}$", "", short)
            return short

        def _first_reason(report: Any) -> str:
            if isinstance(getattr(report, "longrepr", None), tuple):
                longrepr = report.longrepr
                if len(longrepr) >= 3 and longrepr[2]:
                    return _sanitize(str(longrepr[2]))
            longreprtext = getattr(report, "longreprtext", "") or ""
            lines = [line.strip() for line in longreprtext.splitlines() if line.strip()]
            if lines:
                return _sanitize(lines[-1])
            return getattr(report, "outcome", "unknown")

        cases_by_nodeid: dict[str, dict[str, Any]] = {}
        for key, status in status_order:
            for rep in stats.get(key, []):
                nodeid = getattr(rep, "nodeid", "")
                if not nodeid:
                    continue
                duration = float(getattr(rep, "duration", 0.0) or 0.0)
                entry = {
                    "nodeid": nodeid,
                    "display_name": _display_test_name(nodeid),
                    "status": status,
                    "duration": duration,
                    "reason": _first_reason(rep),
                }
                prev = cases_by_nodeid.get(nodeid)
                if prev is None:
                    cases_by_nodeid[nodeid] = entry
                    continue
                prev_rank = status_rank.get(prev["status"], 99)
                new_rank = status_rank.get(status, 99)
                if new_rank < prev_rank:
                    cases_by_nodeid[nodeid] = entry
                elif new_rank == prev_rank and duration > prev["duration"]:
                    cases_by_nodeid[nodeid] = entry

        ordered_cases = sorted(
            cases_by_nodeid.values(),
            key=lambda case: (-case["duration"], status_rank.get(case["status"], 99), case["nodeid"]),
        )

        if ordered_cases:
            f.write("### Execution Table (Slowest First)\n")
            f.write("| # | Test | Status | Duration (s) |\n")
            f.write("|---:|:-----|:-------|-------------:|\n")
            for idx, case in enumerate(ordered_cases, start=1):
                icon = status_icon.get(case["status"], "•")
                f.write(
                    f"| {idx} | `{case['display_name']}` | {icon} {case['status']} | {case['duration']:.2f} |\n"
                )
            f.write("\n")

        if non_passed_total > 0:
            non_passed = [case for case in ordered_cases if case["status"] != "PASSED"]
            f.write("### Non-Passed Summary\n")
            f.write("| # | Test | Status | Duration (s) | Reason |\n")
            f.write("|---:|:-----|:-------|-------------:|:-------|\n")
            for idx, case in enumerate(non_passed, start=1):
                icon = status_icon.get(case["status"], "•")
                reason = case["reason"].replace("|", "\\|")
                f.write(
                    f"| {idx} | `{case['display_name']}` | {icon} {case['status']} | {case['duration']:.2f} | {reason} |\n"
                )
            f.write("\n")

            grouped_reasons: dict[str, dict[str, Any]] = {}
            for case in non_passed:
                reason = case["reason"] or "unknown"
                grouped = grouped_reasons.setdefault(
                    reason, {"count": 0, "max_duration": 0.0, "sample": case["display_name"]}
                )
                grouped["count"] += 1
                grouped["max_duration"] = max(grouped["max_duration"], case["duration"])
            f.write("#### Root Causes (Deduplicated)\n")
            f.write("| Count | Max Duration (s) | Reason | Example Test |\n")
            f.write("|------:|-----------------:|:-------|:-------------|\n")
            for reason, data in sorted(
                grouped_reasons.items(),
                key=lambda item: (-item[1]["count"], -item[1]["max_duration"], item[0]),
            ):
                safe_reason = reason.replace("|", "\\|")
                f.write(
                    f"| {data['count']} | {data['max_duration']:.2f} | {safe_reason} | `{data['sample']}` |\n"
                )
