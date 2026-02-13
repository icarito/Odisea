import pytest
import os
import subprocess
import re
import sys
from pathlib import Path

def pytest_collect_file(parent, file_path):
    # Discovery logic: look for .oys and .json files in 'tests' directories
    if file_path.suffix in [".oys", ".json"] and "tests" in file_path.parts:
        return OysFile.from_parent(parent, path=file_path)

class OysFile(pytest.File):
    def collect(self):
        # One file = One test
        yield OysItem.from_parent(self, name=self.path.name)

class OysItem(pytest.Item):
    def runtest(self):
        godot_bin = os.environ.get("GODOT_BIN", "godot3-bin")
        # Ensure we have a valid binary
        if not os.path.exists(godot_bin) and not _which(godot_bin):
             # Fallback to 'godot' if not found
             godot_bin = "godot"

        # Construct command
        cmd = [
            godot_bin,
            "--headless",
            "--no-window", # Redundant but safe
            "-s",
            "tests/debug_runner.gd",
            "--test-file",
            str(self.path)
        ]

        print(f"[INFO] Executing: {' '.join(cmd)}")

        # Run process with streaming output
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1, # Line buffered
            universal_newlines=True
        )

        # Track errors found in logs
        found_script_error = False
        found_resource_error = False
        found_no_suite_error = False
        captured_failed_asserts = []

        # Stream output
        while True:
            line = process.stdout.readline()
            if not line and process.poll() is not None:
                break
            if line:
                # Check for critical errors (ported from runtest.sh validate_logs)
                if "SCRIPT ERROR:" in line:
                    found_script_error = True
                if "Failed to load resource" in line or "referenced nonexistent resource" in line:
                    found_resource_error = True
                if "No test suites found" in line:
                    found_no_suite_error = True

                # Capture assertion failures for report
                if "ASSERT FAILED" in line or "Assertion failed" in line:
                    clean_assert = re.sub(r'\x1b\[[0-9;]*m', '', line).strip()
                    captured_failed_asserts.append(clean_assert)

                # Filter out known headless spam
                if "VisualServer attempted to free a NULL RID" in line or \
                   "at: free (servers/visual/visual_server_raster.cpp:69)" in line:
                    continue

                # Clean ANSI codes
                clean_line = re.sub(r'\x1b\[[0-9;]*m', '', line).rstrip()
                print(clean_line) # Print to pytest stdout

                # GitHub Actions Annotations
                if os.environ.get("GITHUB_ACTIONS") == "true":
                    if "[ERROR]" in clean_line:
                        print(f"::error file={self.path}::{clean_line}")
                    elif "[WARNING]" in clean_line:
                        print(f"::warning file={self.path}::{clean_line}")

        returncode = process.poll()

        # Check exit code and log errors
        if returncode != 0:
            if returncode == 1:
                # 1 = Assertion Failed -> pytest.fail (Failure)
                failure_msg = f"Test failed with return code {returncode}. Check logs for [ERROR]."
                if captured_failed_asserts:
                    failure_msg += "\nCaptured Failures:\n" + "\n".join(captured_failed_asserts)
                pytest.fail(failure_msg, pytrace=False)
            else:
                # Other = Crash or script error -> Exception (Error)
                raise OysCrashError(f"Test crashed/error with return code {returncode}.")

        # Even if exit code is 0, check for critical errors found in logs
        if found_script_error:
             raise OysCrashError("SCRIPT ERROR detected in logs (failing run).")
        if found_resource_error:
             raise OysCrashError("Resource loading error detected in logs (failing run).")
        if found_no_suite_error:
             raise OysCrashError("No test suites found (failing run).")

    def repr_failure(self, excinfo):
        """Called when self.runtest() raises an exception."""
        if isinstance(excinfo.value, OysCrashError):
            return f"Godot Engine Crash: {excinfo.value}"
        return super().repr_failure(excinfo)

    def reportinfo(self):
        return self.path, 0, f"OYS: {self.name}"

class OysCrashError(Exception):
    pass

def _which(program):
    def is_exe(fpath):
        return os.path.isfile(fpath) and os.access(fpath, os.X_OK)

    fpath, fname = os.path.split(program)
    if fpath:
        if is_exe(program):
            return program
    else:
        for path in os.environ["PATH"].split(os.pathsep):
            exe_file = os.path.join(path, program)
            if is_exe(exe_file):
                return exe_file
    return None

# Hook to generate GitHub Job Summary
def pytest_terminal_summary(terminalreporter, exitstatus, config):
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        summary_file = os.environ["GITHUB_STEP_SUMMARY"]
        with open(summary_file, "a", encoding="utf-8") as f:
            f.write(f"## 🧪 Pytest Results (OYS)\n")
            f.write(f"**Exit Status:** {exitstatus}\n\n")

            stats = terminalreporter.stats
            passed = len(stats.get('passed', []))
            failed = len(stats.get('failed', []))
            errors = len(stats.get('error', []))
            skipped = len(stats.get('skipped', []))

            f.write(f"| Status | Count |\n")
            f.write(f"| :--- | :--- |\n")
            f.write(f"| ✅ Passed | {passed} |\n")
            f.write(f"| ❌ Failed | {failed} |\n")
            f.write(f"| 💥 Errors | {errors} |\n")
            f.write(f"| ⏭️ Skipped | {skipped} |\n\n")

            if failed > 0 or errors > 0:
                f.write("### 🚨 Failures & Errors\n")

                for rep in stats.get('failed', []):
                    f.write(f"- ❌ **FAILED:** `{rep.nodeid}`\n")
                    # Ideally we'd extract the message here but rep.longrepr might be complex

                for rep in stats.get('error', []):
                    f.write(f"- 💥 **ERROR:** `{rep.nodeid}`\n")
