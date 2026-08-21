# QuickApp Runtime iOS

iOS platform adapter for [QuickApp Kit](https://github.com/quickapp-kit). Provides the runtime host foundation on Apple platforms.

## What's in here

This package implements the iOS Runtime Host foundation layer:

- **Composition** — platform composition root, dependency wiring
- **RuntimeHost** — runtime lifecycle entry, startup gating
- **LaunchProfile** — launch configuration and preflight checks
- **PackageSource** — immutable RPK package reads
- **Contracts** — JS engine provider selection, TraceSink, platform port
- **JSONSupport** — typed JSON utilities

Currently UIKit-free. Surface/Mount/Input/Measure will come in later milestones (IOS-S02+).

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
