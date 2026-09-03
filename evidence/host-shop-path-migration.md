# iOS Host Shop Path-Migration Acceptance

## 结论

SwiftUI `QuickAppKitHost` 已使用迁移后的当前 XCFramework 成功加载真实 `shop.rpk`。此前 `Runtime package metadata missing` 的根因是 Host 链接了旧的 `dist/QuickAppKit.xcframework`，不是 RPK 缺少 metadata，也不是 Host 的页面路径问题。

## 输入与结构

- RPK：`/Users/qy/code/my-github/quickapp-kit-ai/quickapp-examples/showcases/shop/dist/shop.rpk`
- RPK SHA-256：`f4a21abc7480a1d96134c4f7fdaf5a4f45ae745ad26457b689ebf7b9fd67d719`
- Host Bundle：`/Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios/build/host-derived/Build/Products/Debug-iphonesimulator/QuickAppKitHost.app/shop.rpk`
- Host Bundle SHA-256：`f4a21abc7480a1d96134c4f7fdaf5a4f45ae745ad26457b689ebf7b9fd67d719`
- RPK 已包含：`META-INF/runtime.json`、`pages/`、`shared/`、`assets/`

## 构建与启动

```text
./tools/build-quickappkit-xcframework.sh
xcodebuild -project QuickAppRuntimeIOS/QuickAppRuntimeIOS.xcodeproj -scheme QuickAppRuntimeIOS -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,id=B112B88F-C165-4460-BB00-083BFBB24BA0' -derivedDataPath build/host-derived build
xcrun simctl install booted build/host-derived/Build/Products/Debug-iphonesimulator/QuickAppKitHost.app
SIMCTL_CHILD_QUICKAPP_RPK=shop xcrun simctl launch --terminate-running-process booted dev.quickappkit.host
```

- XCFramework 重建：通过。
- SwiftUI Host 构建：`BUILD SUCCEEDED`。
- Host Bundle ID：`dev.quickappkit.host`。
- Host 启动：通过，进程 `QuickAppKitHost` 正常运行。

## 真实 Host 日志

```text
ios.ui.surface.created surface=srf:1 frame=<0.0,0.0,402.0,737.7>
ios.ui.scroll.created surface=srf:1 node=node:5
ios.ui.tabs.created surface=srf:1 node=node:9
ios.ui.tabs.state surface=srf:1 selected=0 items=4
ios.ui.scroll.layout surface=srf:1 node=node:5 frame=<12.0,152.0,366.0,576.0>
ios.ui.tabs.layout surface=srf:1 node=node:9 frame=<12.0,786.0,366.0,48.0>
ios.ui.mount.result surface=srf:1 revision=0 operations=826 mounted=1
ios.runtime.started surface=srf:1
ios.ui.surface.present target=srf:1 hidden=0 subviews=1
```

首屏由 Host 真实加载，包含图片列表、滚动容器、20 个商品详情按钮和四项 Tabs；所有 UIKit 控件由 Runtime Mount 创建。

## 边界与剩余动作

- Host 负责 RPK 选择、Surface 承载和 Runtime 生命周期；页面栈、状态、事件和路由仍由 Runtime/Core 管理。
- 本次没有修改 Core、JS、Toolkit、公共 Contract、RPK、Router 或 Runtime 语义。
- Host 的直接启动已通过；详情 push/back、重复进入和退出后的资源归零需在 Simulator 中由用户点击验证，Host 不提供自动业务操作入口。
- C++ `quickapp_ios_simulator` 不是本次用户体验入口。
