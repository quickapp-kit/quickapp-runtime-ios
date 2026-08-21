# QuickApp Runtime iOS

[QuickApp Kit](https://github.com/quickapp-kit) 的 iOS 平台适配层，提供 Apple 平台上的运行时宿主基础。

## 包含内容

本包实现了 iOS Runtime Host 基础层：

- **Composition** — 平台组合根，依赖注入
- **RuntimeHost** — 运行时生命周期入口，启动门控
- **LaunchProfile** — 启动配置与预检
- **PackageSource** — 不可变 RPK 包读取
- **Contracts** — JS 引擎 Provider 选择、TraceSink、平台端口
- **JSONSupport** — 类型安全的 JSON 工具

当前不依赖 UIKit。Surface/Mount/Input/Measure 在后续里程碑（IOS-S02+）实现。

## 环境要求

- Swift 5（Swift Tools 6.0）
- iOS 15+ / macOS 13+
- Xcode 15+

## 构建与测试

```bash
# SPM
swift build
swift test

# 完整验证（debug + release + sanitizers + 边界扫描）
./tools/verify-ios-s01.sh
```

## 目录结构

```
├── Package.swift
├── Sources/
│   └── QuickAppRuntimeIOSFoundation/
│       ├── Composition.swift
│       ├── RuntimeHost.swift
│       ├── LaunchProfile.swift
│       ├── PackageSource.swift
│       ├── Contracts.swift
│       └── JSONSupport.swift
├── Tests/
│   └── QuickAppRuntimeIOSFoundationTests/
├── QuickAppRuntimeIOS/          # Xcode 工程（App Target）
├── tools/                       # 验证脚本
└── evidence/                    # 实现验证文档
```

## 相关仓库

- [quickapp-runtime-core](https://github.com/quickapp-kit/quickapp-runtime-core) — C++ 运行时内核
- [quickapp-runtime-android](https://github.com/quickapp-kit/quickapp-runtime-android) — Android 适配层

## 许可证

[MIT](LICENSE)
