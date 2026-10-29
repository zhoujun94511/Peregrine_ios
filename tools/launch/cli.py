#!/usr/bin/env python3
"""Command-line counterpart of the launch page: list devices and apps, run, collect, and export."""

import argparse
import os
import subprocess
import sys
import time

sys.dont_write_bytecode = True

from core import (  # noqa: E402
    BACKENDS,
    COLLECT_TIMEOUT,
    DURATION_MAX,
    IOS_DIR,
    LOG_DIR,
    ROUNDS_DIR,
    round_home,
    RUN_DIR,
    SHOTS_MODES,
    STAMP_RE,
    THROTTLE_MAX,
    FieldError,
    backend,
    check_paths,
    collect_command,
    install_commands,
    is_simulator,
    keep_runs_count,
    list_apps,
    list_devices,
    list_runs,
    new_stamp,
    parse_env,
    probe_stub,
    prune_runs,
    pull_device_files,
    pull_report,
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
from perf import HostPerf, perf_report_line, pymobiledevice3  # noqa: E402


class CliError(RuntimeError):
    pass


def resolve_udid(udid):
    if udid:
        return udid
    devices = list_devices()
    if len(devices) == 1:
        return devices[0]["udid"]
    if not devices:
        raise CliError("没有找到已连接的 iPhone" if backend() == "goios" else "没有找到已连接的 iPhone 或已启动的模拟器")
    names = "\n".join("  %s  %s" % (device["udid"], device["label"]) for device in devices)
    raise CliError("连接了多台设备，用 --udid 指定其中一台：\n%s" % names)

def check_installed(udid, bundle_id):
    try:
        installed = {app["bundleId"] for app in list_apps(udid)}
    except (RuntimeError, subprocess.TimeoutExpired) as exc:
        raise CliError("这台设备暂时读不到应用：%s" % exc) from exc
    if bundle_id not in installed:
        raise CliError("这台设备上没有 %s" % bundle_id)

def stream(command, environment, log_path, preface=""):
    proc, master = spawn_output(command, environment, IOS_DIR, False)
    interrupted = False
    output = RunOutput()
    with open(log_path, "w", encoding="utf-8", errors="replace", newline="\n") as handle:
        handle.write(preface)
        while True:
            try:
                chunk = os.read(master, 4096)
            except KeyboardInterrupt:
                interrupted = True
                continue
            except OSError:
                break
            if not chunk:
                break
            text = output.feed(chunk)
            sys.stdout.write(text)
            sys.stdout.flush()
            handle.write(text)
        text = output.finish()
        sys.stdout.write(text)
        handle.write(text)
    os.close(master)
    code = 1
    while True:
        try:
            code = proc.wait()
            break
        except KeyboardInterrupt:
            interrupted = True
    if interrupted:
        print("\nrun interrupted", flush=True)
    return code


def append_log(log_path, text):
    sys.stdout.write(text)
    sys.stdout.flush()
    with open(log_path, "a", encoding="utf-8", errors="replace") as handle:
        handle.write(text)


def collect(udid, bundle_id, since, paths):
    try:
        copied, missing = pull_device_files(udid, bundle_id, paths["device"])
        line = pull_report(copied, missing)
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
        line = "device files failed: %s\n" % exc
    append_log(paths["log"], "\n" + line)
    if is_simulator(udid):
        append_log(paths["log"], "crash collect skipped: 模拟器不拉取系统崩溃日志\n")
        return
    append_log(paths["log"], "crash collect start\n")
    command = collect_command(udid, bundle_id, since, paths["log"], paths["crash"])
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
    append_log(paths["log"], output if output.endswith("\n") else output + "\n")


def export_run(stamp, out):
    path = out or os.path.join(round_home("run", stamp), "peregrine-run-%s.zip" % stamp)
    if os.path.isdir(path):
        path = os.path.join(path, "peregrine-run-%s.zip" % stamp)
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, exist_ok=True)
    with open(path, "wb") as handle:
        write_export(stamp, handle)
    print("export success %s" % os.path.abspath(path), flush=True)


def cmd_devices(_args):
    devices = list_devices()
    if not devices:
        print("没有找到已连接的 iPhone" if backend() == "goios" else "没有找到已连接的 iPhone 或已启动的模拟器")
        return 1
    for device in devices:
        print("%s  %-8s %s" % (device["udid"], device["link"] or "-", device["name"]))
    return 0


def cmd_apps(args):
    udid = resolve_udid(args.udid)
    for app in list_apps(udid):
        print("%-50s %-12s %s" % (app["bundleId"], app["version"] or "-", app["name"]))
    return 0


def cmd_run(args):
    udid = resolve_udid(args.udid)
    duration = whole_number(args.duration, "duration", 1, DURATION_MAX, "--duration ")
    throttle = whole_number(args.throttle, "throttle", 1, THROTTLE_MAX, "--throttle ")
    dataport = whole_number(args.dataport, "dataport", 0, 65535, "--dataport ")
    extra = parse_env(args.env)
    keep = keep_runs_count(args.keep)
    check_installed(udid, args.bundle_id)
    port, preface = dataport, ""
    if not args.no_stub_check:
        port, preface = stub_preflight(udid, args.bundle_id, dataport)
        sys.stdout.write(preface)
    team = args.team or signing_team()
    os.makedirs(RUN_DIR, exist_ok=True)
    pruned = prune_runs(keep - 1 if keep > 0 else 0)
    if pruned > 0:
        print("runs pruned %d keep %d" % (pruned, keep), flush=True)
    stamp = new_stamp()
    paths = run_paths(stamp)
    print("run %s log %s" % (stamp, paths["log"]), flush=True)
    since = str(time.time())
    command = test_command(udid, "explore", paths["xcresult"], team)
    host_perf = None
    if args.perf and is_simulator(udid):
        line = "perf host skipped: 模拟器没有 Instruments 通道\n"
        sys.stdout.write(line)
        preface += line
    elif args.perf:
        try:
            host_perf = HostPerf(udid, args.bundle_id, pymobiledevice3())
            host_perf.prepare()
            host_perf.start(paths["device"])
            line = "perf host start %s\n" % host_perf.name
        except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
            if host_perf is not None:
                host_perf.stop()
            host_perf = None
            line = "perf host skipped: %s\n" % exc
        sys.stdout.write(line)
        preface += line
    try:
        code = stream(command, test_environment(args.bundle_id, duration, throttle, port, extra, args.shots, args.perf), paths["log"], preface)
    finally:
        if host_perf is not None:
            host_perf.stop()
    if host_perf is not None:
        append_log(paths["log"], host_perf.line() + "\n")
    if not args.no_collect:
        collect(udid, args.bundle_id, since, paths)
    if args.perf:
        append_log(paths["log"], perf_report_line(paths["device"]) + "\n")
    if args.export is not None:
        export_run(stamp, args.export)
    elif args.shots != "off" and not args.no_collect:
        export_run(stamp, "")
    print("run %s exit %d" % (stamp, code), flush=True)
    return code


def cmd_check(args):
    udid = resolve_udid(args.udid)
    dataport = whole_number(args.dataport, "dataport", 0, 65535, "--dataport ")
    extra = parse_env(args.env)
    if dataport > 0 and not args.bundle_id:
        raise CliError("检查插桩时需要同时给 --bundle-id")
    team = args.team or signing_team()
    os.makedirs(RUN_DIR, exist_ok=True)
    stamp = new_stamp()
    paths = check_paths(stamp)
    print("check %s log %s" % (stamp, paths["log"]), flush=True)
    command = test_command(udid, "check", paths["xcresult"], team)
    code = stream(command, test_environment(args.bundle_id, 0, 0, dataport, extra), paths["log"])
    print("check %s exit %d" % (stamp, code), flush=True)
    return code


def cmd_install(args):
    if backend() != "xcode":
        raise CliError("install 需要在装有 Xcode 的 Mac 上执行")
    udid = resolve_udid(args.udid)
    if is_simulator(udid):
        raise CliError("install 只把 Runner 装到真机，供其他电脑经 go-ios 运行")
    team = args.team or signing_team()
    os.makedirs(LOG_DIR, exist_ok=True)
    log_path = os.path.join(LOG_DIR, "install-%s.log" % new_stamp())
    build, install = install_commands(udid, team)
    code = stream(build, os.environ.copy(), log_path)
    if code != 0:
        print("install build failed exit %d, log %s" % (code, log_path), flush=True)
        return code
    completed = subprocess.run(install, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False)
    append_log(log_path, completed.stdout)
    if completed.returncode != 0:
        print("install failed exit %d, log %s" % (completed.returncode, log_path), flush=True)
        return completed.returncode
    print("install success %s" % udid, flush=True)
    return 0


def cmd_stub(args):
    udid = resolve_udid(args.udid)
    dataport = whole_number(args.dataport, "dataport", 1, 65535, "--dataport ")
    check_installed(udid, args.bundle_id)
    check = probe_stub(udid, args.bundle_id, dataport)
    if os.name == "nt" and check["state"] == "ok":
        closed = " closed %s" % check["closed"] if check.get("closed") else ""
        print("stub check success %s port %d%s" % (args.bundle_id, dataport, closed))
    else:
        print("stub check %s: %s" % (check["state"], check["message"]))
    return 0 if check["usable"] else 1


def cmd_pull(args):
    udid = resolve_udid(args.udid)
    out = args.out or os.path.join(ROUNDS_DIR, "pull-%s" % new_stamp())
    copied, missing = pull_device_files(udid, args.bundle_id, out, args.previous)
    print(pull_report(copied, missing), end="")
    print("device files written %s" % os.path.abspath(out))
    return 0


def cmd_runs(_args):
    stamps = list_runs()
    if not stamps:
        print("还没有运行记录")
        return 0
    for stamp in stamps:
        paths = run_paths(stamp)
        parts = [name for name, path in paths.items() if os.path.exists(path)]
        print("%s  %s" % (stamp, " ".join(parts)))
    return 0


def cmd_export(args):
    stamps = list_runs()
    stamp = args.run or (stamps[-1] if stamps else "")
    if not stamp:
        raise CliError("还没有可导出的运行记录")
    if not STAMP_RE.match(stamp) or stamp not in stamps:
        raise CliError("没有这一轮：%s，用 runs 查看已有记录" % stamp)
    export_run(stamp, args.out)
    return 0


def build_parser():
    parser = argparse.ArgumentParser(prog="cli.py", description="Peregrine 命令行：列设备与应用、跑探索、拉结果、导出。")
    parser.add_argument(
        "--backend",
        choices=BACKENDS,
        help="xcode 经 Xcode 编译并运行；goios 经 go-ios 驱动手机上已安装的 Runner。默认 Mac 上有 Xcode 时用 xcode，否则用 goios",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    install = commands.add_parser("install", help="在 Mac 上编译 Runner 并安装到手机，供其他电脑经 go-ios 运行")
    install.add_argument("--udid", help="设备 UDID；只连一台时可省略")
    install.add_argument("--team", help="开发团队；默认取 DEVELOPMENT_TEAM 或本机 Apple Development 证书")

    commands.add_parser("devices", help="列出已连接的 iPhone")

    apps = commands.add_parser("apps", help="列出设备上的应用")
    apps.add_argument("--udid", help="设备 UDID；只连一台时可省略")

    run = commands.add_parser("run", help="跑一轮探索，结束后拉回设备结果并收集崩溃")
    run.add_argument("--bundle-id", required=True, help="被测应用的 Bundle ID")
    run.add_argument("--udid", help="设备 UDID；只连一台时可省略")
    run.add_argument("--duration", default="1", help="时长，分钟，默认 1")
    run.add_argument("--throttle", default="300", help="节流，毫秒，默认 300")
    run.add_argument("--dataport", default="0", help="插桩数据端口，0 表示不用插桩")
    run.add_argument("--team", help="开发团队；默认取 DEVELOPMENT_TEAM 或本机 Apple Development 证书")
    run.add_argument("--env", action="append", metavar="KEY=VALUE", help="额外传给 Runner 的环境变量，可重复")
    run.add_argument("--no-stub-check", action="store_true", help="跳过开跑前的插桩检测，端口原样交给 Runner")
    run.add_argument("--no-collect", action="store_true", help="结束后不拉设备结果、不收集崩溃")
    run.add_argument("--export", nargs="?", const="", metavar="PATH", help="结束后打包成 zip；不给路径时写进这一轮自己的目录")
    run.add_argument("--shots", choices=SHOTS_MODES, default="off", help="每步存截图并标出候选块和点击目标：change 只存画面变化的步骤，all 每步都存；开启后结束时自动打包")
    run.add_argument("--perf", action="store_true", help="采集被测应用的资源数据：电脑端每秒采一次内存、CPU、线程数、磁盘读写、文件与端口数、唤醒次数和屏幕帧率，并记录前后台切换；插桩模式下另外每步读一次内存、CPU、主线程卡顿、内存警告和设备温度")
    run.add_argument("--keep", help="开跑前按轮次目录清理 .local/rounds，只保留最近几轮（含本轮），默认 20，0 表示不清理")

    check = commands.add_parser("check", help="通信检查 testPingNetwork")
    check.add_argument("--udid", help="设备 UDID；只连一台时可省略")
    check.add_argument("--bundle-id", help="同时检查插桩时的被测应用")
    check.add_argument("--dataport", default="0", help="插桩数据端口")
    check.add_argument("--team", help="开发团队")
    check.add_argument("--env", action="append", metavar="KEY=VALUE", help="额外传给 Runner 的环境变量，可重复")

    stub = commands.add_parser("stub", help="检测被测应用是否接入插桩并在数据端口应答")
    stub.add_argument("--bundle-id", required=True, help="被测应用的 Bundle ID")
    stub.add_argument("--dataport", required=True, help="插桩数据端口")
    stub.add_argument("--udid", help="设备 UDID；只连一台时可省略")

    pull = commands.add_parser("pull", help="从设备拉回 Runner 的结果文件")
    pull.add_argument("--udid", help="设备 UDID；只连一台时可省略")
    pull.add_argument("--bundle-id", help="同时拉回该应用的跨轮复用文件")
    pull.add_argument("--out", help="输出目录，默认 .local/rounds/pull-<时间>")
    pull.add_argument("--previous", action="store_true", help="拉回上一轮的结果；新一轮开始时会把上一轮挪到备份目录")

    commands.add_parser("runs", help="列出 .local/rounds 里每一轮的目录")

    export = commands.add_parser("export", help="把一轮结果打包成 zip")
    export.add_argument("--run", help="运行时间戳，如 20261021-174725；默认最近一轮")
    export.add_argument("--out", help="zip 路径或目录，默认写进这一轮目录里的 peregrine-run-<时间>.zip")
    return parser


HANDLERS = {
    "install": cmd_install,
    "devices": cmd_devices,
    "apps": cmd_apps,
    "run": cmd_run,
    "check": cmd_check,
    "stub": cmd_stub,
    "pull": cmd_pull,
    "runs": cmd_runs,
    "export": cmd_export,
}


def main():
    args = build_parser().parse_args()
    if args.backend:
        os.environ["PEREGRINE_BACKEND"] = args.backend
    tool_path()
    try:
        return HANDLERS[args.command](args)
    except (CliError, FieldError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
