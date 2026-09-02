#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER="$(xcode-select -p)"
CLANG="${DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
CLANGXX="${DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
JOBS="${JOBS:-8}"

configure_and_build() {
  local build_dir="$1"
  local sdk="$2"
  cmake -S "${ROOT}" -B "${ROOT}/${build_dir}" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="${sdk}" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_C_COMPILER="${CLANG}" \
    -DCMAKE_CXX_COMPILER="${CLANGXX}" \
    -DCMAKE_OBJCXX_COMPILER="${CLANGXX}" \
    -DQUICKAPP_IOS_ENABLE_STAGE_LOG=OFF \
    -DQUICKAPP_CORE_BUILD_TESTS=OFF \
    -DQUICKAPP_JS_BUILD_TESTS=OFF
  cmake --build "${ROOT}/${build_dir}" --target QuickAppKit -j "${JOBS}"
}

configure_and_build build-xcframework-sim iphonesimulator
configure_and_build build-xcframework-device iphoneos

OUTPUT="${ROOT}/dist/QuickAppKit.xcframework"
rm -rf "${OUTPUT}"
xcodebuild -create-xcframework \
  -library "${ROOT}/build-xcframework-sim/libQuickAppKit.a" \
  -headers "${ROOT}/include/QuickAppKit" \
  -library "${ROOT}/build-xcframework-device/libQuickAppKit.a" \
  -headers "${ROOT}/include/QuickAppKit" \
  -output "${OUTPUT}"

echo "quickappkit_xcframework=${OUTPUT}"
find "${OUTPUT}" -maxdepth 2 -type f -print | sort
