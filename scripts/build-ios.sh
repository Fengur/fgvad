#!/usr/bin/env bash
# 把 fgvad 编出 iOS device + iOS Simulator 两份产物。
# 输出到：
#   target/aarch64-apple-ios/<profile>/libfgvad.{dylib,a}        (device)
#   target/aarch64-apple-ios-sim/<profile>/libfgvad.{dylib,a}    (simulator)
#
# 用法：
#   scripts/build-ios.sh                    # debug
#   scripts/build-ios.sh --release          # release
#
# 后续打 XCFramework：
#   scripts/build-ios-xcframework.sh        # 还没写，Day 2 任务

set -euo pipefail

PROFILE="debug"
for arg in "$@"; do
  if [[ "$arg" == "--release" ]]; then
    PROFILE="release"
    break
  fi
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 确保两个 iOS target 都装了
for tgt in aarch64-apple-ios aarch64-apple-ios-sim; do
  if ! rustup target list --installed | grep -q "^${tgt}\$"; then
    echo "==> 安装缺失的 rustup target: $tgt"
    rustup target add "$tgt"
  fi
done

echo "==> 编译 aarch64-apple-ios ($PROFILE) [device]"
cargo build --target=aarch64-apple-ios "$@"

echo "==> 编译 aarch64-apple-ios-sim ($PROFILE) [simulator]"
cargo build --target=aarch64-apple-ios-sim "$@"

echo
echo "✓ iOS 产物已就绪："
echo
echo "  device     ($PROFILE):"
ls -la "target/aarch64-apple-ios/${PROFILE}/" | grep -E "libfgvad" | sed 's/^/    /'
echo
echo "  simulator  ($PROFILE):"
ls -la "target/aarch64-apple-ios-sim/${PROFILE}/" | grep -E "libfgvad" | sed 's/^/    /'
echo
echo "  device 链接信息："
otool -L "target/aarch64-apple-ios/${PROFILE}/libfgvad.dylib" 2>&1 | sed 's/^/    /'
