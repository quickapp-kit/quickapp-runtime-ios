# QuickApp Runtime iOS

iOS platform adapter for [QuickApp Kit](https://github.com/quickapp-kit). Provides the runtime host foundation on Apple platforms.

## What's in here

This package implements the iOS Runtime Host and UIKit platform adapter:

- **Composition** — platform composition root, dependency wiring
- **RuntimeHost** — runtime lifecycle entry, startup gating
- **LaunchProfile** — launch configuration and preflight checks
- **PackageSource** — immutable RPK package reads
- **UIKit Gateway** — View/Text/Button mounting, properties, layout, and input
- **Contracts** — JS engine provider selection, TraceSink, platform port
- **JSONSupport** — typed JSON utilities

The current A1 implementation loads the shared TK-S12 RPK, mounts the Home and
Detail pages through UIKit, routes click/push/back through Core, and tears down
the runtime. The iOS platform also registers the existing Core Feature Provider
port for `system.prompt`, `system.device`, and page title/meta operations.

## Requirements

- Swift 5 (Swift Tools 6.0)
- iOS 15+ / macOS 13+
- Xcode 15+

## Build & Test

```bash
# SPM
swift build
swift test

# Full verification (debug + release + sanitizers + boundary scan)
./tools/verify-ios-s01.sh
```

## Project Layout

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
├── QuickAppRuntimeIOS/          # Xcode project (app target)
├── tools/                       # Verification scripts
└── evidence/                    # Implementation evidence docs
```

## Related

- [quickapp-runtime-core](https://github.com/quickapp-kit/quickapp-runtime-core) — C++ runtime kernel
- [quickapp-runtime-android](https://github.com/quickapp-kit/quickapp-runtime-android) — Android adapter

## License

[MIT](LICENSE)
