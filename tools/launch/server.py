#!/usr/bin/env python3
"""Local page that fills the bundle id, duration, and throttle, then runs the test on the phone."""

import json
import os
import re
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse

sys.dont_write_bytecode = True

from core import (  # noqa: E402
    BUNDLE_RE,
    COLLECT_TIMEOUT,
    DURATION_MAX,
    IOS_DIR,
    RUN_DIR,
    SHOTS_MODES,
    STAMP_RE,
    TESTS,
    THROTTLE_MAX,
    FieldError,
    backend,
    check_paths,
    collect_command,
    is_simulator,
    is_target,
    keep_runs_count,
    list_apps,
    list_devices,
    new_stamp,
    probe_stub,
    prune_runs,
    pull_device_files,
    pull_report,
    run_artifacts,
    run_command,
    run_paths,
    signing_team,
    RunOutput,
    spawn_output,
    stub_preflight,
    test_command,
    test_environment,
    tool_path,
    whole_number,
    write_export,
)
from perf import HostPerf, installed_pymobiledevice3, perf_report_line, pymobiledevice3  # noqa: E402

WEB_DIR = os.path.join(os.path.dirname(__file__), "web")
INDEX_PATH = os.path.join(WEB_DIR, "index.html")
DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 8765
LOG_LIMIT = 200000
START_BODY_LIMIT = 65536
STATE_PATH = os.path.join(RUN_DIR, "launch-state.json")


def listen_address():
    host = os.environ.get("PEREGRINE_LAUNCH_HOST") or DEFAULT_HOST
    text = os.environ.get("PEREGRINE_LAUNCH_PORT") or str(DEFAULT_PORT)
    try:
        port = int(text)
    except ValueError:
        raise SystemExit("PEREGRINE_LAUNCH_PORT 不是整数：%s" % text)
    if port < 1 or port > 65535:
        raise SystemExit("PEREGRINE_LAUNCH_PORT 超出范围：%s" % port)
    return host, port


def lan_address():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("1.1.1.1", 80))
        address = sock.getsockname()[0]
    except OSError:
        return ""
    finally:
        sock.close()
    return "" if address.startswith("127.") else address


def load_state():
    data = {}
    try:
        with open(STATE_PATH, "r", encoding="utf-8") as handle:
            loaded = json.load(handle)
        if isinstance(loaded, dict):
            data = loaded
    except (OSError, json.JSONDecodeError):
        data = {}
    duration = data.get("duration", 1)
    throttle = data.get("throttle", 300)
    dataport = data.get("dataport", 0)
    stamp = str(data.get("stamp") or "")
    if not STAMP_RE.match(stamp):
        match = re.search(r"run-(\d{8}-\d{6})\.log$", str(data.get("logPath") or ""))
        stamp = match.group(1) if match else ""
    return {
        "udid": data.get("udid") if isinstance(data.get("udid"), str) else "",
        "bundleId": data.get("bundleId") if isinstance(data.get("bundleId"), str) else "",
        "duration": duration if isinstance(duration, int) and duration > 0 else 1,
        "throttle": throttle if isinstance(throttle, int) and throttle > 0 else 300,
        "dataport": dataport if isinstance(dataport, int) and 0 <= dataport <= 65535 else 0,
        "pid": data.get("pid") if isinstance(data.get("pid"), int) else 0,
        "logPath": data.get("logPath") if isinstance(data.get("logPath"), str) else "",
        "stamp": stamp,
        "test": data.get("test") if data.get("test") in TESTS else "explore",
        "shots": data.get("shots") if data.get("shots") in SHOTS_MODES else "off",
        "perf": bool(data.get("perf")),
        # Missing means a state file written before resume-collect. Do not pull again.
        "collected": True if "collected" not in data else bool(data.get("collected")),
        "since": str(data.get("since") or ""),
    }


def save_state(state):
    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    temporary = STATE_PATH + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False, indent=2)
    os.replace(temporary, STATE_PATH)


def process_command(pid):
    if pid <= 0 or os.name == "nt":
        return ""
    try:
        code, output, _ = run_command(["ps", "-p", str(pid), "-o", "command="], 5)
    except OSError:
        return ""
    if code != 0:
        return ""
    return output.strip()


class Session:
    def __init__(self):
        self.lock = threading.Lock()
        self.proc = None
        self.master = None
        self.log = ""
        self.exit_code = None
        self.collecting = False
        self.perf_install = None
        self.perf_install_error = ""
        self.prefs = load_state()
        self._adopt()

    def _adopt(self):
        pid = self.prefs.get("pid") or 0
        command = process_command(pid)
        alive = ("xcodebuild" in command and "PeregrineRunner" in command) or "runtest.py" in command
        if alive:
            self.exit_code = None
            self.proc = _AdoptedProcess(pid)
            log_path = self.prefs.get("logPath") or ""
            if os.path.isfile(log_path):
                with open(log_path, "r", encoding="utf-8", errors="replace") as handle:
                    self.log = handle.read()[-LOG_LIMIT:]
        else:
            self.prefs["pid"] = 0
            self.proc = None
        if self._should_collect_locked():
            self._start_collect_thread(self.proc)

    def _should_collect_locked(self):
        prefs = self.prefs
        stamp = prefs.get("stamp") or ""
        return (
            not prefs.get("collected")
            and prefs.get("test") == "explore"
            and bool(STAMP_RE.match(stamp))
            and is_target(prefs.get("udid") or "")
            and BUNDLE_RE.match(prefs.get("bundleId") or "") is not None
        )

    def _start_collect_thread(self, proc):
        paths = run_paths(self.prefs["stamp"])
        crash = {
            "udid": self.prefs["udid"],
            "bundleId": self.prefs["bundleId"],
            "since": self.prefs.get("since") or str(time.time()),
            "out": paths["crash"],
            "deviceOut": paths["device"],
            "hostPerf": None,
            "perf": bool(self.prefs.get("perf")),
        }
        log_path = self.prefs.get("logPath") or paths["log"]
        thread = threading.Thread(target=self._collect_when_done, args=(proc, log_path, crash), daemon=True)
        thread.start()

    def _collect_when_done(self, proc, log_path, crash):
        if proc is not None:
            proc.wait()
        with self.lock:
            if self.prefs.get("collected"):
                return
            self.collecting = crash is not None
            if self.proc is proc:
                self._finish_locked()
        if crash is None:
            return
        try:
            self._append_log(log_path, "\nlaunch resumed collect\n")
            if crash.get("perf"):
                self._append_log(log_path, "perf host skipped: 启动页重启后采样进程已经不在\n")
            self._pull_device_files(log_path, crash)
            if crash.get("perf"):
                self._append_log(log_path, perf_report_line(crash["deviceOut"]) + "\n")
            self._collect_crashes(log_path, crash)
        finally:
            self._mark_collected()

    def status(self):
        with self.lock:
            running = self._running_locked()
            log_path = self.prefs.get("logPath") or ""
            payload = {
                "running": running,
                "collecting": self.collecting,
                "exitCode": None if running or self.collecting else self.exit_code,
                "log": self.log[-12000:],
                "hasLog": len(self.log) > 0 or os.path.isfile(log_path),
                "hasExport": not running and not self.collecting and self._export_stamp_locked() != "",
                "udid": self.prefs.get("udid") or "",
                "bundleId": self.prefs.get("bundleId") or "",
                "duration": self.prefs.get("duration") or 1,
                "throttle": self.prefs.get("throttle") or 300,
                "dataport": self.prefs.get("dataport") or 0,
                "test": self.prefs.get("test") or "explore",
                "shots": self.prefs.get("shots") or "off",
                "perf": bool(self.prefs.get("perf")),
                "stubCheck": self.prefs.get("stubCheck") or "",
                "backend": backend(),
                "simulator": is_simulator(self.prefs.get("udid") or ""),
            }
        return payload

    def log_text(self):
        with self.lock:
            log_path = self.prefs.get("logPath") or ""
            if os.path.isfile(log_path):
                with open(log_path, "r", encoding="utf-8", errors="replace") as handle:
                    text = handle.read()
            else:
                text = self.log
        return text

    def _export_stamp_locked(self):
        stamp = self.prefs.get("stamp") or ""
        if not stamp or not any(os.path.exists(path) for path in run_artifacts(stamp)):
            return ""
        return stamp

    def export_stamp(self):
        with self.lock:
            if self._running_locked() or self.collecting:
                raise RuntimeError("这一轮还没结束，结束并收集完后再导出")
            stamp = self._export_stamp_locked()
        if not stamp:
            raise RuntimeError("还没有可导出的运行结果")
        return stamp

    def start(self, udid, bundle_id, duration, throttle, dataport, test="explore", shots="off", perf=False):
        if test not in TESTS:
            raise RuntimeError("没有这种测试：%s" % test)
        if shots not in SHOTS_MODES:
            raise FieldError("shots", "截图只能是 %s" % "、".join(SHOTS_MODES))
        if not is_target(udid):
            raise FieldError("device", "先选择一台设备")
        # 0 表示不用 stub，Peregrine 走截图切分。
        dataport = whole_number(dataport or 0, "dataport", 0, 65535, "数据端口")
        if test == "explore":
            duration = whole_number(duration, "duration", 1, DURATION_MAX, "duration ")
            throttle = whole_number(throttle, "throttle", 1, THROTTLE_MAX, "throttle ")
        else:
            duration = self.prefs.get("duration") or 1
            throttle = self.prefs.get("throttle") or 300
            if dataport == 0:
                bundle_id = ""
        needs_bundle = test == "explore" or dataport > 0
        if needs_bundle and BUNDLE_RE.match(bundle_id or "") is None:
            raise FieldError("bundle", "先选择一个 Bundle ID")
        if needs_bundle:
            try:
                installed = {app["bundleId"] for app in list_apps(udid)}
            except RuntimeError as exc:
                raise FieldError("device", "这台设备暂时读不到应用") from exc
            if bundle_id not in installed:
                raise FieldError("bundle", "这台设备上没有 %s" % bundle_id)
        with self.lock:
            self._ensure_idle_locked()
        port, preface = dataport, ""
        if test == "explore":
            port, preface = stub_preflight(udid, bundle_id, dataport)
        perf = bool(perf) and test == "explore"
        host_perf, perf_note = None, ""
        if perf and is_simulator(udid):
            perf_note = "perf host skipped: 模拟器没有 Instruments 通道\n"
        elif perf:
            host_perf, perf_note = self._prepare_host_perf(udid, bundle_id)
        team = signing_team()
        with self.lock:
            self._ensure_idle_locked()
            self._spawn(udid, bundle_id, duration, throttle, dataport, team, test, port, preface, shots, perf, host_perf, perf_note)
        return self.status()

    def _prepare_host_perf(self, udid, bundle_id):
        """The first install takes minutes, so it runs in the background and this run goes without host sampling."""
        tool = installed_pymobiledevice3()
        if not tool:
            note = "perf host skipped: pymobiledevice3 安装中，完成后下一轮可用\n"
            with self.lock:
                if self.perf_install is None or not self.perf_install.is_alive():
                    if self.perf_install_error:
                        note = "perf host skipped: pymobiledevice3 上次安装失败：%s；已重新开始安装，完成后下一轮可用\n" % self.perf_install_error
                    self.perf_install_error = ""
                    self.perf_install = threading.Thread(target=self._install_perf_tool, daemon=True)
                    self.perf_install.start()
            return None, note
        host_perf = HostPerf(udid, bundle_id, tool)
        try:
            host_perf.prepare()
        except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
            return None, "perf host skipped: %s\n" % exc
        return host_perf, ""

    def _install_perf_tool(self):
        try:
            pymobiledevice3()
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
            sys.stderr.write("perf tool install failed: %s\n" % exc)
            with self.lock:
                self.perf_install_error = str(exc) or type(exc).__name__

    def check_stub(self, udid, bundle_id, dataport):
        if not is_target(udid):
            raise FieldError("device", "先选择一台设备")
        if BUNDLE_RE.match(bundle_id or "") is None:
            raise FieldError("bundle", "先选择一个 Bundle ID")
        dataport = whole_number(dataport or 0, "dataport", 1, 65535, "数据端口")
        with self.lock:
            self._ensure_idle_locked()
        return probe_stub(udid, bundle_id, dataport)

    def _ensure_idle_locked(self):
        if self._running_locked():
            raise RuntimeError("已有一轮测试在跑")
        if self.collecting:
            raise RuntimeError("上一轮还在收集崩溃日志")

    def stop(self):
        with self.lock:
            proc = self.proc
            running = proc is not None and proc.poll() is None
            pid = proc.pid if running else 0
        if not running:
            return self.status()
        if os.name == "nt":
            steps = (lambda: proc.send_signal(signal.CTRL_BREAK_EVENT), proc.terminate, proc.kill)
        else:
            steps = tuple((lambda sig=sig: os.killpg(pid, sig)) for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGKILL))
        for step in steps:
            try:
                step()
            except (ProcessLookupError, OSError):
                break
            if _wait_until(proc, 3):
                break
        with self.lock:
            self._finish_locked()
        return self.status()

    def _running_locked(self):
        return self.proc is not None and self.proc.poll() is None

    def _spawn(self, udid, bundle_id, duration, throttle, dataport, team, test, port, preface, shots, perf=False, host_perf=None, perf_note=""):
        os.makedirs(RUN_DIR, exist_ok=True)
        stub_check = preface.strip()
        preface += perf_note
        keep = keep_runs_count()
        pruned = prune_runs(keep - 1 if keep > 0 else 0)
        if pruned > 0:
            preface += "runs pruned %d keep %d\n" % (pruned, keep)
        stamp = new_stamp()
        paths = run_paths(stamp) if test == "explore" else check_paths(stamp)
        log_path = paths["log"]
        command = test_command(udid, test, paths["xcresult"], team)
        if test == "explore":
            environment = test_environment(bundle_id, duration, throttle, port, None, shots, perf)
        else:
            environment = test_environment(bundle_id, 0, 0, port)
        if host_perf is not None:
            try:
                host_perf.start(paths["device"])
                preface += "perf host start %s\n" % host_perf.name
            except (OSError, ValueError) as exc:
                host_perf.stop()
                host_perf = None
                preface += "perf host skipped: %s\n" % exc
        try:
            proc, master = spawn_output(command, environment, IOS_DIR, True)
        except BaseException:
            if host_perf is not None:
                host_perf.stop()
            raise
        self.proc = proc
        self.master = master
        self.log = preface
        self.exit_code = None
        self.prefs = {
            "udid": udid,
            "bundleId": bundle_id or self.prefs.get("bundleId") or "",
            "duration": duration,
            "throttle": throttle,
            "dataport": dataport,
            "pid": proc.pid,
            "logPath": log_path,
            "stamp": stamp if test == "explore" else "",
            "test": test,
            "shots": shots if test == "explore" else self.prefs.get("shots") or "off",
            "perf": perf if test == "explore" else bool(self.prefs.get("perf")),
            "collected": test != "explore",
            "since": str(time.time()) if test == "explore" else "",
            "stubCheck": stub_check,
        }
        save_state(self.prefs)
        crash = None
        if test == "explore":
            crash = {
                "udid": udid,
                "bundleId": bundle_id,
                "since": self.prefs["since"],
                "out": paths["crash"],
                "deviceOut": paths["device"],
                "hostPerf": host_perf,
                "perf": perf,
            }
        thread = threading.Thread(target=self._read_output, args=(master, log_path, proc, crash, preface), daemon=True)
        thread.start()

    def _append_log(self, log_path, text):
        with open(log_path, "a", encoding="utf-8", errors="replace") as handle:
            handle.write(text)
        with self.lock:
            self.log = (self.log + text)[-LOG_LIMIT:]

    def _pull_device_files(self, log_path, crash):
        try:
            copied, missing = pull_device_files(crash["udid"], crash["bundleId"], crash["deviceOut"])
            line = pull_report(copied, missing)
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
            line = "device files failed: %s\n" % exc
        self._append_log(log_path, "\n" + line)

    def _collect_crashes(self, log_path, crash):
        if is_simulator(crash.get("udid") or ""):
            self._append_log(log_path, "\ncrash collect skipped: 模拟器不拉取系统崩溃日志\n")
            return
        self._append_log(log_path, "\ncrash collect start\n")
        command = collect_command(crash["udid"], crash["bundleId"], crash["since"], log_path, crash["out"])
        try:
            if os.name == "nt":
                completed = subprocess.run(
                    command,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    encoding="utf-8",
                    errors="replace",
                    timeout=COLLECT_TIMEOUT,
                    check=False,
                )
            else:
                completed = subprocess.run(
                    command,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    timeout=COLLECT_TIMEOUT,
                    check=False,
                )
            output = completed.stdout
        except (OSError, subprocess.TimeoutExpired) as exc:
            output = "crash collect failed: %s\n" % exc
        self._append_log(log_path, output if output.endswith("\n") else output + "\n")

    def _read_output(self, master, log_path, proc, crash, preface):
        output = RunOutput()
        with open(log_path, "w", encoding="utf-8", errors="replace", newline="\n") as handle:
            handle.write(preface)
            while True:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                text = output.feed(chunk)
                handle.write(text)
                handle.flush()
                with self.lock:
                    self.log = (self.log + text)[-LOG_LIMIT:]
            text = output.finish()
            handle.write(text)
            with self.lock:
                self.log = (self.log + text)[-LOG_LIMIT:]
        try:
            os.close(master)
        except OSError:
            pass
        proc.wait()
        with self.lock:
            self.collecting = crash is not None
            if self.proc is proc:
                self._finish_locked()
        if crash is None:
            return
        try:
            host_perf = crash.get("hostPerf")
            if host_perf is not None:
                host_perf.stop()
                self._append_log(log_path, host_perf.line() + "\n")
            self._pull_device_files(log_path, crash)
            if crash.get("perf"):
                self._append_log(log_path, perf_report_line(crash["deviceOut"]) + "\n")
            self._collect_crashes(log_path, crash)
        finally:
            self._mark_collected()

    def _mark_collected(self):
        with self.lock:
            self.collecting = False
            self.prefs["collected"] = True
            save_state(self.prefs)

    def _finish_locked(self):
        if self.proc is not None:
            self.exit_code = self.proc.poll()
        self.prefs["pid"] = 0
        save_state(self.prefs)


class _AdoptedProcess:
    def __init__(self, pid):
        self.pid = pid

    def poll(self):
        try:
            os.kill(self.pid, 0)
        except ProcessLookupError:
            return 0
        except PermissionError:
            return None
        return None

    def wait(self, timeout=None):
        deadline = None if timeout is None else time.time() + timeout
        while self.poll() is None:
            if deadline is not None and time.time() >= deadline:
                raise subprocess.TimeoutExpired("xcodebuild", timeout)
            time.sleep(0.2)
        return self.poll()


def _wait_until(proc, seconds):
    try:
        proc.wait(timeout=seconds)
        return True
    except subprocess.TimeoutExpired:
        return False


RUNNER = Session()


# noinspection PyPep8Naming
class Handler(BaseHTTPRequestHandler):
    def __init__(self, request: Any, client_address: Any, server: ThreadingHTTPServer) -> None:
        super().__init__(request, client_address, server)

    def do_GET(self):
        path = urlparse(self.path).path
        static = {
            "/": (INDEX_PATH, "text/html; charset=utf-8"),
            "/launch.css": (os.path.join(WEB_DIR, "launch.css"), "text/css; charset=utf-8"),
            "/launch.js": (os.path.join(WEB_DIR, "launch.js"), "text/javascript; charset=utf-8"),
            "/favicon.svg": (os.path.join(WEB_DIR, "favicon.svg"), "image/svg+xml"),
            "/favicon-32.png": (os.path.join(WEB_DIR, "favicon-32.png"), "image/png"),
            "/favicon.ico": (os.path.join(WEB_DIR, "favicon-32.png"), "image/png"),
            "/apple-touch-icon.png": (os.path.join(WEB_DIR, "apple-touch-icon.png"), "image/png"),
        }
        if path in static:
            self._send_file(*static[path])
            return
        if path == "/api/devices":
            self._send_devices()
            return
        if path == "/api/apps":
            self._send_apps()
            return
        if path == "/api/status":
            self._send_json(200, RUNNER.status())
            return
        if path == "/api/log":
            self._send_log()
            return
        if path == "/api/export":
            self._send_export()
            return
        if path == "/api/stub":
            self._send_stub()
            return
        self._send_json(404, {"error": "没有这个地址"})

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/start":
            self._start()
            return
        if path == "/api/stop":
            self._send_json(200, RUNNER.stop())
            return
        self._send_json(404, {"error": "没有这个地址"})

    def _send_devices(self):
        try:
            devices = list_devices()
        except (RuntimeError, subprocess.TimeoutExpired) as exc:
            self._send_json(500, {"error": str(exc)})
            return
        body = RUNNER.status()
        body["devices"] = devices
        self._send_json(200, body)

    def _send_apps(self):
        query = parse_qs(urlparse(self.path).query)
        udid = (query.get("udid") or [""])[0]
        try:
            apps = list_apps(udid)
        except (RuntimeError, subprocess.TimeoutExpired) as exc:
            self._send_json(500, {"error": str(exc)})
            return
        self._send_json(200, {"apps": apps})

    def _start(self):
        try:
            length = int(self.headers.get("Content-Length") or "0")
        except (TypeError, ValueError):
            self._send_json(400, {"error": "Content-Length 不是整数"})
            return
        if length < 0:
            self._send_json(400, {"error": "Content-Length 不能为负数"})
            return
        if length > START_BODY_LIMIT:
            self._send_json(413, {"error": "请求体过大"})
            return
        raw = self.rfile.read(length) if length > 0 else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._send_json(400, {"error": "请求不是 JSON"})
            return
        if not isinstance(payload, dict):
            self._send_json(400, {"error": "请求必须是 JSON 对象"})
            return
        try:
            status = RUNNER.start(
                payload.get("udid") or "",
                payload.get("bundleId") or "",
                payload.get("duration"),
                payload.get("throttle"),
                payload.get("dataport"),
                payload.get("test") or "explore",
                payload.get("shots") or "off",
                payload.get("perf") is True,
            )
        except FieldError as exc:
            self._send_json(400, {"error": str(exc), "field": exc.field})
            return
        except (RuntimeError, subprocess.TimeoutExpired) as exc:
            self._send_json(400, {"error": str(exc)})
            return
        self._send_json(200, status)

    def _send_log(self):
        text = RUNNER.log_text()
        data = text.encode("utf-8")
        query = parse_qs(urlparse(self.path).query)
        download = (query.get("download") or [""])[0] in ("1", "true", "yes")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        if download:
            self.send_header("Content-Disposition", 'attachment; filename="peregrine-run.log"')
        self.end_headers()
        self.wfile.write(data)

    def _send_stub(self):
        query = parse_qs(urlparse(self.path).query)
        value = lambda key: (query.get(key) or [""])[0]
        try:
            check = RUNNER.check_stub(value("udid"), value("bundleId"), value("dataport"))
        except FieldError as exc:
            self._send_json(400, {"error": str(exc), "field": exc.field})
            return
        except (RuntimeError, subprocess.TimeoutExpired) as exc:
            self._send_json(400, {"error": str(exc)})
            return
        self._send_json(200, check)

    def _send_export(self):
        try:
            stamp = RUNNER.export_stamp()
        except RuntimeError as exc:
            self._send_json(409, {"error": str(exc)})
            return
        with tempfile.TemporaryFile() as handle:
            try:
                write_export(stamp, handle)
            except OSError as exc:
                self._send_json(500, {"error": "打包失败：%s" % exc})
                return
            size = handle.tell()
            handle.seek(0)
            self.send_response(200)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Content-Length", str(size))
            self.send_header("Content-Disposition", 'attachment; filename="peregrine-run-%s.zip"' % stamp)
            self.end_headers()
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                self.wfile.write(chunk)

    def _send_file(self, path, content_type):
        try:
            with open(path, "rb") as handle:
                data = handle.read()
        except OSError:
            self._send_json(500, {"error": "页面文件打不开"})
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(data)

    def _send_json(self, status, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        return


def main():
    tool_path()
    os.makedirs(RUN_DIR, exist_ok=True)
    host, port = listen_address()
    server = ThreadingHTTPServer((host, port), Handler)
    local = "http://127.0.0.1:%s/" % port
    print("Peregrine 启动页 %s（%s）" % (local, backend()), flush=True)
    if host not in ("127.0.0.1", "::1"):
        lan = lan_address()
        if lan:
            print("局域网 %s" % ("http://%s:%s/" % (lan, port)), flush=True)
        elif host == "0.0.0.0":
            print("局域网 http://<本机局域网地址>:%s/" % port, flush=True)
        else:
            print("局域网 %s" % ("http://%s:%s/" % (host, port)), flush=True)
    skip_browser = os.environ.get("PEREGRINE_LAUNCH_NO_BROWSER")
    if skip_browser != "1":
        threading.Timer(0.4, lambda: webbrowser.open(local)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n启动页已关闭")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
