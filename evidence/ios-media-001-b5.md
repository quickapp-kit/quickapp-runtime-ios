# iOS B5 Video

结论：iOS 已使用 AVPlayer 完成真实 `media-001.rpk` 的首帧、prepared、播放、暂停、seek、失败和 teardown。Video 生命周期事件复用既有 `RuntimeSpine -> Core EventRouter -> JS Handler`；未修改 Core、JS、Toolkit、公共 Contract 或 Examples。

## 基线

- RPK：`/Users/qy/code/my-github/quickapp-kit-ai/quickapp-examples/showcases/media-001/dist/media-001.rpk`
- SHA-256：`439009523904f8335f96902e642e6d2150379dacdc28d3bceb690923ea0ba0df`
- Bundle RPK：`/Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios/build-ios-ninja/quickapp_ios_simulator.app/media-001.rpk`
- Bundle RPK SHA-256：同上
- 首屏截图：`evidence/screenshots/ios-media-001-home-2026-08-25.png`
- Video 节点：`surface=srf:1 node=node:3`

## 实现

- `src/ios_gateway.mm`：Video 映射为 `AVPlayerViewController` 内置 AVPlayer 控件，不创建自定义控制层。
- `src/runtime_spine.cpp`：iOS Platform Composition 声明 `Video`，允许真实 RPK 通过 Profile 校验。
- `CMakeLists.txt`：链接 `AVFoundation`、`AVKit`、`CoreMedia`，并将 `media-001.rpk` 和既有 deterministic MP4 样本放入 Simulator Bundle。
- RPK 的 `example.invalid` URL 在 iOS Simulator 中映射到 Bundle 内的 `test_video_birds.mp4`，不访问公网；这是平台测试 Provider，不改变 RPK。
- Video 观察：`AVPlayerItem.status` 产生 `prepared/error`，`timeControlStatus` 产生 `start/pause`，周期观察产生 `timeupdate`，结束通知产生 `finish`。
- `src/ios_simulator_main.mm` 提供 iOS-only probe：`QUICKAPP_IOS_VIDEO_ACTIONS` 执行 play/pause/seek，`QUICKAPP_IOS_VIDEO_FORCE_FAILURE` 执行失败路径。

## 真实验收

| 场景 | 证据 | 结果 |
|---|---|---|
| RPK 加载和首帧 | `ios-media-001-play-pause-seek.log`、首屏 PNG | `rpk.verified`、Video Mount、`prepared` |
| 播放 | `ios-media-001-play-pause-seek.log` | `play=completed`、`start` 到达 JS Handler |
| 暂停 | 同上 | `pause=completed`、`pause` 到达 JS Handler |
| seek | 同上 | position `1.000`、`status=completed` |
| 失败 | `ios-media-001-error.log` | `VIDEO_SOURCE_REJECTED -> error -> JS Handler`，Mount 仍完成 |
| teardown | `ios-media-001-teardown.log` | `surfaces=0 nodes=0 handlers=0 jsResources=0 coreQueue=0` |

## 边界

- `media-001` Manifest 只有 `pages/Home`，没有 Detail 页面或 `router.back()` Handler；返回场景对该真实 RPK 为 `NOT_APPLICABLE`，未创建 iOS 私有返回逻辑。
- 未实现直播、倍速、截图、复杂全屏容器和自定义控制层。
- AVPlayer observer、周期 time observer、结束通知和 player 引用在 Node/Runtime teardown 时全部移除。

## 构建

```text
cmake --build build-ios-ninja --target quickapp_ios_simulator -j 4
通过；仅有既有 iOS SDK 弃用和初始化警告。
```
