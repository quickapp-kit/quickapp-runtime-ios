# iOS Host Shop Tabs Visibility

## 结论

已修复 SwiftUI `QuickAppKitHost` 中 Tabs 被布局到屏幕外的问题。根因是 Host 使用固定视口 `390x844`，而真实 Runtime Surface 为 `402x737.7`；Host 顶部栏占用高度后，Tabs 被计算到 `y=786`。现在 Runtime 使用实际 Surface bounds 创建，Tabs 位于可视区域内。

## 输入

- RPK：`/Users/qy/code/my-github/quickapp-kit-ai/quickapp-examples/showcases/shop/dist/shop.rpk`
- SHA-256：`f4a21abc7480a1d96134c4f7fdaf5a4f45ae745ad26457b689ebf7b9fd67d719`
- Host：`dev.quickappkit.host`

## 修改

- 文件：`QuickAppRuntimeIOS/QuickAppRuntimeIOS/ContentView.swift`
- 变化：`createRuntime` 改为使用承载 Runtime 的 `UIView.bounds.width/height`。
- 未修改 Core、JS、Toolkit、公共 Contract、RPK、Router 或 Runtime 语义。

## 构建与启动

```text
xcodebuild -project QuickAppRuntimeIOS/QuickAppRuntimeIOS.xcodeproj -scheme QuickAppRuntimeIOS -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,id=B112B88F-C165-4460-BB00-083BFBB24BA0' -derivedDataPath build/host-derived build
xcrun simctl install booted build/host-derived/Build/Products/Debug-iphonesimulator/QuickAppKitHost.app
SIMCTL_CHILD_QUICKAPP_RPK=shop xcrun simctl launch --terminate-running-process booted dev.quickappkit.host
```

- Build：`BUILD SUCCEEDED`
- Launch：成功
- RPK：真实 Bundle RPK

## 运行证据

```text
ios.ui.surface.created surface=srf:1 frame=<0.0,0.0,402.0,737.7>
ios.ui.scroll.created surface=srf:1 node=node:5
ios.ui.tabs.created surface=srf:1 node=node:9
ios.ui.tabs.state surface=srf:1 selected=0 items=4
ios.ui.scroll.layout surface=srf:1 node=node:5 frame=<12.0,136.0,378.0,501.0>
ios.ui.tabs.layout surface=srf:1 node=node:9 frame=<12.0,680.0,378.0,48.0>
ios.ui.mount.result surface=srf:1 revision=0 operations=826 mounted=1
ios.runtime.started surface=srf:1
ios.ui.surface.present target=srf:1 hidden=0 subviews=1
```

Tabs 的最终底部为 `728`，小于 Surface 高度 `737.7`，因此可见且具备点击区域。

## 验收状态

- Home、图片列表、Scroll、Tabs 首屏挂载：通过。
- Tabs 可视布局：通过。
- 用户手动点击 Tabs、详情 push/back、退出和 teardown：Host 已启动并保持运行，交由用户现场操作。
- 阻塞问题：无。
