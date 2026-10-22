#!/usr/bin/env python3
"""Runs one Peregrine test through go-ios on a phone that already has the runner installed.

Every PEREGRINE_* variable in this process's environment is handed to the runner. The runner's
NSLog output is streamed to stdout, and the run ends with ** TEST SUCCEEDED ** or ** TEST FAILED **
like xcodebuild, exiting 0 or 65.
"""

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time

sys.dont_write_bytecode = True

from core import DEVIMAGES_DIR, RUN_DIR, RUNNER_CONTAINER, TESTS, ensure_tunnel, go_ios, go_ios_env, tunnel_info_args  # noqa: E402

XCTEST_CONFIG = "PeregrineRunner.xctest"
FAILED_CODE = 65
# Runner NSLog lines carry a full date; XCTest's own debug lines carry only the time of day.
NSLOG_RE = re.compile(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+[+-]\d{4} ")
XCTEST_RE = re.compile(r"^\d\d:\d\d:\d\d\.\d{3} ")
# go-ios before 1.1 prints the results as a Go struct instead of JSON.
GO_CASE_RE = re.compile(
    r"\{ClassName:(\S+) MethodName:(\S+) Status:(\S+) Err:\{Message:(.*?) File:\S* Line:\d+} Duration:(\S+)"
)
GO_DURATION_RE = re.compile(r"(\d+(?:\.\d+)?)(h|ms|us|µs|ns|m|s)")
GO_UNITS = {"h": 3600, "m": 60, "s": 1, "ms": 1e-3, "us": 1e-6, "µs": 1e-6, "ns": 1e-9}


def go_seconds(text):
    return sum(float(number) * GO_UNITS[unit] for number, unit in GO_DURATION_RE.findall(text))


def parse_cases(output):
    for line in reversed(output):
        if line.startswith("[{\""):
            try:
                results = json.loads(line)
            except ValueError:
                continue
            return [
                {
                    "class": case.get("ClassName"),
                    "method": case.get("MethodName"),
                    "status": case.get("Status") or "unknown",
                    "message": (case.get("Err") or {}).get("Message") or "",
                    "seconds": (case.get("Duration") or 0) / 1e9,
                }
                for suite in results
                for case in suite.get("TestCases") or []
            ]
        if line.startswith("[{Name:"):
            return [
                {"class": c, "method": m, "status": s, "message": e.strip(), "seconds": go_seconds(d)}
                for c, m, s, e, d in GO_CASE_RE.findall(line)
            ]
    return []


def emit(text):
    sys.stdout.write(text)
    sys.stdout.flush()


class RunnerLog:
    """Follows the go-ios log file and keeps the runner's own lines."""

    def __init__(self, path):
        self.path = path
        self.offset = 0
        self.pending = ""
        self.keep = False

    def drain(self, final=False):
        try:
            with open(self.path, "r", encoding="utf-8", errors="replace") as handle:
                handle.seek(self.offset)
                chunk = handle.read()
                self.offset = handle.tell()
        except OSError:
            return
        lines = (self.pending + chunk).split("\n")
        self.pending = "" if final else lines.pop()
        for line in lines:
            if NSLOG_RE.match(line):
                self.keep = True
            elif XCTEST_RE.match(line):
                self.keep = False
            if self.keep and line:
                emit(line + "\n")


def prepare(udid):
    go = go_ios()
    ensure_tunnel(udid)
    os.makedirs(RUN_DIR, exist_ok=True)
    image = [go, "image", "auto", "--basedir=%s" % DEVIMAGES_DIR, "--udid=%s" % udid]
    if os.name == "nt":
        image.extend(tunnel_info_args())
        completed = subprocess.run(
            image,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            encoding="utf-8",
            errors="replace",
            env=go_ios_env(),
            creationflags=subprocess.CREATE_NO_WINDOW,
            timeout=300,
            check=False,
        )
    else:
        completed = subprocess.run(
            image,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=300,
            check=False,
        )
    if completed.returncode != 0:
        lines = (completed.stdout or "").strip().splitlines()
        raise RuntimeError("挂载开发者磁盘映像失败：%s" % (lines[-1] if lines else completed.returncode))
    return go


def runtest_command(go, udid, test, log_path):
    command = [
        go,
        "runtest",
        "--udid=%s" % udid,
        "--test-runner-bundle-id=%s" % RUNNER_CONTAINER,
        "--xctest-config=%s" % XCTEST_CONFIG,
        "--test-to-run=%s" % TESTS[test].split("/", 1)[1],
        "--log-output=%s" % log_path,
        "--nojson",
    ]
    if os.name == "nt":
        command.extend(tunnel_info_args())
    bundle_id = os.environ.get("PEREGRINE_BUNDLEID", "")
    if bundle_id:
        command.append("--bundle-id=%s" % bundle_id)
    for key in sorted(os.environ):
        if key.startswith("PEREGRINE_") and key != "PEREGRINE_BACKEND" and os.environ[key]:
            command.append("--env=%s=%s" % (key, os.environ[key]))
    return command


def report(output, code):
    """Prints the test case results go-ios returns and gives the exit code."""
    cases = parse_cases(output)
    if not cases and code < 0:
        emit("go-ios runtest stopped by signal %d\n** TEST INTERRUPTED **\n" % -code)
        return 128 - code
    if not cases:
        errors = [line for line in output if re.search(r"level=(error|fatal)", line, re.IGNORECASE)]
        emit("go-ios runtest exit %d%s\n" % (code, (": " + errors[-1]) if errors else ""))
        emit("** TEST FAILED **\n")
        return code or FAILED_CODE
    passed = True
    for case in cases:
        emit("Test Case '-[%s %s]' %s (%.3f seconds).\n" % (case["class"], case["method"], case["status"], case["seconds"]))
        if case["message"]:
            emit("%s\n" % case["message"])
        passed = passed and case["status"] == "passed"
    emit("** TEST SUCCEEDED **\n" if passed else "** TEST FAILED **\n")
    return 0 if passed else FAILED_CODE


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--udid", required=True)
    parser.add_argument("--test", choices=sorted(TESTS), default="explore")
    args = parser.parse_args()
    try:
        go = prepare(args.udid)
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
        emit("%s\n** TEST FAILED **\n" % exc)
        return 1
    emit("go-ios runtest %s\n" % TESTS[args.test])

    code = 1
    with tempfile.TemporaryDirectory() as scratch:
        log_path = os.path.join(scratch, "runner.log")
        command = runtest_command(go, args.udid, args.test, log_path)
        if os.name == "nt":
            proc = subprocess.Popen(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                encoding="utf-8",
                errors="replace",
                env=go_ios_env(),
                creationflags=subprocess.CREATE_NO_WINDOW,
            )
        else:
            proc = subprocess.Popen(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                errors="replace",
            )

        def forward(_signum, _frame):
            # go-ios ends the runner on the device when it is interrupted.
            if os.name == "nt":
                proc.terminate()
            else:
                proc.send_signal(signal.SIGINT)

        # Ctrl+C and the launch page's stop reach go-ios through the shared process group.
        for name in ("SIGINT", "SIGBREAK"):
            if hasattr(signal, name):
                signal.signal(getattr(signal, name), lambda _signum, _frame: None)
        signal.signal(signal.SIGTERM, forward)

        output = []
        reader = threading.Thread(target=lambda: output.extend(line.rstrip("\n") for line in proc.stdout), daemon=True)
        reader.start()
        follower = RunnerLog(log_path)
        while proc.poll() is None:
            follower.drain()
            time.sleep(0.3)
        reader.join(5)
        follower.drain(final=True)
        code = report(output, proc.returncode)
    return code


if __name__ == "__main__":
    sys.exit(main())
