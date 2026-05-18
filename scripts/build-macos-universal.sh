#!/usr/bin/env bash
# 把 fgvad 同时编出 arm64 + x86_64 两份产物并 lipo 成 universal binary。
# 输出到 target/universal-apple-darwin/<profile>/libfgvad.{dylib,a}。
#
# 用法：
#   scripts/build-macos-universal.sh           # debug profile
#   scripts/build-macos-universal.sh --release # release profile
#   scripts/build-macos-universal.sh --release --frozen   # 透传任意 cargo 参数

set -euo pipefail

# 解析 --release（用来决定 profile 子目录名）
PROFILE="debug"
for arg in "$@"; do
  if [[ "$arg" == "--release" ]]; then
    PROFILE="release"
    break
  fi
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 确保两个 target 都装了
for tgt in aarch64-apple-darwin x86_64-apple-darwin; do
  if ! rustup target list --installed | grep -q "^${tgt}\$"; then
    echo "==> 安装缺失的 rustup target: $tgt"
    rustup target add "$tgt"
  fi
done

echo "==> 编译 aarch64-apple-darwin ($PROFILE)"
cargo build --target=aarch64-apple-darwin "$@"

echo "==> 编译 x86_64-apple-darwin ($PROFILE)"
cargo build --target=x86_64-apple-darwin "$@"

OUT_DIR="target/universal-apple-darwin/${PROFILE}"
mkdir -p "$OUT_DIR"

echo "==> lipo 合成 universal libfgvad.dylib"
lipo -create \
  "target/aarch64-apple-darwin/${PROFILE}/libfgvad.dylib" \
  "target/x86_64-apple-darwin/${PROFILE}/libfgvad.dylib" \
  -output "${OUT_DIR}/libfgvad.dylib"

echo "==> lipo 合成 universal libfgvad.a"
lipo -create \
  "target/aarch64-apple-darwin/${PROFILE}/libfgvad.a" \
  "target/x86_64-apple-darwin/${PROFILE}/libfgvad.a" \
  -output "${OUT_DIR}/libfgvad.a"

echo
echo "✓ Universal 产物已就绪："
ls -la "$OUT_DIR/"
echo
echo "  dylib 架构："
file "$OUT_DIR/libfgvad.dylib" | sed 's/^/    /'
echo "  staticlib 架构："
file "$OUT_DIR/libfgvad.a" | sed 's/^/    /'
