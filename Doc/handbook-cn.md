# 使用手册

[简体中文](handbook-cn.md) · [English](handbook-en.md)

依赖安装、签名与首次运行见 [README](../README.md)。本文说明日常执行方式、真机与模拟器对照、环境变量、配置文件、结果文件与崩溃收集。

## 执行测试

被测应用须已安装在目标上，且可以手动打开。目标可以是已解锁、数据线连接的 iPhone，也可以是已启动的模拟器。用法见下文「真机与模拟器」。

启动页在仓库根目录执行：

```shell
python3 tools/launch/server.py
```

浏览器打开 `http://127.0.0.1:8765/`，或启动时打印的局域网地址。选择设备与应用。时长单位为分钟，节流单位为毫秒。数据端口留空时使用截图。填写数据端口后，可单击其右侧的「检测」，在真机上重启被测应用并确认其接入插桩、端口由其应答，结果显示在输入框下方。模拟器无法从电脑探测插桩，「检测」不可用，开跑后由 Runner 自行探活。单击「开始」。填写了数据端口且目标为真机时，开始前先执行同一检测：被测应用未接入插桩，或端口由其他应用的插桩应答时，本轮不传数据端口、改用截图，原因写在日志首行。关闭页面不会终止测试，须单击「终止」。「通信检查」运行下文的 `testPingNetwork`，只需选择设备；填了数据端口时须同时选择被测应用，并检查插桩。日志与 `.xcresult` 存为 `check-<时间>`，不拉回设备结果、不收集崩溃，也不能打包导出。

开发团队默认取自本机 Apple Development 证书。需要指定时：

```shell
DEVELOPMENT_TEAM=<Team ID> python3 tools/launch/server.py
```

启动后会自动用默认浏览器打开本机地址。在没有图形界面的电脑上运行，或不需要自动打开时，设置 `PEREGRINE_LAUNCH_NO_BROWSER=1`。默认监听所有网卡，同一局域网的其他电脑可用启动时打印的「局域网 http://<本机地址>:8765/」打开同一页面；开始、终止和看日志都作用在跑启动页的那台电脑上。只允许本机打开时设置 `PEREGRINE_LAUNCH_HOST=127.0.0.1`，端口不是 8765 时设置 `PEREGRINE_LAUNCH_PORT`。

### 命令行

`tools/launch/cli.py` 提供与启动页相同的能力，二者共用 `tools/launch/core.py`。隧道和安装日志在 `tools/launch/.run/`。下载的依赖在 `tools/launch/.local/`，每一轮的运行日志和结果在 `tools/launch/.local/rounds/<轮次>/`。在仓库根目录执行：

```shell
python3 tools/launch/cli.py install [--udid <UDID>] [--team <Team ID>]
python3 tools/launch/cli.py devices
python3 tools/launch/cli.py apps [--udid <UDID>]
python3 tools/launch/cli.py run --bundle-id com.example.app [--duration 10] [--throttle 300] \
  [--dataport 9797] [--env PEREGRINE_UI_SOURCE=combined] [--export [<路径>]] [--shots off|change|all] [--perf] [--keep 20]
python3 tools/launch/cli.py check [--bundle-id com.example.app --dataport 9797]
python3 tools/launch/cli.py stub --bundle-id com.example.app --dataport 9797
python3 tools/launch/cli.py pull [--bundle-id com.example.app] [--out <目录>] [--previous]
python3 tools/launch/cli.py runs
python3 tools/launch/cli.py export [--run <时间戳>] [--out <路径>]
```

| 子命令       | 作用                                                                                                                                                                                                                                                     |
|-----------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `install` | 仅限装有 Xcode 的 Mac：`xcodebuild build-for-testing` 编译 Runner，再经 `devicectl` 安装到**真机**，不运行测试。日志存为 `install-<时间>.log`。拒绝模拟器                                                                                                                                 |
| `devices` | 列出已连接 iPhone（USB / Network）以及 `xcode` 方式下已启动的模拟器（`Simulator`）的 UDID 和名称                                                                                                                                                                                |
| `apps`    | 列出目标上用户安装的应用：Bundle ID、版本、名称。真机经 `ideviceinstaller` / `ios apps`；模拟器经 `simctl listapps`                                                                                                                                                                |
| `run`     | 跑一轮探索。输出实时打印并写入 `run-<时间>.log`；结束后拉回结果文件；真机再收集崩溃日志，模拟器跳过。带 `--export` 时再打成 zip，不给路径写到 `.local/rounds/`。`--shots` 不为 `off` 时，未给 `--export` 也打包到 `.local/rounds/`（`--no-collect` 时除外）。退出码与 `xcodebuild` 一致                                                                 |
| `check`   | 运行 `testPingNetwork`，日志与 `.xcresult` 存为 `check-<时间>`，不计入运行记录                                                                                                                                                                                           |
| `stub`    | 检测被测应用是否接入插桩、数据端口是否由其应答，结论见下文「插桩」。可用时退出码为 0，否则为 1。模拟器跳过电脑侧探测，打印 `stub check skipped`，退出码为 0                                                                                                                                                            |
| `pull`    | 从 Runner 临时目录拉回 `peregrine-events.jsonl`、`peregrine-coverage.txt`、`peregrine-applet.txt`、`peregrine-shots.zip`（开启步骤截图时才有），给了 `--bundle-id` 时再拉回该应用的复用文件；加 `--previous` 时改为拉回上一轮备份，不含复用文件。真机经 `devicectl` / `ios fsync`，模拟器经 `simctl get_app_container` |
| `runs`    | 列出 `.local/rounds/` 里每一轮的时间戳和已有产物（log、xcresult、crash、device）                                                                                                                                                                                                    |
| `export`  | 把一轮的日志、`.xcresult`、崩溃报告和设备结果打成 `peregrine-run-<时间>.zip`，默认最近一轮                                                                                                                                                                                         |

共同约定：

- `--backend xcode|goios` 写在子命令之前，指定运行方式，见下文「在 Linux 与 Windows 上运行」。
- 只连一台目标时可省略 `--udid`；连了多台时会列出可选项并退出。
- 开发团队依次取 `--team`、环境变量 `DEVELOPMENT_TEAM`、本机 Apple Development 证书。
- `--env KEY=VALUE` 可重复，用于传入启动页没有的环境变量，例如 `PEREGRINE_UI_SOURCE`、`PEREGRINE_COMMAND_PORT`、`PEREGRINE_STRINGS`；`--bundle-id`、`--duration`、`--throttle`、`--dataport` 优先于 `--env` 中的同名变量。
- `--shots change|all` 开启步骤截图，见下文「步骤截图」；默认 `off`，等同于环境变量 `PEREGRINE_SHOTS`。
- `--perf` 开启资源采样，见下文「资源采样」；同时设置环境变量 `PEREGRINE_PERF=1`。模拟器没有电脑端 Instruments，只把该变量交给 Runner 供插桩端采样。
- `run` 开跑前清理 `.local/rounds/` 里最旧的轮次目录，只保留最近 `--keep` 轮（含本轮，默认 20，0 表示不清理）。一轮就是一个 `run-<时间>/` 或 `check-<时间>/` 目录，里面有日志、`.xcresult`、`device/`、`crash/` 和 zip。`.local/tools/`、`.local/devimages/`、`.local/build/`、`.local/state.json` 和 `.run/` 不在清理范围内。日志打印 `runs pruned <轮数> keep <保留数>`。启动页按环境变量 `PEREGRINE_KEEP_RUNS` 取保留轮数，未设置时为 20。
- `run` 期间按 Ctrl+C 只停止测试，随后照常拉回结果；真机再收集崩溃，模拟器跳过。不需要收集时加 `--no-collect`。
- `--dataport` 大于 0 时，真机开跑前执行与 `stub` 相同的检测，结论写在日志首行；不可用时本轮改用截图。模拟器跳过电脑侧检测，端口原样交给 Runner。加 `--no-stub-check` 跳过检测。
- 真机读不到应用列表时（例如未安装 `ideviceinstaller`），`run` 打印 `app check skipped` 并继续。模拟器经 `simctl listapps` 列出。
- 参数错误或设备不可用时，错误写到标准错误，退出码为 2。

也可以在 `Peregrine/` 目录直接调用 `xcodebuild`，此时不会自动拉回设备结果和收集崩溃：

```shell
PEREGRINE_BUNDLEID=com.example.app \
PEREGRINE_DURATION=10 \
PEREGRINE_THROTTLE=300 \
xcodebuild test \
  -workspace Peregrine.xcworkspace \
  -scheme PeregrineRunner \
  -destination 'platform=iOS,id=<设备 UDID>' \
  -only-testing:PeregrineRunner/PeregrineRunner/testPeregrine \
  DEVELOPMENT_TEAM=<Team ID> \
  -allowProvisioningUpdates
```

真机 UDID 取自 `xcrun xctrace list devices`。模拟器写 `-destination 'platform=iOS Simulator,id=<UUID>'`，UUID 取自 `xcrun simctl list devices booted`，或启动页 / `cli.py devices` 中标记为 Simulator 的项。

经启动页或 `cli.py` 运行时，运行日志不含 XCTest 的活动记录，即 `xcodebuild` 输出中以 `t =` 开头、记录每次元素查询、等待空闲与事件合成的行；含 `Assertion Failure` 的活动记录照常保留。结束时日志打印 `xctest activity hidden <行数> lines, see .xcresult`。这些记录完整保存在 `.xcresult` 中，可用 Xcode 打开，或执行 `xcrun xcresulttool get test-results activities --path <.xcresult 路径> --test-id PeregrineRunner/testPeregrine` 查看。每步的动作、目标与耗时已写入 `peregrine-events.jsonl`。

日志出现 `ui source`、结束时的 `coverage <页面数>: ...` 与 `coverage written`，且以 `** TEST SUCCEEDED **` 结束，即表示该次测试完成。启动页将同一份输出写入 `tools/launch/.local/rounds/run-<时间>/run-<时间>.log`。每轮结束后，启动页从 Runner 的临时目录（真机：Xcode 方式经 `xcrun devicectl`，go-ios 方式经 `ios fsync`；模拟器经 `simctl get_app_container`）拉回 `peregrine-events.jsonl`、`peregrine-coverage.txt`、`peregrine-applet.txt`、`peregrine-shots.zip`（开启步骤截图时）和被测应用的 `peregrine-<Bundle ID>.reuse.json`，放在同一目录的 `device/`，崩溃报告放在 `crash/`，日志末尾打印 `device files success` 和拉回的文件名。

一轮指一次 `testPeregrine` 测试，即启动页的一次「开始」、一次 `cli.py run` 或一次 `xcodebuild test`，持续到设定的测试时长结束。一轮内不删除结果文件；唯一的例外是步骤截图数超过上限时删除本轮最早的截图。

Runner 每轮开始时把上一轮留在目标上的事件日志、覆盖率、applet 结果与步骤截图移入 Runner 临时目录下的 `peregrine-previous/`，同时删除其中更早一轮的文件，日志打印 `previous run keep success <文件数>`。因此 `peregrine-events.jsonl` 只含本轮事件，目标上最多保留本轮与上一轮两份结果。复用文件 `peregrine-<Bundle ID>.reuse.json` 跨轮累积，不移动也不删除。

上一轮结束时拉回失败（运行日志中出现 `device files failed`），或直接用 `xcodebuild` 运行而未拉回时：下一轮开始前用 `cli.py pull` 拉回；下一轮已经开始，则用 `cli.py pull --previous` 拉回上一轮。此后再开始新一轮时，这份备份即被删除。

结束并收集完成后，「打包导出」下载 `peregrine-run-<时间>.zip`，内含本轮的运行日志、`.xcresult`、崩溃报告和设备结果文件；「导出日志」只下载运行日志。运行和收集期间不能打包导出。模拟器轮次没有崩溃报告目录。

### 真机与模拟器

Peregrine 支持已连接、已解锁的 iPhone，也支持装有 Xcode 的 Mac 在 `xcode` 方式下把**已启动**的模拟器当作目标。两种目标都能跑界面识别、动作、恢复、插桩、命令端口、通信检查，以及 Runner 写入后的结果拉回。`goios`、Linux 与 Windows 只能连真机。

使用模拟器时：

1. 用 Simulator 或 `xcrun simctl boot` 启动目标机。未启动的不会出现在设备列表。
2. 被测应用必须是 `iphonesimulator` 包，已经装在该模拟器上，并能手动打开。应用嵌入的 framework 也必须是模拟器切片；装入真机切片时进程会立即退出，系统报 `have 'iOS', need 'iOS-simulator'`。
3. 启动页或 `cli.py devices` 中该项的连接方式为 `Simulator`。`cli.py run --udid <模拟器 UUID>` 使用 `-destination 'platform=iOS Simulator,id=…'`。
4. `cli.py install` 拒绝模拟器：它只把 Runner 装到真机，供 go-ios 使用。在模拟器上，`xcodebuild test` 会自行安装本轮 Runner。

| 能力                                     | 真机                        | 模拟器                                                                         |
|----------------------------------------|---------------------------|-----------------------------------------------------------------------------|
| 探索主循环（点击、手势、Home、重启）                   | 支持                        | 支持                                                                          |
| `screenshot` / `snapshot` / `combined` | 支持                        | 支持                                                                          |
| 插桩控件树（目标内 `127.0.0.1`）                 | 支持                        | 支持。电脑侧 `iproxy` / `ios forward` 检测跳过，日志 `stub check skipped`，由 Runner 启动后探活 |
| 通信检查 `testPingNetwork`                 | 支持                        | 支持                                                                          |
| 事件、覆盖、步骤截图的写入与拉回                       | `devicectl` / `ios fsync` | `simctl get_app_container`                                                  |
| Runner 记录的疑似崩溃、动作超时                    | 支持                        | 支持                                                                          |
| 插桩端资源采样（内存、CPU、主线程、内存警告）               | 支持                        | 支持。温度状态几乎恒为 `nominal`，不作依据                                                  |
| 电脑端资源采样（Instruments 内存、CPU、帧率）         | 支持（iOS 17.4+ USB）         | 不支持。日志 `perf host skipped`。`--perf` 仍把 `PEREGRINE_PERF=1` 传给 Runner，供插桩端采样  |
| 系统崩溃 / Jetsam 拉取                       | 支持                        | 不支持。日志 `crash collect skipped`                                              |
| `install`、go-ios、Linux / Windows       | 支持                        | 不支持                                                                         |
| USB / Network、国行无线数据授权                 | 有                         | 无。模拟器走 Mac 网络                                                               |

模拟器上的探索与通信检查已在 iPhone 17（iOS 26.5）与 iPhone 13（iOS 15.2）上跑通。

### 在 Linux 与 Windows 上运行

Runner 只能在 Mac 上编译和签名。手机上装好 Runner 后，Linux、Windows 电脑可经 [go-ios](https://github.com/danielpaulus/go-ios) 运行它，不需要 Xcode。go-ios 不能以模拟器为目标。

1. 在 Mac 上执行 `python3 tools/launch/cli.py install`，编译 Runner 并安装到手机。Runner 的签名到期、更换手机或更新 Peregrine 后，须重新执行。
2. 在 Linux 或 Windows 上安装 Python 3。Linux 需运行 `usbmuxd`；Windows 需安装 Apple Mobile Device Support（随 iTunes 或 Apple Devices 提供）。手机须开启开发者模式并信任这台电脑。
3. 将仓库复制到这台电脑，按前文启动 `server.py` 或使用 `cli.py`，不需要执行 `pod install`，也不需要另行安装 go-ios。

go-ios 按以下顺序确定：

1. 环境变量 `GO_IOS` 指定的路径。
2. go-ios v1.3.2：首次使用时从 [GitHub Releases](https://github.com/danielpaulus/go-ios/releases/tag/v1.3.2) 下载本平台的 `go-ios-<mac|linux|win>.zip`，校验 SHA-256 后取出可执行文件，存放在 `tools/launch/.local/tools/go-ios-v1.3.2/<mac|linux|win>/`，之后直接使用。Linux 按 CPU 架构取 `ios-amd64` 或 `ios-arm64`。
3. 下载失败时，使用 `PATH` 中的 `ios` 命令；`PATH` 中也没有时报错，并给出下载地址。

下载优先使用系统的 `curl`（macOS、Linux 与 Windows 10 及以上版本自带），沿用系统的证书与代理设置；找不到 `curl` 时改用 Python 自带的下载，python.org 安装的 macOS 版 Python 须先运行其 `Install Certificates.command`。无法访问 GitHub 时，手动下载上述压缩包，解压后用 `GO_IOS` 指定其中的可执行文件。

Windows 上，iOS 17 及以上版本的用户态隧道需要 `wintun.dll`。首次使用时同时从 [wintun.net](https://www.wintun.net/) 下载 `wintun-0.14.1.zip`，校验 SHA-256 后按 CPU 架构取出 `bin\<amd64|arm64|x86>\wintun.dll`，放在 `ios.exe` 所在目录，无需手动放置，也不必放入 `C:\Windows\System32`。用 `GO_IOS` 指定 go-ios 时，须自行将 `wintun.dll` 放在该 `ios.exe` 所在目录。

校验不通过的文件不会写入。删除 `tools/launch/.local/tools/` 后，下次运行时重新下载。

运行方式按以下顺序确定：环境变量 `PEREGRINE_BACKEND`（`xcode` 或 `goios`）、`cli.py --backend`，未指定时 macOS 上能找到 `xcodebuild` 即为 `xcode`，否则为 `goios`。启动页标题旁显示当前方式，启动时终端打印 `Peregrine 启动页 <地址>（<方式>）`。

go-ios 方式与 Xcode 方式的差别：

| 环节              | Xcode 方式                                                                                                                                                                                                | go-ios 方式                                                                                                                                                                            |
|-----------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 运行测试            | `xcodebuild test`，每轮按需编译并安装 Runner                                                                                                                                                                      | `tools/launch/runtest.py` 调用 `ios runtest`，运行手机上已安装的 Runner                                                                                                                          |
| 传给 Runner 的环境变量 | scheme 中映射的 `PEREGRINE_BUNDLEID`、`PEREGRINE_DURATION`、`PEREGRINE_THROTTLE`、`PEREGRINE_DATAPORT`、`PEREGRINE_LAUNCHENV`、`PEREGRINE_COMMAND_PORT`、`PEREGRINE_UI_SOURCE`、`PEREGRINE_SHOTS`、`PEREGRINE_PERF` | 当前进程中所有非空的 `PEREGRINE_` 变量                                                                                                                                                           |
| 日志              | `xcodebuild` 的输出，已滤去 XCTest 的活动记录                                                                                                                                                                       | Runner 的输出，已滤去 XCTest 自身的调试记录；结尾打印 `Test Case '-[PeregrineRunner <方法>]' passed/failed (<秒> seconds).` 与 `** TEST SUCCEEDED **` 或 `** TEST FAILED **`，中途终止时为 `** TEST INTERRUPTED **` |
| 结果包             | `.xcresult`                                                                                                                                                                                             | 无                                                                                                                                                                                    |
| 设备与应用列表         | 真机：`xctrace`、`ideviceinstaller`，型号取自 `devicectl`。模拟器：`simctl list devices booted`、`simctl listapps`                                                                                                     | `ios list`、`ios info`、`ios apps`，型号由 `tools/launch/models.py` 按型号标识对照。没有模拟器                                                                                                          |
| 拉回结果文件、收集崩溃     | 真机：`devicectl`、`idevicecrashreport`。模拟器：`simctl get_app_container`，不收集崩溃                                                                                                                                | `ios fsync`、`ios crash cp`                                                                                                                                                           |
| 插桩检测            | 真机：`iproxy`、`devicectl`。模拟器跳过电脑侧检测                                                                                                                                                                      | `ios forward`、`ios launch`、`ios kill`                                                                                                                                                |

设备列表显示为「型号 (iOS 版本) · 连接方式」，例如 `iPhone 15 Pro Max (18.6.2) · USB`；已启动的模拟器为 `Simulator`。手机改过名称时，名称显示在型号之前。go-ios 方式下，`models.py` 未收录的型号标识原样显示，例如 `iPhone19,1`；尚未与这台电脑配对的手机单独列为「未配对，先在手机上信任这台电脑」，不影响其他手机。

iOS 17 及以上版本，go-ios 须经隧道连接手机。运行前若 `ios tunnel ls` 中没有这台手机，会在后台执行 `ios tunnel start --userspace` 并等待至多 20 秒；隧道在测试结束后继续保留，供下一轮使用。每轮测试前还会执行 `ios image auto`，开发者磁盘映像已挂载时直接跳过，未挂载时下载并挂载，映像存放在 `tools/launch/.local/devimages/`。

go-ios 1.0.x 与 1.2 及以上版本的测试结果输出格式不同（前者为 Go 结构体文本，后者为 JSON），`runtest.py` 两种都能解析，因此 `GO_IOS` 也可以指定 1.0.x 版本。

go-ios 方式已在 macOS 上验证：`PATH` 中只有 Python 与 `curl`，go-ios v1.3.2 自动下载并通过校验，设备与应用列表、插桩检测与自动关闭、通信检查、1 分钟探索、拉回结果文件、崩溃收集与打包导出均正常；用 go-ios 1.2.0 另验证了中途终止，手机上的 Runner 随之退出。

### 通信检查

`-only-testing:PeregrineRunner/PeregrineRunner/testPingNetwork` 检查探索所用的通信链路，几秒内结束：

| 项目               | 内容                                                                             | 是否必须通过 |
|------------------|--------------------------------------------------------------------------------|--------|
| `loopback`       | 设备本机 127.0.0.1 的 TCP 收发                                                        | 是      |
| `command_server` | 启动命令端口并向其发送一条 `BACK`，确认收到 200 且命令入队。设置了 `PEREGRINE_COMMAND_PORT` 时用该端口，否则用空闲端口 | 是      |
| `stub`           | 设置了 `PEREGRINE_BUNDLEID` 与 `PEREGRINE_DATAPORT` 时，启动被测应用并探测插桩                  | 设置时是   |
| `internet`       | 外网可达性：`reachable`、`denied` 或 `unreachable`                                     | 见下文    |

每项成功时日志打印一行，例如 `loopback success`、`command server success port 8100`、`stub success port 9797`、`internet success`。外网不可用时打印 `internet denied (not required)` 或 `internet unreachable (not required)`；需要外网时括号内为 `required`。外网请求失败时另打一行 `ping network failed HTTP <状态码> <错误>`，需要外网时只在等待结束后打印一次。用例失败时，失败信息汇总各项结果。

探索、命令端口与插桩只使用 127.0.0.1，不需要外网。部分国行设备会拒绝 Runner 使用无线数据，系统通常不弹授权框，日志中为 `internet denied`，此时不影响探索。只有配置了 `sceneConfigURL` / `sceneCallback`（或对应环境变量），或设置 `PEREGRINE_REQUIRE_INTERNET=1` 时，外网不可达才判为失败；此时会等待并尝试点击无线数据授权框，最长约 75 秒。

## 环境变量

scheme `PeregrineRunner` 中下列键的值为 `${PEREGRINE_*}`，因此启动 `xcodebuild` 时的环境变量会传入测试进程。若将其中一项改为字面值，同名环境变量不再生效。

| 变量                           | 说明                                                                                                | 示例                                |
|------------------------------|---------------------------------------------------------------------------------------------------|-----------------------------------|
| `PEREGRINE_BUNDLEID`         | 被测应用。必需                                                                                           | `com.example.app`                 |
| `PEREGRINE_DURATION`         | 分钟。默认 1。未设置、0 或负数都按默认值                                                                            | `10`                              |
| `PEREGRINE_THROTTLE`         | 操作间隔，毫秒。默认 300                                                                                    | `300`                             |
| `PEREGRINE_DATAPORT`         | 插桩端口。未设置或为 0 时使用截图                                                                                | `9797`                            |
| `PEREGRINE_LAUNCHENV`        | 写入被测应用的环境变量。各项为 `键=值`，以 `:` 分隔                                                                    | `isAutoTestUI=1:channel=AutoTest` |
| `PEREGRINE_UI_SOURCE`        | `combined`（默认）、`screenshot` 或 `snapshot`。插桩探活成功时忽略                                                | `screenshot`                      |
| `PEREGRINE_COMMAND_PORT`     | 设备本机的命令端口，1–65535。小于或等于 0 时不监听；端口被占用时日志打印 `not listening`，启动日志里的 `command` 显示 0                   | `8100`                            |
| `PEREGRINE_COVERAGE_DIR`     | Runner 进程在目标上的输出目录。指定 Mac 路径无效                                                                    |                                   |
| `PEREGRINE_CONFIG`           | 配置目录。其中的同名 JSON 覆盖包内文件                                                                            |                                   |
| `PEREGRINE_STRINGS`          | 输入框候选文本，每行一条                                                                                      |                                   |
| `SCENE_CALLBACK`             | 覆盖 `appconfig.json` 中的 `sceneCallback`                                                            |                                   |
| `SCENE_CONFIG_URL`           | 覆盖 `appconfig.json` 中的 `sceneConfigURL`                                                           |                                   |
| `ACTION_TIMEOUT_MS`          | 单个动作超过该毫秒数时记一条 `action_timeout`。默认 8000                                                           |                                   |
| `PEREGRINE_REQUIRE_INTERNET` | 为 `1` 时，`testPingNetwork` 要求外网可达                                                                  | `1`                               |
| `PEREGRINE_SHOTS`            | 步骤截图：`off`（默认）、`change`（画面指纹变化时保存）、`all`（每步保存）                                                    | `change`                          |
| `PEREGRINE_SHOTS_LIMIT`      | 目标上最多保留的截图张数，超出时删除最早的。默认 500                                                                      | `300`                             |
| `PEREGRINE_PERF`             | 为 `1` 时开启插桩端资源采样，每步向插桩读取一次被测应用的资源数据，写入事件日志。默认关闭；未使用插桩时不生效。电脑端采样由启动页「资源采样」或 `cli.py run --perf` 开启 | `1`                               |

scheme 只包含 `PEREGRINE_BUNDLEID`、`PEREGRINE_DURATION`、`PEREGRINE_THROTTLE`、`PEREGRINE_DATAPORT`、`PEREGRINE_LAUNCHENV`、`PEREGRINE_UI_SOURCE`、`PEREGRINE_COMMAND_PORT`、`PEREGRINE_SHOTS`、`PEREGRINE_PERF`。其余变量在命令行加 `TEST_RUNNER_` 前缀传入，例如 `TEST_RUNNER_PEREGRINE_REQUIRE_INTERNET=1`。

## 配置文件

运行时读取 `Peregrine/peregrine-behavior/config/`，并打入 `PGBehaviorConfig.bundle`。

| 文件                    | 读取的字段                                                                                                                                       |
|-----------------------|---------------------------------------------------------------------------------------------------------------------------------------------|
| `testconfig.json`     | `SkipCheckBlock`、`SkipRestart`、`SkipHome`、`GestureRatio`                                                                                    |
| `setting.json`        | `channel`，仅写入日志                                                                                                                             |
| `default.jsonsetting` | `events`、`actions`、`sequences`                                                                                                              |
| `appconfig.json`      | `cases`、`sceneLimit`、`sceneLimits`、`sceneCallback`、`applet.schema`、`excludeRects`、`excludeElements`、`sceneConfigURL`。包内默认文件为空对象，上述字段均按未设置处理 |

动作 JSON 的常用字段为 `act`、`pos`、`id`、`text`、`path`、`duration`、`throttle`。此处的 `duration` 与 `throttle` 属于单条动作，不是上表中的启动参数。

- `TYPE` 的 `text` 是要输入的内容，不用于查找控件。带 `id` 或 `pos` 时先点击目标再输入，否则输入到当前焦点。
- `CLICK_TEXT`、`CLICK_ID` 按控件文字或 accessibility identifier 查找目标。截图与 `combined` 模式下改为读取一次系统界面快照来查找；找不到时跳过，日志打印 `target not found`。
- `SCHEMA` 与 `applet.schema` 通过 URL scheme 打开页面，需要 iOS 16.4 及以上。
- `excludeRects` 按截图像素坐标排除固定区域，适用于位置不变的控件。可拖动的悬浮控件（如调试悬浮按钮）改用 `excludeElements`，写控件的 accessibility identifier 或文字，例如 `"excludeElements": ["BCDebuggerLogo"]`，须与控件的 identifier 或文字完全一致。每一步按该控件当前的位置，丢弃控件本身以及中心落在其范围内的候选目标；本步没有该控件时不排除任何区域。日志打印 `exclude elements covers <控件数> dropped <丢弃数>`。候选目标来自截图切分时（截图模式，以及 `combined` 模式未改用界面快照的步骤），每次切分多一次界面查询。
- 画面停滞按画面指纹判断：连续 4 步停在同一画面时，依次尝试上滑、强制返回、重启应用（`SkipRestart` 为 true 时不重启），日志打印 `block recovery <动作>`。重启并离开该画面后，这一指纹冷却 60 步，期间不再上滑、强制返回或再次重启，日志打印 `block recovery cooldown <指纹> steps 60`。重启后画面没有离开，或全部尝试后画面仍未变化，日志打印 `block recovery gave up`，该画面在本轮不再触发恢复。按决策次数累计到 101 步的重启不进入这次冷却。
- 页面停滞按探索状态判断，覆盖画面细节在变、但始终在少数几个页面之间来回的情况（例如图片查看页每次点击后图片位置略有变化）。最近 8 步没有发现新页面，且这 8 步只涉及不超过 3 个页面时，先连续 3 步避开这几个页面已试过的动作并随机选择目标，之后依次尝试边缘右滑返回、点击左上或右上角的小控件（关闭、返回按钮通常在此，没有时改为向下拖动）、从屏幕上部向下拖动（关闭弹出的页面）、重启应用，相邻两次尝试之间插入一步普通探索。进入新页面即停止升级。`SkipRestart` 为 true 时最后一步改为边缘右滑返回。日志打印 `cycle escape <back|corner|dismiss> <动作>` 与 `cycle escape restart`。这次重启真正执行后，仍落在同一组页面里的后续循环要等 60 步才再开一轮逃生，日志打印 `cycle escape cooldown steps 60`。决策满 101 步触发的重启不进入这次冷却。
- 相册选择器、分享面板等系统页面没有可用的控件信息，依次执行边缘右滑返回、从屏幕上部向下拖动，仍未离开时请求回到被测应用。日志打印 `outside <页面> step <次数> <back|dismiss|foreground>`。
- 自动探索在点击之外按比例混入手势，比例由 `testconfig.json` 的 `GestureRatio` 设置，键与默认值为 `SWIPE` 0.10、`LONG_PRESS` 0.06、`DOUBLE_TAP` 0.03、`PINCH` 0.02、`DRAG` 0.02，表示每一步选用该手势的概率，其余步骤为点击。比例总和超过 1 时按比例缩放到总和为 1；某个键设为 0 即关闭该手势。`SWIPE` 与 `PINCH` 作用于屏幕中部（横向 10% 至 90%、纵向 20% 至 80%），滑动方向为上 45%、下 25%、左 15%、右 15%，捏合为放大、缩小各半。`LONG_PRESS`、`DOUBLE_TAP`、`DRAG` 作用于选中的目标，`DRAG` 从目标中心按住后拖到随机位置。选中的目标可滚动时改为滑动，是输入框时改为输入文字，不受该比例影响。
- 截图切分按点数判断控件类型，同一套阈值适用于不同分辨率的设备。贴近屏幕边缘的区域与边框颜色不一致的区域不视为弹窗，避免把全屏页面的局部误判为弹窗、只在其中选择目标。
- 切分粒度随画面内容调整：纯色背景上的文字、图标、按钮逐个切分；照片等纹理区域（边长不小于 40 点、颜色深浅分布分散、内部有明显纹理）只作为一个 `image` 候选块，其中的枝叶、轮廓不再各自成块。照片上叠加的纯色控件保留为单独的块；叠加在照片上的半透明控件（例如深色圆底的返回按钮）会并入照片块，`combined` 模式下点击照片块时由界面快照补回真实控件。全屏看图页的候选块由 26 个降为 8 个，切分耗时不变（Mac 上每张约 7 毫秒）。

## 结果

`xcodebuild` 在结束前输出：

```text
coverage 3: Home x10, Detail x4, Form x2
coverage written
```

数字为不同页面的数量，其后为每个页面的访问次数。同一内容写入目标上的 `peregrine-coverage.txt`。同目录还包括 `peregrine-events.jsonl` 与 `peregrine-applet.txt`。未设置 `PEREGRINE_COVERAGE_DIR` 时，目录为 Runner 的临时目录。

结束时还输出一行 `explore score ...`，汇总步数、画面变化率、不同画面数、同一画面最长连续步数等探索指标，末尾的 `acts` 为各类动作的执行次数，例如 `acts BACK:12,CLICK:41,LONG_PRESS:5,SWIPE_UP:4`。

### 步骤截图

用于排查探索过程，默认关闭。启动页「步骤截图」、`cli.py run --shots` 或环境变量 `PEREGRINE_SHOTS` 设为 `change` 时，只在画面指纹与上一张不同时保存；设为 `all` 时每步保存。每张截图缩放到屏幕点数大小，存为 JPEG（约 30 至 50 KB），绿色框为该步的候选块，红色框为本步操作的目标，拖动画出路径，底部一行为步数、动作、节点来源和目标文字。文件名为 `<步数>-<动作>.jpg`，步数按实际执行的步骤计，`change` 模式下跳过的步骤不占文件但占步数。同一目录的 `index.jsonl` 每行对应一张截图，字段为 `step`、`file`、`time`（毫秒时间戳）、`act`、`target`（`[left, top, width, height]`，单位为点）、`text`、`source`、`activity`、`nodes`、`fingerprint`。

截图先写在 Runner 临时目录的 `peregrine-shots/`，目标上最多保留 `PEREGRINE_SHOTS_LIMIT` 张（默认 500），超出时删除最早的，日志打印一次 `shots limit <张数> reached, oldest dropped`。测试结束时打包为 `peregrine-shots.zip` 并删除该目录，日志打印 `shots archive success <张数>`；打包失败时打印 `shots archive failed`，目录保留，Xcode 方式下照常拉回该目录。随后与其他结果文件一起拉回 `run-<时间>/device/`，并打入导出的 `peregrine-run-<时间>.zip`。

开启截图后每步多一次缩放与 JPEG 编码；插桩模式下本步不截屏，开启截图后每步额外截屏一次。

### 崩溃与异常

Runner 每一步先检查被测应用是否还在前台。进程已退出时记一次疑似崩溃，并把应用重新拉起；两次检测之间没有新操作时算同一次。单个动作超过 `ACTION_TIMEOUT_MS`（默认 8000 毫秒）时记一次动作超时，可作为卡顿的线索。

每次疑似崩溃或动作超时，日志打印一行 `peregrine anomaly`，其后是此前最多 8 步操作，每步一行 `peregrine anomaly step`，含时间、页面、动作和目标。结束时打印汇总，同样的计数写入 `peregrine-events.jsonl` 中 `task_end` 的 `anomalies` 字段：

```text
anomaly summary suspected_crash 2 suspected_crash_restart 0 action_timeout 0 left_foreground 1
```

`suspected_crash`、`suspected_crash_restart`、`action_timeout` 总是列出；`left_foreground` 等其他类型只在本轮发生过时列出。

Runner 读不到系统崩溃日志，所以只知道“进程没了”，不知道原因。崩溃类型和调用栈由 Mac 上的 `tools/crash/collect.py` 补齐：它从**真机**拉取本轮时间段内被测应用的崩溃日志和内存超限（Jetsam）记录，按异常类型和崩溃线程前 3 个有效栈帧去重计数，再按时间对上 Runner 日志里的操作路径。需要 `idevicecrashreport` 与 `ideviceinstaller`（Homebrew 安装 `libimobiledevice` 与 `ideviceinstaller`）。模拟器没有这条通道，结束后日志打印 `crash collect skipped`，只保留 Runner 自己的疑似崩溃与超时计数。

通过启动页或 `cli.py run` 运行时，真机每轮结束后自动收集，启动页状态显示「正在收集设备结果和崩溃日志」；模拟器只拉回结果文件，状态为「正在拉回结果」。报告写入 `tools/launch/.local/rounds/run-<时间>/crash/`。直接调用 `xcodebuild` 时，在仓库根目录执行：

```shell
python3 tools/crash/collect.py --udid <设备 UDID> --bundle-id com.example.app \
  --since "2026-10-21 16:00:00" --log <xcodebuild 输出> --out <报告目录>
```

`--since` 填本轮开始时间（本地时间，或 Unix 秒数）；`--log` 可省略，省略时报告里没有操作路径。输出示例：

```text
crash collect crash 6 jetsam 0 signatures 2 runner_exits 6 timeouts 0
  4x 未捕获的 Objective-C 异常（SIGABRT） | CoreFoundation -[__NSSingleObjectArrayI objectAtIndex:] > StubDemo -[SDHome crashWithException] > ...
  2x 非法内存访问（EXC_BAD_ACCESS SIGSEGV） | StubDemo -[SDDetail crashWithNull] > ...
crash report written <报告目录>/crash-report.md
```

报告目录包含：

| 文件                  | 内容                                                            |
|---------------------|---------------------------------------------------------------|
| `crash-report.md`   | 汇总表；每个崩溃点的类型、次数、时间、异常原因、崩溃线程栈和崩溃前的操作；没有找到系统日志的进程退出；动作超时及其前的操作 |
| `crash-report.json` | 同样内容的结构化数据                                                    |
| `reports/`          | 原始 `.ips` 日志，可用 Xcode 打开                                      |

Objective-C、Swift 和 C/C++ 的崩溃都会被收集。识别的类型有未捕获的 Objective-C 异常（报告里带异常名和原因）、主动终止（abort、断言）、非法内存访问、Swift 运行时错误（数组越界单独标出；强制解包 nil、`fatalError`、`precondition` 在日志里无法区分，归为一类）、看门狗超时（启动或主线程卡住太久）、资源超限、受保护资源误用和内存超限。Swift 的错误文本（例如 `Unexpectedly found nil`）只写入设备系统日志，不在崩溃日志里，报告中以崩溃函数和函数内偏移定位；同一函数内不同位置的崩溃按偏移分开计数。栈帧能否显示函数名取决于被测应用的符号：自己编译的 Debug 包通常直接可读，商店包只显示偏移地址，需要用对应的 dSYM 符号化。系统写日志有几秒延迟，脚本默认先等 5 秒再拉取。

## 插桩

若需读取被测应用自身的界面树，请按 [插桩接入](./插桩接入.md) 将 `peregrine-stub` 链接到被测应用，并设置 `PEREGRINE_DATAPORT`。日志为 `alive 1` 且界面来源为 `ui stub` 时，表示正在使用界面树。

数据端口须与被测应用匹配。插桩在应用退到后台后仍监听端口，另一个接入插桩的应用留在后台时，会替被测应用应答同一端口。为此，真机上启动页与命令行在开跑前检测，Runner 在探活后核对；模拟器跳过电脑侧检测，由 Runner 启动后探活。

真机上，启动页「检测」、`cli.py stub` 以及开跑前的检测经 `iproxy` 连到手机端口：先不带端口重启被测应用，此时端口仍有应答即为他人占用：应答方能报出 Bundle ID 时，经 `devicectl` 结束该应用的进程，端口释放后继续检测，提示末尾注明「已自动关闭原先占用该端口的 <Bundle ID>」；应答方为旧版插桩、无法确定是哪个应用，或结束进程失败时，结论为 `other`。再带端口重启，等待至多 8 秒，用 `app_info` 读取应答方的 Bundle ID。结论如下：

| 结论       | 日志首行                                                                        | 本轮做法                           |
|----------|-----------------------------------------------------------------------------|--------------------------------|
| `ok`     | `stub check success <Bundle ID> port <端口>`，自动关闭过占用方时后接 `closed <Bundle ID>` | 使用插桩                           |
| `legacy` | `stub check legacy: …`                                                      | 插桩版本早于 `app_info`，无法核对归属，仍使用插桩 |
| `other`  | `stub check other: 端口 … 已被 … 占用 …；本轮不用插桩，改用截图`                              | 不传数据端口；须在手机上手动关闭占用方            |
| `none`   | `stub check none: … 没有插桩响应 …；本轮不用插桩，改用截图`                                   | 不传数据端口                         |

检测本身失败时（例如未安装 `iproxy`），或目标为模拟器时，日志首行为 `stub check skipped: …`，端口原样交给 Runner。

Runner 探活成功后再发 `app_info`：Bundle ID 与 `PEREGRINE_BUNDLEID` 一致时打 `stub app_info success <Bundle ID>`；不一致时打 `stub port <端口> belongs to <Bundle ID>, not <被测应用>; stub not used`，本轮改用截图；旧版插桩不支持 `app_info` 时打 `stub app_info unavailable on port <端口>, port trusted`，照常使用插桩。

### 资源采样

用于定位内存上涨与泄漏、内存超限、CPU 占用、卡顿和掉帧，默认关闭。启动页「资源采样」选「采集内存、CPU、帧率」或 `cli.py run --perf` 时，真机同时开启两路采样，只对探索测试生效：电脑端采样对任何应用生效；插桩端采样只在插桩模式下生效，另外提供主线程卡顿、内存警告与设备温度状态。模拟器没有 Instruments 通道，电脑端打印 `perf host skipped`，`--perf` 仍把 `PEREGRINE_PERF=1` 传给 Runner，有插桩时采插桩端指标。任一路启动失败时只打印原因，测试照常进行。

| 指标                           | 电脑端             | 插桩端    |
|------------------------------|-----------------|--------|
| 内存（`phys_footprint`）、CPU、线程数 | 约每秒一次           | 每步至多一次 |
| 磁盘读写量、打开的文件数、Mach 端口数、中断唤醒次数 | 约每秒一次           | 无      |
| 屏幕帧率                         | 每秒一次，整块屏幕       | 无      |
| 前后台切换、系统内存级别通知               | 发生时记录           | 无      |
| 主线程卡顿、内存警告、设备温度状态            | 无               | 每步至多一次 |
| 内存超限被系统结束（Jetsam）            | 由崩溃收集统计，见「崩溃收集」 | 无      |

开销实测（iPhone 15，6 核，iOS 26.2，被测应用在前台，两次测量）：与不采样相比，电脑端采样使手机上的 `sysmond` 增加 8%～14% 的单核占用，约合整机 CPU 的 1.3%～2.3%；`DTServiceHub` 未见增加；二者内存不变。插桩端采样每秒至多一次请求，在被测应用内的开销见下文。同一被测应用开启与关闭采样时，每分钟执行的步数在随机波动范围内。

#### 电脑端采样

经 [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) 订阅手机上 Instruments 的 `sysmontap`、帧率与 `mobilenotifications` 服务，与 Xcode Instruments 取自同一组服务，不改动被测应用。Mac、Linux、Windows 用法相同，均通过用户态隧道连接 iOS 17 及以上的设备，不需要 root 或管理员权限，也不需要 Xcode。

- 依赖写在 `tools/requirements.txt`，当前为 pymobiledevice3 11.42.0。首次使用时，在 `tools/launch/.local/tools/pymobiledevice3-11.42.0/` 创建独立的 Python 虚拟环境并按该文件安装，需要 Python 3.9 及以上，耗时取决于网络，之后直接使用。也可预先执行 `python3 -m pip install -r tools/requirements.txt`。`cli.py` 等安装完成再开跑；启动页不等待，在后台安装，本轮日志打印 `perf host skipped: pymobiledevice3 安装中，完成后下一轮可用`，测试照常进行；安装失败时，下一轮日志打印 `perf host skipped: pymobiledevice3 上次安装失败：<原因>；已重新开始安装，完成后下一轮可用`。用环境变量 `PYMOBILEDEVICE3` 可指定已安装的 `pymobiledevice3` 可执行文件。
- 手机须与电脑完成「信任此电脑」配对。只用 `devicectl` 连接过的手机可能尚未配对，此时日志为 `perf host skipped: The user refused to trust this computer.`，在手机上点「信任」后重跑即可。
- 开跑前按 Bundle ID 查出被测应用的可执行文件名，日志打印 `perf host start <进程名>`；采样跟随同名进程，应用重启后自动接上新进程。采样进程在本轮结束时退出，启动页或 `cli.py` 被强制结束时也随之退出。因此测试进行中重启启动页，测试会继续，但电脑端采样就此停止，本轮不输出电脑端汇总与采样报告。
- pymobiledevice3 11.42.0 的 `notifications` 命令遇到无法转成 JSON 的通知内容（例如系统内存级别通知中的日期）会退出。使用自动安装的 pymobiledevice3 时，这类内容记为 `{"$repr": "<原始内容>"}`，采样不中断；用 `PYMOBILEDEVICE3` 指定的可执行文件不在虚拟环境中时无此处理，`notifications` 可能提前退出，见下文的提前退出提示。
- Linux 与 Windows 上，iOS 17.0 至 17.3.1 需要以 root 或管理员身份另行运行 `pymobiledevice3 remote tunneld`；iOS 17.4 及以上无此要求。

结果写入 `run-<时间>/device/`，随设备结果一起打包导出：

| 文件                   | 内容                                                                                                                                                                                                                                                    |
|----------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `perf-process.jsonl` | 约每秒一行：`pid`、`name`、`cpuUsage`（100 为一个核满载）、`physFootprint`（物理内存占用，字节，与系统判定内存超限的口径一致）、`threadCount`、`diskBytesRead` 与 `diskBytesWritten`（进程启动以来的磁盘读写字节数）、`nfiles`（打开的文件数）、`machPortCount`（Mach 端口数）、`intWakeups`（进程启动以来的中断唤醒次数）、`timestamp`（UTC）        |
| `perf-fps.jsonl`     | 每秒一行：`fps`、`timestamp`。为整块屏幕的 Core Animation 帧率，画面静止时为 0                                                                                                                                                                                              |
| `perf-notify.jsonl`  | 每条通知一行：`timestamp`（电脑收到的时间，UTC）与 `event`（原始通知）。`applicationStateNotification:` 为应用状态变化，含 `pid` 与 `state_description`（如 `Running`、`Suspended`、`Terminated`）；`memoryLevelNotification:` 为系统内存级别通知，含 `code` 与 `pid`，`pid` 为 -1 表示整机，`code` 的含义 Apple 未公开 |
| `perf-host.log`      | pymobiledevice3 的错误输出，采样正常时通常为空                                                                                                                                                                                                                       |

结束时日志输出 `perf host samples <进程样本数> launches <进程数> peak_mb <内存峰值> peak_time <峰值时刻> cpu_avg <平均 CPU> cpu_max <最高 CPU> fps_samples <帧率样本数> fps_avg <帧率均值> fps_low <低帧秒数> background_s <后台秒数> disk_read_mb <磁盘读> disk_write_mb <磁盘写> files_max <最多文件数> ports_max <最多端口数> wakeups_per_s <每秒唤醒> memory_levels <系统内存级别通知数>`。

- `cpu_avg` 与 `cpu_max` 不计每次启动的第一条样本，该条没有 `cpuUsage`。
- 帧率采样从编译 Runner 前开始，到测试结束后停止，且为整块屏幕的帧率。汇总只统计第一条到最后一条进程样本之间、且被测进程处于 `Running` 状态的秒，被排除的后台秒数记为 `background_s`；`perf-fps.jsonl` 保留全部记录。状态以当时正在采样的进程的最近一次状态变化为准，没有收到状态变化时视为在前台。
- `fps_avg` 与 `fps_low` 只统计帧率大于 0 的秒，`fps_low` 为其中低于 30 帧的秒数。
- `disk_read_mb`、`disk_write_mb` 为各次启动内计数增量之和，`wakeups_per_s` 为各次启动的唤醒增量之和除以采样总时长。
- 某路采样在测试结束前退出时，汇总行后追加 `perf host process|fps|notify exited <退出码> before the run ended: <原因>`，原因取自 `perf-host.log` 中最后一条 `ERROR`。

#### 插桩端采样

开启后（`--perf`，或直接用 `xcodebuild` 时设置 `PEREGRINE_PERF=1`），Runner 给被测应用的启动环境加上 `stubPerf=1`，插桩随应用启动开始检测主线程并统计内存警告；Runner 每步操作后向插桩发一次 `app_perf`，两次至少间隔 1 秒，等待至多 1 秒，结果写成一条 `perf` 事件：

| 字段                | 含义                                                                           |
|-------------------|------------------------------------------------------------------------------|
| `footprint_bytes` | 被测应用的物理内存占用（`phys_footprint`），与电脑端的 `physFootprint` 口径相同                     |
| `cpu_percent`     | 被测应用各线程的 CPU 占用之和，100 为一个核满载，保留一位小数                                          |
| `threads`         | 线程数                                                                          |
| `main_max_ms`     | 自上一条 `perf` 以来主线程最长的无响应时间，毫秒                                                 |
| `main_slow`       | 自上一条 `perf` 以来主线程无响应达到 250 毫秒的次数                                             |
| `memory_warnings` | 自上一条 `perf` 以来应用收到 `UIApplicationDidReceiveMemoryWarningNotification` 的次数    |
| `thermal_state`   | 设备温度状态：`nominal`、`fair`、`serious`、`critical`，取自 `NSProcessInfo.thermalState` |

主线程检测每 0.1 秒向主线程投递一个空任务，记录从投递到执行的间隔；同一时刻只有一个任务在等待，主线程卡住时不会堆积。超过 10 秒未收到 `app_perf` 时检测自行停止。读取内存、CPU 与温度状态在插桩的后台线程完成，不占用主线程；内存警告由通知中心回调计数，不另开线程或定时器。

结束时日志输出 `perf samples <样本数> peak_mb <内存峰值> peak_sample <峰值所在样本序号> main_max_ms <最长无响应> main_slow <慢响应次数> memory_warnings <内存警告次数> thermal_max <最高温度状态，无样本时为 none> missed <未取到的次数>`。应用重启后插桩约 2 秒才开始监听，这段时间的采样计入 `missed`。同样的数值写入事件日志 `task_end` 的 `perf` 字段：`samples`、`peak_bytes`、`peak_sample`、`main_max_ms`、`main_slow`、`memory_warnings`、`thermal_max`、`missed`。

#### 采样报告

启动页或 `cli.py run --perf` 拉回设备结果后，把两路采样与事件日志的操作步骤按时间对齐，写入 `run-<时间>/device/perf-report.txt`，日志打印 `perf report success <路径>`；两路都没有样本时打印 `perf report skipped: no samples`。报告包括：

- 内存峰值及其时刻，以及峰值前最近执行的一步操作（电脑端）。
- 每次启动（每个 `pid`）的起始、结束与峰值内存，以及按线性拟合算出的增长斜率（MiB/分钟）；持续不足 30 秒的启动不计斜率。斜率持续为正说明内存只涨不降，是排查泄漏的起点（电脑端）。
- 内存增长最多的 5 步：每步从该步开始到下一步开始，同一进程内的内存变化（电脑端）。
- 每次启动的文件数与 Mach 端口数起止值及斜率（个/分钟）、磁盘读写量、每秒唤醒次数；文件数或端口数持续上涨提示句柄泄漏（电脑端）。
- 应用退到后台的次数，不含进程结束（电脑端）。
- 系统内存级别通知的时刻、`code`、`pid`，以及其前最近执行的一步操作（电脑端）。
- 主线程卡顿（单次 250 毫秒及以上）、内存警告、`nominal` 以外的温度状态，以及各自之前最近执行的一步操作（插桩端）。

插桩端的条目按事件日志中的先后顺序归到它之前的那一步，结果准确。电脑端的条目只能按时间对齐，而事件日志的时间精确到秒，同一秒内开始的多步操作会被归入其中最后一步，因此电脑端条目对应的步骤只作定位参考。

#### 未纳入的指标

以下指标开销大、会改变被测应用的运行状态，或适用范围与 Peregrine 不符，不纳入采样：

| 指标                                                         | 不纳入的原因                                          |
|------------------------------------------------------------|-------------------------------------------------|
| 内存图（`memgraph`）、内存分配记录（`allocations`）、虚拟内存区域（`vm-regions`） | 只支持开发签名的应用；抓取内存图期间被测进程会暂停，分配记录需由工具重新启动应用，均会干扰探索 |
| 内核追踪（`core-profile-session`）                               | 记录全系统的调度与系统调用事件，数据量和手机端开销都大                     |
| GPU 与显存（`graphics`）                                        | 需要手机持续读取图形计数器，开销未经验证，且整屏帧率已能反映掉帧                |
| 按进程的能耗（`energy`）与网络流量（`network-statistics`）                | 各需再开一路常驻服务，开销未经验证；耗电倾向可先看中断唤醒次数                 |
| 系统日志（`oslog`）                                              | 日志量大，pymobiledevice3 标注为不稳定                     |
| 卡顿时的主线程调用栈                                                 | 需在插桩内反复挂起主线程取栈，并另做符号化，开销与风险高于收益                 |
| 插桩端的应用自身帧率（`CADisplayLink`）                                | 每帧在主线程回调，并会让系统保持较高的屏幕刷新率，改变被测应用的耗电与刷新行为         |
