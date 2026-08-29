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

## Contract Revalidation (2026-08-27)

结论：按当前 Media Resource Contract 约束重新验证后，旧文档中
`example.invalid -> test_video_birds.mp4` 的 Bundle 映射不再成立；该映射违反了
“不得用网络 URL 替代 RPK 内本地资源”。本次 iOS Adapter 已改为只接受 RPK 内
`assets/...` 路径，并在 AVPlayer 创建前校验 MIME、字节长度、SHA-256 和 16 MiB
预算，成功后才写入受控临时缓存。

- 当前仓库没有独立命名为 Media Resource Contract 的文档；本次遵循现有
  `host-component-contract.md`、`event-contract.md` 和 `artifact-contract.md` 的约束，
  不新增或修改公共 Contract。
- 真实 RPK：`/Users/qy/code/my-github/quickapp-kit-ai/quickapp-examples/showcases/media-001/dist/media-001.rpk`
- RPK SHA-256：`439009523904f8335f96902e642e6d2150379dacdc28d3bceb690923ea0ba0df`
- RPK 成员没有本地视频；仅有 `assets/images/media-poster.png`。Video `src` 为
  `https://example.invalid/quickapp-kit/demo.mp4`，因此真实运行结果是
  `MEDIA_PATH_INVALID -> MEDIA_SOURCE_REJECTED -> error`，不是 `prepared`。
- 运行日志：`evidence/showcase-logs/ios-media-001-resource-contract-2026-08-27.log`
- 错误态截图：`evidence/screenshots/ios-media-001-error-state-2026-08-27.png`
- Bundle RPK：`build-ios-ninja/quickapp_ios_simulator.app/media-001.rpk`，SHA-256 同上。
- 关键日志：
  `ios.video.resource ... code=MEDIA_PATH_INVALID path=https://example.invalid/quickapp-kit/demo.mp4`
  `ios.video.source ... code=MEDIA_SOURCE_REJECTED`
  `ios.video.event ... type=error`
  `ios.video.control ... action=play|pause|seek status=failed code=VIDEO_NOT_READY`
- Teardown 日志：`ios.runtime.stopped surfaces=0 nodes=0 handlers=0 pendingCallbacks=0 jsResources=0 coreQueue=0`，
  随后 `ios.runtime.platform.resources surfaces=0 nodes=0`。
- 在没有合规本地视频资源的前提下，`prepared/start/pause/finish` 不适用；没有伪造
  AVPlayer 生命周期，也没有把视频字节传入 Core。

可播放的下一条真实验收前提是：Toolkit 生成包含 `assets/videos/*.mp4` 的 RPK，且
其资源描述包含与字节一致的 `video/mp4`、`byteLength` 和 `sha256`；该前提不能在
本任务中通过修改 Core、Toolkit、RPK 或公共 Contract 绕过。
