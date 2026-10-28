"""Device, build, and result helpers shared by the launch page and the command line."""

import codecs
import csv
import hashlib
import io
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import zipfile
from datetime import datetime

from models import marketing_name

try:
    import pty
except ImportError:
    pty = None

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
IOS_DIR = os.path.join(ROOT, "Peregrine")
LAUNCH_DIR = os.path.dirname(os.path.abspath(__file__))
# .run is only logs. Delete it freely. Downloads and run results live in .local.
RUN_DIR = os.path.join(LAUNCH_DIR, ".run")
LOG_DIR = RUN_DIR
LOCAL_DIR = os.path.join(LAUNCH_DIR, ".local")
TOOLS_DIR = os.path.join(LOCAL_DIR, "tools")
DEVIMAGES_DIR = os.path.join(LOCAL_DIR, "devimages")
ROUNDS_DIR = os.path.join(LOCAL_DIR, "rounds")
BUILD_DIR = os.path.join(LOCAL_DIR, "build")
STATE_PATH = os.path.join(LOCAL_DIR, "state.json")
GO_IOS_VERSION = "v1.3.2"
GO_IOS_URL = "https://github.com/danielpaulus/go-ios/releases/download/%s/go-ios-%s.zip"
GO_IOS_SHA256 = {
    "mac": "100f225bfdd039081bcbdaf45029df3e67032673f3e0ca1fa3c050898c230c57",
    "linux": "a55fdb4c507391c0548252e01d1deb6ae3c7fd99cfbce842c6f80569cc125604",
    "win": "939c6bcaafed183a92afb9f79cc11b1f935fa6389bfc94d3902e3f52c4dff3fe",
}
WINTUN_URL = "https://www.wintun.net/builds/wintun-0.14.1.zip"
WINTUN_SHA256 = "07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51"
DOWNLOAD_TIMEOUT = 300
DOWNLOAD_LOCK = threading.Lock()
RUNTEST_PATH = os.path.join(LAUNCH_DIR, "runtest.py")
COLLECT_PATH = os.path.join(ROOT, "tools", "crash", "collect.py")
COLLECT_TIMEOUT = 600
RUNNER_CONTAINER = "com.eternalengine.PeregrineRunner.xctrunner"
BACKENDS = ("xcode", "goios")
RUN_FIELDS = ("PEREGRINE_BUNDLEID", "PEREGRINE_DURATION", "PEREGRINE_THROTTLE", "PEREGRINE_DATAPORT", "PEREGRINE_SHOTS", "PEREGRINE_PERF")
TUNNEL_WAIT = 20
DEVICE_PULL_TIMEOUT = 120
DEVICE_FILES = ("peregrine-events.jsonl", "peregrine-coverage.txt", "peregrine-applet.txt", "peregrine-shots.zip")
PREVIOUS_FOLDER = "peregrine-previous"
SHOTS_MODES = ("off", "change", "all")
KEEP_RUNS = 20
TESTS = {
    "explore": "PeregrineRunner/PeregrineRunner/testPeregrine",
    "check": "PeregrineRunner/PeregrineRunner/testPingNetwork",
}
STAMP_RE = re.compile(r"^\d{8}-\d{6}$")
UDID_RE = re.compile(r"^[0-9A-F]{8}-[0-9A-F]{16}$")
SIM_UDID_RE = re.compile(
    r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
)
BUNDLE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.-]*$")
DEVICE_LINE_RE = re.compile(r"\(([0-9A-F]{8}-[0-9A-F]{16})\)\s*$")
VERSION_RE = re.compile(r"^(.*\S)\s+\(([0-9.]+)\)$")
GENERIC_NAMES = ("iPhone", "iPad")
TEAM_RE = re.compile(r"\bOU=([A-Z0-9]{10})\b")
ENV_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")
# XCTest's activity trace under xcodebuild: "    t =     3.19s Tap ...". The same activities are kept in the .xcresult.
XCTEST_ACTIVITY_RE = re.compile(r"^\s+t =\s+(?:[\d.]+|nan)s ")
XCTEST_ACTIVITY_KEEP = "Assertion Failure"
DURATION_MAX = 10080
THROTTLE_MAX = 60000
# stub.m binds about 2 seconds after launch; the runner's own launch probe waits 8.
STUB_WAIT = 8


class FieldError(RuntimeError):
    def __init__(self, field, message):
        super().__init__(message)
        self.field = field


def is_simulator(udid):
    return SIM_UDID_RE.match(udid or "") is not None


def is_target(udid):
    return UDID_RE.match(udid or "") is not None or is_simulator(udid)


def test_destination(udid):
    if is_simulator(udid):
        return "platform=iOS Simulator,id=%s" % udid
    return "platform=iOS,id=%s" % udid


def run_command(args, timeout, env=None):
    # go-ios writes UTF-8. text=True would use the ANSI code page and fail on Chinese Windows.
    options = {}
    if env is not None:
        options["env"] = env
    if os.name == "nt":
        # Windows consoles decode with the ANSI code page; go-ios writes UTF-8.
        options["encoding"] = "utf-8"
        options["errors"] = "replace"
        options["creationflags"] = subprocess.CREATE_NO_WINDOW
    else:
        options["text"] = True
    completed = subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
        **options,
    )
    stdout = completed.stdout if isinstance(completed.stdout, str) else ""
    stderr = completed.stderr if isinstance(completed.stderr, str) else ""
    return completed.returncode, stdout, stderr


def tool_path():
    if sys.platform == "darwin":
        os.environ["PATH"] = os.pathsep.join(["/opt/homebrew/bin", "/usr/local/bin", os.environ.get("PATH", "")])


def backend():
    """xcode builds and runs through Xcode; goios drives a runner already installed on the phone."""
    chosen = os.environ.get("PEREGRINE_BACKEND", "").strip().lower()
    if chosen not in BACKENDS:
        chosen = "xcode" if sys.platform == "darwin" and shutil.which("xcodebuild") else "goios"
    os.environ["PEREGRINE_BACKEND"] = chosen
    return chosen


def download_member(url, digest, member, target):
    """Downloads a zip, checks its SHA-256, and writes one member to target."""
    sys.stderr.write("download %s\n" % url)
    with tempfile.TemporaryDirectory() as scratch:
        archive = os.path.join(scratch, "download.zip")
        # curl uses the system trust store; python.org builds on macOS ship without one.
        curl = shutil.which("curl")
        if curl:
            code, output, error = run_command(
                [curl, "-fsSL", "--retry", "2", "--max-time", str(DOWNLOAD_TIMEOUT), "-o", archive, url],
                DOWNLOAD_TIMEOUT + 30,
            )
            if code != 0:
                raise RuntimeError((error or output or "curl exited %d" % code).strip())
        else:
            with urllib.request.urlopen(url, timeout=DOWNLOAD_TIMEOUT) as response:
                payload = response.read()
            if not isinstance(payload, bytes):
                raise RuntimeError("下载 %s 没有返回内容" % url)
            with open(archive, "wb") as sink:
                sink.write(payload)
        hasher = hashlib.sha256()
        with open(archive, "rb") as handle:
            for block in iter(lambda: handle.read(1 << 20), b""):
                hasher.update(block)
        if hasher.hexdigest() != digest:
            raise RuntimeError("%s 的 SHA-256 与预期不符" % url)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        partial = target + ".partial"
        with zipfile.ZipFile(archive) as bundle:
            with bundle.open(member) as source:
                extracted = source.read()
        if not isinstance(extracted, bytes):
            raise RuntimeError("压缩包里没有 %s" % member)
        with open(partial, "wb") as sink:
            sink.write(extracted)
    os.chmod(partial, 0o755)
    os.replace(partial, target)


def downloaded_go_ios():
    """go-ios GO_IOS_VERSION for this platform, downloaded on first use; Windows also gets wintun.dll beside it."""
    machine = platform.machine().lower()
    arch = {"x86_64": "amd64", "amd64": "amd64", "aarch64": "arm64", "arm64": "arm64"}.get(machine, machine)
    if sys.platform == "darwin":
        folder, member, name = "mac", "ios", "ios"
    elif os.name == "nt":
        folder, member, name = "win", "ios.exe", "ios.exe"
    elif sys.platform.startswith("linux"):
        folder, member, name = "linux", "ios-%s" % arch, "ios"
    else:
        raise RuntimeError("go-ios 没有 %s 的版本" % sys.platform)
    target = os.path.join(TOOLS_DIR, "go-ios-%s" % GO_IOS_VERSION, folder, name)
    with DOWNLOAD_LOCK:
        if not os.path.isfile(target):
            url = GO_IOS_URL % (GO_IOS_VERSION, folder)
            download_member(url, GO_IOS_SHA256[folder], member, target)
        if os.name == "nt":
            placed = os.path.join(os.path.dirname(target), "wintun.dll")
            if not os.path.isfile(placed):
                wintun_arch = "x86" if machine in ("x86", "i386", "i686") else arch
                download_member(WINTUN_URL, WINTUN_SHA256, "wintun/bin/%s/wintun.dll" % wintun_arch, placed)
    return target


def go_ios():
    path = os.environ.get("GO_IOS", "").strip()
    if not path:
        try:
            path = downloaded_go_ios()
        except (OSError, RuntimeError, KeyError, zipfile.BadZipFile) as exc:
            path = shutil.which("ios") or ""
            if not path:
                raise RuntimeError(
                    "下载 go-ios %s 失败（%s）；可手动下载 %s 解压后用环境变量 GO_IOS 指定 ios 可执行文件"
                    % (GO_IOS_VERSION, exc, GO_IOS_URL % (GO_IOS_VERSION, "<mac|linux|win>"))
                ) from exc
    os.environ["GO_IOS"] = path
    return path


# Same pinned agent port as the Windows userspace tunnel: not go-ios's default 60105.
TUNNEL_INFO_PORT = 28100
DEFAULT_AGENT_PORT = 60105


def tunnel_info_args():
    return ["--tunnel-info-port", str(TUNNEL_INFO_PORT)]


def go_ios_env():
    """go-ios must not see ENABLE_GO_IOS_AGENT, or it forks a second tunnel on port 60105."""
    env = os.environ.copy()
    env.pop("ENABLE_GO_IOS_AGENT", None)
    return env


def go_ios_run(args, timeout, udid=""):
    command = [go_ios()] + args + (["--udid=%s" % udid] if udid else [])
    code, output, error = run_command(command, timeout, go_ios_env() if os.name == "nt" else None)
    if code != 0:
        lines = [line for line in (error or output).strip().splitlines() if line.strip()]
        raise RuntimeError("go-ios %s 失败：%s" % (args[0], lines[-1] if lines else "exit %d" % code))
    return output


def go_ios_json(args, timeout, udid=""):
    output = go_ios_run(args, timeout, udid)
    for line in reversed(output.strip().splitlines()):
        line = line.strip()
        if line.startswith(("{", "[")):
            return json.loads(line)
    raise RuntimeError("go-ios %s 没有输出结果" % args[0])


def go_devices():
    """One phone not paired with this computer makes list --details fail for all, so fall back to one query per phone."""
    try:
        return go_ios_json(["list", "--details"], 30).get("deviceList") or []
    except RuntimeError:
        pass
    devices = []
    entries = go_ios_json(["list"], 30).get("deviceList") or []
    if not isinstance(entries, list):
        entries = []
    for item in entries:
        udid = item if isinstance(item, str) else ""
        info = {}
        if udid:
            try:
                loaded = go_ios_json(["info"], 30, udid)
            except RuntimeError:
                loaded = {}
            if isinstance(loaded, dict):
                info = loaded
        if not udid:
            continue
        if info.get("ProductVersion"):
            row = dict(info)
            row["Udid"] = udid
            devices.append(row)
        else:
            devices.append({"Udid": udid, "Unpaired": True})
    return devices


def tunnel_list():
    """JSON array from `tunnel ls`, or None when the pinned agent is not listening.

    A warning object on its own line is not a tunnel. An agent that is down exits non-zero.
    """
    _code, output, _error = run_command([go_ios(), "tunnel", "ls", *tunnel_info_args()], 15, go_ios_env())
    for line in output.splitlines():
        line = line.strip()
        if not line.startswith("["):
            continue
        try:
            data = json.loads(line)
        except ValueError:
            continue
        if isinstance(data, list):
            return data
    return None


def tunnel_up(udid):
    listed = tunnel_list()
    if not listed:
        return False
    return any(isinstance(item, dict) and item.get("udid") == udid for item in listed)


def reclaim_tunnel_agents():
    """Stop a leftover ios.exe listening on the pinned info port or go-ios's default 60105."""
    if os.name != "nt":
        return
    code, output, _error = run_command(["netstat", "-ano", "-p", "tcp"], 15)
    if code != 0:
        return
    ports = {str(TUNNEL_INFO_PORT), str(DEFAULT_AGENT_PORT)}
    pids = []
    for line in output.splitlines():
        parts = line.split()
        if len(parts) < 5 or parts[3] != "LISTENING":
            continue
        _host, sep, port = parts[1].rpartition(":")
        if sep and port in ports and parts[4].isdigit():
            pids.append(parts[4])
    for pid in pids:
        code, output, _error = run_command(["tasklist", "/FI", "PID eq %s" % pid, "/FO", "CSV", "/NH"], 15)
        if "ios.exe" not in output.lower():
            continue
        run_command(["taskkill", "/PID", pid, "/F"], 15)


def start_tunnel():
    os.makedirs(LOG_DIR, exist_ok=True)
    log = open(os.path.join(LOG_DIR, "tunnel.log"), "ab")
    options = {
        "stdin": subprocess.DEVNULL,
        "stdout": log,
        "stderr": subprocess.STDOUT,
        "env": go_ios_env(),
    }
    if os.name == "nt":
        options["creationflags"] = subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        options["start_new_session"] = True
    try:
        subprocess.Popen([go_ios(), "tunnel", "start", "--userspace", *tunnel_info_args()], **options)
    finally:
        log.close()


def tunnel_failure():
    path = os.path.join(LOG_DIR, "tunnel.log")
    lines = []
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = [line for line in handle.read().splitlines() if line.strip()]
    except OSError:
        lines = []
    detail = lines[-1] if lines else ""
    text = "go-ios 隧道没有建立"
    if detail:
        text += "：%s" % detail
    return text + "；可手动执行 ios tunnel start --userspace --tunnel-info-port %d" % TUNNEL_INFO_PORT


def ensure_tunnel(udid):
    """iOS 17 and later reach testmanagerd and process control only through a go-ios userspace tunnel."""
    version = next((item.get("ProductVersion") or "" for item in go_devices() if item.get("Udid") == udid), "")
    major = version.split(".")[0]
    if not major.isdigit() or int(major) < 17:
        return
    if os.name != "nt":
        if go_ios_json(["tunnel", "ls"], 15, udid):
            return
        subprocess.Popen(
            [go_ios(), "tunnel", "start", "--userspace"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        deadline = time.time() + TUNNEL_WAIT
        while time.time() < deadline:
            time.sleep(1)
            if go_ios_json(["tunnel", "ls"], 15, udid):
                return
        raise RuntimeError("go-ios 隧道没有建立；手动执行 ios tunnel start --userspace 查看原因")
    if tunnel_up(udid):
        return
    # An agent that is already up on 28100 is shared. Starting another one fights it for lockdown.
    if tunnel_list() is None:
        reclaim_tunnel_agents()
        start_tunnel()
    deadline = time.time() + TUNNEL_WAIT
    while time.time() < deadline:
        time.sleep(1)
        if tunnel_up(udid):
            return
    raise RuntimeError(tunnel_failure())


def spawn_output(command, environment, cwd, new_group):
    """Starts command and returns it with a file descriptor carrying its merged output."""
    if pty is not None:
        master, slave = pty.openpty()
        try:
            proc = subprocess.Popen(
                command, cwd=cwd, env=environment, stdin=slave, stdout=slave, stderr=slave, start_new_session=new_group
            )
        except Exception:
            os.close(master)
            os.close(slave)
            raise
        os.close(slave)
        return proc, master
    flags = subprocess.CREATE_NEW_PROCESS_GROUP if new_group and os.name == "nt" else 0
    proc = subprocess.Popen(
        command,
        cwd=cwd,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        creationflags=flags,
    )
    reader = os.dup(proc.stdout.fileno())
    proc.stdout.close()
    return proc, reader


class RunOutput:
    """Turns raw test output into log text: one "\\n" per line, XCTest activity lines dropped."""

    def __init__(self):
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")
        self.pending = ""
        self.hidden = 0

    def feed(self, chunk):
        lines = (self.pending + self.decoder.decode(chunk)).split("\n")
        self.pending = lines.pop()
        return "".join(self._kept(line) for line in lines)

    def finish(self):
        tail, self.pending = self.pending + self.decoder.decode(b"", final=True), ""
        text = self._kept(tail) if tail.strip() else ""
        if self.hidden:
            text += "xctest activity hidden %d lines, see .xcresult\n" % self.hidden
        return text

    def _kept(self, line):
        line = line.rstrip("\r")
        if XCTEST_ACTIVITY_RE.match(line) and XCTEST_ACTIVITY_KEEP not in line:
            self.hidden += 1
            return ""
        return line + "\n"


def parse_devices(text):
    devices = []
    in_online = False
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("=="):
            in_online = line == "== Devices =="
            continue
        if not in_online:
            continue
        match = DEVICE_LINE_RE.search(line)
        if match is None:
            continue
        udid = match.group(1)
        name = line[: match.start()].strip() or udid
        devices.append({"udid": udid, "name": name, "kind": "device"})
    return devices


def sim_runtime_version(runtime):
    match = re.search(r"iOS-(\d+)-(\d+(?:-\d+)?)", runtime or "")
    if match:
        return match.group(1) + "." + match.group(2).replace("-", ".")
    match = re.search(r"iOS[ -](\d+\.\d+)", runtime or "")
    return match.group(1) if match else ""


def parse_simctl_devices(payload):
    devices = []
    for runtime, items in (payload.get("devices") or {}).items():
        if not isinstance(items, list):
            continue
        version = sim_runtime_version(runtime)
        for item in items:
            if not isinstance(item, dict) or item.get("state") != "Booted":
                continue
            if item.get("isAvailable") is False:
                continue
            udid = item.get("udid") or ""
            if SIM_UDID_RE.match(udid) is None:
                continue
            name = item.get("name") or udid
            title = "%s (%s)" % (name, version) if version else name
            devices.append(
                {
                    "udid": udid,
                    "name": title,
                    "link": "Simulator",
                    "kind": "simulator",
                    "label": "%s · Simulator" % title,
                }
            )
    return devices


def list_simulators():
    if sys.platform != "darwin":
        return []
    code, output, _ = run_command(["xcrun", "simctl", "list", "devices", "--json"], 30)
    if code != 0:
        return []
    try:
        payload = json.loads(output)
    except ValueError:
        return []
    return parse_simctl_devices(payload)


def parse_connections(text):
    connections = {}
    for raw in text.splitlines():
        line = raw.strip()
        parts = line.split()
        if not parts or UDID_RE.match(parts[0]) is None:
            continue
        connections[parts[0]] = "Network" if "Network" in line else "USB"
    return connections


def unquote_field(value):
    value = value.strip()
    if len(value) >= 2 and value.startswith('"') and value.endswith('"'):
        return value[1:-1].replace('""', '"')
    return value


def parse_apps(text):
    apps = []
    reader = csv.reader(io.StringIO(text.replace(', "', ',"')))
    for row in reader:
        if len(row) < 1:
            continue
        bundle_id = unquote_field(row[0])
        if bundle_id in ("", "CFBundleIdentifier") or not BUNDLE_RE.match(bundle_id):
            continue
        if "xctrunner" in bundle_id.lower():
            continue
        version = unquote_field(row[1]) if len(row) > 1 else ""
        name = unquote_field(row[2]) if len(row) > 2 else ""
        label = "%s · %s" % (name, bundle_id) if name else bundle_id
        apps.append(
            {
                "bundleId": bundle_id,
                "name": name or bundle_id,
                "version": version,
                "label": label,
            }
        )
    apps.sort(key=lambda app: app["name"].casefold())
    return apps


def parse_team(subject):
    match = TEAM_RE.search(subject or "")
    return match.group(1) if match else ""


def whole_number(value, field, low, high, label):
    message = "%s需要是 %d 到 %d 的整数" % (label, low, high)
    if isinstance(value, str):
        value = value.strip()
        if not value.isdigit():
            raise FieldError(field, message)
        value = int(value)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise FieldError(field, message)
    if isinstance(value, float) and not value.is_integer():
        raise FieldError(field, message)
    number = int(value)
    if number < low or number > high:
        raise FieldError(field, message)
    return number


def signing_team():
    override = os.environ.get("DEVELOPMENT_TEAM", "").strip()
    if override or backend() == "goios":
        return override
    code, pem, _ = run_command(["security", "find-certificate", "-c", "Apple Development", "-p"], 15)
    if code != 0 or "BEGIN CERTIFICATE" not in pem:
        return ""
    completed = subprocess.run(
        ["openssl", "x509", "-noout", "-subject"],
        input=pem,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )
    return parse_team(completed.stdout)


def device_title(name, model, version):
    """Model and iOS version, led by the device name only when the user has renamed the phone."""
    title = model or name
    if version:
        title = "%s (%s)" % (title, version)
    if name and model and name not in GENERIC_NAMES and name != model:
        title = "%s · %s" % (name, title)
    return title


def marketing_names():
    try:
        devices = devicectl_json(["list", "devices"], 30).get("devices") or []
    except RuntimeError:
        return {}
    names = {}
    for device in devices:
        hardware = device.get("hardwareProperties") or {}
        if hardware.get("udid") and hardware.get("marketingName"):
            names[hardware["udid"]] = hardware["marketingName"]
    return names


def list_devices():
    if backend() == "goios":
        devices = []
        for item in go_devices():
            udid = item.get("Udid") or ""
            if item.get("Unpaired"):
                name = "未配对，先在手机上信任这台电脑"
                devices.append({"udid": udid, "name": name, "link": "", "kind": "device", "label": "%s · %s" % (udid, name)})
                continue
            link = "Network" if (item.get("ConnectionType") or "") == "Network" else "USB"
            name = device_title(item.get("DeviceName") or "", marketing_name(item.get("ProductType")), item.get("ProductVersion") or "")
            devices.append({"udid": udid, "name": name or udid, "link": link, "kind": "device", "label": "%s · %s" % (name or udid, link)})
        return devices
    code, output, error = run_command(["xcrun", "xctrace", "list", "devices"], 30)
    if code != 0:
        simulators = list_simulators()
        if simulators:
            return simulators
        raise RuntimeError((error or output or "读取设备失败").strip())
    devices = parse_devices(output)
    _, connection_text, _ = run_command(["idevice_id", "-l", "-n"], 15)
    connections = parse_connections(connection_text)
    models = marketing_names()
    for device in devices:
        match = VERSION_RE.match(device["name"])
        if match is not None:
            device["name"] = device_title(match.group(1), models.get(device["udid"], ""), match.group(2))
        link = connections.get(device["udid"], "")
        device["link"] = link
        device["kind"] = "device"
        device["label"] = "%s · %s" % (device["name"], link) if link else device["name"]
    return devices + list_simulators()


def list_apps(udid):
    if is_simulator(udid):
        if backend() == "goios":
            raise RuntimeError("模拟器只支持 Xcode 方式")
        return list_simulator_apps(udid)
    if UDID_RE.match(udid or "") is None:
        raise RuntimeError("先选择一台 iPhone 或已启动的模拟器")
    if backend() == "goios":
        return go_apps(udid)
    _, connection_text, _ = run_command(["idevice_id", "-l", "-n"], 15)
    network = parse_connections(connection_text).get(udid) == "Network"
    attempts = (["-n"], []) if network else ([], ["-n"])
    error = "读取应用列表失败"
    for flag in attempts:
        code, output, err = run_command(
            ["ideviceinstaller", "-u", udid, *flag, "list", "--user"],
            30,
        )
        if code == 0:
            return parse_apps(output)
        error = (err or output or error).strip()
    raise RuntimeError(error)


def go_apps(udid):
    apps = []
    for item in go_ios_json(["apps"], 60, udid):
        bundle_id = item.get("CFBundleIdentifier") or ""
        if not BUNDLE_RE.match(bundle_id) or "xctrunner" in bundle_id.lower():
            continue
        name = item.get("CFBundleDisplayName") or item.get("CFBundleName") or ""
        apps.append(
            {
                "bundleId": bundle_id,
                "name": name or bundle_id,
                "version": item.get("CFBundleShortVersionString") or "",
                "label": "%s · %s" % (name, bundle_id) if name else bundle_id,
            }
        )
    apps.sort(key=lambda app: app["name"].casefold())
    return apps


def list_simulator_apps(udid):
    code, output, error = run_command(["xcrun", "simctl", "listapps", udid], 30)
    if code != 0:
        raise RuntimeError((error or output or "读取模拟器应用失败").strip())
    converted = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", "-"],
        input=output,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        check=False,
    )
    if converted.returncode != 0:
        raise RuntimeError((converted.stderr or "解析模拟器应用列表失败").strip())
    try:
        payload = json.loads(converted.stdout)
    except ValueError as exc:
        raise RuntimeError("解析模拟器应用列表失败") from exc
    if not isinstance(payload, dict):
        raise RuntimeError("解析模拟器应用列表失败")
    apps = []
    for bundle_id, item in payload.items():
        if not isinstance(item, dict):
            continue
        if not BUNDLE_RE.match(bundle_id) or "xctrunner" in bundle_id.lower():
            continue
        if item.get("ApplicationType") != "User":
            continue
        name = item.get("CFBundleDisplayName") or item.get("CFBundleName") or bundle_id
        version = item.get("CFBundleShortVersionString") or ""
        apps.append(
            {
                "bundleId": bundle_id,
                "name": name or bundle_id,
                "version": version,
                "label": "%s · %s" % (name, bundle_id) if name else bundle_id,
            }
        )
    apps.sort(key=lambda app: app["name"].casefold())
    return apps


def free_port():
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    finally:
        probe.close()
    return port


def stub_rpc(local_port, method, timeout):
    body = json.dumps({"jsonrpc": "2.0", "id": 0, "method": method, "params": {}}).encode("utf-8")
    request = urllib.request.Request(
        "http://127.0.0.1:%d/" % local_port,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = json.loads(response.read().decode("utf-8", "replace"))
    except (OSError, ValueError, urllib.error.URLError):
        return None
    return data if isinstance(data, dict) else None


def stub_message(check, bundle_id, port):
    state = check["state"]
    if state == "ok":
        name = check.get("name")
        target = "%s（%s）" % (name, bundle_id) if name else bundle_id
        text = "%s 已接入插桩，端口 %d 应答正常" % (target, port)
    elif state == "legacy":
        text = "端口 %d 有插桩响应，但插桩版本较旧，无法确认属于 %s" % (port, bundle_id)
    elif state == "other":
        owner = check.get("owner") or ""
        if not owner:
            text = "端口 %d 已被其他应用的旧版插桩占用，不是 %s，无法确定是哪个应用；先在手机上关掉其他接入插桩的应用" % (port, bundle_id)
        elif check.get("closeError"):
            text = "端口 %d 已被 %s 的插桩占用，不是 %s；自动关闭失败（%s），先在手机上关掉那个应用" % (
                port, owner, bundle_id, check["closeError"])
        else:
            text = "端口 %d 已被 %s 的插桩占用，不是 %s；先在手机上关掉那个应用" % (port, owner, bundle_id)
    else:
        text = "%s 在端口 %d 上没有插桩响应：应用未接入插桩，或装的不是接入插桩的 Debug 包" % (bundle_id, port)
    if check.get("closed"):
        text += "；已自动关闭原先占用该端口的 %s" % check["closed"]
    return text


def stub_owner(local_port):
    reply = stub_rpc(local_port, "app_info", 2) or {}
    info = reply.get("result") if isinstance(reply.get("result"), dict) else {}
    return info


def stub_answers(local_port):
    reply = stub_rpc(local_port, "kill_process", 1)
    return reply is not None and "result" in reply


def launch_app(udid, bundle_id, environment):
    if backend() == "goios":
        ensure_tunnel(udid)
        options = ["--env=%s=%s" % pair for pair in environment.items()]
        try:
            launch = ["launch", bundle_id, "--kill-existing"]
            if os.name == "nt":
                launch.extend(tunnel_info_args())
            go_ios_run(launch + options, 60, udid)
        except RuntimeError as exc:
            raise RuntimeError("启动 %s 失败：%s" % (bundle_id, exc)) from exc
        return
    command = ["xcrun", "devicectl", "device", "process", "launch", "--device", udid, "--terminate-existing"]
    if environment:
        command += ["--environment-variables", json.dumps(environment)]
    code, output, error = run_command(command + [bundle_id], 60)
    if code != 0:
        lines = (error or output or "devicectl exited %d" % code).strip().splitlines()
        raise RuntimeError("启动 %s 失败：%s" % (bundle_id, lines[-1] if lines else ""))
    return


def devicectl_json(args, timeout):
    payload = {}
    with tempfile.TemporaryDirectory() as folder:
        path = os.path.join(folder, "result.json")
        code, output, error = run_command(["xcrun", "devicectl"] + args + ["--json-output", path], timeout)
        if code != 0 or not os.path.exists(path):
            lines = (error or output or "devicectl exited %d" % code).strip().splitlines()
            raise RuntimeError(lines[-1] if lines else "devicectl exited %d" % code)
        with open(path, encoding="utf-8") as handle:
            payload = json.load(handle).get("result") or {}
    return payload


def app_pids(udid, bundle_id):
    apps = devicectl_json(["device", "info", "apps", "--device", udid, "--bundle-id", bundle_id], 30).get("apps") or []
    urls = [app["url"] for app in apps if app.get("url")]
    if not urls:
        return []
    processes = devicectl_json(["device", "info", "processes", "--device", udid], 30).get("runningProcesses") or []
    return [
        process["processIdentifier"]
        for process in processes
        if any((process.get("executable") or "").startswith(url) for url in urls)
    ]


def terminate_app(udid, bundle_id):
    if backend() == "goios":
        ensure_tunnel(udid)
        try:
            kill = ["kill", bundle_id]
            if os.name == "nt":
                kill.extend(tunnel_info_args())
            go_ios_run(kill, 30, udid)
        except RuntimeError as exc:
            raise RuntimeError("结束 %s 失败：%s" % (bundle_id, exc)) from exc
        return
    pids = app_pids(udid, bundle_id)
    if not pids:
        raise RuntimeError("没有找到 %s 的进程" % bundle_id)
    for pid in pids:
        code, output, error = run_command(
            ["xcrun", "devicectl", "device", "process", "terminate", "--device", udid, "--pid", str(pid)], 30
        )
        if code != 0:
            lines = (error or output or "devicectl exited %d" % code).strip().splitlines()
            raise RuntimeError("结束 %s 失败：%s" % (bundle_id, lines[-1] if lines else ""))


def release_port(udid, owner, local_port):
    """Terminates the app holding the stub port; returns an error text, or "" once the port is free."""
    try:
        terminate_app(udid, owner)
    except (RuntimeError, subprocess.TimeoutExpired, ValueError) as exc:
        return str(exc)
    deadline = time.time() + 3
    while time.time() < deadline:
        if not stub_answers(local_port):
            return ""
        time.sleep(0.3)
    return "端口仍有应答"


def probe_stub(udid, bundle_id, port):
    """Launch the app with stubPort set and ask the stub who it belongs to over usbmux."""
    if is_simulator(udid):
        return {
            "state": "skipped",
            "usable": True,
            "message": "模拟器无法从电脑探测插桩，开跑后由 Runner 自行探测",
        }
    local = free_port()
    if backend() == "goios":
        command = [go_ios(), "forward", str(local), str(port), "--udid=%s" % udid]
        missing = "没有找到 go-ios"
    else:
        _, connection_text, _ = run_command(["idevice_id", "-l", "-n"], 15)
        network = parse_connections(connection_text).get(udid) == "Network"
        command = ["iproxy", "-u", udid] + (["-n"] if network else []) + ["%d:%d" % (local, port)]
        missing = "没有 iproxy，先安装 libimobiledevice"
    try:
        proxy = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError as exc:
        raise RuntimeError(missing) from exc
    check = None
    closed = ""
    try:
        # Without stubPort the target's own stub stays closed, so an answer now is another app.
        launch_app(udid, bundle_id, {})
        time.sleep(0.5)
        if stub_answers(local):
            owner = stub_owner(local).get("bundle_id") or ""
            failure = release_port(udid, owner, local) if owner and owner != bundle_id else "占用方未知"
            if failure:
                check = {"state": "other", "owner": owner, "closeError": failure}
            else:
                closed = owner
        if check is None:
            launch_app(udid, bundle_id, {"stubPort": str(port)})
            deadline = time.time() + STUB_WAIT
            alive = False
            while time.time() < deadline:
                if stub_answers(local):
                    alive = True
                    break
                time.sleep(0.4)
            if not alive:
                check = {"state": "none"}
            else:
                info = stub_owner(local)
                owner = info.get("bundle_id") or ""
                if not owner:
                    check = {"state": "legacy"}
                else:
                    check = {
                        "state": "ok" if owner == bundle_id else "other",
                        "owner": owner,
                        "name": info.get("name") or "",
                        "version": info.get("version") or "",
                    }
    finally:
        proxy.terminate()
        try:
            proxy.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proxy.kill()
    if closed:
        check["closed"] = closed
    check = _with_usable(check)
    check["message"] = stub_message(check, bundle_id, port)
    return check


def _with_usable(check):
    """Sets usable on the probe dict. The parameter stays untyped so a bool can sit beside the strings."""
    check["usable"] = check.get("state") in ("ok", "legacy")
    return check


def stub_preflight(udid, bundle_id, port):
    """Returns the data port to hand the runner and one log line explaining the choice."""
    if port <= 0:
        return 0, ""
    if is_simulator(udid):
        return port, "stub check skipped: 模拟器由 Runner 自行探测\n"
    try:
        check = probe_stub(udid, bundle_id, port)
    except (RuntimeError, subprocess.TimeoutExpired) as exc:
        return port, "stub check skipped: %s；交给 Runner 自行探测\n" % exc
    if check["state"] == "ok":
        closed = " closed %s" % check["closed"] if check.get("closed") else ""
        return port, "stub check success %s port %d%s\n" % (bundle_id, port, closed)
    if check["usable"]:
        return port, "stub check %s: %s\n" % (check["state"], check["message"])
    return 0, "stub check %s: %s；本轮不用插桩，改用截图\n" % (check["state"], check["message"])


def new_stamp():
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def round_home(kind, stamp):
    """One directory for a single run or check: its log, xcresult, pulled files, and crash report."""
    path = os.path.join(ROUNDS_DIR, "%s-%s" % (kind, stamp))
    os.makedirs(path, exist_ok=True)
    return path


def run_paths(stamp):
    base = round_home("run", stamp)
    return {
        "log": os.path.join(base, "run-%s.log" % stamp),
        "xcresult": os.path.join(base, "run-%s.xcresult" % stamp),
        "crash": os.path.join(base, "crash"),
        "device": os.path.join(base, "device"),
    }


def check_paths(stamp):
    base = round_home("check", stamp)
    return {
        "log": os.path.join(base, "check-%s.log" % stamp),
        "xcresult": os.path.join(base, "check-%s.xcresult" % stamp),
    }


def run_artifacts(stamp):
    return list(run_paths(stamp).values())


def _round_dirs():
    return [ROUNDS_DIR] if os.path.isdir(ROUNDS_DIR) else []


def list_runs():
    stamps = set()
    for root in _round_dirs():
        for name in os.listdir(root):
            match = re.match(r"^run-(\d{8}-\d{6})", name)
            if match:
                stamps.add(match.group(1))
    return sorted(stamps)


def keep_runs_count(value=None):
    """How many round directories .local/rounds keeps; PEREGRINE_KEEP_RUNS overrides the default, 0 keeps everything."""
    text = value if value is not None else os.environ.get("PEREGRINE_KEEP_RUNS", "")
    if str(text).strip() == "":
        return KEEP_RUNS
    return whole_number(text, "keep", 0, 100000, "保留轮数")


def prune_runs(keep):
    """Removes the oldest rounds beyond keep, with their checks and export zips; returns how many went."""
    if keep <= 0 or not _round_dirs():
        return 0
    stamps = {}
    for root in _round_dirs():
        for name in os.listdir(root):
            match = re.match(r"^(?:run|check|peregrine-run)-(\d{8}-\d{6})", name)
            if match:
                stamps.setdefault(match.group(1), []).append(os.path.join(root, name))
    old = sorted(stamps)[:-keep]
    for stamp in old:
        for path in stamps[stamp]:
            if os.path.isdir(path):
                shutil.rmtree(path, ignore_errors=True)
            elif os.path.exists(path):
                os.remove(path)
    return len(old)


def parse_env(pairs):
    extra = {}
    for pair in pairs or []:
        key, sep, value = pair.partition("=")
        if not sep or ENV_RE.match(key) is None:
            raise FieldError("env", "环境变量要写成 KEY=VALUE：%s" % pair)
        extra[key] = value
    return extra


def test_command(udid, test, result_path, team):
    if backend() == "goios":
        if is_simulator(udid):
            raise RuntimeError("模拟器只支持 Xcode 方式")
        return [sys.executable, RUNTEST_PATH, "--udid", udid, "--test", test]
    command = [
        "xcodebuild",
        "test",
        "-workspace",
        "Peregrine.xcworkspace",
        "-scheme",
        "PeregrineRunner",
        "-configuration",
        "Debug",
        "-destination",
        test_destination(udid),
        "-only-testing:%s" % TESTS[test],
        "-resultBundlePath",
        result_path,
        "-allowProvisioningUpdates",
    ]
    if team:
        command.append("DEVELOPMENT_TEAM=%s" % team)
    return command


def test_environment(bundle_id, duration, throttle, dataport, extra=None, shots="off", perf=False):
    """The page and CLI fields own these; a value left in the shell would override an empty field."""
    environment = os.environ.copy()
    for key in RUN_FIELDS:
        environment.pop(key, None)
    environment.update(extra or {})
    if bundle_id:
        environment["PEREGRINE_BUNDLEID"] = bundle_id
    if duration:
        environment["PEREGRINE_DURATION"] = str(duration)
    if throttle:
        environment["PEREGRINE_THROTTLE"] = str(throttle)
    if dataport > 0:
        environment["PEREGRINE_DATAPORT"] = str(dataport)
    if shots in SHOTS_MODES and shots != "off":
        environment["PEREGRINE_SHOTS"] = shots
    if perf:
        environment["PEREGRINE_PERF"] = "1"
    return environment


def collect_command(udid, bundle_id, since, log_path, out):
    return [
        sys.executable,
        COLLECT_PATH,
        "--udid", udid,
        "--bundle-id", bundle_id,
        "--since", since,
        "--log", log_path,
        "--out", out,
    ]


def install_commands(udid, team):
    """Builds the runner on this Mac and installs it, so other hosts can run it through go-ios."""
    if is_simulator(udid):
        raise RuntimeError("install 只把 Runner 装到真机，供其他电脑经 go-ios 运行")
    derived = BUILD_DIR
    build = [
        "xcodebuild",
        "build-for-testing",
        "-workspace",
        "Peregrine.xcworkspace",
        "-scheme",
        "PeregrineRunner",
        "-configuration",
        "Debug",
        "-destination",
        "platform=iOS,id=%s" % udid,
        "-derivedDataPath",
        derived,
        "-allowProvisioningUpdates",
    ]
    if team:
        build.append("DEVELOPMENT_TEAM=%s" % team)
    app = os.path.join(derived, "Build", "Products", "Debug-iphoneos", "PeregrineRunner-Runner.app")
    install = ["xcrun", "devicectl", "device", "install", "app", "--device", udid, app]
    return build, install


def pull_device_files(udid, bundle_id, out, previous=False):
    names = list(DEVICE_FILES)
    folder = PREVIOUS_FOLDER + "/" if previous else ""
    if bundle_id and not previous:
        names.append("peregrine-%s.reuse.json" % bundle_id)
    if is_simulator(udid):
        return pull_simulator_files(udid, names, out, previous)
    if backend() == "goios":
        os.makedirs(out, exist_ok=True)
        copied = []
        for name in names:
            try:
                pull = ["fsync", "--app=%s" % RUNNER_CONTAINER, "pull", "--srcPath=/tmp/%s%s" % (folder, name), "--dstPath=%s" % out]
                if os.name == "nt":
                    pull.extend(tunnel_info_args())
                go_ios_run(pull, DEVICE_PULL_TIMEOUT, udid)
            except RuntimeError:
                continue
            if os.path.isfile(os.path.join(out, name)):
                copied.append(name)
        if not copied:
            raise RuntimeError("Runner 临时目录里没有结果文件")
        return copied
    copied = []
    with tempfile.TemporaryDirectory() as scratch:
        pulled = os.path.join(scratch, "tmp")
        code, output, error = run_command(
            [
                "xcrun", "devicectl", "device", "copy", "from",
                "--device", udid,
                "--domain-type", "appDataContainer",
                "--domain-identifier", RUNNER_CONTAINER,
                "--source", "tmp",
                "--destination", pulled,
            ],
            DEVICE_PULL_TIMEOUT,
        )
        if code != 0 or not os.path.isdir(pulled):
            message = (error or output or "devicectl exited %d" % code).strip().splitlines()
            raise RuntimeError(message[-1] if message else "devicectl failed")
        if previous:
            pulled = os.path.join(pulled, PREVIOUS_FOLDER)
        os.makedirs(out, exist_ok=True)
        output_dir = out if isinstance(out, str) else os.fsdecode(out)
        for name in names:
            file_name = name if isinstance(name, str) else str(name)
            source = os.path.join(pulled, file_name)
            destination = os.path.join(output_dir, file_name)
            if os.path.isfile(source):
                shutil.copy2(source, destination)
                copied.append(file_name)
        # The runner leaves the folder when it could not pack it.
        shots = os.path.join(pulled, "peregrine-shots")
        if os.path.isdir(shots):
            shutil.copytree(shots, os.path.join(output_dir, "peregrine-shots"), dirs_exist_ok=True)
            copied.append("peregrine-shots")
        if not copied:
            raise RuntimeError("Runner 临时目录里没有结果文件")
    return copied


def pull_simulator_files(udid, names, out, previous):
    code, output, error = run_command(
        ["xcrun", "simctl", "get_app_container", udid, RUNNER_CONTAINER, "data"],
        DEVICE_PULL_TIMEOUT,
    )
    if code != 0:
        lines = (error or output or "simctl exited %d" % code).strip().splitlines()
        raise RuntimeError(lines[-1] if lines else "simctl failed")
    pulled = os.path.join(output.strip(), "tmp")
    if previous:
        pulled = os.path.join(pulled, PREVIOUS_FOLDER)
    if not os.path.isdir(pulled):
        raise RuntimeError("Runner 临时目录里没有结果文件")
    os.makedirs(out, exist_ok=True)
    copied = []
    output_dir = out if isinstance(out, str) else os.fsdecode(out)
    for name in names:
        file_name = name if isinstance(name, str) else str(name)
        source = os.path.join(pulled, file_name)
        destination = os.path.join(output_dir, file_name)
        if os.path.isfile(source):
            shutil.copy2(source, destination)
            copied.append(file_name)
    shots = os.path.join(pulled, "peregrine-shots")
    if os.path.isdir(shots):
        shutil.copytree(shots, os.path.join(output_dir, "peregrine-shots"), dirs_exist_ok=True)
        copied.append("peregrine-shots")
    if not copied:
        raise RuntimeError("Runner 临时目录里没有结果文件")
    return copied


def write_export(stamp, handle):
    root = "peregrine-run-%s" % stamp
    with zipfile.ZipFile(handle, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in run_artifacts(stamp):
            if os.path.isfile(path):
                archive.write(path, os.path.join(root, os.path.basename(path)))
                continue
            parent = os.path.dirname(path)
            for folder, _, files in os.walk(path):
                for name in files:
                    full = os.path.join(folder, name)
                    archive.write(full, os.path.join(root, os.path.relpath(full, parent)))
