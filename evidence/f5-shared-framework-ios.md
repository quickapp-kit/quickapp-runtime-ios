# F5 iOS Shared Framework 回归

## 结论

F5 未通过。目标 `gallery-001.rpk` 已正确注入 iOS Host，RPK 内容和 Shared Framework 引用均正确；Host 创建 Runtime 后进入 Core loop，但没有完成页面 VM 初始化、RenderTransaction、Event 或首屏 Mount。该问题超出本次仅允许修改 Host RPK 注入、测试和证据文件的范围，未修改公共 Runtime。

## 输入校验

源文件：`/Users/qy/code/my-github/quickapp-kit-ai/quickapp-examples/showcases/gallery-001/dist/gallery-001.rpk`

源 RPK SHA-256：`9ad56f1006804f4eadd41d021dd4ae20f61b0bdf4e6b8b051ab10eb4bae33884`

Simulator Host Bundle：`/Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios/build-host-app/Build/Products/Debug-iphonesimulator/QuickAppKitHost.app/gallery-001.rpk`

Bundle RPK SHA-256：`9ad56f1006804f4eadd41d021dd4ae20f61b0bdf4e6b8b051ab10eb4bae33884`

RPK 内容已验证：

- `framework/_quickapp-kit_framework-v1.js` 存在；
- `pages/pages/Home/index.js` 声明依赖 `@quickapp-kit/framework-v1`；
- Home 页面通过 `$app_require$("@quickapp-kit/framework-v1").default.createReactivePageVm(...)` 创建页面 VM；
- Detail 页面同样声明并加载 Shared Framework。

## 构建与启动

构建命令：

```sh
xcodebuild -project QuickAppRuntimeIOS/QuickAppRuntimeIOS.xcodeproj \
  -scheme QuickAppRuntimeIOS -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build-host-app CODE_SIGNING_ALLOWED=NO build
```

结果：`BUILD SUCCEEDED`。

安装并启动命令：

```sh
xcrun simctl install booted \
  /Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios/build-host-app/Build/Products/Debug-iphonesimulator/QuickAppKitHost.app
SIMCTL_CHILD_QUICKAPP_RPK=gallery-001 \
  xcrun simctl launch --terminate-running-process \
  booted dev.quickappkit.host
```

启动结果：首次目标包启动 `dev.quickappkit.host: 80207`；最终保持现场启动 `dev.quickappkit.host: 80276`。

截图：`/tmp/f5-ios-host-gallery-final.png`

## 运行证据

Host 关键日志：

```text
ios.ui.surface.created surface=srf:1 frame=<0.0,0.0,402.0,737.7>
```

未观察到以下预期事件：

- `ios.runtime.started`；
- Shared Framework module loaded；
- app/page VM initialized；
- `RenderTransaction`；
- Event Handler；
- Navigation push/back；
- UIKit button/image mount；
- teardown resource-zero result。

进程采样显示 Host 的 `RuntimeSpine::Impl::run` 已进入循环，JS executor 线程处于等待状态；因此现场不是 Host 桌面选择失败，也不是 RPK 路径或 Bundle 哈希错误。

## 验收结果

| 项目 | 结果 |
|---|---|
| Home 首屏 | 未通过，Host 停在加载状态 |
| 状态更新 / RenderTransaction | 未执行 |
| 真实 Button 点击 | 未执行 |
| Detail push/back | 未执行 |
| 三次重复进入返回 | 未执行 |
| Image 资源 | 未进入 Mount，未执行 |
| Runtime teardown 资源归零 | 未执行 |

## 对照说明

旧的直接 iOS Simulator 中存在 `gallery-001.rpk`，但其哈希为 `3f4e75176f05a38373e9a28781d5a5d217724785aad139740f2e26d785f0e10b`，且不包含 `framework/_quickapp-kit_framework-v1.js`。它不是本次 F5 输入，不能证明 Shared Framework 回归通过。

当前可运行的 `shop.rpk` 结构与目标包不同：其 `quickapp-kit/runtime.json` 的 `sharedModules` 为空，Home/Page 模块依赖列表为空；目标 `gallery-001.rpk` 的 `sharedModules` 包含 `@quickapp-kit/framework-v1`，且 Home/Detail 页面均通过 `$app_require$` 加载该模块。因而 `shop` 在 iOS Host 可运行，只能证明无 Shared Framework 的页面链路正常，不能覆盖本次 F5。

## 修改范围

- Host RPK 注入：`QuickAppRuntimeIOS/QuickAppRuntimeIOS/ContentView.swift`；
- 本证据文件：`evidence/f5-shared-framework-ios.md`。

未修改 Core、JS Runtime、Toolkit、公共 Contract、RPK、Router、Runtime Tree、Bridge 或其他平台。

## 剩余阻塞

需要在后续允许修改 Shared Framework Runtime 集成或 JS/公共层后，定位目标包在 SDK Host 路径中未完成页面 VM/首屏 Mount 的原因；本轮按边界停止。

## 重打包复验（2026-09-03）

### 结论

重新构建 Toolkit 并生成新的 `gallery-001.rpk` 后，产物为确定性同包，SHA-256 仍为 `9ad56f1006804f4eadd41d021dd4ae20f61b0bdf4e6b8b051ab10eb4bae33884`。将该包重新注入、构建、安装并启动 iOS Host 后，现象不变：页面停留在“正在加载 gallery-001”，只创建了 Surface，没有进入 JS Framework 加载、页面 VM 初始化或首屏 Mount。因此本次复验不支持“旧 RPK 文件损坏”这一假设，阻塞仍位于 iOS Host/Runtime 的 Shared Framework 执行链路。

### 重建命令

```sh
cd /Users/qy/code/my-github/quickapp-kit-ai/quickapp-toolkit
npm run build
cd /Users/qy/code/my-github/quickapp-kit-ai/quickapp-examples
node showcases/gallery-001/scripts/build-gallery.mjs
```

构建结果：`PASS`，`deterministicBuild=true`，包大小 `48523` bytes。

### 新包校验

源包：`/Users/qy/code/my-github/quickapp-kit-ai/quickapp-examples/showcases/gallery-001/dist/gallery-001.rpk`

源包 SHA-256：`9ad56f1006804f4eadd41d021dd4ae20f61b0bdf4e6b8b051ab10eb4bae33884`

Shared Framework SHA-256：`b53464aa786d024cd0938015caf11171ea7f3dcfa8e16f2f0f0a9d5a9e26e1af`

RPK 仍包含 `framework/_quickapp-kit_framework-v1.js`；`quickapp-kit/runtime.json` 仍声明 `sharedModules`；Home/Detail 页面仍通过 `$app_require$` 加载 `@quickapp-kit/framework-v1`。

### iOS 重新验证

Host 构建命令：

```sh
cd /Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios
xcodebuild -project QuickAppRuntimeIOS/QuickAppRuntimeIOS.xcodeproj \
  -scheme QuickAppRuntimeIOS -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build-host-app CODE_SIGNING_ALLOWED=NO build
```

结果：`BUILD SUCCEEDED`。

安装并启动：

```sh
xcrun simctl install booted \
  /Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios/build-host-app/Build/Products/Debug-iphonesimulator/QuickAppKitHost.app
SIMCTL_CHILD_QUICKAPP_RPK=gallery-001 \
  xcrun simctl launch --terminate-running-process \
  booted dev.quickappkit.host
```

Bundle 中的 `gallery-001.rpk` SHA-256 与源包一致：`9ad56f1006804f4eadd41d021dd4ae20f61b0bdf4e6b8b051ab10eb4bae33884`。

截图：`/tmp/quickapp-gallery-rebuilt-ios.png`

日志：`/tmp/quickapp-gallery-rebuilt-ios.log`

关键运行日志：

```text
ios.ui.surface.created surface=srf:1 frame=<0.0,0.0,402.0,737.7>
```

未观察到 `ios.runtime.started`、Shared Framework module loaded、页面 VM 初始化、`RenderTransaction`、UIKit Mount 或事件日志。Host 画面停留在“正在加载 gallery-001”。

### 复验结果

| 项目 | 结果 |
|---|---|
| Toolkit 重建 | 通过 |
| RPK 生成与结构校验 | 通过 |
| RPK 源包/Bundle 哈希一致 | 通过 |
| iOS Host 构建安装 | 通过 |
| iOS Gallery 首屏加载 | 未通过，仍停在加载状态 |
| 交互、路由、teardown | 未执行 |

此前 F5 宿主复验未修改 Core、JS Runtime、Toolkit、公共 Contract、RPK 或 iOS Runtime 代码；本次定位仅在 iOS Runtime 增加失败日志。

### 根因定位（2026-09-03）

使用当前 iOS Spine Probe 复现同一真实 RPK，模块加载结果为：

```text
ios.js.module id=@quickapp-kit/app kind=app status=loaded error=
ios.js.module id=@quickapp-kit/framework-v1 kind=shared status=loaded error=
ios.js.module id=@quickapp-kit/page/pages/Home kind=page status=loaded error=
```

随后页面 VM 在 `onInit` 失败：

```text
scope=page phase=onInit code=JS_EXCEPTION
message=require outside module evaluation
```

结论：RPK 校验、shared module 加载和页面模块加载均已通过；失败发生在 Core JS ModuleLoader 创建页面 VM 时，页面 `createPageVm` 内通过 `$app_require$` 加载已声明的 shared framework。当前 ModuleLoader 只允许在 module factory evaluation 期间执行 `$app_require$`，因此拒绝该合法页面 VM 初始化路径。该缺口属于公共 Core/JS Runtime 契约，不能通过 iOS 平台旁路修复；iOS 仅增加了失败日志以完成定位，未改变渲染、路由或 RPK 语义。
