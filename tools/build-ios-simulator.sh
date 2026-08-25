#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT}/build-ios-ninja"
DEVELOPER="$(xcode-select -p)"
CLANG="${DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
CLANGXX="${DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"

cmake -S "${ROOT}" -B "${BUILD_DIR}" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_C_COMPILER="${CLANG}" \
  -DCMAKE_CXX_COMPILER="${CLANGXX}" \
  -DCMAKE_OBJCXX_COMPILER="${CLANGXX}" \
  -DQUICKAPP_IOS_ENABLE_STAGE_LOG=ON \
  -DQUICKAPP_CORE_BUILD_TESTS=OFF \
  -DQUICKAPP_JS_BUILD_TESTS=OFF
cmake --build "${BUILD_DIR}" --target quickapp_ios_simulator -j "${JOBS:-8}"

echo "ios_simulator_bundle=${BUILD_DIR}/quickapp_ios_simulator.app"
file "${BUILD_DIR}/quickapp_ios_simulator.app/quickapp_ios_simulator"
shasum -a 256 "${BUILD_DIR}/quickapp_ios_simulator.app/tk-s12-lvgl-p0.rpk"
shasum -a 256 "${BUILD_DIR}/quickapp_ios_simulator.app/gallery-001.rpk"
shasum -a 256 "${BUILD_DIR}/quickapp_ios_simulator.app/consumer-001.rpk"
shasum -a 256 "${BUILD_DIR}/quickapp_ios_simulator.app/wearable-001.rpk"
