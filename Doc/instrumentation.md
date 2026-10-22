# Instrumentation

[简体中文](插桩接入.md) · [English](instrumentation.md)

Updated 2026-10-22. The stub (`peregrine-stub` / `PGStub` in the code) lets Peregrine read the view tree inside the app under test, instead of splitting a screenshot. After integration, page names come from view controllers and tap targets come from real controls, so exploration is more accurate.

The stub is optional. Without it, Peregrine still works, using screenshots and system snapshots. On a Simulator the protocol is the same: the Runner and the app share `127.0.0.1` inside the guest. The host cannot preflight with `iproxy`; `cli.py stub` prints `skipped` and the Runner probes after launch. The app under test must be an `iphonesimulator` build. See [Physical device and Simulator](handbook-en.md#physical-device-and-simulator).

Before you start:

- You can change and rebuild the app under test, and install a Debug build on the test phone or a booted Simulator.
- The app under test uses CocoaPods. If it does not, see section 3.
- Peregrine itself has already run once, following the [README](../README_en.md).

## 1. Quick integration

### Step 1: Add the dependency

In the app's Podfile, add two lines to the app target:

```ruby
target 'YourApp' do
  # ... existing pods
  pod 'peregrine-stub', :path => '<peregrine-ios repo>/Peregrine', :configurations => ['Debug']
  pod 'GCDWebServer', :configurations => ['Debug']
end
```

- `:path` points at this repository's `Peregrine/` directory (where `peregrine-stub.podspec` lives).
- `:configurations => ['Debug']` keeps the stub out of Release. If the test build uses another configuration (for example a custom `Beta`), list that name as well.
- GCDWebServer is a stub dependency and is already declared in the podspec, so CocoaPods installs it automatically. The extra line is required because `:configurations` is not passed to dependencies; without it, GCDWebServer is linked into Release.

If the Podfile has `use_frameworks!`, or the build reports `SDK does not contain 'libarclite'`, add the following at the end of the Podfile (merge it into an existing `post_install` if you have one). GCDWebServer declares iOS 8; current Xcode no longer builds deployment targets below iOS 12:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 12.0
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
      end
    end
  end
end
```

Then run:

```shell
pod install
```

No application code is required. The stub loads when the app starts, and it only opens its server when Peregrine launches the app (see section 4). If the user opens the app from the Home Screen, the stub does nothing.

### Step 2: Install the Debug build

Open the `.xcworkspace` in Xcode, select the test phone or a booted Simulator, and run once with the Debug configuration (Product > Run). You can stop the run after it is installed. A Simulator needs an `iphonesimulator` build, including embedded frameworks; a device slice exits immediately with `have 'iOS', need 'iOS-simulator'`.

### Step 3: Self-check

From this repository's `Peregrine/` directory, run the communication check. `9797` can be any free port:

```shell
PEREGRINE_BUNDLEID=<app Bundle ID> PEREGRINE_DATAPORT=9797 \
xcodebuild test -workspace Peregrine.xcworkspace -scheme PeregrineRunner \
  -destination 'platform=iOS,id=<device UDID>' \
  -only-testing:PeregrineRunner/PeregrineRunner/testPingNetwork \
  DEVELOPMENT_TEAM=<Team ID> -allowProvisioningUpdates
```

It finishes in about ten seconds. `stub success port 9797` and `** TEST SUCCEEDED **` mean the stub is in. If you see `stub failed port 9797`, use section 5. For a Simulator, use `-destination 'platform=iOS Simulator,id=<UUID>'`.

You can also confirm in Xcode alone: in the app scheme (Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables) add `stubPort` with value `9797` and run the app. After about two seconds the Xcode console prints `start peregrine stub listen success on 127.0.0.1:9797`. Remove that variable after you confirm.

### Step 4: Start exploring

On the launch page, set **数据端口** (data port) to `9797` and click **开始** (start). From the command line, pass `PEREGRINE_DATAPORT`:

```shell
PEREGRINE_BUNDLEID=<app Bundle ID> PEREGRINE_DATAPORT=9797 PEREGRINE_DURATION=1 \
xcodebuild test -workspace Peregrine.xcworkspace -scheme PeregrineRunner \
  -destination 'platform=iOS,id=<device UDID>' \
  -only-testing:PeregrineRunner/PeregrineRunner/testPeregrine \
  DEVELOPMENT_TEAM=<Team ID> -allowProvisioningUpdates
```

`stub probe port 9797 alive 1 ... ui stub` means this run is using the stub tree. `alive 0` means the stub was not reached and the run fell back to screenshot recognition. For a Simulator, use `-destination 'platform=iOS Simulator,id=<UUID>'` as well.

On a physical phone, the launch page and `tools/launch/cli.py run` check before the run whether the app under test has the stub and whether that app is answering on the port; the result is the first log line. If the stub is missing or another app owns the port, the data port is not passed and the run uses screenshots. You can also check on its own: click **检测** (probe) next to the data port, or run `python3 tools/launch/cli.py stub --bundle-id <Bundle ID> --dataport 9797`. A Simulator cannot be probed from the host: **检测** is disabled, `cli.py stub` prints `skipped`, and the Runner probes after launch. The result codes are in the [handbook](./handbook-en.md) section "Instrumentation".

## 2. Optional: keep some views out of the tree

Debug overlays, watermarks, and analytics panels interfere with exploration. Subclass `PGStub` and override `shouldExposeView:`; a view that returns NO is omitted with its subtree.

The subclass must be wrapped in `#if DEBUG`. The stub is Debug-only; without the guard, a Release build fails to link because `PGStub` is missing.

Objective-C:

```objc
#if DEBUG
#import "stub.h"

@interface MyStub : PGStub
@end

@implementation MyStub
- (BOOL)shouldExposeView:(UIView *)view
{
    if ([view.accessibilityIdentifier isEqualToString:@"debug-panel"]) {
        return NO;
    }
    return [super shouldExposeView:view];
}
@end
#endif
```

With `use_frameworks!`, both `#import "stub.h"` and `#import <peregrine_stub/stub.h>` work.

Swift: add `#import "stub.h"` to the bridging header (preferably inside `#if DEBUG`). The subclass needs `@objc(Name)` so the stub can find it by name:

```swift
#if DEBUG
@objc(MyStub)
final class MyStub: PGStub {
    override func shouldExposeView(_ view: UIView) -> Bool {
        if view.accessibilityIdentifier == "debug-panel" { return false }
        return super.shouldExposeView(view)
    }
}
#endif
```

Tell the stub which subclass to use, one of:

- Add `PGStubClass` to the app's Info.plist, value `MyStub`.
- Pass `PEREGRINE_LAUNCHENV=PGStubClass=MyStub` when starting exploration. If both are set, this one wins.

If the name is wrong or the class is not a `PGStub` subclass, the app console prints `peregrine stub class MyStub is not a PGStub subclass, using PGStub`. The stub falls back to the default rules and exploration continues.

## 3. Without CocoaPods

This repository's `Peregrine.xcworkspace` has a `peregrine_stub` scheme. The product is `peregrine_stub.framework` with GCDWebServer already linked. The test app in section 6 uses this path:

1. In this repository's `Peregrine/` directory run `pod install`, open `Peregrine.xcworkspace` in Xcode, and select the `peregrine_stub` scheme. For a physical phone, destination Any iOS Device; for a Simulator, build again against that Simulator. The two slices cannot be mixed.
2. Add the built `peregrine_stub.framework` to the app target, Embed & Sign under General > Frameworks, Libraries, and Embedded Content.
3. In this path the framework is embedded in every configuration. Remove it before a store build, or give the test build its own target.

## 4. How the port is matched

The app under test opens the server only when its own process environment has `stubPort` greater than 0, including Debug builds. Peregrine sets that variable when it launches the app:

- When `PEREGRINE_DATAPORT` is greater than 0 and `PEREGRINE_LAUNCHENV` does not already contain `stubPort`, Peregrine adds the same port. Setting `PEREGRINE_DATAPORT` is enough.
- Two seconds after `UIApplicationDidFinishLaunchingNotification`, the stub listens on `127.0.0.1:<port>` and accepts only local connections.
- After launch, Peregrine probes that port every 0.4 seconds for 8 seconds. One success uses the stub tree; otherwise the run falls back to `PEREGRINE_UI_SOURCE`.
- After a successful probe it sends `app_info` and checks the responder's Bundle ID. The stub keeps listening after the app goes to the background, so another stubbed app left in the background can answer on the same port. If the Bundle ID does not match, the log is `stub port <port> belongs to <Bundle ID>, not <app under test>; stub not used` and the run does not use the stub.

The Runner and the app under test are on the same target. The address is the target's own `127.0.0.1`. It does not go over Wi-Fi. A Mac port forward is only for a physical-phone host preflight; a Simulator cannot be probed with `iproxy`.

While the run is in progress, `PGStubWatch` watches the stub:

- The first empty tree in a stretch is re-probed within 4 seconds. After an app restart the stub needs 2 seconds before it listens again; this wait covers that. A successful probe fetches the tree immediately.
- After 5 empty trees in a row it probes once more. Success means the page is actually empty and the stub stays in use; failure logs `stub lost on port <port>` and the rest of the run uses `PEREGRINE_UI_SOURCE`.

Each tree fetch waits at most 4 seconds; a timeout counts as an empty tree.

## 5. Common problems

| Symptom                                                                       | Cause and fix                                                                                                                                                                                                                                                                                                                                                                                                                                               |
|-------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Self-check prints `stub failed port 9797`, or the run log is `alive 0`        | Check in order: the target has the Debug build (or the configuration listed in `:configurations`), and on a Simulator it must be an `iphonesimulator` slice; the app target's Other Linker Flags include `$(inherited)`; the port is free (the Xcode check in step 3 prints `start peregrine stub listen failed` if it is not); a cold start did not take more than 6 seconds (the stub listens 2 seconds after launch, and the probe waits only 8 seconds) |
| Why Other Linker Flags must include `$(inherited)`                            | The stub starts from `+load`. CocoaPods adds `-ObjC` through `$(inherited)` so the linker keeps `PGStub` even when nothing references it directly. A hard-coded flag without `$(inherited)` drops the stub: the build succeeds, but nothing listens on the port                                                                                                                                                                                             |
| Release build: `Undefined symbols ... _OBJC_CLASS_$_PGStub`                   | The subclass is not wrapped in `#if DEBUG`; see section 2                                                                                                                                                                                                                                                                                                                                                                                                   |
| Build: `SDK does not contain 'libarclite'`                                    | The Podfile is missing the `post_install` from step 1                                                                                                                                                                                                                                                                                                                                                                                                       |
| GCDWebServer is still in the Release build                                    | The Podfile omitted `pod 'GCDWebServer', :configurations => ['Debug']`                                                                                                                                                                                                                                                                                                                                                                                      |
| The app has no stub, but a data port was filled in                            | The pre-run check reports `stub check none`, the port is not passed, and the run uses screenshots without waiting 8 seconds for a probe timeout                                                                                                                                                                                                                                                                                                             |
| The message ends with "already closed the previous owner of this port …"      | Another stubbed app still in the background held the port. The pre-run check ended that process; this run continues                                                                                                                                                                                                                                                                                                                                         |
| First log line is `stub check other`, or the Runner logs `belongs to … not …` | The port is taken and could not be closed automatically: the owner is a legacy stub that cannot report a Bundle ID, or ending the process failed (the reason is in the message). Close other stubbed apps on the target, or give the app under test another port                                                                                                                                                                                            |
| First log line is `stub check legacy`                                         | The stub in the app predates `app_info`. It works, but ownership cannot be checked. `pod install` again and rebuild the Debug package to upgrade                                                                                                                                                                                                                                                                                                            |
| Does opening the app from the Home Screen start the server?                   | No. Only a Peregrine launch passes `stubPort`                                                                                                                                                                                                                                                                                                                                                                                                               |
| A button is in the tree but is never tapped                                   | Under section 7 it may be marked not clickable: disabled, an ancestor has interaction off, off-screen, or fully covered by a view above it                                                                                                                                                                                                                                                                                                                  |
| The subclass did not take effect                                              | Check the app console for `is not a PGStub subclass`. A Swift subclass needs `@objc(Name)`                                                                                                                                                                                                                                                                                                                                                                  |

## 6. Validation records

### Physical phone

On 2026-10-21, on an iPhone 15 Pro Max (iOS 18.6.2), a test app was used. Its home screen has navigation into a detail page, a `pageSheet`, a disabled button, a button hidden in a hidden view, a button hidden in a view with interaction off, a card with a tap gesture, and a 300-point-tall list with 140-point row spacing. A `PGStub` subclass hides that card. Direct tree fetches were forwarded to the Mac with `iproxy 9797:9797`.

| Check                                                                  | Result                                                                                                                                                                                       |
|------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Launch without `stubPort`                                              | Nothing listens on the port                                                                                                                                                                  |
| Unknown method                                                         | Returns `-32601`                                                                                                                                                                             |
| Home tree, `PGStubClass` points at the subclass                        | The hidden button and the card are absent; the interaction-off button is in the tree but not clickable; the list keeps only the first two visible rows; page name `SDHome`                   |
| Tree after presenting a `pageSheet`                                    | Page name `SDSheet`; the sheet buttons are clickable; home buttons and list rows underneath are not                                                                                          |
| Peregrine, 2 minutes                                                   | Passed. All 69 steps used the stub tree; reached `SDHome`, `SDSheet`, `SDDetail`; 31 taps hit elements directly; the app was restarted 7 times, each time reattached by the empty-tree probe |
| Mid-run, restart the app so the stub no longer starts                  | Passed. After 4 empty trees: `stub lost on port 9797`, then screenshot and snapshot correction; the subclass-hidden card was never tapped while the stub was in use                          |
| Section 1 CocoaPods integration (static library and `use_frameworks!`) | Debug contains `PGStub` and GCDWebServer; Release contains neither. After installing the Debug build, `testPingNetwork` prints `stub success port 9797`                                      |
| Section 3 framework integration                                        | `testPingNetwork` prints `stub success port 9797`                                                                                                                                            |
| Section 2 Swift subclass, `use_frameworks!`                            | Debug and Release both compile. With `PGStubClass=MyStub` the card is absent; without `@objc(Name)` it prints `is not a PGStub subclass, using PGStub` and the card stays in the tree        |
| Request without `Content-Type: application/json`, or a non-JSON body   | Returns a normal result or `-32601`; the app does not crash                                                                                                                                  |
| `cli.py stub` against the test app                                     | `ok`, about 5 seconds                                                                                                                                                                        |
| Test app left in the background on 9797, then probe Excel (no stub)    | Ends the test-app process, result `none`, message notes the test app was closed, about 11 seconds                                                                                            |
| Probe Excel after restarting the test app without a port               | `none`                                                                                                                                                                                       |
| Excel, port 9797, 1 minute                                             | First line `stub check none`; the Runner never received the port; `alive 0 ... ui combined`; the test passed                                                                                 |
| Test app, port 9797, 1 minute                                          | First line `stub check success`; the Runner logs `stub app_info success`; `ui stub` for the whole run; the test passed                                                                       |

The same day, Notes (no stub) ran with the `combined` source: 59 steps, 11 taps hit elements directly. The test app is not in this repository.

### Simulator

On 2026-10-22, on iPhone 17 (iOS 26.5) and iPhone 13 (iOS 15.2) Simulators, a StubDemo outside this repository (`iphonesimulator` slice) was used: about one minute of exploration stayed on `ui stub` and reached `SDHome`, `SDDetail`, and `SDSheet`; the communication check passed; the host printed `stub check skipped`, `perf host skipped`, and `crash collect skipped`; `--perf` still passed `PEREGRINE_PERF=1` to the Runner and stub-side samples were written. A device-slice stub framework installed on a Simulator exits immediately.

## 7. Protocol

`PGStubClient` sends JSON-RPC 2.0 to `http://127.0.0.1:<port>/`, with `id` always 0:

```json
{"jsonrpc": "2.0", "id": 0, "method": "<method>", "params": {}}
```

The stub does not check `Content-Type`. A body that is not a JSON object is treated as an unknown method and returns `-32601`. `PGStubClient` treats a response shorter than 10 bytes or without `result` as failure.

| Method         | Stub behavior                                                                                                                                                                                                                                                                                                                                                                                              | Who uses it                                                |
|----------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------|
| `kill_process` | Does not enter the main thread; returns `result: true`; the process does not exit                                                                                                                                                                                                                                                                                                                          | `PGStubWatch` probe                                        |
| `app_info`     | Does not enter the main thread; `result` is `{"bundle_id", "name", "version"}` from the host app's `Info.plist`                                                                                                                                                                                                                                                                                            | `PGStubWatch` and the launch page, to check port ownership |
| `app_perf`     | Does not enter the main thread; `result` is `{"footprint_bytes", "cpu_percent", "threads", "main_max_ms", "main_slow", "memory_warnings", "thermal_state"}`. Field meanings are in the handbook section "Stub-side sampling". With `stubPerf=1` in the launch environment, main-thread watching starts with the app; otherwise it starts on the first request; it stops after 10 seconds without a request | `PGPerfSampler`, once per step when `PEREGRINE_PERF` is on |
| `get_ui_tree`  | Builds the tree on the main thread, serializes in the background; `result` is an array of `elem_info` trees. Concurrent requests while the main thread is busy share one build. An exception while building returns an empty array                                                                                                                                                                         | `PGStepScreen`, every step                                 |

Any other method name returns `{"error":{"code":-32601,"message":"method not found"}}`.

A `get_ui_tree` node is `{ "elem_info": {...}, "children": [...] }`. `elem_info` has `type` (view class name), `rect` (`left`, `top`, `width`, `height`, screen coordinates, rounded), `identifier`, `label`, `value`, `visible`, `interactive`, `scrollable`, `clickable`, and `controller` when the view belongs to a view controller.

Hidden or transparent views are omitted with their subtree. `rect` is the visible part clipped to the screen and to `clipsToBounds` ancestors; a clip that is empty sets `visible` to false, and a `clipsToBounds` view that clips to empty drops the whole subtree.

`clickable` marks enabled `UIControl`s, views with button or link accessibility traits, table/collection rows, and views that have their own tap gesture. Disabled controls, views off-screen, and views whose ancestor has `userInteractionEnabled` off are not marked. A parent is not clickable just because a child is. System windows such as the keyboard and the cursor are omitted.

Later siblings are drawn on top. If a later sibling (or a descendant within two levels) is visible, can receive touches, has an opaque background or a class name containing `Dimming`, and fully covers a view on screen, the covered view and its subtree are not marked `clickable`. So when a `pageSheet` is presented, buttons on the page underneath stay in the tree but are not clickable.

The page name uses the content controller (for example `Form`) and skips navigation and keyboard controllers. When one level has several branches, search starts from the last (topmost), so a presented page names itself.

The Runner hashes the whole tree structure as the step's screen fingerprint. Paywall, ad, and image-zoom gates and exploration scoring use it to decide whether the screen changed; gates and element matching flatten the tree first.

Empty-tree counting is in `PGActionCycle`: a returned tree string shorter than 20 counts once; more than 50 in a row sends `RESTART`.

## 8. Limits

- The stub only reads the view tree. Taps, long presses, and typing go through `PGOperatePlayer` on the `XCUIElement` when the node matches a `hittable` element and the two rectangles overlap by at least half. Misses, covered elements, element-action errors, swipes, and back still use coordinate gestures. `typeText` is not called when the keyboard has no focus. A single failed gesture synthesis is caught by `PGOperatePlayer` and the run continues.
- The server binds to the target's `127.0.0.1`, with no authentication and no encryption. Ship it only in test or debug builds, never in a store build. Access from a Mac to a physical phone needs a port forward first (for example `iproxy 9797:9797`, then request `http://127.0.0.1:9797/`). Peregrine itself runs on the target and does not need a forward; a Simulator also cannot be preflighted with `iproxy`.
- `wifi_denied` does not affect this path, because it does not use Wi-Fi.
