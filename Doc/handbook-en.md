# Handbook

[简体中文](handbook-cn.md) · [English](handbook-en.md)

For setup, signing, and the first run, see the [README](../README_en.md). This document covers day-to-day execution, physical device vs Simulator, environment variables, configuration files, result files, and crash collection.

## Running a test

The app under test must already be installed on the target and must open by hand. The target is an unlocked iPhone connected by cable, or a booted Simulator. See "Physical device and Simulator" below.

Start the launch page from the repository root:

```shell
python3 tools/launch/server.py
```

Open `http://127.0.0.1:8765/` or the LAN address printed at startup. Choose a device and an app. Duration is in minutes, throttle in milliseconds. Leave the data port empty to use screenshots. After filling a data port, click **检测** (probe) next to it to restart the app on a physical phone and confirm that its stub answers on that port; the result is shown under the field. A Simulator cannot be probed from the host, so **检测** is disabled and the Runner probes after launch. Click **开始** (start). If a data port is filled and the target is a physical phone, the same probe runs before the start: when the app has no stub, or another app's stub answers on the port, this run does not pass the data port and uses screenshots instead; the reason is the first log line. Closing the page does not stop the test; click **终止** (stop). **通信检查** (communication check) runs `testPingNetwork` below and only needs a device; if a data port is filled, the app under test must also be selected and the stub is checked. Logs and `.xcresult` are stored as `check-<time>`, without pulling device files, collecting crashes, or exporting a bundle.

The development team defaults to the local Apple Development certificate. To set it:

```shell
DEVELOPMENT_TEAM=<Team ID> python3 tools/launch/server.py
```

Startup opens the local address in the default browser. On a machine without a GUI, or when you do not want that, set `PEREGRINE_LAUNCH_NO_BROWSER=1`. The server listens on every interface by default; other computers on the same LAN can open the printed `LAN http://<address>:8765/` and share this page. Start, stop, and the log all act on the computer that runs the launch page. To accept local connections only, set `PEREGRINE_LAUNCH_HOST=127.0.0.1`. To use a port other than 8765, set `PEREGRINE_LAUNCH_PORT`.

### Command line

`tools/launch/cli.py` has the same capabilities as the launch page. They share `tools/launch/core.py`. Tunnel and install logs are in `tools/launch/.run/`. Downloads are in `tools/launch/.local/`, and each run's log and results are in `tools/launch/.local/rounds/<stamp>/`. Results from the CLI show up on the page and the other way around. From the repository root:

```shell
python3 tools/launch/cli.py install [--udid <UDID>] [--team <Team ID>]
python3 tools/launch/cli.py devices
python3 tools/launch/cli.py apps [--udid <UDID>]
python3 tools/launch/cli.py run --bundle-id com.example.app [--duration 10] [--throttle 300] \
  [--dataport 9797] [--env PEREGRINE_UI_SOURCE=combined] [--export [<path>]] [--shots off|change|all] [--perf] [--keep 20]
python3 tools/launch/cli.py check [--bundle-id com.example.app --dataport 9797]
python3 tools/launch/cli.py stub --bundle-id com.example.app --dataport 9797
python3 tools/launch/cli.py pull [--bundle-id com.example.app] [--out <dir>] [--previous]
python3 tools/launch/cli.py runs
python3 tools/launch/cli.py export [--run <stamp>] [--out <path>]
```

| Subcommand | Role                                                                                                                                                                                                                                                                                                                                                                                                              |
|------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `install`  | Mac with Xcode only: `xcodebuild build-for-testing` builds the Runner, then `devicectl` installs it on a **physical phone**, without running a test. The log is `install-<time>.log`. Rejects a Simulator                                                                                                                                                                                                         |
| `devices`  | Lists connected iPhones (USB / Network) and, on the `xcode` path, booted Simulators (`Simulator`)                                                                                                                                                                                                                                                                                                                 |
| `apps`     | Lists user-installed apps on the target: Bundle ID, version, name. Physical phone: `ideviceinstaller` / `ios apps`. Simulator: `simctl listapps`                                                                                                                                                                                                                                                                  |
| `run`      | One exploration run. Output is printed live and written to `run-<time>.log`; afterwards result files are pulled; crash logs are collected on a physical phone and skipped on a Simulator. `--export` also writes a zip, defaulting to `.local/rounds/` when no path is given. When `--shots` is not `off`, a zip is written to `.local/rounds/` even without `--export` (unless `--no-collect`). The exit code matches `xcodebuild` |
| `check`    | Runs `testPingNetwork`. Log and `.xcresult` are stored as `check-<time>` and are not counted as a run                                                                                                                                                                                                                                                                                                             |
| `stub`     | Checks whether the app under test has the stub and answers on the data port; see "Instrumentation" below. Exit code 0 if usable, otherwise 1. On a Simulator the host-side probe is skipped (`stub check skipped`, exit 0)                                                                                                                                                                                        |
| `pull`     | Pulls `peregrine-events.jsonl`, `peregrine-coverage.txt`, `peregrine-applet.txt`, and `peregrine-shots.zip` (only when step screenshots are on) from the Runner temp directory; with `--bundle-id` also pulls that app's reuse file; `--previous` pulls the previous-run backup, without the reuse file. Physical phone: `devicectl` / `ios fsync`. Simulator: `simctl get_app_container`                         |
| `runs`     | Lists each stamp under `.local/rounds/` and which artifacts it has (log, xcresult, crash, device)                                                                                                                                                                                                                                                                                                                                              |
| `export`   | Packs one run's log, `.xcresult`, crash report, and device files into `peregrine-run-<time>.zip`, defaulting to the latest run                                                                                                                                                                                                                                                                                    |

Shared rules:

- `--backend xcode|goios` goes before the subcommand and selects the runner path; see "Running on Linux and Windows" below.
- `--udid` can be omitted when one target is connected; with several targets, they are listed and the command exits.
- The team is taken from `--team`, then `DEVELOPMENT_TEAM`, then the local Apple Development certificate.
- `--env KEY=VALUE` can be repeated for variables the launch page does not expose, such as `PEREGRINE_UI_SOURCE`, `PEREGRINE_COMMAND_PORT`, `PEREGRINE_STRINGS`. `--bundle-id`, `--duration`, `--throttle`, and `--dataport` override the same names in `--env`.
- `--shots change|all` turns on step screenshots; see "Step screenshots" below. The default is `off`, the same as `PEREGRINE_SHOTS`.
- `--perf` turns on resource sampling; see "Resource sampling" below. It also sets `PEREGRINE_PERF=1`. A Simulator has no host Instruments path; the variable is still passed to the Runner for stub-side sampling.
- Before `run`, the oldest directories in `.local/rounds/` are removed, leaving the last `--keep` runs (including this one; default 20; 0 means no prune). One run is one `run-<time>/` or `check-<time>/` directory holding the log, `.xcresult`, `device/`, `crash/`, and zip. `.local/tools/`, `.local/devimages/`, `.local/build/`, `.local/state.json`, and `.run/` are left alone. The log prints `runs pruned <n> keep <kept>`. The launch page reads `PEREGRINE_KEEP_RUNS`, default 20.
- Ctrl+C during `run` only stops the test; result files are still pulled. A physical phone then collects crashes; a Simulator skips that. Add `--no-collect` to skip collection.
- When `--dataport` is greater than 0, a physical-phone `run` does the same check as `stub` and writes the result as the first log line; if the stub is not usable, this run uses screenshots. A Simulator skips the host-side check and passes the port through. `--no-stub-check` skips the check.
- When the physical-phone app list cannot be read (for example `ideviceinstaller` is missing), `run` prints `app check skipped` and continues. A Simulator lists apps through `simctl listapps`.
- Bad arguments or an unavailable device go to stderr with exit code 2.

You can also call `xcodebuild` from `Peregrine/`. That path does not pull device files or collect crashes:

```shell
PEREGRINE_BUNDLEID=com.example.app \
PEREGRINE_DURATION=10 \
PEREGRINE_THROTTLE=300 \
xcodebuild test \
  -workspace Peregrine.xcworkspace \
  -scheme PeregrineRunner \
  -destination 'platform=iOS,id=<device UDID>' \
  -only-testing:PeregrineRunner/PeregrineRunner/testPeregrine \
  DEVELOPMENT_TEAM=<Team ID> \
  -allowProvisioningUpdates
```

The physical-phone UDID is the identifier of the target iPhone in `xcrun xctrace list devices`. For a Simulator, use `-destination 'platform=iOS Simulator,id=<UUID>'`. The UUID is in `xcrun simctl list devices booted`, or the launch page / `cli.py devices` row marked Simulator.

When the launch page or `cli.py` runs a test, the run log does not include XCTest activity lines — the `t =` lines in `xcodebuild` output that record each element query, idle wait, and event synthesis. Activity lines that contain `Assertion Failure` are kept. At the end the log prints `xctest activity hidden <n> lines, see .xcresult`. The full activity tree is in the `.xcresult`; open it in Xcode, or run `xcrun xcresulttool get test-results activities --path <.xcresult path> --test-id PeregrineRunner/testPeregrine`. Each step's action, target, and duration are already in `peregrine-events.jsonl`.

`ui source`, a final `coverage <pages>: ...` and `coverage written`, and `** TEST SUCCEEDED **` mean the test finished. The launch page writes the same output to `tools/launch/.local/rounds/run-<time>/run-<time>.log`. After each run it pulls `peregrine-events.jsonl`, `peregrine-coverage.txt`, `peregrine-applet.txt`, `peregrine-shots.zip` (when step screenshots are on), and the app's `peregrine-<Bundle ID>.reuse.json` from the Runner temp directory (physical phone: `xcrun devicectl` on the Xcode path, `ios fsync` on go-ios; Simulator: `simctl get_app_container`) into that run's `device/`, writes the crash report into `crash/`, and prints `device files success` plus the file names.

A run is one `testPeregrine`: one **开始** on the launch page, one `cli.py run`, or one `xcodebuild test`, until the configured duration ends. Result files are not deleted during a run, except that step screenshots above the limit drop the oldest ones of this run.

At the start of each run the Runner moves the previous run's event log, coverage, applet result, and step screenshots on the target into `peregrine-previous/` under the Runner temp directory, and deletes an older copy already there. The log prints `previous run keep success <n>`. So `peregrine-events.jsonl` holds only this run, and the target keeps at most this run and the previous one. The reuse file `peregrine-<Bundle ID>.reuse.json` accumulates across runs and is neither moved nor deleted.

If the previous pull failed (`device files failed` in the run log), or you used `xcodebuild` and never pulled: pull with `cli.py pull` before the next run; if the next run has already started, use `cli.py pull --previous`. Starting another run after that deletes this backup.

After the run and collection finish, **打包导出** (export bundle) downloads `peregrine-run-<time>.zip` with this run's log, `.xcresult`, crash report, and device files; **导出日志** (export log) downloads only the run log. Export is disabled while a run or collection is in progress. A Simulator run has no crash-report directory.

### Physical device and Simulator

Peregrine supports a connected, unlocked iPhone, and a **booted** Simulator on a Mac with Xcode using the `xcode` path. Both targets run UI source, actions, recovery, the stub, the command port, the communication check, and pulling files the Runner wrote. `goios`, Linux, and Windows connect only to a physical phone.

To use a Simulator:

1. Boot the destination with Simulator or `xcrun simctl boot`. Shutdown destinations do not appear in the device list.
2. The app under test must be an `iphonesimulator` build, already installed on that Simulator, and able to open by hand. Embedded frameworks must also be Simulator slices; a device slice exits immediately with `have 'iOS', need 'iOS-simulator'`.
3. The launch page and `cli.py devices` show the link as `Simulator`. `cli.py run --udid <Simulator UUID>` uses `-destination 'platform=iOS Simulator,id=…'`.
4. `cli.py install` rejects a Simulator: it only installs the Runner on a physical phone for go-ios. On a Simulator, `xcodebuild test` installs this run's Runner itself.

| Capability                                                             | Physical iPhone           | Simulator                                                                                                            |
|------------------------------------------------------------------------|---------------------------|----------------------------------------------------------------------------------------------------------------------|
| Exploration loop (tap, gesture, Home, restart)                         | Yes                       | Yes                                                                                                                  |
| `screenshot` / `snapshot` / `combined`                                 | Yes                       | Yes                                                                                                                  |
| Stub view tree (on-target `127.0.0.1`)                                 | Yes                       | Yes. The host-side `iproxy` / `ios forward` probe is skipped (`stub check skipped`); the Runner probes after launch  |
| Communication check `testPingNetwork`                                  | Yes                       | Yes                                                                                                                  |
| Writing and pulling events, coverage, step screenshots                 | `devicectl` / `ios fsync` | `simctl get_app_container`                                                                                           |
| Runner suspected-crash and action-timeout counts                       | Yes                       | Yes                                                                                                                  |
| Stub-side resource samples (memory, CPU, main thread, memory warnings) | Yes                       | Yes. Thermal state stays `nominal` and is not a decision input                                                       |
| Host-side resource samples (Instruments memory, CPU, frame rate)       | Yes (iOS 17.4+ USB)       | No. The log prints `perf host skipped`. `--perf` still passes `PEREGRINE_PERF=1` to the Runner for stub-side samples |
| System-crash / Jetsam pull                                             | Yes                       | No. The log prints `crash collect skipped`                                                                           |
| `install`, go-ios, Linux / Windows                                     | Yes                       | No                                                                                                                   |
| USB / Network, China-region cellular denial                            | Yes                       | No. The Simulator uses the Mac network                                                                               |

Exploration and the communication check have been run on iPhone 17 (iOS 26.5) and iPhone 13 (iOS 15.2) Simulators.

### Running on Linux and Windows

The Runner can be built and signed only on a Mac. After it is installed on the phone, a Linux or Windows computer can run it through [go-ios](https://github.com/danielpaulus/go-ios), without Xcode. go-ios cannot target a Simulator.

1. On a Mac, run `python3 tools/launch/cli.py install` to build the Runner and install it on the phone. Do this again when the Runner's signature expires, you change phones, or you update Peregrine.
2. Install Python 3 on Linux or Windows. Linux needs `usbmuxd` running; Windows needs Apple Mobile Device Support (shipped with iTunes or Apple Devices). The phone must have Developer Mode on and must trust this computer.
3. Copy the repository to that computer and start `server.py` or use `cli.py` as above. You do not need `pod install`, and you do not need to install go-ios yourself.

go-ios is resolved in this order:

1. The path in `GO_IOS`.
2. go-ios v1.3.2: on first use, download this platform's `go-ios-<mac|linux|win>.zip` from [GitHub Releases](https://github.com/danielpaulus/go-ios/releases/tag/v1.3.2), check the SHA-256, extract the binary into `tools/launch/.local/tools/go-ios-v1.3.2/<mac|linux|win>/`, and reuse it afterward. Linux picks `ios-amd64` or `ios-arm64` from the CPU.
3. If the download fails, use `ios` on `PATH`; if that is missing too, the command errors and prints the download URL.

Downloads prefer the system `curl` (shipped on macOS, Linux, and Windows 10+), using the system's certificates and proxy. If `curl` is missing, Python's own downloader is used; a python.org macOS Python must run its `Install Certificates.command` first. If GitHub is unreachable, download the zip by hand, extract it, and point `GO_IOS` at the binary.

On Windows, the iOS 17+ userspace tunnel needs `wintun.dll`. On first use, `wintun-0.14.1.zip` is also downloaded from [wintun.net](https://www.wintun.net/), checked against its SHA-256, and `bin\<amd64|arm64|x86>\wintun.dll` is placed next to `ios.exe`. You do not put it in `C:\Windows\System32`. If `GO_IOS` points at your own `ios.exe`, put `wintun.dll` in that directory yourself.

Files that fail the checksum are not written. Deleting `tools/launch/.local/tools/` downloads them again on the next run.

The path is chosen in this order: `PEREGRINE_BACKEND` (`xcode` or `goios`), then `cli.py --backend`; if neither is set, macOS uses `xcode` when `xcodebuild` is found, otherwise `goios`. The launch page shows the path next to its title, and the terminal prints `Peregrine 启动页 <url>（<path>）`.

Differences between go-ios and Xcode:

| Step                             | Xcode path                                                                                                                                                                                                            | go-ios path                                                                                                                                                                                                                              |
|----------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Run the test                     | `xcodebuild test`; builds and installs the Runner as needed                                                                                                                                                           | `tools/launch/runtest.py` calls `ios runtest` on the Runner already on the phone                                                                                                                                                         |
| Environment passed to the Runner | The scheme-mapped `PEREGRINE_BUNDLEID`, `PEREGRINE_DURATION`, `PEREGRINE_THROTTLE`, `PEREGRINE_DATAPORT`, `PEREGRINE_LAUNCHENV`, `PEREGRINE_COMMAND_PORT`, `PEREGRINE_UI_SOURCE`, `PEREGRINE_SHOTS`, `PEREGRINE_PERF` | Every non-empty `PEREGRINE_` variable in this process                                                                                                                                                                                    |
| Log                              | `xcodebuild` output, with XCTest activity lines removed                                                                                                                                                               | Runner output, with XCTest's own debug lines removed; ends with `Test Case '-[PeregrineRunner <method>]' passed/failed (<s> seconds).` and `** TEST SUCCEEDED **` or `** TEST FAILED **`, or `** TEST INTERRUPTED **` if stopped mid-run |
| Result bundle                    | `.xcresult`                                                                                                                                                                                                           | none                                                                                                                                                                                                                                     |
| Device and app lists             | Physical phone: `xctrace`, `ideviceinstaller`; model from `devicectl`. Simulator: `simctl list devices booted`, `simctl listapps`                                                                                     | `ios list`, `ios info`, `ios apps`; model from `tools/launch/models.py`. No Simulator                                                                                                                                                    |
| Pull results, collect crashes    | Physical phone: `devicectl`, `idevicecrashreport`. Simulator: `simctl get_app_container`, no crash collect                                                                                                            | `ios fsync`, `ios crash cp`                                                                                                                                                                                                              |
| Stub probe                       | Physical phone: `iproxy`, `devicectl`. Simulator skips the host-side check                                                                                                                                            | `ios forward`, `ios launch`, `ios kill`                                                                                                                                                                                                  |

The device list is `model (iOS version) · link`, for example `iPhone 15 Pro Max (18.6.2) · USB`. A booted Simulator shows as `Simulator`. A renamed phone puts the name before the model. On go-ios, a product type not in `models.py` is shown as-is, for example `iPhone19,1`. A phone that has not paired with this computer is listed separately as "unpaired, trust this computer on the phone first" and does not block the others.

On iOS 17 and later, go-ios needs a tunnel. If `ios tunnel ls` does not list this phone, `ios tunnel start --userspace` is started in the background and waited on for up to 20 seconds. The tunnel stays up after the test for the next run. Each run also runs `ios image auto`: skip when the developer disk image is already mounted, otherwise download and mount it into `tools/launch/.local/devimages/`.

go-ios 1.0.x and 1.2+ print test results in different formats (Go struct text vs JSON). `runtest.py` parses both, so `GO_IOS` may point at a 1.0.x binary.

The go-ios path has been verified on macOS with a `PATH` that contains only Python and `curl`, go-ios v1.3.2 downloaded and checksummed automatically: device and app lists, stub probe and auto-close, communication check, a 1-minute exploration, pulling result files, crash collection, and export all worked. go-ios 1.2.0 was also used to verify a mid-run stop, after which the Runner on the phone exited.

### Communication check

`-only-testing:PeregrineRunner/PeregrineRunner/testPingNetwork` checks the paths exploration uses and finishes in a few seconds:

| Item             | What it checks                                                                                                                                          | Must pass              |
|------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------|
| `loopback`       | TCP send and receive on the device's 127.0.0.1                                                                                                          | yes                    |
| `command_server` | Starts the command port, sends one `BACK`, and requires HTTP 200 with the command queued. Uses `PEREGRINE_COMMAND_PORT` when set, otherwise a free port | yes                    |
| `stub`           | When `PEREGRINE_BUNDLEID` and `PEREGRINE_DATAPORT` are set, launches the app and probes the stub                                                        | yes when those are set |
| `internet`       | Reachability: `reachable`, `denied`, or `unreachable`                                                                                                   | see below              |

Each success prints one line, for example `loopback success`, `command server success port 8100`, `stub success port 9797`, `internet success`. When the internet is not required, a misprints `internet denied (not required)` or `internet unreachable (not required)`; when it is required, the parentheses say `required`. A failed internet request also prints `ping network failed HTTP <status> <error>`, once after the wait when the internet is required. If the test case fails, the failure message lists every item.

Exploration, the command port, and the stub use 127.0.0.1 only and do not need the internet. Some China-region devices deny the Runner wireless data without a permission dialog; the log is `internet denied`, and exploration is not affected. The internet is required only when `sceneConfigURL` / `sceneCallback` (or the matching environment variables) are set, or when `PEREGRINE_REQUIRE_INTERNET=1`. Then an unreachable internet fails the check; the Runner waits and tries to tap the wireless-data dialog, up to about 75 seconds.

## Environment variables

In scheme `PeregrineRunner` the following keys are `${PEREGRINE_*}`, so environment variables you set when starting `xcodebuild` reach the test process. If you replace one of them with a literal, the matching environment variable no longer applies.

| Variable                     | Meaning                                                                                                                                                                                                                                 | Example                           |
|------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------|
| `PEREGRINE_BUNDLEID`         | App under test. Required                                                                                                                                                                                                                | `com.example.app`                 |
| `PEREGRINE_DURATION`         | Minutes. Default 1. Unset, 0, or negative use the default                                                                                                                                                                               | `10`                              |
| `PEREGRINE_THROTTLE`         | Interval between actions, milliseconds. Default 300                                                                                                                                                                                     | `300`                             |
| `PEREGRINE_DATAPORT`         | Stub port. Unset or 0 uses screenshots                                                                                                                                                                                                  | `9797`                            |
| `PEREGRINE_LAUNCHENV`        | Environment written into the app under test. `key=value` items separated by `:`                                                                                                                                                         | `isAutoTestUI=1:channel=AutoTest` |
| `PEREGRINE_UI_SOURCE`        | `combined` (default), `screenshot`, or `snapshot`. Ignored when the stub probe succeeds                                                                                                                                                 | `screenshot`                      |
| `PEREGRINE_COMMAND_PORT`     | On-device command port, 1–65535. At or below 0, nothing listens; if the port is taken the log prints `not listening` and `command` in the start line is 0                                                                               | `8100`                            |
| `PEREGRINE_COVERAGE_DIR`     | Output directory of the Runner process on the target. A Mac path is ignored                                                                                                                                                             |                                   |
| `PEREGRINE_CONFIG`           | Config directory. Same-named JSON files there override the bundled files                                                                                                                                                                |                                   |
| `PEREGRINE_STRINGS`          | Candidate strings for text fields, one per line                                                                                                                                                                                         |                                   |
| `SCENE_CALLBACK`             | Overrides `sceneCallback` in `appconfig.json`                                                                                                                                                                                           |                                   |
| `SCENE_CONFIG_URL`           | Overrides `sceneConfigURL` in `appconfig.json`                                                                                                                                                                                          |                                   |
| `ACTION_TIMEOUT_MS`          | An action longer than this many milliseconds records `action_timeout`. Default 8000                                                                                                                                                     |                                   |
| `PEREGRINE_REQUIRE_INTERNET` | `1` makes `testPingNetwork` require a reachable internet                                                                                                                                                                                | `1`                               |
| `PEREGRINE_SHOTS`            | Step screenshots: `off` (default), `change` (save when the screen fingerprint changes), `all` (save every step)                                                                                                                         | `change`                          |
| `PEREGRINE_SHOTS_LIMIT`      | Maximum screenshots kept on the target; older ones are dropped. Default 500                                                                                                                                                             | `300`                             |
| `PEREGRINE_PERF`             | `1` turns on stub-side resource sampling: one `app_perf` read per step, written to the event log. Off by default; no effect without the stub. Host-side sampling is turned on by the launch-page **资源采样** switch or `cli.py run --perf` | `1`                               |

The scheme only maps `PEREGRINE_BUNDLEID`, `PEREGRINE_DURATION`, `PEREGRINE_THROTTLE`, `PEREGRINE_DATAPORT`, `PEREGRINE_LAUNCHENV`, `PEREGRINE_UI_SOURCE`, `PEREGRINE_COMMAND_PORT`, `PEREGRINE_SHOTS`, `PEREGRINE_PERF`. Pass the others with a `TEST_RUNNER_` prefix, for example `TEST_RUNNER_PEREGRINE_REQUIRE_INTERNET=1`.

## Configuration files

At run time the files under `Peregrine/peregrine-behavior/config/` are read and packed into `PGBehaviorConfig.bundle`.

| File                  | Fields read                                                                                                                                                                                                   |
|-----------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `testconfig.json`     | `SkipCheckBlock`, `SkipRestart`, `SkipHome`, `GestureRatio`                                                                                                                                                   |
| `setting.json`        | `channel`, written to the log only                                                                                                                                                                            |
| `default.jsonsetting` | `events`, `actions`, `sequences`                                                                                                                                                                              |
| `appconfig.json`      | `cases`, `sceneLimit`, `sceneLimits`, `sceneCallback`, `applet.schema`, `excludeRects`, `excludeElements`, `sceneConfigURL`. The bundled default is an empty object; all of those fields are treated as unset |

Common action JSON fields are `act`, `pos`, `id`, `text`, `path`, `duration`, `throttle`. `duration` and `throttle` here belong to a single action, not the launch parameters in the table above.

- For `TYPE`, `text` is what to type, not a query. With `id` or `pos` the target is tapped first, otherwise typing goes to the current focus.
- `CLICK_TEXT` and `CLICK_ID` find a target by label or accessibility identifier. In screenshot and `combined` modes this reads one system snapshot; a miss skips the action and logs `target not found`.
- `SCHEMA` and `applet.schema` open a page through a URL scheme and need iOS 16.4 or later.
- `excludeRects` exclude a fixed region in screenshot pixel coordinates, for controls that do not move. A draggable overlay (a debug button, for example) should use `excludeElements` with the control's accessibility identifier or label, such as `"excludeElements": ["BCDebuggerLogo"]`, matched exactly. Each step uses the control's current position and drops the control itself plus any candidate whose center falls inside it. If the control is absent this step, nothing is excluded. The log prints `exclude elements covers <n> dropped <m>`. When candidates come from screenshot segmentation (screenshot mode, and `combined` steps that did not switch to a snapshot), each split does one extra snapshot query.
- A frozen screen is detected by fingerprint. After 4 steps on the same screen the Runner tries swipe-up, a forced back, then an app restart (`SkipRestart` true skips the restart), and logs `block recovery <action>`. After a restart that leaves the screen, that fingerprint waits 60 steps before another swipe, forced back, or restart, and the log prints `block recovery cooldown <fingerprint> steps 60`. If the restart does not leave, or the screen is still there after the last attempt, the log prints `block recovery gave up` and that screen will not trigger recovery again in this run. The restart that fires after 101 decisions does not enter this cooldown.
- A page cycle is detected from exploration state, for screens that keep changing in detail while staying among a few pages (a photo viewer whose image shifts slightly after each tap). When the last 8 steps found no new page and touched at most 3 pages, the next 3 steps avoid already-tried actions on those pages and pick a random target, then the Runner tries an edge-right back, a tap on a small control in the top-left or top-right corner (close and back usually live there; otherwise a downward drag), a downward drag from the top of the screen (to dismiss a presented page), and an app restart, with one ordinary exploration step between attempts. Reaching a new page stops the escalation. When `SkipRestart` is true the last step is an edge-right back instead. The log prints `cycle escape <back|corner|dismiss> <action>` and `cycle escape restart`. After that restart actually runs, a later loop whose pages all sit inside the same set waits 60 steps before another escape, and the log prints `cycle escape cooldown steps 60`. The restart that fires after 101 decisions does not enter this cooldown.
- System pages such as the photo picker and the share sheet have no usable control info. The Runner tries an edge-right back, then a downward drag from the top; if that still does not leave, it asks to return to the app under test. The log prints `outside <page> step <n> <back|dismiss|foreground>`.
- Automatic exploration mixes gestures with taps. Ratios come from `GestureRatio` in `testconfig.json`. Keys and defaults: `SWIPE` 0.10, `LONG_PRESS` 0.06, `DOUBLE_TAP` 0.03, `PINCH` 0.02, `DRAG` 0.02 — the probability of choosing that gesture on a step; the rest are taps. If the sum exceeds 1, the values are scaled to 1. A key set to 0 turns that gesture off. `SWIPE` and `PINCH` act in the middle of the screen (10%–90% horizontally, 20%–80% vertically). Swipe directions are up 45%, down 25%, left 15%, right 15%; pinch is half zoom-in, half zoom-out. `LONG_PRESS`, `DOUBLE_TAP`, and `DRAG` act on the chosen target; `DRAG` holds the target center and moves to a random point. A scrollable chosen target becomes a swipe, and a text field becomes typing; those are not affected by the ratios.
- Screenshot segmentation classifies controls in points, so the same thresholds apply across resolutions. Regions against the screen edge whose color does not match the chrome are not treated as dialogs, so a slice of a full-screen page is not mistaken for a dialog that would confine targets.
- Split granularity follows the content: text, icons, and buttons on a flat background are split one by one; a textured region such as a photo (edge at least 40 points, a spread of tones, visible internal texture) is one `image` candidate, and leaves or contours inside it are not split further. Opaque controls on top of a photo stay as their own blocks; translucent controls on a photo (a dark circular back button, for example) merge into the photo block, and in `combined` mode a tap on that block is corrected by the snapshot. A full-screen photo page drops from 26 candidates to 8; split time stays about 7 milliseconds per image on a Mac.

## Results

`xcodebuild` prints before it exits:

```text
coverage 3: Home x10, Detail x4, Form x2
coverage written
```

The number is how many distinct pages were seen, followed by visit counts. The same text is written to `peregrine-coverage.txt` on the target. That directory also has `peregrine-events.jsonl` and `peregrine-applet.txt`. When `PEREGRINE_COVERAGE_DIR` is unset, this is the Runner temp directory.

The end of the run also prints `explore score ...`: steps, screen-change rate, distinct screens, longest streak on one screen, and at the end `acts` with per-action counts, for example `acts BACK:12,CLICK:41,LONG_PRESS:5,SWIPE_UP:4`.

### Step screenshots

For reviewing a run. Off by default. The launch-page **步骤截图** switch, `cli.py run --shots`, or `PEREGRINE_SHOTS` set to `change` saves only when the screen fingerprint differs from the last shot; `all` saves every step. Each shot is scaled to screen points and stored as JPEG (about 30–50 KB). Green boxes are this step's candidates, the red box is the action target, a drag draws its path, and the bottom line is the step number, action, node source, and target text. The file name is `<step>-<action>.jpg`. The step number counts executed steps; skipped steps in `change` mode do not take a file but still consume a step number. `index.jsonl` in the same directory has one line per shot: `step`, `file`, `time` (ms), `act`, `target` (`[left, top, width, height]` in points), `text`, `source`, `activity`, `nodes`, `fingerprint`.

Shots are written first to `peregrine-shots/` in the Runner temp directory. The target keeps at most `PEREGRINE_SHOTS_LIMIT` (default 500); older ones are dropped and the log prints `shots limit <n> reached, oldest dropped` once. At the end of the test they are packed into `peregrine-shots.zip` and that directory is deleted (`shots archive success <n>`). A failed pack prints `shots archive failed`, keeps the directory, and on the Xcode path the directory is still pulled. The zip is then pulled with the other result files into `run-<time>/device/` and into the exported `peregrine-run-<time>.zip`.

Turning shots on adds one scale-and-JPEG per step. In stub mode the step does not screenshot; turning shots on adds one extra screenshot per step.

### Crashes and anomalies

Before each step the Runner checks that the app under test is still in the foreground. If the process has exited it records a suspected crash and relaunches the app. Two detections with no new action between them count as one. An action longer than `ACTION_TIMEOUT_MS` (default 8000 ms) records an action timeout, which can hint at a stall.

Each suspected crash or action timeout prints one `peregrine anomaly` line, then up to 8 previous steps as `peregrine anomaly step` with time, page, action, and target. The end-of-run summary uses the same counts in `task_end.anomalies` of `peregrine-events.jsonl`:

```text
anomaly summary suspected_crash 2 suspected_crash_restart 0 action_timeout 0 left_foreground 1
```

`suspected_crash`, `suspected_crash_restart`, and `action_timeout` are always listed; `left_foreground` and other kinds appear only when they occurred in this run.

The Runner cannot read system crash logs, so it only knows that the process is gone, not why. Types and stacks are filled in by `tools/crash/collect.py` on the computer: it pulls crash logs and Jetsam records for the app under test from a **physical phone** in this run's time window, groups them by exception type and the first 3 useful frames of the crashing thread, and lines them up with the Runner log by time. It needs `idevicecrashreport` and `ideviceinstaller` (Homebrew packages `libimobiledevice` and `ideviceinstaller`). A Simulator has no such path; the log prints `crash collect skipped` and keeps only the Runner's own suspected-crash and timeout counts.

A launch-page or `cli.py run` collects automatically after each physical-phone run. The page shows "collecting device results and crash logs"; on a Simulator it only pulls result files and shows "pulling results". The output is appended to the run log, and the report is written to `tools/launch/.local/rounds/run-<time>/crash/`. After a direct `xcodebuild`, from the repository root:

```shell
python3 tools/crash/collect.py --udid <device UDID> --bundle-id com.example.app \
  --since "2026-10-21 16:00:00" --log <xcodebuild output> --out <report dir>
```

`--since` is this run's start (local time or Unix seconds). `--log` is optional; without it the report has no action path. Example output:

```text
crash collect crash 6 jetsam 0 signatures 2 runner_exits 6 timeouts 0
  4x uncaught Objective-C exception (SIGABRT) | CoreFoundation -[__NSSingleObjectArrayI objectAtIndex:] > StubDemo -[SDHome crashWithException] > ...
  2x bad memory access (EXC_BAD_ACCESS SIGSEGV) | StubDemo -[SDDetail crashWithNull] > ...
crash report written <report dir>/crash-report.md
```

The report directory contains:

| File                | Contents                                                                                                                                                                                    |
|---------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `crash-report.md`   | Summary table; each crash site's type, count, time, reason, crashing-thread stack, and the actions before it; process exits with no system log; action timeouts and the actions before them |
| `crash-report.json` | The same data, structured                                                                                                                                                                   |
| `reports/`          | Raw `.ips` logs, openable in Xcode                                                                                                                                                          |

Objective-C, Swift, and C/C++ crashes are all collected. Recognized types: uncaught Objective-C exceptions (name and reason in the report), deliberate abort (abort, assertion), bad memory access, Swift runtime errors (out-of-bounds is called out; force-unwrap of nil, `fatalError`, and `precondition` cannot be told apart in the log and are one class), watchdog timeout (launch or main thread stuck too long), resource limit, protected-resource misuse, and Jetsam. Swift error text such as `Unexpectedly found nil` is only in the device system log, not the crash log; the report locates those by function and offset, and different sites in the same function are counted separately by offset. Whether frames show function names depends on the app's symbols: a Debug build you compiled is usually readable; a store build shows offsets and needs the matching dSYM. The system writes logs with a few seconds of delay; the script waits 5 seconds before pulling.

## Instrumentation

To read the app's own view tree, link `peregrine-stub` into the app as in the [instrumentation guide](./instrumentation.md) and set `PEREGRINE_DATAPORT`. `alive 1` and UI source `ui stub` mean the tree is in use.

The data port must belong to the app under test. The stub keeps listening after the app goes to the background, so another stubbed app left in the background can answer on the same port. On a physical phone the launch page and CLI probe before the run; the Runner checks again after its own probe. A Simulator skips the host-side check and the Runner probes after launch.

On a physical phone, the launch-page **检测**, `cli.py stub`, and the pre-run check reach the phone port through `iproxy`. They first restart the app under test without a port; if the port still answers, someone else owns it. When the responder reports a Bundle ID, that process is ended through `devicectl`, the port is freed, and the check continues; the message ends with "already closed the previous owner of this port <Bundle ID>". A legacy stub that cannot name the app, or a failed kill, is `other`. Then the app is restarted with the port, waited on for up to 8 seconds, and `app_info` reads the responder's Bundle ID:

| Result   | First log line                                                                                 | This run                                                                    |
|----------|------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------|
| `ok`     | `stub check success <Bundle ID> port <port>`, plus `closed <Bundle ID>` if an owner was closed | use the stub                                                                |
| `legacy` | `stub check legacy: …`                                                                         | stub older than `app_info`, ownership cannot be checked, still use the stub |
| `other`  | `stub check other: port … is owned by …; this run will not use the stub, screenshots instead`  | do not pass the data port; close the owner on the phone                     |
| `none`   | `stub check none: … no stub response …; this run will not use the stub, screenshots instead`   | do not pass the data port                                                   |

If the check itself fails (for example `iproxy` is missing), or the target is a Simulator, the first line is `stub check skipped: …` and the port is passed through.

After a successful probe the Runner sends `app_info`. A Bundle ID matching `PEREGRINE_BUNDLEID` logs `stub app_info success <Bundle ID>`. A mismatch logs `stub port <port> belongs to <Bundle ID>, not <app under test>; stub not used` and this run uses screenshots. A legacy stub without `app_info` logs `stub app_info unavailable on port <port>, port trusted` and the stub is used as usual.

### Resource sampling

For memory growth and leaks, Jetsam, CPU, stalls, and dropped frames. Off by default. The launch-page **资源采样** choice "采集内存、CPU、帧率" or `cli.py run --perf` starts both paths on a physical phone, for exploration only. Host-side sampling works for any app; stub-side sampling works only in stub mode and also reports main-thread stalls, memory warnings, and thermal state. A Simulator has no Instruments path, so the host prints `perf host skipped`; `--perf` still passes `PEREGRINE_PERF=1` to the Runner for stub-side samples when the stub is up. If either path fails to start, only the reason is printed and the test continues.

| Metric                                                   | Host                                                     | Stub                  |
|----------------------------------------------------------|----------------------------------------------------------|-----------------------|
| Memory (`phys_footprint`), CPU, thread count             | about once per second                                    | at most once per step |
| Disk I/O, open files, Mach ports, interrupt wakeups      | about once per second                                    | no                    |
| Screen frame rate                                        | once per second, whole screen                            | no                    |
| Foreground/background, system memory-level notifications | when they occur                                          | no                    |
| Main-thread stall, memory warning, thermal state         | no                                                       | at most once per step |
| Jetsam                                                   | counted by crash collection; see "Crashes and anomalies" | no                    |

Measured cost (iPhone 15, 6 cores, iOS 26.2, app in the foreground, two runs): host-side sampling raised on-phone `sysmond` by 8%–14% of one core, about 1.3%–2.3% of the whole device; `DTServiceHub` did not increase; memory of both was unchanged. Stub-side sampling is at most one request per second; in-app cost is below. Steps per minute with sampling on and off stayed within random variation.

#### Host-side sampling

[pymobiledevice3](https://github.com/doronz88/pymobiledevice3) subscribes to the phone's Instruments `sysmontap`, frame-rate, and `mobilenotifications` services — the same services Xcode Instruments uses — and does not change the app under test. Usage is the same on Mac, Linux, and Windows, over a userspace tunnel to iOS 17 and later, without root or administrator rights, and without Xcode.

- Dependencies are in `tools/requirements.txt`, currently pymobiledevice3 11.42.0. On first use a separate virtual environment is created at `tools/launch/.local/tools/pymobiledevice3-11.42.0/` and installed from that file. Python 3.9 or later is required; time depends on the network; later runs reuse it. You can also run `python3 -m pip install -r tools/requirements.txt` beforehand. `cli.py` waits for the install; the launch page does not, and this run logs `perf host skipped: pymobiledevice3 安装中，完成后下一轮可用` while the test continues. A failed install makes the next run log `perf host skipped: pymobiledevice3 上次安装失败：<reason>；已重新开始安装，完成后下一轮可用`. `PYMOBILEDEVICE3` can point at an already installed `pymobiledevice3` binary.
- The phone must have completed "Trust This Computer". A phone that has only been used with `devicectl` may not be paired; the log is `perf host skipped: The user refused to trust this computer.` Tap Trust on the phone and run again.
- Before the run, the executable name is looked up from the Bundle ID and the log prints `perf host start <process>`. Sampling follows that name and attaches to a new process after an app restart. The sampler exits when this run ends, and also when the launch page or `cli.py` is killed. So restarting the launch page mid-test leaves the test running but stops host-side sampling; this run will not write a host summary or sampling report.
- pymobiledevice3 11.42.0 `notifications` exits on a payload its JSON encoder does not know (for example a date in a memory-level notification). With the auto-installed copy those values are written as `{"$repr": "<raw>"}` and sampling continues. A `PYMOBILEDEVICE3` binary outside that virtual environment does not get this treatment and `notifications` may exit early; see the early-exit line below.
- On Linux and Windows, iOS 17.0–17.3.1 needs `pymobiledevice3 remote tunneld` started separately as root or Administrator. iOS 17.4 and later do not.

Results go into `run-<time>/device/` and are packed with the device files:

| File                 | Contents                                                                                                                                                                                                                                                                                                                                                                                                 |
|----------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `perf-process.jsonl` | About one line per second: `pid`, `name`, `cpuUsage` (100 is one core at full), `physFootprint` (physical memory, bytes; the same figure the system uses for Jetsam), `threadCount`, `diskBytesRead` and `diskBytesWritten` (bytes since process start), `nfiles` (open files), `machPortCount`, `intWakeups` (interrupt wakeups since process start), `timestamp` (UTC)                                 |
| `perf-fps.jsonl`     | One line per second: `fps`, `timestamp`. Whole-screen Core Animation frame rate; 0 when the screen is still                                                                                                                                                                                                                                                                                              |
| `perf-notify.jsonl`  | One line per notification: `timestamp` (when the computer received it, UTC) and `event` (raw notification). `applicationStateNotification:` is an app-state change with `pid` and `state_description` (`Running`, `Suspended`, `Terminated`, …). `memoryLevelNotification:` is a system memory-level notification with `code` and `pid`; `pid` −1 means the whole device; Apple has not published `code` |
| `perf-host.log`      | pymobiledevice3 stderr; usually empty when sampling is healthy                                                                                                                                                                                                                                                                                                                                           |

At the end the log prints `perf host samples <process samples> launches <processes> peak_mb <peak> peak_time <when> cpu_avg <avg CPU> cpu_max <max CPU> fps_samples <n> fps_avg <avg> fps_low <low-fps seconds> background_s <background seconds> disk_read_mb <read> disk_write_mb <write> files_max <max files> ports_max <max ports> wakeups_per_s <wakeups> memory_levels <memory-level notifications>`.

- `cpu_avg` and `cpu_max` skip the first sample of each launch; that sample has no `cpuUsage`.
- Frame-rate sampling starts before the Runner is built and stops after the test, and is the whole screen. The summary only counts seconds between the first and last process sample while the process is `Running`; excluded background seconds are `background_s`. `perf-fps.jsonl` keeps every record. State is the latest change for the process being sampled; with no change it is treated as foreground.
- `fps_avg` and `fps_low` only count seconds with fps greater than 0. `fps_low` is how many of those are below 30.
- `disk_read_mb` and `disk_write_mb` are the sum of counter deltas across launches. `wakeups_per_s` is the sum of wakeup deltas across launches divided by total sample time.
- If a path exits before the test ends, the summary is followed by `perf host process|fps|notify exited <code> before the run ended: <reason>`, with the reason taken from the last `ERROR` in `perf-host.log`.

#### Stub-side sampling

When on (`--perf`, or `PEREGRINE_PERF=1` with a direct `xcodebuild`), the Runner adds `stubPerf=1` to the app's launch environment. The stub starts watching the main thread and counting memory warnings as the app launches. After each step the Runner sends one `app_perf`, at least 1 second after the previous one, waiting at most 1 second, and writes a `perf` event:

| Field             | Meaning                                                                                             |
|-------------------|-----------------------------------------------------------------------------------------------------|
| `footprint_bytes` | Physical memory of the app (`phys_footprint`), the same definition as host-side `physFootprint`     |
| `cpu_percent`     | Sum of the app's threads, 100 is one core at full, one decimal place                                |
| `threads`         | Thread count                                                                                        |
| `main_max_ms`     | Longest main-thread hang since the previous `perf`, milliseconds                                    |
| `main_slow`       | Times the main thread did not respond for 250 ms since the previous `perf`                          |
| `memory_warnings` | Times the app received `UIApplicationDidReceiveMemoryWarningNotification` since the previous `perf` |
| `thermal_state`   | Device thermal state: `nominal`, `fair`, `serious`, `critical`, from `NSProcessInfo.thermalState`   |

The main-thread watch posts an empty block to the main queue every 0.1 seconds and records the delay until it runs. Only one block is outstanding, so a stuck main thread does not queue more. After 10 seconds without `app_perf` the watch stops itself. Memory, CPU, and thermal state are read on a stub background thread. Memory warnings are counted from the notification-center callback; no extra thread or timer.

At the end the log prints `perf samples <n> peak_mb <peak> peak_sample <index of the peak> main_max_ms <longest hang> main_slow <slow count> memory_warnings <n> thermal_max <hottest state, or none when there are no samples> missed <missed reads>`. After an app restart the stub needs about 2 seconds before it listens; samples in that window count as `missed`. The same numbers go into `task_end.perf` in the event log: `samples`, `peak_bytes`, `peak_sample`, `main_max_ms`, `main_slow`, `memory_warnings`, `thermal_max`, `missed`.

#### Sampling report

After the launch page or `cli.py run --perf` pulls device files, both sampling paths are aligned with event-log steps and written to `run-<time>/device/perf-report.txt`. The log prints `perf report success <path>`; with no samples on either path, `perf report skipped: no samples`. The report includes:

- Memory peak and when it happened, plus the last step before the peak (host).
- Each launch (each `pid`): start, end, peak memory, and a linear-fit slope in MiB/minute. Launches shorter than 30 seconds have no slope. A slope that stays positive means memory only rose, a starting point for leak work (host).
- The 5 steps with the largest memory growth: from that step's start to the next step's start, within the same process (host).
- Each launch's open-file and Mach-port start/end and slope (per minute), disk I/O, and wakeups per second. A rising file or port count hints at a handle leak (host).
- Times the app left the foreground, not counting process death (host).
- System memory-level notifications: time, `code`, `pid`, and the last step before each (host).
- Main-thread stalls (a single hang of 250 ms or more), memory warnings, and thermal states other than `nominal`, each with the last step before it (stub).

Stub-side rows are attached to the preceding step by event-log order and are exact. Host-side rows can only be aligned by time, and event-log times are whole seconds, so several steps that start in the same second are all attributed to the last of them. Treat the host-side step as a location hint.

#### Metrics not included

These are expensive, change how the app runs, or do not fit Peregrine, and are not sampled:

| Metric                                                            | Why it is out                                                                                                                                                        |
|-------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Memory graph (`memgraph`), allocations, VM regions (`vm-regions`) | Development-signed apps only; capturing a memory graph pauses the process; allocations require the tool to relaunch the app. All of that interferes with exploration |
| Kernel trace (`core-profile-session`)                             | Whole-system scheduling and syscalls; large data and large on-phone cost                                                                                             |
| GPU and VRAM (`graphics`)                                         | The phone would keep reading graphics counters; cost is unverified, and whole-screen frame rate already shows dropped frames                                         |
| Per-process energy (`energy`) and network (`network-statistics`)  | Each needs another always-on service; cost unverified. Energy tendency can start from interrupt wakeups                                                              |
| System log (`oslog`)                                              | Large volume; pymobiledevice3 marks it unstable                                                                                                                      |
| Main-thread stacks at a stall                                     | Would repeatedly suspend the main thread inside the stub and then symbolicate; cost and risk outweigh the gain                                                       |
| App-owned frame rate in the stub (`CADisplayLink`)                | A main-thread callback every frame, and it keeps a higher refresh rate, which changes the app's power and display behavior                                           |
