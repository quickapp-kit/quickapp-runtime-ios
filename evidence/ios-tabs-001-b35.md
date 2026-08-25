# iOS B3.5 Tabs

结论：iOS Tabs 原生映射已完成并通过编译，但真实 `tabs-001.rpk` 验收被公共 JS 初始绑定合同阻塞；未伪造首屏或交互通过。

## iOS 实现

- `Tabs` 映射为 `UISegmentedControl`。
- `items` 使用现有本地 `|` 分隔格式生成原生 segment。
- `selected` 受控更新只同步 `selectedSegmentIndex`，不触发用户 `change`。
- 用户切换生成 `{ index, value }`，经既有 `dispatchInput -> Core EventRouter -> JS Handler`。
- 重复切换和 Node/Surface teardown 复用既有 UIKit 生命周期；未创建第二棵树、第二套路由或平台业务状态。
- iOS Runtime Composition 声明 `Tabs`，真实 `tabs-001.rpk` 已加入 Simulator Bundle。

## 构建

```text
cmake --build build-ios-ninja --target quickapp_ios_simulator -j 4
通过。
```

RPK：`quickapp-examples/showcases/tabs-001/dist/tabs-001.rpk`

SHA-256：`9a53e285d8d4cf13080b782f64762b6ab44596ad3c3ab68ace08a19340108792`

## 真实启动结果

Simulator 已加载真实 RPK，但页面未进入 Mount：

```text
ios.stage=rpk.verified
ios.stage=page.start.completed
ios.stage=initial.command.js
ios.stage=page.vm.failed
ios.page.vm.error=page VM is unavailable
```

根因来自公共 JS：`AlphaInitialBindingStage::evaluateOnExecutor` 当前只接受初始绑定结果 `string` 或 `boolean`，而 Tabs 的 `selected` binding 返回 `number`。因此页面初始化阶段在进入平台 Mount 前失败。iOS 侧不能修改这个类型或绕过 JS Framework。

对照验证：同一 iOS 构建加载 `media-001.rpk` 可正常进入 `page.vm.ready` 和 Video Mount，说明本次失败不是 iOS Simulator、Bundle 或 Tabs UIKit 编译问题。

## 验收状态

- 首屏：BLOCKED，未 Mount。
- 用户切换 `change({index,value})`：BLOCKED，未到达真实控件。
- 状态回写：BLOCKED，依赖 JS number binding。
- 重复切换：BLOCKED。
- teardown：未作为 Tabs 成功验收声称；运行时可由 Simulator 关闭。

## 放行条件

公共 JS 初始绑定阶段必须按已冻结 Tabs 合同接受 `number`，并保持该数值进入 Core Runtime Tree/RenderTransaction。公共层修复后，重新使用本 RPK 验证 iOS 首屏、切换、状态回写、重复切换和 teardown。

