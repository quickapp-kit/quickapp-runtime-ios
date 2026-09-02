# iOS Host RPK Gallery Evidence

## 目录

- [1. 结论](#1-结论)
- [2. 构建](#2-构建)
- [3. 边界](#3-边界)
- [4. 限制](#4-限制)

## 1. 结论

`QuickAppKitHost` 已改为桌面式 RPK Gallery。首页只展示应用图标网格和名称；用户点击图标后进入全屏 Runtime 页面，点击“退出应用”销毁当前 Runtime 并返回应用桌面。Host Bundle 自动收集 Toolkit evidence 和 quickapp showcases 下的 RPK。

## 2. 构建

命令：

```sh
cd /Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios
xcodebuild -project QuickAppRuntimeIOS/QuickAppRuntimeIOS.xcodeproj \
  -scheme QuickAppRuntimeIOS \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build-host-app \
  CODE_SIGNING_ALLOWED=NO build
```

结果：`BUILD SUCCEEDED`。

Host App：

```text
/Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios/build-host-app/Build/Products/Debug-iphonesimulator/QuickAppKitHost.app
```

Bundle 内 RPK 数量：`23`。

## 3. 边界

- RPK 桌面、应用名称和选择状态属于 Host Gallery，不属于 Runtime。
- 每次只向一个 Runtime 加载一个 RPK；点击应用先调用 `destroy`，再创建并加载目标 Runtime。
- Core 继续唯一管理当前应用的 Runtime Tree、Navigation、Lifecycle 和事件语义。
- Host 不维护页面栈、业务状态、NodeId、Runtime Tree、第二套路由或旁路 Bridge。
- RPK 仍是 XCFramework 外部输入，未复制进 `QuickAppKit.xcframework`。

## 4. 限制

首次点击应用后停在“正在加载”的根因是 SDK Facade 创建 Gateway/RuntimeSpine 后遗漏既有 `bindGateway`，导致平台 Surface 结果无法回送 Core。已在 `src/quickapp_kit.mm` 补齐绑定，并重新生成 XCFramework、重建 Host。

Simulator 已恢复并完成真实启动验证：

```text
xcrun simctl install booted build-host-app/Build/Products/Debug-iphonesimulator/QuickAppKitHost.app
xcrun simctl launch --terminate-running-process booted dev.quickappkit.host
dev.quickappkit.host: 92156
```

首屏为桌面式 RPK 图标网格；本次未自动点击，应用保持运行，交由用户手动点击图标进入全屏 Runtime。修复版启动进程号：`98194`。

状态：`IOS_HOST_DESKTOP_GALLERY_READY_FOR_MANUAL_APP_LAUNCH`。

## 5. 退出修复

- 根因：Host 主线程调用 Runtime `destroy` 并等待 Core 线程；Core 清理期间 iOS Gateway 又同步回主线程清理 UIKit，形成死锁。
- 修复：iOS Gateway 的 Core 线程清理改为异步投递主线程；Host 的退出动作继续先销毁 Runtime，再返回桌面。未修改 Core、JS、Toolkit 或公共 Contract。
- 同时修复状态文案插值，避免显示字面量 `(app.name)`。
- 修复版已重新生成 XCFramework、重建 Host 并启动，进程号：`99477`。

状态：`IOS_HOST_DESKTOP_GALLERY_EXIT_DEADLOCK_FIXED_READY_FOR_MANUAL_CHECK`。
