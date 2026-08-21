#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

mkdir -p .build-cache/clang
export CLANG_MODULE_CACHE_PATH="$ROOT/.build-cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build-cache/clang"

if rg -n 'import (UIKit|SwiftUI)|\b(UIView|UIViewController|MountTransaction|PlatformInputMessage)\b' Sources; then
  echo "IOS-S01 boundary violation: IOS-S02+ type found in Foundation Sources" >&2
  exit 1
fi

swift test --disable-sandbox --scratch-path .build/debug
swift build --disable-sandbox --configuration release --scratch-path .build/release
swift test --disable-sandbox --sanitize=address --scratch-path .build/asan
swift test --disable-sandbox --sanitize=thread --scratch-path .build/tsan

IOS_SIMULATOR_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
mkdir -p .build/ios-simulator
xcrun swiftc \
  -parse-as-library \
  -target arm64-apple-ios15.0-simulator \
  -sdk "$IOS_SIMULATOR_SDK" \
  -module-cache-path .build-cache/clang \
  -module-name QuickAppRuntimeIOSFoundation \
  -emit-module \
  -emit-module-path .build/ios-simulator/QuickAppRuntimeIOSFoundation.swiftmodule \
  Sources/QuickAppRuntimeIOSFoundation/*.swift

echo "IOS-S01 verification passed"
