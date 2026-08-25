# iOS B3: List + Scroll

结论：iOS 已完成真实 `list-001.rpk` 的 List/Scroll 平台实现；Core Runtime Tree、keyed `for`、事件路由和生命周期仍是唯一共享链路。四类滚动事件、首屏 Mount、列表点击 push 和 teardown 均有 Host Probe 证据；该 RPK 本身没有 Detail 页面和 `router.back()`，因此“返回”不在此案例中伪造验收。

## 基线

- RPK: `/Users/qy/code/my-github/quickapp-kit-ai/quickapp-examples/showcases/list-001/dist/list-001.rpk`
- SHA-256: `f9087a6e1a9b0cc9c104a57586b6196636b8a2853d386ab68551fa2c0eb640c2`
- Bundle RPK SHA-256: 同上
- DSL: `Scroll -> List -> keyed for`，4 个任务项，Scroll handlers 为 `scroll`、`scrollend`、`scrolltop`、`scrollbottom`

## iOS 实现

- `kScroll` 映射为 UIKit `UIScrollView`，由 Core MountTransaction 设置 frame，并由子树 frame 计算 `contentSize`。
- `kList` 映射为裁剪的 UIKit `UIView` 容器；不创建平台私有列表状态或第二棵树。
- `scrollViewDidScroll` 发送 `scroll`，顶部/底部状态发生边沿变化时发送对应边界事件。
- `scrollViewDidEndDragging` / `scrollViewDidEndDecelerating` 发送 `scrollend`。
- 事件 payload 统一包含 `scrollOffset`、`contentSize`、`viewportSize`，并经既有 `RuntimeSpine -> Core Event Router -> JS Handler`。
- Surface 销毁时移除 UIKit 子树和 Scroll delegate，资源由既有 Runtime teardown 归零。

## 验收证据

Host Probe 日志位于 `evidence/showcase-logs/`：

- `ios-list-001-scroll-host-probe.log`: `scroll` queued/dispatched，JS handler executed。
- `ios-list-001-scrollend-host-probe.log`: `scrollend` queued/dispatched，JS handler executed。
- `ios-list-001-scrolltop-host-probe.log`: `scrolltop` queued/dispatched，JS handler executed。
- `ios-list-001-scrollbottom-host-probe.log`: `scrollbottom` queued/dispatched，JS handler executed；边界状态更新产生 1 个增量 render transaction。
- 每次 probe 结束均为 `surfaces=0 nodes=0 handlers=0 pendingCallbacks=0 jsResources=0 coreQueue=0`。

首屏真实 iOS Simulator 截图：

- `evidence/screenshots/ios-list-001-home-2026-08-25.png`

首屏确认真实加载了四个 keyed-for 项目和 UIKit Button。Computer Use 的 Simulator 滚动注入在本次环境返回 `noWindowsAvailable`，因此不把手工拖动伪记为通过；滚动事件链由 Host Probe 直接验证。

列表点击和重复进入：

- `ios-list-001-route-host-probe.log`
- `ios-list-001-route-repeat-host-probe.log`
- 点击真实列表 Button `node:25` 后，`srf:1 -> srf:2` push 成功，第二个 Surface 完整 Mount。
- `list-001` 的 `onOpen` 明确是 `router.push({ uri: '/pages/Home' })`，没有 Detail 页面和 `router.back()` handler；因此本案例的返回不是适用项，不能用平台私有 back 冒充。
- 两次重复进入均完成 teardown，最终资源归零。已有 Gallery/Commerce 案例继续承担真实多页 Detail push/back 验收。

## 构建状态

- 本轮 iOS/Host target 重建被共享 `quickapp-runtime-js/src/abi/runtime_abi_codec.cpp` 的已有 `object.contains` 指针编译错误阻断；该文件不属于本平台，本轮未修改。
- iOS B3 代码在该共享错误出现前已完成编译；本轮验证的 RPK Bundle 已包含目标 RPK，SHA-256 与源文件一致。

## 范围边界

本轮只修改 `quickapp-runtime-ios`。未修改 Core、JS、Toolkit、公共 Contract、Examples、第二套路由或第二棵 Tree。
