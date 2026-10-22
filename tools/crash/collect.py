#!/usr/bin/env python3
"""Pulls the crash and jetsam reports of the app under test for one run, groups them by
stack signature, and attaches the steps Peregrine logged before each one.

    python3 tools/crash/collect.py --udid <UDID> --bundle-id <bundle id> \
        --since "2026-10-21 16:00:00" [--until ...] [--log run.log] --out <dir>

Needs idevicecrashreport and ideviceinstaller (libimobiledevice), or go-ios when
PEREGRINE_BACKEND=goios (the ios command on PATH, or GO_IOS).
"""

import argparse
import csv
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone

ANOMALY_RE = re.compile(r"peregrine anomaly (\{.*})\s*$")
STEP_RE = re.compile(r"peregrine anomaly step (\{.*})\s*$")
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
        if os.name == "nt":
            completed = subprocess.run(
                args,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                encoding="utf-8",
                errors="replace",
                timeout=timeout,
                check=False,
            )
        else:
            completed = subprocess.run(
                args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout, check=False
            )
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
    return os.environ.get("GO_IOS", "").strip() or shutil.which("ios") or "ios"


def device_flags(udid):
    if go_ios():
        return []
    _, usb, _ = run(["idevice_id", "-l"], 15)
    return [] if udid in usb.split() else ["-n"]


def executable_name(udid, bundle_id, flags):
    if go_ios():
        code, text, _ = run([go_ios(), "apps", "--udid=%s" % udid], 60)
        line = next((line for line in reversed(text.splitlines()) if line.startswith("[")), "[]") if code == 0 else "[]"
        try:
            apps = json.loads(line)
        except ValueError:
            apps = []
        return next((app.get("CFBundleExecutable") or "" for app in apps if app.get("CFBundleIdentifier") == bundle_id), "")
    code, text, _ = run(["ideviceinstaller", "-u", udid, *flags, "list", "--user", "-a", "CFBundleIdentifier", "-a", "CFBundleExecutable"], 60)
    if code != 0:
        return ""
    for row in csv.reader(io.StringIO(text.replace(', "', ',"'))):
        if len(row) >= 2 and row[0].strip().strip('"') == bundle_id:
            return row[1].strip().strip('"')
    return ""


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
        frames = threads[index].get("frames", []) if 0 <= index < len(threads) else []
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
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".ips"):
            continue
        path = os.path.join(directory, name)
        header, body = read_report(path)
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
                "path": path,
                "type": label,
                "exception": body.get("exception") or {},
                "termination": (body.get("termination") or {}).get("indicator", ""),
                "message": crash_message(body),
                "frames": [text for _, text, _ in frames[:FRAME_LIMIT]],
                "signature": signature(label, frames),
            })
        elif header.get("bug_type") == "298" and executable:
            for process in body.get("processes") or []:
                name = process.get("name") or ""
                # Jetsam truncates long process names.
                if name and executable.startswith(name) and process.get("reason"):
                    label = "内存超限被系统结束（Jetsam %s）" % process["reason"]
                    crashes.append({
                        "kind": "jetsam",
                        "time": moment,
                        "file": name,
                        "path": path,
                        "type": label,
                        "exception": {},
                        "termination": "",
                        "message": "峰值约 %s 页" % process.get("lifetimeMax", "?"),
                        "frames": [],
                        "signature": label,
                    })
    crashes.sort(key=lambda item: item["time"])
    return crashes


def read_runner_log(path):
    anomalies = []
    summary = {}
    if not path or not os.path.isfile(path):
        return anomalies, summary
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
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


def write_report(out, bundle_id, since, until, crashes, groups, unmatched, summary, timeouts):
    reports_dir = os.path.join(out, "reports")
    os.makedirs(reports_dir, exist_ok=True)
    for crash in crashes:
        shutil.copy2(crash["path"], os.path.join(reports_dir, crash["file"]))
    data = {
        "bundle_id": bundle_id,
        "since": local_text(since),
        "until": local_text(until),
        "runner": summary,
        "crash_count": sum(1 for crash in crashes if crash["kind"] == "crash"),
        "jetsam_count": sum(1 for crash in crashes if crash["kind"] == "jetsam"),
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
        "被测应用 `%s`，时间 %s 至 %s。" % (bundle_id, data["since"], data["until"]),
        "",
        "| 项目 | 次数 |",
        "| --- | --- |",
        "| 崩溃日志 | %d |" % data["crash_count"],
        "| 内存超限 | %d |" % data["jetsam_count"],
        "| 不同崩溃点 | %d |" % len(groups),
        "| Runner 检测到进程退出 | %d |" % sum(summary.get(kind, 0) for kind in CRASH_KINDS),
        "| 动作超时 | %d |" % summary.get("action_timeout", 0),
        "",
    ]
    for number, entry in enumerate(data["groups"], 1):
        lines += ["## %d. %s（%d 次）" % (number, entry["type"], entry["count"]), ""]
        lines.append("时间：%s。日志：%s。" % ("、".join(entry["times"]), "、".join("`%s`" % path for path in entry["files"])))
        if entry["message"]:
            lines += ["", "系统信息：%s" % entry["message"]]
        if entry["frames"]:
            lines += ["", "```text"] + entry["frames"] + ["```"]
        if entry["steps"]:
            lines += ["", "崩溃前的操作："] + [""] + steps_rows(entry["steps"])
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
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
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
    executable = executable_name(args.udid, args.bundle_id, flags)
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
        data = write_report(args.out, args.bundle_id, since, until, crashes, groups, unmatched, summary, timeouts)
    finally:
        shutil.rmtree(pulled, ignore_errors=True)
    print("crash collect crash %d jetsam %d signatures %d runner_exits %d timeouts %d" % (
        data["crash_count"], data["jetsam_count"], len(groups), sum(summary.get(kind, 0) for kind in CRASH_KINDS), summary.get("action_timeout", 0)))
    for entry in data["groups"]:
        top = entry["signature"].split(" | ", 1)[-1]
        print("  %dx %s | %s" % (entry["count"], entry["type"], top))
    print("crash report written %s" % os.path.join(args.out, "crash-report.md"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
