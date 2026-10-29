#!/usr/bin/env python3
# noinspection SpellCheckingInspection,GrazieInspection
"""Pulls the crash and jetsam reports of the app under test for one run, groups them by
stack signature, and attaches the steps Peregrine logged before each one.

    python3 tools/crash/collect.py --udid <UDID> --bundle-id <bundle id> \
        --since "2026-10-21 16:00:00" [--until ...] [--log run.log] --out <dir>

Needs idevicecrashreport and ideviceinstaller (libimobiledevice), or go-ios when
PEREGRINE_BACKEND=goios (the ios command on PATH, or GO_IOS).
"""

import argparse
import csv
import importlib.util
import io
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone

ANOMALY_RE = re.compile(r"peregrine anomaly ({.*})\s*$")
STEP_RE = re.compile(r"peregrine anomaly step ({.*})\s*$")
SUMMARY_RE = re.compile(r"anomaly summary ((?:[a-z_]+ \d+ ?)+)\s*$")
CRASH_KINDS = ("suspected_crash", "suspected_crash_restart")
NOISE_IMAGES = {
    "libsystem_kernel.dylib",
    "libsystem_pthread.dylib",
    "libsystem_c.dylib",
    "libc++abi.dylib",
    "libobjc.A.dylib",
}
NOISE_SYMBOLS = ("__exceptionPreprocess", "objc_exception_throw", "abort")
# Swift runtime traps run through _assertionFailure and the closures inside it.
SWIFT_TRAP = "_assertionFailure"
FRAME_LIMIT = 12
SIGNATURE_FRAMES = 3
# Reports are written a few seconds after the exit; one detected at the end of a run can land later.
MATCH_BEFORE = timedelta(seconds=5)
MATCH_AFTER = timedelta(seconds=180)
WATCHDOG_CODE = 0x8BADF00D


def run(args, timeout):
    try:
        completed = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 1, "", str(exc)
    return completed.returncode, completed.stdout, completed.stderr


def parse_time(value):
    value = (value or "").strip()
    if re.fullmatch(r"\d+(\.\d+)?", value):
        return datetime.fromtimestamp(float(value), timezone.utc)
    for pattern in ("%Y-%m-%d %H:%M:%S.%f %z", "%Y-%m-%d %H:%M:%S %z", "%Y-%m-%dT%H:%M:%SZ"):
        try:
            parsed = datetime.strptime(value, pattern)
        except ValueError:
            continue
        else:
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    for pattern in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.strptime(value, pattern).astimezone()
        except ValueError:
            continue
    raise ValueError("unknown time %r" % value)


def local_text(moment):
    return moment.astimezone().strftime("%Y-%m-%d %H:%M:%S")


def go_ios():
    if os.environ.get("PEREGRINE_BACKEND") != "goios":
        return ""
    chosen = os.environ.get("GO_IOS", "").strip()
    if chosen:
        return chosen
    names = ("ios.exe", "ios") if os.name == "nt" else ("ios",)
    for folder in os.environ.get("PATH", "").split(os.pathsep):
        if not folder:
            continue
        for name in names:
            candidate = pathlib.Path(folder) / name
            if candidate.is_file():
                return str(candidate)
    return "ios"


def device_flags(udid):
    if go_ios():
        return []
    _, usb, _ = run(["idevice_id", "-l"], 15)
    return [] if udid in usb.split() else ["-n"]


def product_marketing_name(product_type):
    key = (product_type or "").strip()
    if not key:
        return ""
    path = pathlib.Path(__file__).resolve().parents[1] / "launch" / "models.py"
    spec = importlib.util.spec_from_file_location("peregrine_device_models", path)
    if spec is None or spec.loader is None:
        return key
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    names = getattr(module, "MARKETING_NAMES", None)
    if not isinstance(names, dict):
        return key
    found = names.get(key, key)
    return found if isinstance(found, str) else key


def json_value(text, opener):
    line = next((item for item in reversed((text or "").splitlines()) if item.strip().startswith(opener)), "")
    if not line:
        return None
    try:
        return json.loads(line)
    except ValueError:
        return None


def idevice_value(udid, flags, key):
    code, text, _ = run(["ideviceinfo", "-u", udid, *flags, "-k", key], 20)
    if code != 0:
        return ""
    return text.strip()


def device_record(udid, flags):
    """Name, marketing model, and iOS version of the phone this run used."""
    record = {"name": "", "model": "", "system": "", "udid": udid}
    if go_ios():
        code, text, _ = run([go_ios(), "info", "--udid=%s" % udid], 30)
        info = json_value(text, "{") if code == 0 else None
        info = info if isinstance(info, dict) else {}
        product = info.get("ProductType") or ""
        record["name"] = info.get("DeviceName") or ""
        record["system"] = info.get("ProductVersion") or ""
        record["model"] = product_marketing_name(product) if product else ""
        return record
    record["name"] = idevice_value(udid, flags, "DeviceName")
    record["system"] = idevice_value(udid, flags, "ProductVersion")
    product = idevice_value(udid, flags, "ProductType")
    record["model"] = product_marketing_name(product) if product else ""
    return record


def app_record(udid, bundle_id, flags):
    """Display name, version, and executable of the app under test."""
    record = {"name": "", "bundle_id": bundle_id, "version": "", "build": "", "executable": ""}
    if go_ios():
        code, text, _ = run([go_ios(), "apps", "--udid=%s" % udid], 60)
        apps = json_value(text, "[") if code == 0 else None
        apps = apps if isinstance(apps, list) else []
        item = next((app for app in apps if isinstance(app, dict) and app.get("CFBundleIdentifier") == bundle_id), {})
        record["name"] = item.get("CFBundleDisplayName") or item.get("CFBundleName") or ""
        record["version"] = item.get("CFBundleShortVersionString") or ""
        record["build"] = item.get("CFBundleVersion") or ""
        record["executable"] = item.get("CFBundleExecutable") or ""
        return record
    code, text, _ = run([
        "ideviceinstaller", "-u", udid, *flags, "list", "--user",
        "-a", "CFBundleIdentifier",
        "-a", "CFBundleDisplayName",
        "-a", "CFBundleName",
        "-a", "CFBundleShortVersionString",
        "-a", "CFBundleVersion",
        "-a", "CFBundleExecutable",
    ], 60)
    if code != 0:
        record["executable"] = executable_only(udid, bundle_id, flags)
        return record
    for row in csv.reader(io.StringIO(text.replace(', "', ',"'))):
        cells = [cell.strip().strip('"') for cell in row]
        if len(cells) >= 6 and cells[0] == bundle_id:
            record["name"] = cells[1] or cells[2]
            record["version"] = cells[3]
            record["build"] = cells[4]
            record["executable"] = cells[5]
            return record
    record["executable"] = executable_only(udid, bundle_id, flags)
    return record


def executable_only(udid, bundle_id, flags):
    code, text, _ = run(["ideviceinstaller", "-u", udid, *flags, "list", "--user", "-a", "CFBundleIdentifier", "-a", "CFBundleExecutable"], 60)
    if code != 0:
        return ""
    for row in csv.reader(io.StringIO(text.replace(', "', ',"'))):
        cells = [cell.strip().strip('"') for cell in row]
        if len(cells) >= 2 and cells[0] == bundle_id:
            return cells[1]
    return ""


def executable_name(udid, bundle_id, flags):
    return app_record(udid, bundle_id, flags)["executable"]


def pull_reports(udid, flags, destination):
    if go_ios():
        code, text, error = run([go_ios(), "crash", "cp", "*.ips", destination, "--udid=%s" % udid], 300)
        if code != 0:
            raise RuntimeError((error or text or "go-ios crash cp failed").strip().splitlines()[-1])
        return
    code, text, error = run(["idevicecrashreport", "-k", "-u", udid, *flags, destination], 300)
    if code != 0:
        raise RuntimeError((error or text or "idevicecrashreport failed").strip())


def read_report(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        raw = handle.read()
    first, _, rest = raw.partition("\n")
    try:
        header = json.loads(first)
    except json.JSONDecodeError:
        return None, None
    try:
        body = json.loads(rest)
    except json.JSONDecodeError:
        body = None
    return header, body


def frame_text(frame, images):
    image = images[frame["imageIndex"]] if 0 <= frame.get("imageIndex", -1) < len(images) else {}
    if not isinstance(image, dict):
        image = {}
    name = image.get("name") or "?"
    if frame.get("symbol"):
        return name, "%s %s + %s" % (name, frame["symbol"], frame.get("symbolLocation", 0))
    return name, "%s +0x%x" % (name, frame.get("imageOffset", 0))


def crash_frames(body):
    images = body.get("usedImages") or []
    frames = body.get("lastExceptionBacktrace")
    if not frames:
        threads = body.get("threads") or []
        index = body.get("faultingThread", 0)
        thread = threads[index] if 0 <= index < len(threads) else None
        frames = thread.get("frames", []) if isinstance(thread, dict) else []
    return [frame_text(frame, images) + (frame.get("symbol") or "",) for frame in frames]


def crash_message(body):
    lines = []
    reason = body.get("exceptionReason") or {}
    if reason.get("composed_message"):
        lines.append("%s: %s" % (reason.get("name") or "exception", reason["composed_message"]))
    for values in (body.get("asi") or {}).values():
        lines.extend(value for value in values if isinstance(value, str))
    return " ".join(lines)


def crash_type(body, frames):
    exception = body.get("exception") or {}
    termination = body.get("termination") or {}
    kind = exception.get("type") or ""
    signal = exception.get("signal") or ""
    if termination.get("namespace") == "FRONTBOARD" or termination.get("code") == WATCHDOG_CODE:
        return "看门狗超时（启动或主线程卡住太久，被系统结束）"
    if kind == "EXC_BAD_ACCESS":
        return "非法内存访问（EXC_BAD_ACCESS %s）" % signal
    if kind == "EXC_BREAKPOINT":
        symbols = [symbol for _, _, symbol in frames]
        if any("_checkSubscript" in symbol for symbol in symbols):
            return "Swift 运行时错误：数组越界（EXC_BREAKPOINT）"
        if any(SWIFT_TRAP in symbol for symbol in symbols):
            return "Swift 运行时错误：强制解包 nil、fatalError 或 precondition 等（EXC_BREAKPOINT）"
        return "运行时陷阱（EXC_BREAKPOINT）"
    if kind == "EXC_CRASH" and signal == "SIGABRT":
        if body.get("lastExceptionBacktrace") or "uncaught exception" in crash_message(body):
            return "未捕获的 Objective-C 异常（SIGABRT）"
        return "主动终止（abort 或断言，SIGABRT）"
    if kind == "EXC_RESOURCE":
        return "资源超限（EXC_RESOURCE）"
    if kind == "EXC_GUARD":
        return "受保护资源误用（EXC_GUARD）"
    return ("%s %s" % (kind, signal)).strip() or "未知"


def signature(type_label, frames):
    picked = []
    for image, text, symbol in frames:
        if image in NOISE_IMAGES or SWIFT_TRAP in symbol or any(symbol.startswith(noise) for noise in NOISE_SYMBOLS):
            continue
        # The offset of the first frame tells apart two crash sites in one function.
        picked.append(text if not picked else text.rsplit(" + ", 1)[0])
        if len(picked) == SIGNATURE_FRAMES:
            break
    return type_label + " | " + " > ".join(picked)


def collect_reports(directory, bundle_id, executable, since, until):
    crashes = []
    folder = directory if isinstance(directory, str) else os.fsdecode(directory)
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".ips"):
            continue
        report_path = str(pathlib.Path(folder) / name)
        header, body = read_report(report_path)
        if header is None or body is None:
            continue
        try:
            moment = parse_time(header.get("timestamp"))
        except ValueError:
            continue
        if moment < since or moment > until:
            continue
        if header.get("bug_type") == "309" and header.get("bundleID") == bundle_id:
            frames = crash_frames(body)
            label = crash_type(body, frames)
            crashes.append({
                "kind": "crash",
                "time": moment,
                "file": name,
                "path": report_path,
                "type": label,
                "exception": body.get("exception") or {},
                "termination": (body.get("termination") or {}).get("indicator", ""),
                "message": crash_message(body),
                "frames": [text for _, text, _ in frames[:FRAME_LIMIT]],
                "signature": signature(label, frames),
            })
        elif header.get("bug_type") == "298" and executable:
            for process in body.get("processes") or []:
                process_name = process.get("name") or ""
                # Jetsam truncates long process names. Keep the .ips name so two
                # events for the same executable do not overwrite one report file.
                if process_name and executable.startswith(process_name) and process.get("reason"):
                    label = "内存超限被系统结束（Jetsam %s）" % process["reason"]
                    crashes.append({
                        "kind": "jetsam",
                        "time": moment,
                        "file": name,
                        "path": report_path,
                        "type": label,
                        "exception": {},
                        "termination": "",
                        "message": "峰值约 %s 页" % process.get("lifetimeMax", "?"),
                        "frames": [],
                        "signature": label,
                    })
    crashes.sort(key=lambda item: item["time"])
    return crashes


def read_runner_log(log_path):
    anomalies = []
    summary = {}
    if not log_path or not os.path.isfile(log_path):
        return anomalies, summary
    with open(log_path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            step = STEP_RE.search(line)
            if step:
                if anomalies:
                    try:
                        anomalies[-1]["steps"].append(json.loads(step.group(1)))
                    except json.JSONDecodeError:
                        pass
                continue
            head = ANOMALY_RE.search(line)
            if head:
                try:
                    item = json.loads(head.group(1))
                    item["moment"] = parse_time(item.get("time"))
                except (json.JSONDecodeError, ValueError):
                    continue
                item["steps"] = []
                anomalies.append(item)
                continue
            total = SUMMARY_RE.search(line)
            if total:
                words = total.group(1).split()
                summary = {words[i]: int(words[i + 1]) for i in range(0, len(words) - 1, 2)}
    return anomalies, summary


def match_steps(crashes, anomalies):
    exits = [item for item in anomalies if item.get("kind") in CRASH_KINDS]
    used = set()
    for crash in crashes:
        for index, item in enumerate(exits):
            if index in used:
                continue
            if crash["time"] - MATCH_BEFORE <= item["moment"] <= crash["time"] + MATCH_AFTER:
                used.add(index)
                crash["steps"] = item["steps"]
                break
        crash.setdefault("steps", [])
    return [item for index, item in enumerate(exits) if index not in used]


def group(crashes):
    groups = {}
    for crash in crashes:
        groups.setdefault(crash["signature"], []).append(crash)
    return sorted(groups.values(), key=lambda items: (-len(items), items[0]["time"]))


def steps_rows(steps):
    rows = ["| 时间 | 页面 | 动作 | 目标 |", "| --- | --- | --- | --- |"]
    for step in steps:
        try:
            moment = local_text(parse_time(step.get("time")))
        except ValueError:
            moment = step.get("time", "")
        rows.append("| %s | %s | %s | %s |" % (moment, step.get("activity", ""), step.get("act", ""), (step.get("target") or "").replace("|", "\\|")))
    return rows


def table_rows(pairs):
    rows = ["| 项目 | 内容 |", "| --- | --- |"]
    for label, value in pairs:
        text = value if isinstance(value, str) else ""
        if text:
            rows.append("| %s | %s |" % (label, text.replace("|", "\\|")))
    return rows


def version_text(app):
    version = app.get("version") or ""
    build = app.get("build") or ""
    if version and build:
        return "%s (%s)" % (version, build)
    return version or build


def write_report(out, bundle_id, since, until, crashes, groups, unmatched, summary, timeouts, device, app):
    reports_dir = os.path.join(out, "reports")
    os.makedirs(reports_dir, exist_ok=True)
    for crash in crashes:
        shutil.copy2(crash["path"], os.path.join(reports_dir, crash["file"]))
    crash_count = sum(1 for crash in crashes if crash["kind"] == "crash")
    jetsam_count = sum(1 for crash in crashes if crash["kind"] == "jetsam")
    counted = []
    if isinstance(summary, dict):
        for kind in CRASH_KINDS:
            value = summary.get(kind, 0)
            counted.append(value if isinstance(value, int) else 0)
    runner_exits = sum(counted)
    raw_timeouts = summary.get("action_timeout", 0) if isinstance(summary, dict) else 0
    action_timeouts = raw_timeouts if isinstance(raw_timeouts, int) else 0
    since_text = local_text(since)
    until_text = local_text(until)
    device_info = {key: device.get(key) or "" for key in ("name", "model", "system", "udid")}
    app_info = {
        "name": app.get("name") or "",
        "bundle_id": app.get("bundle_id") or bundle_id,
        "version": app.get("version") or "",
        "build": app.get("build") or "",
    }
    data = {
        "bundle_id": bundle_id,
        "device": device_info,
        "app": app_info,
        "since": since_text,
        "until": until_text,
        "runner": summary,
        "crash_count": crash_count,
        "jetsam_count": jetsam_count,
        "groups": [
            {
                "type": items[0]["type"],
                "signature": items[0]["signature"],
                "count": len(items),
                "times": [local_text(item["time"]) for item in items],
                "files": ["reports/" + item["file"] for item in items],
                "message": items[0]["message"],
                "frames": items[0]["frames"],
                "steps": next((item["steps"] for item in items if item["steps"]), []),
            }
            for items in groups
        ],
        "exits_without_report": [{"kind": item["kind"], "time": local_text(item["moment"]), "steps": item["steps"]} for item in unmatched],
        "timeouts": [{"time": local_text(item["moment"]), "steps": item["steps"]} for item in timeouts],
    }
    with open(os.path.join(out, "crash-report.json"), "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)

    lines = [
        "# 崩溃报告",
        "",
        "## 测试机型",
        "",
        *table_rows([
            ("名称", device_info["name"]),
            ("机型", device_info["model"]),
            ("系统", device_info["system"]),
            ("UDID", device_info["udid"]),
        ]),
        "",
        "## 被测应用",
        "",
        *table_rows([
            ("名称", app_info["name"]),
            ("Bundle ID", app_info["bundle_id"]),
            ("版本", version_text(app_info)),
        ]),
        "",
        "时间 %s 至 %s。" % (since_text, until_text),
        "",
        "| 项目 | 次数 |",
        "| --- | --- |",
        "| 崩溃日志 | %d |" % crash_count,
        "| 内存超限 | %d |" % jetsam_count,
        "| 不同崩溃点 | %d |" % len(groups),
        "| Runner 检测到进程退出 | %d |" % runner_exits,
        "| 动作超时 | %d |" % action_timeouts,
        "",
    ]
    for number, items in enumerate(groups, 1):
        head = items[0]
        label = head.get("type") if isinstance(head, dict) else ""
        times = [local_text(item["time"]) for item in items]
        files = ["reports/" + item["file"] for item in items]
        message = head.get("message") if isinstance(head, dict) else ""
        frames = head.get("frames") if isinstance(head, dict) else []
        steps = next((item["steps"] for item in items if item.get("steps")), [])
        lines += ["## %d. %s（%d 次）" % (number, label if isinstance(label, str) else "", len(items)), ""]
        lines.append("时间：%s。日志：%s。" % ("、".join(times), "、".join("`%s`" % name for name in files)))
        if message:
            lines += ["", "系统信息：%s" % message]
        if frames:
            lines += ["", "```text"] + list(frames) + ["```"]
        if steps:
            lines += ["", "崩溃前的操作："] + [""] + steps_rows(steps)
        lines.append("")
    if data["exits_without_report"]:
        lines += ["## 进程退出但没有找到系统日志", "", "可能是被系统正常回收、被其他进程结束，或日志还没写出。", ""]
        for item in unmatched:
            lines += ["- %s，%s" % (local_text(item["moment"]), item["kind"])]
        lines.append("")
    if timeouts:
        lines += ["## 动作超时", ""]
        for item in timeouts:
            lines += ["%s：" % local_text(item["moment"]), ""] + steps_rows(item["steps"]) + [""]
    with open(os.path.join(out, "crash-report.md"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    return data


def main():
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n\n")[0])
    parser.add_argument("--udid", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--since", required=True, help="local time 'YYYY-MM-DD HH:MM:SS' or epoch seconds")
    parser.add_argument("--until", default="", help="defaults to now")
    parser.add_argument("--log", default="", help="xcodebuild output of the run")
    parser.add_argument("--out", required=True)
    parser.add_argument("--settle", type=float, default=5.0, help="seconds to wait for the last report to be written")
    args = parser.parse_args()

    since = parse_time(args.since)
    if args.settle > 0:
        time.sleep(args.settle)
    until = parse_time(args.until) if args.until else datetime.now(timezone.utc)
    flags = device_flags(args.udid)
    target_app = app_record(args.udid, args.bundle_id, flags)
    target_device = device_record(args.udid, flags)
    executable = target_app["executable"]
    anomalies, summary = read_runner_log(args.log)
    os.makedirs(args.out, exist_ok=True)
    pulled = tempfile.mkdtemp(prefix="pull-", dir=args.out)
    try:
        try:
            pull_reports(args.udid, flags, pulled)
        except RuntimeError as exc:
            print("crash collect failed: %s" % exc)
            return 1
        crashes = collect_reports(pulled, args.bundle_id, executable, since, until)
        unmatched = match_steps(crashes, anomalies)
        groups = group(crashes)
        timeouts = [item for item in anomalies if item.get("kind") == "action_timeout"]
        write_report(args.out, args.bundle_id, since, until, crashes, groups, unmatched, summary, timeouts, target_device, target_app)
    finally:
        shutil.rmtree(pulled, ignore_errors=True)
    crash_count = sum(1 for crash in crashes if crash["kind"] == "crash")
    jetsam_count = sum(1 for crash in crashes if crash["kind"] == "jetsam")
    counted = []
    if isinstance(summary, dict):
        for kind in CRASH_KINDS:
            value = summary.get(kind, 0)
            counted.append(value if isinstance(value, int) else 0)
    runner_exits = sum(counted)
    raw_timeouts = summary.get("action_timeout", 0) if isinstance(summary, dict) else 0
    action_timeouts = raw_timeouts if isinstance(raw_timeouts, int) else 0
    print("crash collect crash %d jetsam %d signatures %d runner_exits %d timeouts %d" % (
        crash_count, jetsam_count, len(groups), runner_exits, action_timeouts))
    for items in groups:
        head = items[0] if items else {}
        stack_text = head.get("signature") if isinstance(head, dict) else ""
        label = head.get("type") if isinstance(head, dict) else ""
        top = stack_text.split(" | ", 1)[-1] if isinstance(stack_text, str) else ""
        print("  %dx %s | %s" % (len(items), label if isinstance(label, str) else "", top))
    print("crash report written %s" % os.path.join(args.out, "crash-report.md"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
