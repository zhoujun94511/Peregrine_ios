"""Host-side resource sampling of the app under test through pymobiledevice3 (Instruments sysmontap and FPS).

Works the same on macOS, Linux and Windows with iOS 17.4+ over USB, without root. The userspace tunnel is
forced so it never competes with Xcode or devicectl for the device's RemoteXPC connection.
"""
import datetime
import json
import os
import subprocess
import sys
import threading

from core import TOOLS_DIR, run_command

REQUIREMENTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "requirements.txt")


def _pinned_version():
    with open(REQUIREMENTS, encoding="utf-8") as handle:
        for line in handle:
            text = line.strip()
            if text.startswith("pymobiledevice3=="):
                return text.split("==", 1)[1]
    raise RuntimeError("tools/requirements.txt 没有 pymobiledevice3==")


PMD3_VERSION = _pinned_version()
INSTALL_TIMEOUT = 1800
QUERY_TIMEOUT = 60
PROCESS_FILE = "perf-process.jsonl"
FPS_FILE = "perf-fps.jsonl"
NOTIFY_FILE = "perf-notify.jsonl"
HOST_LOG = "perf-host.log"
REPORT_FILE = "perf-report.txt"
EVENTS_FILE = "peregrine-events.jsonl"
PROCESS_KEYS = ("pid", "name", "cpuUsage", "physFootprint", "threadCount",
                "diskBytesRead", "diskBytesWritten", "nfiles", "machPortCount", "intWakeups")
FOREGROUND_STATE = "Running"
LOW_FPS = 30
SLOW_MAIN_MS = 250
TOP_STEPS = 5
SLOPE_SECONDS = 30
MB = 1048576.0


def _layout():
    root = os.path.join(TOOLS_DIR, "pymobiledevice3-%s" % PMD3_VERSION)
    folder, name = ("Scripts", "pymobiledevice3.exe") if os.name == "nt" else ("bin", "pymobiledevice3")
    return root, folder, os.path.join(root, folder, name)


def venv_python():
    """Project .venv, the interpreter used to launch host-side sampling."""
    root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    folder, name = ("Scripts", "python.exe") if os.name == "nt" else ("bin", "python")
    return os.path.join(root, ".venv", folder, name)


def tool_beside(python):
    name = "pymobiledevice3.exe" if os.name == "nt" else "pymobiledevice3"
    return os.path.join(os.path.dirname(python), name)


def installed_pymobiledevice3():
    """The pymobiledevice3 to use without installing anything; empty when it still has to be installed."""
    path = os.environ.get("PYMOBILEDEVICE3", "").strip()
    if path:
        return path
    if os.name == "nt":
        bundled = tool_beside(venv_python())
        if os.path.isfile(bundled):
            return bundled
    target = _layout()[2]
    return target if os.path.isfile(target) else ""


def pymobiledevice3():
    """pymobiledevice3 PMD3_VERSION from the project .venv, installed there on first use."""
    path = installed_pymobiledevice3()
    if path:
        return path
    if sys.version_info < (3, 9):
        major, minor = sys.version_info[0], sys.version_info[1]
        raise RuntimeError("pymobiledevice3 需要 Python 3.9 及以上，当前 %d.%d" % (major, minor))
    python = venv_python()
    if os.name == "nt" and os.path.isfile(python):
        sys.stderr.write("perf tool install pymobiledevice3 %s into .venv\n" % PMD3_VERSION)
        code, output, error = run_command([python, "-m", "pip", "install", "-q", "-r", REQUIREMENTS], INSTALL_TIMEOUT)
        target = tool_beside(python)
        if code != 0 or not os.path.isfile(target):
            raise RuntimeError(failure(error or output, "pip exited %d" % code))
        sys.stderr.write("perf tool install success\n")
        return target
    root, folder, target = _layout()
    sys.stderr.write("perf tool install pymobiledevice3 %s, first use only\n" % PMD3_VERSION)
    code, output, error = run_command([sys.executable, "-m", "venv", root], 300)
    if code != 0:
        raise RuntimeError(failure(error or output, "venv exited %d" % code))
    pip = os.path.join(root, folder, "python.exe" if os.name == "nt" else "python")
    code, output, error = run_command(
        [pip, "-m", "pip", "install", "-q", "-r", REQUIREMENTS], INSTALL_TIMEOUT
    )
    if code != 0 or not os.path.isfile(target):
        raise RuntimeError(failure(error or output, "pip exited %d" % code))
    sys.stderr.write("perf tool install success\n")
    return target


# The notifications command stops at the first payload its JSON encoder does not know; this writes such
# values as {"$repr": ...} instead.
TOLERANT_MAIN = """import sys
import pymobiledevice3.cli.cli_common as common
encode = common.default_json_encoder
def tolerant(value):
    try:
        return encode(value)
    except TypeError:
        return {"$repr": repr(value)[:500]}
common.default_json_encoder = tolerant
from pymobiledevice3.__main__ import main
sys.argv = ["pymobiledevice3"] + sys.argv[1:]
sys.exit(main())
"""


def tolerant_command(tool):
    """tool through its own interpreter with TOLERANT_MAIN when it sits in a virtualenv, else tool as is."""
    folder = os.path.dirname(tool)
    for name in ("python.exe", "python3", "python"):
        python = os.path.join(folder, name)
        if os.path.isfile(python):
            return [python, "-c", TOLERANT_MAIN]
    return [tool]


def failure(text, fallback):
    """pymobiledevice3 ends a failure with a hint to rerun with -v; the ERROR line before it is the cause."""
    lines = (text or "").strip().splitlines()
    for line in reversed(lines):
        if " ERROR " in line:
            return line.split(" ERROR ", 1)[1].strip()
    return lines[-1] if lines else fallback


def app_executable(tool, udid, bundle_id):
    code, output, error = run_command([tool, "apps", "query", "--udid", udid, bundle_id], QUERY_TIMEOUT)
    if code != 0:
        raise RuntimeError(failure(error or output, "apps query exited %d" % code))
    info = json.loads(output).get(bundle_id) or {}
    name = info.get("CFBundleExecutable") or ""
    if not name:
        raise RuntimeError("手机上没有 %s" % bundle_id)
    return name


class HostPerf:
    """Streams the app's CPU, memory and threads about once a second, and the screen FPS, into out."""

    def __init__(self, udid, bundle_id, tool):
        self.udid = udid
        self.bundle_id = bundle_id
        self.tool = tool
        self.out = ""
        self.name = ""
        self.handles = []
        self.exits = []

    def prepare(self):
        """Looks up the app's process name; slow enough to keep out of any lock."""
        self.name = app_executable(self.tool, self.udid, self.bundle_id)
        return self.name

    def start(self, out):
        tool = self.tool
        self.out = out
        os.makedirs(self.out, exist_ok=True)
        connection = ["--udid", self.udid, "--userspace"]
        keys = []
        for key in PROCESS_KEYS:
            keys += ["-k", key]
        process = [tool, "developer", "dvt", "sysmon", "process", "monitor", "process"] + connection + [
            "--filter", "name=%s" % self.name, "--choose", "last", "--keep-monitoring", "-i", "1000",
            "-o", os.path.join(self.out, PROCESS_FILE)] + keys
        fps = [tool, "developer", "dvt", "fps"] + connection
        notify = tolerant_command(tool) + ["developer", "dvt", "notifications"] + connection
        log = open(os.path.join(self.out, HOST_LOG), "a", encoding="utf-8")
        try:
            self.handles.append(self._spawn("process", process, None, log))
            self.handles.append(self._spawn("fps", fps, os.path.join(self.out, FPS_FILE), log))
            self.handles.append(self._spawn("notify", notify, os.path.join(self.out, NOTIFY_FILE), log, True))
        finally:
            log.close()

    @staticmethod
    def _spawn(label, command, stdout_path, log, stamp=False):
        sink = open(stdout_path, "w", encoding="utf-8") if stdout_path else subprocess.DEVNULL
        guarded = [sys.executable, "-B", os.path.abspath(__file__), "--guard"] + (["--stamp"] if stamp else []) + command
        handle = subprocess.Popen(guarded, stdout=sink, stderr=log, stdin=subprocess.PIPE)
        return label, handle, sink

    def stop(self):
        for label, handle, sink in self.handles:
            if handle.poll() is not None:
                self.exits.append((label, handle.returncode))
            else:
                try:
                    handle.stdin.close()
                    handle.wait(timeout=15)
                except (OSError, subprocess.TimeoutExpired):
                    handle.kill()
                    handle.wait()
            if handle.stdin is not None and not handle.stdin.closed:
                handle.stdin.close()
            if sink is not subprocess.DEVNULL:
                sink.close()
        self.handles = []

    def line(self):
        """perf host samples <n> launches <n> peak_mb <x> peak_time <time> cpu_avg <x> cpu_max <x> fps_samples <n> fps_avg <x> fps_low <n>
        background_s <n> disk_read_mb <x> disk_write_mb <x> files_max <n> ports_max <n> wakeups_per_s <x> memory_levels <n>,
        then one perf host <monitor> exited line per monitor that ended before stop."""
        rows = read_jsonl(os.path.join(self.out, PROCESS_FILE))
        frames = read_jsonl(os.path.join(self.out, FPS_FILE))
        states, notices = read_notifications(self.out, {row.get("pid") for row in rows})
        background = 0
        if rows:
            first, last = parse_time(rows[0].get("timestamp")), parse_time(rows[-1].get("timestamp"))
            if first is not None and last is not None:
                frames = [row for row in frames if first <= (parse_time(row.get("timestamp")) or first) <= last]
            kept = [row for row in frames if in_foreground(states, rows, parse_time(row.get("timestamp")))]
            background = len(frames) - len(kept)
            frames = kept
        frames = [row["fps"] for row in frames if isinstance(row.get("fps"), (int, float))]
        lines = [summary_line(rows, frames, background, len(notices))]
        for label, code in self.exits:
            reason = failure(read_text(os.path.join(self.out, HOST_LOG)), "no error output")
            lines.append("perf host %s exited %s before the run ended: %s" % (label, code, reason))
        return "\n".join(lines)


def summary_line(rows, frames, background=0, notices=0):
    if not rows:
        return "perf host samples 0 fps_samples %d memory_levels %d" % (len(frames), notices)
    peak = max(rows, key=lambda row: row.get("physFootprint") or 0)
    cpu = [row["cpuUsage"] for row in rows if isinstance(row.get("cpuUsage"), (int, float))]
    moving = [value for value in frames if value > 0]
    launches = launch_groups(rows)
    seconds = sum(launch_seconds(group) for group in launches)
    return ("perf host samples %d launches %d peak_mb %.1f peak_time %s cpu_avg %.1f cpu_max %.1f fps_samples %d fps_avg %.1f fps_low %d "
            "background_s %d disk_read_mb %.1f disk_write_mb %.1f files_max %d ports_max %d wakeups_per_s %.1f memory_levels %d") % (
        len(rows),
        len(launches),
        (peak.get("physFootprint") or 0) / MB,
        local_time(peak.get("timestamp", "")),
        sum(cpu) / len(cpu) if cpu else 0,
        max(cpu) if cpu else 0,
        len(frames),
        sum(moving) / len(moving) if moving else 0,
        sum(1 for value in moving if value < LOW_FPS),
        background,
        sum(counter_delta(group, "diskBytesRead") for group in launches) / MB,
        sum(counter_delta(group, "diskBytesWritten") for group in launches) / MB,
        max_value(rows, "nfiles"),
        max_value(rows, "machPortCount"),
        sum(counter_delta(group, "intWakeups") for group in launches) / seconds if seconds > 0 else 0,
        notices,
    )


def launch_groups(rows):
    """Samples split per process, in launch order."""
    groups = {}
    for row in rows:
        groups.setdefault(row.get("pid"), []).append(row)
    return list(groups.values())


def launch_seconds(group):
    start, end = parse_time(group[0].get("timestamp")), parse_time(group[-1].get("timestamp"))
    return (end - start).total_seconds() if start is not None and end is not None else 0


def counter_delta(group, key):
    """Growth of a counter the kernel keeps since the process started."""
    values = [row[key] for row in group if isinstance(row.get(key), (int, float))]
    return values[-1] - values[0] if len(values) > 1 else 0


def max_value(rows, key):
    values = [row[key] for row in rows if isinstance(row.get(key), (int, float))]
    return max(values) if values else 0


def read_notifications(out, pids):
    """App state changes of the given processes as (time, state), and every memory notification as (time, payload)."""
    states, notices = [], []
    for row in read_jsonl(os.path.join(out, NOTIFY_FILE)):
        when, event = parse_time(row.get("timestamp")), row.get("event")
        if when is None or not isinstance(event, list) or not event:
            continue
        selector = str(event[0])
        if selector.startswith("applicationState"):
            for entry in event[1] if len(event) > 1 and isinstance(event[1], list) else []:
                if isinstance(entry, dict) and entry.get("pid") in pids:
                    states.append((when, str(entry.get("state_description", "")), entry.get("pid")))
        elif "emory" in selector:
            notices.append((when, event))
    states.sort(key=lambda pair: pair[0])
    notices.sort(key=lambda pair: pair[0])
    return states, notices


def backgrounded(states):
    """Changes from running to any state but Terminated, per process."""
    last, count = {}, 0
    for _, state, pid in states:
        if last.get(pid, "").startswith(FOREGROUND_STATE) and not state.startswith(FOREGROUND_STATE) and state != "Terminated":
            count += 1
        last[pid] = state
    return count


def in_foreground(states, rows, when):
    """Whether the process sampled last before when was in front; it counts as in front until its own state change says otherwise."""
    if when is None:
        return True
    pid = None
    for row in rows:
        sampled = parse_time(row.get("timestamp"))
        if sampled is not None and sampled > when:
            break
        pid = row.get("pid")
    current = FOREGROUND_STATE
    for changed, state, owner in states:
        if changed > when:
            break
        if owner == pid:
            current = state
    return current.startswith(FOREGROUND_STATE)


def read_jsonl(path):
    rows = []
    if not os.path.isfile(path):
        return rows
    with open(path, encoding="utf-8", errors="replace") as handle:
        for text in handle:
            text = text.strip()
            if not text.startswith("{"):
                continue
            try:
                rows.append(json.loads(text))
            except ValueError:
                continue
    return rows


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return ""


def parse_time(stamp):
    """Host samples carry +00:00 and the event log Z; both are UTC. Returns None when stamp is unusable."""
    if not isinstance(stamp, str) or not stamp:
        return None
    try:
        value = datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    except ValueError:
        return None
    return value if value.tzinfo is not None else value.replace(tzinfo=datetime.timezone.utc)


def local_time(stamp):
    value = parse_time(stamp)
    return value.astimezone().strftime("%H:%M:%S") if value is not None else stamp


def write_report(out):
    """Ties the samples in out to the steps of the event log there; returns the log line to print."""
    rows = [row for row in read_jsonl(os.path.join(out, PROCESS_FILE)) if parse_time(row.get("timestamp")) and row.get("physFootprint")]
    events = read_jsonl(os.path.join(out, EVENTS_FILE))
    steps, stalls, warnings, heat = [], [], [], []
    for event in events:
        when = parse_time(event.get("timestamp"))
        if event.get("event_type") == "action_start" and when is not None:
            action = event.get("action") or {}
            text = ("%s %s" % (action.get("type", ""), action.get("target", ""))).strip()
            steps.append((when, len(steps) + 1, text))
        elif event.get("event_type") == "perf":
            sample, step = event.get("perf") or {}, steps[-1] if steps else None
            if (sample.get("main_max_ms") or 0) >= SLOW_MAIN_MS:
                stalls.append((event, step))
            if (sample.get("memory_warnings") or 0) > 0:
                warnings.append((event, step))
            if sample.get("thermal_state") not in (None, "nominal"):
                heat.append((event, step))
    states, notices = read_notifications(out, {row.get("pid") for row in rows})
    if not rows and not stalls and not warnings and not heat:
        return "perf report skipped: no samples"
    lines = []
    if rows:
        peak = max(rows, key=lambda row: row["physFootprint"])
        lines.append("内存峰值 %.1f MiB，%s，%s" % (peak["physFootprint"] / MB, local_time(peak["timestamp"]), step_text(steps, parse_time(peak["timestamp"]))))
        lines.append("")
        lines.append("每次启动的内存变化（斜率为线性拟合，单位 MiB/分钟）：")
        for pid in sorted({row.get("pid") for row in rows}, key=lambda value: first_time(rows, value)):
            lines.append("  " + launch_text([row for row in rows if row.get("pid") == pid]))
        growth = step_growth(rows, steps)
        if growth:
            lines.append("")
            lines.append("内存增长最多的步骤（从该步开始到下一步开始）：")
            for delta, number, text in growth[:TOP_STEPS]:
                lines.append("  +%.1f MiB  第 %d 步 %s" % (delta / MB, number, text))
        lines.append("")
        lines.append("每次启动的文件、端口、磁盘与唤醒（斜率单位 个/分钟）：")
        for group in launch_groups(rows):
            lines.append("  " + resource_text(group))
        lines.append("")
        lines.append("应用退到后台 %d 次（不含进程结束）" % backgrounded(states))
    lines.append("")
    if notices:
        lines.append("系统内存级别通知（电脑端，code 含义 Apple 未公开，pid -1 表示整机）：")
        for when, event in notices:
            payload = event[1][0] if len(event) > 1 and isinstance(event[1], list) and event[1] and isinstance(event[1][0], dict) else {}
            detail = "code %s pid %s" % (payload.get("code"), payload.get("pid")) if payload else json.dumps(event, ensure_ascii=False)[:200]
            lines.append("  %s，%s，%s" % (when.astimezone().strftime("%H:%M:%S"), step_text(steps, when), detail))
    else:
        lines.append("系统内存级别通知：无")
    lines.append("")
    if stalls:
        lines.append("主线程卡顿（插桩，单次 %d ms 及以上）：" % SLOW_MAIN_MS)
        for event, step in stalls:
            lines.append("  %d ms，%s，%s" % (event["perf"]["main_max_ms"], local_time(event.get("timestamp")), step_label(step)))
    else:
        lines.append("主线程卡顿：插桩未采样或未发现 %d ms 及以上的卡顿" % SLOW_MAIN_MS)
    for title, items, key in (("内存警告（插桩）", warnings, "memory_warnings"), ("设备温度偏高（插桩）", heat, "thermal_state")):
        if items:
            lines.append("")
            lines.append(title + "：")
            for event, step in items:
                lines.append("  %s，%s，%s" % (event["perf"][key], local_time(event.get("timestamp")), step_label(step)))
    path = os.path.join(out, REPORT_FILE)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    return "perf report success %s" % path


def perf_report_line(out):
    try:
        return write_report(out)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        return "perf report failed: %s" % exc


def first_time(rows, pid):
    return min(parse_time(row["timestamp"]) for row in rows if row.get("pid") == pid)


def step_text(steps, when):
    before = [step for step in steps if when is not None and step[0] <= when]
    return step_label(before[-1] if before else None)


def step_label(step):
    if step is None:
        return "第一步操作之前"
    _, number, text = step
    return "第 %d 步 %s 之后" % (number, text)


def launch_text(rows):
    values = [row["physFootprint"] / MB for row in rows]
    text = "pid %s  %s 至 %s  起 %.1f MiB  止 %.1f MiB  峰 %.1f MiB" % (
        rows[0].get("pid"), local_time(rows[0]["timestamp"]), local_time(rows[-1]["timestamp"]), values[0], values[-1], max(values))
    span = launch_seconds(rows)
    if span < SLOPE_SECONDS:
        return text + "  不足 %d 秒，不计斜率" % SLOPE_SECONDS
    return text + "  斜率 %+.1f（%d 秒）" % (slope_per_minute(rows, "physFootprint") / MB, span)


def slope_per_minute(rows, key):
    """Least-squares growth of key per minute over the samples that carry it."""
    start = parse_time(rows[0]["timestamp"])
    points = [((parse_time(row["timestamp"]) - start).total_seconds() / 60.0, row[key]) for row in rows if isinstance(row.get(key), (int, float))]
    if len(points) < 2:
        return 0
    mean_x = sum(x for x, _ in points) / len(points)
    mean_y = sum(y for _, y in points) / len(points)
    spread = sum((x - mean_x) ** 2 for x, _ in points)
    return sum((x - mean_x) * (y - mean_y) for x, y in points) / spread if spread else 0


def first_last(rows, key):
    values = [row[key] for row in rows if isinstance(row.get(key), (int, float))]
    return (values[0], values[-1]) if values else (0, 0)


def resource_text(rows):
    files, ports = first_last(rows, "nfiles"), first_last(rows, "machPortCount")
    span = launch_seconds(rows)
    text = "pid %s  文件 %d→%d  端口 %d→%d  磁盘读 %.1f MiB  磁盘写 %.1f MiB  唤醒 %.1f 次/秒" % (
        rows[0].get("pid"), files[0], files[1], ports[0], ports[1],
        counter_delta(rows, "diskBytesRead") / MB, counter_delta(rows, "diskBytesWritten") / MB,
        counter_delta(rows, "intWakeups") / span if span > 0 else 0)
    if span < SLOPE_SECONDS:
        return text
    return text + "  文件斜率 %+.1f  端口斜率 %+.1f" % (slope_per_minute(rows, "nfiles"), slope_per_minute(rows, "machPortCount"))


def step_growth(rows, steps):
    """Footprint change across each step, from the last sample before it starts to the last sample before the next starts, same process only."""
    times = [parse_time(row["timestamp"]) for row in rows]
    growth = []
    for index, (start, number, text) in enumerate(steps):
        end = steps[index + 1][0] if index + 1 < len(steps) else times[-1]
        before = [i for i, when in enumerate(times) if when <= start]
        after = [i for i, when in enumerate(times) if when <= end]
        if not before or not after or rows[before[-1]].get("pid") != rows[after[-1]].get("pid"):
            continue
        delta = rows[after[-1]]["physFootprint"] - rows[before[-1]]["physFootprint"]
        if delta > 0:
            growth.append((delta, number, text))
    growth.sort(key=lambda row: -row[0])
    return growth


def guard(command, stamp=False):
    """Runs command until it exits or stdin closes, which also happens when the process that started it dies.
    stamp wraps each output line as {"timestamp", "event"}, for monitors that only carry device clock ticks."""
    # Unbuffered, or piped output would arrive in blocks and get late timestamps.
    child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE if stamp else None,
                             env=dict(os.environ, PYTHONUNBUFFERED="1"))

    def end_on_close():
        try:
            sys.stdin.buffer.read()
        except (OSError, ValueError):
            pass
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                child.kill()

    threading.Thread(target=end_on_close, daemon=True).start()
    if stamp:
        for raw in child.stdout:
            text = raw.decode("utf-8", "replace").strip()
            if not text:
                continue
            try:
                event = json.loads(text)
            except ValueError:
                event = text
            stamped = {"timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(), "event": event}
            sys.stdout.write(json.dumps(stamped, ensure_ascii=False) + "\n")
            sys.stdout.flush()
    return child.wait() or 0


if __name__ == "__main__" and len(sys.argv) > 2 and sys.argv[1] == "--guard":
    marked = sys.argv[2] == "--stamp"
    # The stdin reader may still be blocked; a normal interpreter shutdown would abort on its lock.
    # noinspection PyProtectedMember
    os._exit(guard(sys.argv[3:] if marked else sys.argv[2:], marked))
