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

        # Stream output
        while True:
            line = process.stdout.readline()
            if not line and process.poll() is not None:
                break
            if line:
                # Filter out known headless spam
                if "VisualServer attempted to free a NULL RID" in line:
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

        # Check exit code
        if returncode != 0:
            if returncode == 1:
                # 1 = Assertion Failed -> pytest.fail (Failure)
                pytest.fail(f"Test failed with return code {returncode}. Check logs for [ERROR].", pytrace=False)
            else:
                # Other = Crash or script error -> Exception (Error)
                raise OysCrashError(f"Test crashed/error with return code {returncode}.")

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
