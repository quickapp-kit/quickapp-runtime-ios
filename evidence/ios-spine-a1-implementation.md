# iOS A1 Implementation Evidence

## 结论

iOS A1 的共享运行链路和真实 UIKit 首屏/点击/路由已成立；真实 iOS teardown 仍未完成，当前状态为 `IOS-A1 UI_VERIFIED + TEARDOWN_PENDING`。

已验证的主链路是：同一份 `tk-s07-case001.rpk` -> RPK Loader -> 共享 QuickJS/JS Framework -> 共享 C++ Core -> Platform Gateway -> Core Event Router -> JS Handler -> Core Navigation -> 第二个 Surface。Host teardown 已验证；真实 iOS teardown 仍待补齐。

## 目录

- [范围](#范围)
- [已验证事实](#已验证事实)
- [合理推断](#合理推断)
- [待验证项](#待验证项)
- [复现命令](#复现命令)
- [失败与降级](#失败与降级)
- [合同影响](#合同影响)

## 范围

本轮只修改 `quickapp-runtime-ios`：

- iOS Runtime Spine、UIKit Gateway、UIKit Surface/Mount Adapter。
- iOS Simulator App target，内置真实联盟基线 RPK。
- macOS Host probe，用于在 CoreSimulator 不可用时验证共享 RPK/Core/JS 主链路。
- iOS Host teardown 顺序修复：JS-owned services 通过 `JsEngineService::stop` 的 owner-thread teardown barrier 释放，不使用会在 Quiescing 后被取消的普通队列任务。

未修改 Core、JS Runtime、Toolkit、Android、LVGL 或公共 Contract。

## 已验证事实

### 1. 真实 RPK 与共享链路

Host probe 使用：

`/Users/qy/code/my-github/quickapp-kit-ai/quickapp-toolkit/evidence/tk-s07-case001.rpk`

SHA-256：`32e012e2235c7ffa36143d9619c90264bbbab5ae0d083e12a13092859990b493`

实际输出：

```text
ios.probe.first surfaces=1 nodes=3 handlers=1 jsResources=3
ios.probe.after_click surfaces=2 nodes=8 handlers=2 jsResources=5
ios.probe.runtime.stopped surfaces=0 nodes=0 handlers=0 pendingCallbacks=0 jsResources=0 coreQueue=0
```

这证明：首屏已建立；`node:3` 点击经过共享事件/JS/Core 链路后产生第二个 Surface；停止后 Surface、Runtime Node、Handler、JS 资源和 Core 队列归零。

### 2.1 真实 iOS Simulator 运行

设备：`iPhone 17 Pro`，iOS `26.5`。

已验证：

- App 通过 `simctl install/launch` 启动。
- 真实 UIKit 首屏显示 RPK 内容。
- Simulator 日志记录：`ios.input.click surface=srf:1 node=node:3`。
- 点击真实 UIKit Button 后 Detail 页面显示；截图见：
  - `evidence/screenshots/ios-a1-first-rpk.png`
  - `evidence/screenshots/ios-a1-detail.png`
- 首次真实运行发现并修复两个 iOS Adapter 缺口：`textAlign`、`borderRadius`；修复后首屏 Mount 完成。

### 3. iOS Simulator 构建

构建目标：`arm64-apple-ios15.0-simulator`

产物：

`quickapp-runtime-ios/build-ios-ninja/quickapp_ios_simulator.app/quickapp_ios_simulator`

已验证：

- Mach-O `arm64` 可执行文件生成。
- Bundle 内含 `tk-s07-case001.rpk`，SHA 与输入一致。
- Bundle Identifier：`dev.quickappkit.ios.simulator`。
- 链接 UIKit、Foundation 和 zlib。
- `nm` 符号清单包含 `QuickJsEngineProvider`、`JsEngineService`、`ModuleLoader`、`VmLifecycleService`、`RuntimeSpine`、Core `SurfaceController` 等符号。
- 没有引入第二个 JS Engine Provider 或第二套 JS Framework。

### 4. Swift Foundation 回归

使用隔离的 SwiftPM scratch/module cache 执行：

```text
Executed 19 tests, with 0 failures
```

这保留了 IOS-S01 原有的 19 项 Foundation/PackageSource/RuntimeHost 验证。

### 5. Host AddressSanitizer

Host probe 使用 `-fsanitize=address -fno-omit-frame-pointer` 构建并运行，输出与普通构建一致，未报告 AddressSanitizer 错误。Apple macOS 当前不支持 `detect_leaks=1`，因此本次结果是 AddressSanitizer 内存访问检查，不是 LeakSanitizer 报告。

## 合理推断

- iOS App target 的 Objective-C++ Gateway 能够把 UIKit 主线程操作限制在平台层，并将结果以 typed message 返回 Runtime Spine；该结论目前由编译和符号清单支持，尚未由真实 UIKit 点击运行支持。
- iOS Host 复用的 Core/JS 静态库来自同一工作区构建，Host probe 与 Simulator target 使用同一组 shared library targets；最终发布工程仍应在集成阶段生成正式 link map。

## 待验证项

以下项目仍未验证：

1. iOS App target 的正式 link map 文件。
2. iOS Simulator 下 DebugSanitizer/等价内存运行结果。
3. Scene/Host 关闭期间的 UIKit 输入隔离与迟到回调。
4. 真实 iOS teardown 后资源归零；`simctl terminate` 未触发当前 AppDelegate 的 `applicationWillTerminate`。
5. RPK 加载失败、UIKit Mount 失败的真实 App UI 失败路径。

Host probe 的 AddressSanitizer 已通过；真实 Simulator UI 已验证，运行期 Sanitizer 和 teardown 仍待补齐。

## 复现命令

### Host probe

```sh
cd /Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios
cmake -S . -B build-host -G Ninja \
  -DQUICKAPP_CORE_BUILD_TESTS=OFF \
  -DQUICKAPP_JS_BUILD_TESTS=OFF
cmake --build build-host --target quickapp_ios_spine_probe -j 8
./build-host/quickapp_ios_spine_probe \
  /Users/qy/code/my-github/quickapp-kit-ai/quickapp-toolkit/evidence/tk-s07-case001.rpk
```

### iOS Simulator target

```sh
cd /Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios
./tools/build-ios-simulator.sh
xcrun simctl list devices available
```

本次构建、安装、启动和交互均成功。

### Host AddressSanitizer

```sh
cmake -S . -B build-host-asan -G Ninja \
  -DQUICKAPP_CORE_BUILD_TESTS=OFF \
  -DQUICKAPP_JS_BUILD_TESTS=OFF \
  -DCMAKE_C_FLAGS='-fsanitize=address -fno-omit-frame-pointer' \
  -DCMAKE_CXX_FLAGS='-fsanitize=address -fno-omit-frame-pointer' \
  -DCMAKE_EXE_LINKER_FLAGS='-fsanitize=address'
cmake --build build-host-asan --target quickapp_ios_spine_probe -j 8
ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 \
  ./build-host-asan/quickapp_ios_spine_probe \
  /Users/qy/code/my-github/quickapp-kit-ai/quickapp-toolkit/evidence/tk-s07-case001.rpk
```

结果：主链路和 teardown 输出正常，无 AddressSanitizer 报告。

### Swift tests

```sh
cd /Users/qy/code/my-github/quickapp-kit-ai/quickapp-runtime-ios
SWIFT_MODULECACHE_PATH=/tmp/quickapp-ios-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/quickapp-ios-module-cache \
swift test --disable-sandbox \
  --scratch-path /tmp/quickapp-ios-swift-tests
```

## 失败与降级

- RPK 读取或校验失败：Host 不发布 Runtime，返回失败，不创建半存活 Surface。
- UIKit Mount/Surface 投递失败：Gateway 返回 typed failure，Core 保持唯一状态所有者并执行清理。
- Scene 关闭期间再次输入：Gateway/Host 拒绝迟到输入，不创建新的 RequestId 或旁路路由。
- teardown 期间 JS 队列任务：由 JS Executor 的 teardown barrier 处理；普通 queued task 在 Quiescing 后可被取消，不能承担资源释放职责。
- CoreSimulatorService 不可用：保留可重复的 Host probe 和 Simulator 编译证据，不把编译推断为 UIKit 运行成功。

## 合同影响

公共 Contract 未变化。iOS 只实现平台侧 Gateway/Adapter 和 Runtime Host；Core 继续拥有 Runtime Tree、Navigation、Lifecycle，JS Runtime/Framework 和 RPK Loader 继续复用共享实现。

当前状态：`IOS-A1 IMPLEMENTED + HOST_VERIFIED + SIMULATOR_BUILD_VERIFIED + UI_VERIFIED + TEARDOWN_PENDING`。

下一步只补齐真实 iOS teardown、运行期 Sanitizer 和正式 link map，再由总架构复核是否标记 `IOS-A1 VERIFIED`。本轮停止扩展 IOS-S02 及外围能力。
