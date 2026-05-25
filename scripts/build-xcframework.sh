#!/usr/bin/env bash
# 把 fgvad 三 slice 合 FgvadCore.xcframework,ten_vad 三 slice 合 TenVad.xcframework。
# 输出到 dist/。
#
# 用法:
#   scripts/build-xcframework.sh           # debug
#   scripts/build-xcframework.sh --release # release(发版用)
#
# 依赖:
#   - rustup target: aarch64-apple-ios / aarch64-apple-ios-sim /
#                    aarch64-apple-darwin / x86_64-apple-darwin
#   - macOS Xcode(xcodebuild -create-xcframework)

set -euo pipefail

PROFILE="debug"
PROFILE_FLAG=""
for arg in "$@"; do
  if [[ "$arg" == "--release" ]]; then
    PROFILE="release"
    PROFILE_FLAG="--release"
    break
  fi
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DIST="$ROOT/dist"
mkdir -p "$DIST"

# 1) iOS device + iOS sim 编出来
"$ROOT/scripts/build-ios.sh" $PROFILE_FLAG

# 2) macOS universal 编出来
"$ROOT/scripts/build-macos-universal.sh" $PROFILE_FLAG

# 3) 准备 headers 目录:include/ 已经有 fgvad.h + module.modulemap,
#    xcodebuild -create-xcframework 直接拿这个目录。

# 4) 清理旧产物(xcodebuild 不接受已存在的 -output)
rm -rf "$DIST/FgvadCore.xcframework" "$DIST/TenVad.xcframework"

# 5) 合 FgvadCore.xcframework
echo "==> 合 FgvadCore.xcframework"
xcodebuild -create-xcframework \
  -library "$ROOT/target/aarch64-apple-ios/$PROFILE/libfgvad.a" \
  -headers "$ROOT/include" \
  -library "$ROOT/target/aarch64-apple-ios-sim/$PROFILE/libfgvad.a" \
  -headers "$ROOT/include" \
  -library "$ROOT/target/universal-apple-darwin/$PROFILE/libfgvad.a" \
  -headers "$ROOT/include" \
  -output "$DIST/FgvadCore.xcframework"

# 6) 合 TenVad.xcframework(从 vendor/ 三个 slice)
echo "==> 合 TenVad.xcframework"
xcodebuild -create-xcframework \
  -framework "$ROOT/vendor/ten-vad/iOS/device/ten_vad.framework" \
  -framework "$ROOT/vendor/ten-vad/iOS/simulator/ten_vad.framework" \
  -framework "$ROOT/vendor/ten-vad/macOS/ten_vad.framework" \
  -output "$DIST/TenVad.xcframework"

echo
echo "完成:"
ls -d "$DIST"/*.xcframework
