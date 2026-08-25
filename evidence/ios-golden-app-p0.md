# iOS Golden App P0 Evidence

## Scope

This evidence covers the iOS platform adapter only. Core, JS Framework,
Toolkit, and the shared RPK are treated as read-only inputs.

## Input

RPK:

```text
/Users/qy/code/my-github/quickapp-kit-ai/quickapp-toolkit/evidence/tk-s12-lvgl-p0.rpk
```

SHA-256:

```text
25977ea6d92ed571ed6d019c3b0dc0b3ee5f1576acdf1ac3ee98fa68244ed74b
```

## Build

Host C++ spine:

```text
cmake -S . -B build-host -G Ninja -DQUICKAPP_CORE_BUILD_TESTS=OFF -DQUICKAPP_JS_BUILD_TESTS=OFF
cmake --build build-host -j 4
```

Result: passed.

iOS Simulator UIKit bundle:

```text
./tools/build-ios-simulator.sh
```

Result: `quickapp_ios_simulator.app` compiled successfully with the UIKit
Gateway and the TK-S12 RPK embedded as a bundle resource.

## Host Runtime Probe

```text
./build-host/quickapp_ios_spine_probe \
  /Users/qy/code/my-github/quickapp-kit-ai/quickapp-toolkit/evidence/tk-s12-lvgl-p0.rpk
```

Result:

```text
ios.probe.first surfaces=1 nodes=5 handlers=2 jsResources=3
ios.probe.after_click surfaces=2 nodes=9 handlers=3 jsResources=5
ios.probe.after_back surfaces=1 nodes=9 handlers=2 jsResources=3
ios.probe.runtime.stopped surfaces=0 nodes=0 handlers=0 pendingCallbacks=0 jsResources=0 coreQueue=0
```

This verifies:

```text
RPK load
-> Home mount
-> Detail push
-> NavigationClose / router.back()
-> Home reveal
-> teardown
```

## Boundary Changes

- iOS Gateway maps View/Text/Button and supported host properties to UIKit.
- UIKit input dispatches through the existing Core Event Router.
- iOS Runtime Spine handles typed NavigationPush and NavigationClose messages.
- iOS Gateway implements the existing Core Feature Provider port for prompt,
  device, title, and meta requests; unsupported methods return typed
  `unsupported` results.
- Incremental MoveHost and RemoveHost use the existing Core operation shapes.
- No Core, JS Framework, Toolkit, Examples, Android, or LVGL files were modified.

Feature wiring is compile-verified in the UIKit target. Direct visual Feature
invocation remains pending Simulator service availability; the current shared
TK-S12 RPK does not exercise those APIs during its Home/Detail regression.

## UIKit Detail Back Regression

Root cause classification: **A**. The defect was at the UIKit interaction
boundary. The iOS adapter now explicitly enables the surface and UIButton,
keeps the button target attached to the real mounted node, and emits
structured creation/layout/input diagnostics. Core Router and JS ABI were not
changed.

Host regression:

```text
ios.event.click.queued surface=srf:1 node=node:5 accepted=1
ios.event.click.dispatched surface=srf:1 node=node:5 accepted=1
ios.event.click.queued surface=srf:2 node=node:4 accepted=1
ios.event.click.dispatched surface=srf:2 node=node:4 accepted=1
ios.navigation.close request=req:j-100002 source=srf:2
ios.platform.close.result completed=1 request=req:j-100002
ios.probe.first surfaces=1 nodes=5 handlers=2 jsResources=3
ios.probe.after_click surfaces=2 nodes=9 handlers=3 jsResources=5
ios.probe.after_back surfaces=1 nodes=9 handlers=2 jsResources=3
ios.probe.runtime.stopped surfaces=0 nodes=0 handlers=0 pendingCallbacks=0 jsResources=0
```

Real UIKit Simulator result: the mounted Detail button exposed as
`返回 Home`, a real Simulator UI click returned the accessibility tree to
Home, and the Bundle was rebuilt with the following embedded RPK hash:

```text
25977ea6d92ed571ed6d019c3b0dc0b3ee5f1576acdf1ac3ee98fa68244ed74b
```

## Swift Tests

```text
swift test
```

Result: `19 tests, 0 failures`.

## Remaining Environment Limitation

The UIKit Simulator bundle compiles successfully, but `xcrun simctl` cannot
connect to `CoreSimulatorService` in the current environment. Visual Simulator
launch and screenshot verification remain pending an available Simulator
service. This is an environment limitation, not an iOS source or bundle build
failure.
