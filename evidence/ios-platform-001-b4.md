# iOS B4 Platform Feature Provider

结论：iOS 已接入 `prompt/fetch/file` 三个 typed Platform Provider，并使用真实 `platform-001.rpk` 验证 deterministic `completed`、`failed`、`cancelled`、无 Provider `unsupported` 和私有文件读取。Host probe 已验证同一真实 RPK 的 Runtime teardown 资源归零；Core、JS、Toolkit、公共 Contract 和 Examples 未修改。

## 基线

- RPK：`/Users/qy/code/my-github/quickapp-kit-ai/quickapp-examples/showcases/platform-001/dist/platform-001.rpk`
- SHA-256：`79ace8e7a28eeef67c31ae3cb519af7c7e3a85c8556c8ecb4811456f3a49035d`
- Bundle 内 SHA-256：同上
- 首屏截图：`evidence/screenshots/ios-platform-001-home-2026-08-25.png`

## 实现

- `src/ios_gateway.mm`：同一 iOS Provider 实现 `system.prompt`、`system.fetch`、`system.file`。
- `prompt.confirm`：普通消息返回 `completed`；包含 `cancel/取消` 的 deterministic probe 返回 `cancelled`；包含 `fail/失败` 的 probe 返回 `failed`。
- `fetch`：只接受本地 deterministic URL：
  - `local://platform/status` -> `completed`，HTTP `200`，text/json payload。
  - `local://platform/failure` -> `failed`。
  - `local://platform/cancelled` -> `cancelled`。
  - 其他 URL -> `failed`，不访问公网。
- `file`：只使用内存 Provider；仅接受 `private/` 且拒绝 `..`、`//` 路径。初始私有文件为 `private/platform-state.txt`，支持 read/write/exists/delete；Provider close 时清空内存文件。
- `src/runtime_spine.cpp`：把现有 `FeatureRequest` 转换为 Core typed `ModuleRegistry` 请求，并将 `FeatureResult` 通过既有 ABI 返回 JS；注册 `system.fetch`、`system.file` Provider。
- `src/ios_simulator_main.mm`：增加 iOS 自有 Feature probe 环境变量和受控 teardown 入口，仅用于真实 Simulator 验收，不改变 Runtime 公共 Contract。
- `CMakeLists.txt`：将 `platform-001.rpk` 放入 iOS Simulator Bundle。

## 真实 iOS 验收

日志目录：`evidence/showcase-logs/`。

| 场景 | 日志 | 结果 |
|---|---|---|
| prompt completed | `ios-platform-001-prompt-completed.log` | `provider.result ... status=completed` |
| prompt cancelled | `ios-platform-001-prompt-cancelled.log` | `provider.result ... status=cancelled` |
| fetch completed | `ios-platform-001-fetch-completed.log` | `provider.result ... status=completed` |
| fetch failed | `ios-platform-001-fetch-failed.log` | `provider.result ... status=failed` |
| fetch cancelled | `ios-platform-001-fetch-cancelled.log` | `provider.result ... status=cancelled` |
| file read | `ios-platform-001-file-completed.log` | `provider.result ... status=completed` |
| no Provider | `ios-platform-001-no-provider.log` + Host probe | Host `status=unsupported` |
| UIKit feature run | `ios-platform-001-teardown.log` | Provider invocation and RPK page mount completed; no UIKit teardown-zero assertion was recorded |

Host no-Provider probe：

- `ios-platform-001-prompt-host-probe.log`
- `ios-platform-001-fetch-host-probe.log`
- `ios-platform-001-file-host-probe.log`
- 三次最终均为 `surfaces=0 nodes=0 handlers=0 pendingCallbacks=0 jsResources=0 coreQueue=0`。
- Host probe 的 prompt、fetch、file 请求均在同一真实 RPK 上走 `status=unsupported` 路径，并完成 Runtime destroy。

## 边界与阻塞

当前冻结 `Provider::invoke` 是同步接口，没有新增异步 Provider Contract；因此 `cancelled` 使用 deterministic local provider 输入验证，未伪造异步网络请求。Core 仍只负责 Registry、typed request/result、RequestId 和 Surface 生命周期，不访问网络或文件系统。

最新构建已通过：`cmake --build build-ios-ninja --target quickapp_ios_simulator -j 4` 和 `cmake --build build-host --target quickapp_ios_spine_probe -j 4`。构建期间仅有已有的初始化和 iOS SDK 弃用警告，无 B4 编译错误。重新启动当前 Bundle 后，真实 UIKit Simulator 日志再次出现 `ios.feature.provider.result ... status=completed`。
