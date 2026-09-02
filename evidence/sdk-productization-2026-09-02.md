# QuickApp Kit iOS SDK Productization Evidence

## 目录

- [1. 结论](#1-结论)
- [2. 已验证](#2-已验证)
- [3. 未完成验收](#3-未完成验收)
- [4. 边界与风险](#4-边界与风险)

## 1. 结论

`QuickAppKit.xcframework` 和最小 `QuickAppKitHost` 已生成并通过编译。XCFramework 不携带 RPK，Host 通过文件选择器把 RPK 作为外部输入交给 SDK。真实 `commerce-001.rpk` 端到端验收本次未完成，因为指定文件不存在，且当前 CoreSimulatorService 无法连接。

## 2. 已验证

### 2.1 XCFramework

构建命令：

```sh
cd /Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios
./tools/build-quickappkit-xcframework.sh
```

产物：

```text
/Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios/dist/QuickAppKit.xcframework
```

包含两个 slice：

- `ios-arm64-simulator/libQuickAppKit.a`，arm64
- `ios-arm64/libQuickAppKit.a`，arm64

公开头文件：`QuickAppKit.h`；模块映射：`module.modulemap`。产物内没有 `.rpk` 文件。

### 2.2 Host

构建命令：

```sh
xcodebuild -project QuickAppRuntimeIOS/QuickAppRuntimeIOS.xcodeproj \
  -scheme QuickAppRuntimeIOS \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build-host-app \
  CODE_SIGNING_ALLOWED=NO build
```

结果：`BUILD SUCCEEDED`。

产物：

```text
/Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios/build-host-app/Build/Products/Debug-iphonesimulator/QuickAppKitHost.app
```

Host 只负责选择本地 RPK、提供 UIKit Surface、展示状态和销毁 Runtime；页面栈、业务状态、Runtime Tree、NodeId 和事件路由不在 Host 中维护。

### 2.3 公共 API

Objective-C API 可由 Swift 直接调用，公开入口对应：

- `createRuntimeWithViewportWidth:height:error:`
- `loadRPKFromURL:completion:`
- `attachSurface:error:`
- `dispatchInput:error:`
- `updateLifecycle:error:`
- `destroyRuntime`

Objective-C++ Gateway 持有 C++ Runtime 的唯一 RAII 所有权；`destroyRuntime` 幂等，并在销毁后拒绝新的输入和加载操作。

## 3. 未完成验收

指定输入：

```text
/Users/qy/code/my-github/quickapp-kit-ai/quickapp-examples/showcases/commerce-001/dist/commerce-001.rpk
```

结果：文件不存在。当前可用 showcase RPK 中没有 `commerce-001`，因此无法记录该 RPK 的 SHA-256，也不能用其他案例替代正式验收。

尝试执行 `xcrun simctl list runtimes` 和 `xcrun simctl list devices available`，均因 `CoreSimulatorService connection refused` 失败；本次没有安装、启动或截图，也没有伪造 UIKit 交互结果。

因此以下项目保持待验收：

- commerce 首屏 Image/Text/Button/List/Scroll/Tabs/if；
- 商品详情 push/back 和重复加载；
- 真实 Simulator 交互截图；
- 运行时 teardown 资源归零。

## 4. 边界与风险

- 本次修改仅在 `quickapp-runtime-ios`；未修改 Core、JS、Toolkit、公共 Contract、RPK、Examples 或其他平台。
- XCFramework 当前以静态库 slice 交付，宿主需要链接 UIKit、Foundation、AVFoundation、AVKit、CoreMedia 和 libc++。
- `updateLifecycle` 已暴露为稳定入口；当前底层 Runtime 没有可调用的前后台生命周期实现，对该信号返回 typed `unsupported`，未伪造成功。
- 真实 commerce RPK 补齐且 CoreSimulatorService 恢复后，需要重新构建/安装 Host，完成端到端验收并补充截图与资源计数。

状态：`SDK_BUILD_READY_COMMERCE_ACCEPTANCE_BLOCKED`。
