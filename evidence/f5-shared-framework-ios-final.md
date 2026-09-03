# F5 Shared Framework iOS Final Regression

## 结论

iOS 侧通过最终回归。目标 RPK 的 Shared Framework、App/Page VM、首屏挂载、点击事件、Detail push/back 和 teardown 均可运行；未出现 `require outside module evaluation`。

## 输入校验

- 源 RPK：`/Users/qy/code/my-github/quickapp-kit-ai/quickapp-examples/showcases/inspection-board/dist/gallery-001.rpk`
- 源 SHA-256：`e35b477b237dd846e2a419b8ee7d02e3b9a2b9cac1348ee1e70fa50480c9b52c`
- Bundle RPK：`gallery-001.rpk`
- Bundle SHA-256：`e35b477b237dd846e2a419b8ee7d02e3b9a2b9cac1348ee1e70fa50480c9b52c`
- RPK 内容：`app.js`、`framework/_quickapp-kit_framework-v1.js`、Home/Detail `index.js`、`quickapp-kit/runtime.json`

## 构建与启动

```text
cmake --build /Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios/build-ios-ninja --target quickapp_ios_simulator -j 4
xcrun simctl install booted /Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios/build-ios-ninja/quickapp_ios_simulator.app
SIMCTL_CHILD_QUICKAPP_RPK=gallery-001 xcrun simctl launch --terminate-running-process booted dev.quickappkit.ios.simulator
```

- Build：通过；仅有既有编译警告。
- Install：通过。
- Launch：通过，进程保持运行。
- UIKit surface：`402x778`。

## UIKit 运行证据

```text
ios.a1.runtime.started rpk=.../quickapp_ios_simulator.app/gallery-001.rpk
ios.ui.surface.created surface=srf:1 frame=<0.0,0.0,402.0,778.0>
ios.ui.button.created surface=srf:1 node=node:4
ios.ui.button.created surface=srf:1 node=node:14
ios.ui.button.created surface=srf:1 node=node:19
ios.ui.button.created surface=srf:1 node=node:24
ios.ui.button.layout surface=srf:1 node=node:14 frame=<100.0,24.0,88.0,26.0> text=查看详情 enabled=1
ios.ui.mount.result surface=srf:1 revision=0 operations=132 mounted=1
ios.runtime.started surface=srf:1
ios.ui.surface.present target=srf:1 hidden=0 subviews=1
```

首屏真实挂载了标题、刷新按钮、图片资源、三条列表项和三个详情按钮；按钮均完成 UIKit 创建、布局和启用。

## Core/JS 主链回归

命令：

```text
./build-debug-host/quickapp_ios_spine_probe .../inspection-board/dist/gallery-001.rpk node:14 click '' '' '' node:6
```

同一真实 RPK 连续执行 3 次，结果每次一致：

```text
ios.probe.first surfaces=1 nodes=24 handlers=4 jsResources=3
ios.event.click.dispatched surface=srf:1 node=node:14 accepted=1
ios.js.event.executed surface=srf:1 handler=hdl:srf:1-2-blk:srf:1-2-pumpA accepted=1
ios.probe.after_click surfaces=2 nodes=30 handlers=5 jsResources=5
ios.event.click.dispatched surface=srf:2 node=node:6 accepted=1
ios.navigation.close request=req:j-100002 source=srf:2
ios.platform.close.result completed=1 request=req:j-100002
ios.probe.after_back surfaces=1 nodes=30 handlers=4 jsResources=3
ios.probe.runtime.stopped surfaces=0 nodes=0 handlers=0 pendingCallbacks=0 jsResources=0 coreQueue=0
```

## 变更范围

- 仅更新 iOS 测试探针，使返回节点可显式传入：`src/ios_spine_probe.cpp`。
- 新增本文件作为 iOS 最终回归证据。
- 未修改 Core、JS Runtime、Toolkit、公共 Contract、RPK、Router、Runtime Tree、Bridge 或其他平台。

## 剩余问题

无阻塞问题。探针旧默认返回节点不适用于 Gallery 的 Detail 页面；本次仅通过测试参数指定真实返回按钮 `node:6`，不改变 Runtime 语义。
