# iOS B6 URL Provider

结论：B6 iOS 平台实现当前被前置公共输入阻塞，未开始写平台代码，也未伪造 external 或 webview 验收。

## 已验证事实

- 工作区不存在 `quickapp-examples/showcases/url-001/dist/url-001.rpk`。
- 当前 iOS Bundle 也没有 `url-001.rpk`。
- 当前冻结 JS ABI 的 `FeatureModule` 只有 `Prompt`、`Fetch`、`File`。
- 当前冻结 JS ABI 的 `FeatureMethod` 没有 `openUrl` 或 `webview`。
- 当前 Core `ModuleRegistry` 只有 Prompt、Device、PageHost、Fetch、File 五类模块。
- 当前 iOS `RuntimeSpine` 只能把已有 `prompt/fetch/file` 请求送入 Core `ModuleRegistry`。

## 架构判断

`external` 和 `webview` 必须先由公共实现定义 typed Feature Contract、JS ABI、Toolkit lowering、manifest capability 并生成真实 `url-001.rpk`，然后 iOS Provider 才能通过既有：

```text
真实 RPK
-> JS Facade / ABI
-> Core Feature Registry
-> iOS Provider
-> UIApplication / WKWebView
```

在 iOS 侧直接识别某个页面、写死 URL、扩展 `dispatchFeature` 字符串或绕过 Core 调起 UIKit，会产生平台旁路能力，不能作为 B6 验收。

## 未执行项

- 未调起系统默认浏览器。
- 未打开 `WKWebView` 页面。
- 未验证失败、关闭和 teardown。
- 未修改 `quickapp-runtime-ios` 运行时代码。

## 放行条件

1. 公共实现提供 `openUrl` / `webview` 的 typed ABI 和 Core Provider 模块映射。
2. Toolkit 生成真实 `url-001.rpk`，并提供 SHA-256。
3. iOS Bundle 内置该 RPK。
4. 再由 iOS 平台实现 `UIApplication` external 调起和 `WKWebView` 页面生命周期。

