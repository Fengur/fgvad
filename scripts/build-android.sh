#!/usr/bin/env bash
# 编 fgvad-jni（含 fgvad 静态链） → 拷到 demo jniLibs。
# 用法：
#   scripts/build-android.sh                    # debug
#   scripts/build-android.sh --release          # release
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

NDK="${ANDROID_NDK_HOME:-$HOME/Library/Android/sdk/ndk/28.2.13676358}"
if [[ ! -d "$NDK" ]]; then
  echo "✗ 找不到 NDK：$NDK"
  echo "  请装 NDK 28.2.13676358 或设 ANDROID_NDK_HOME"
  exit 1
fi

# 注意：Apple Silicon Mac 的 NDK 仍然叫 darwin-x86_64（Google 沿用旧名，
# 实际是 arm64 原生二进制）。不要改成 darwin-arm64。
TOOLCHAIN_BIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin"
if [[ ! -x "$TOOLCHAIN_BIN/aarch64-linux-android26-clang" ]]; then
  echo "✗ 找不到 NDK toolchain: $TOOLCHAIN_BIN"
  exit 1
fi

# 自动装 rustup target
if ! rustup target list --installed | grep -q '^aarch64-linux-android$'; then
  echo "==> 安装 rustup target aarch64-linux-android"
  rustup target add aarch64-linux-android
fi

export CC_aarch64_linux_android="$TOOLCHAIN_BIN/aarch64-linux-android26-clang"
export CXX_aarch64_linux_android="$TOOLCHAIN_BIN/aarch64-linux-android26-clang++"
export AR_aarch64_linux_android="$TOOLCHAIN_BIN/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$CC_aarch64_linux_android"

cd "$ROOT/examples/android/fgvad-jni"
echo "==> 编译 fgvad-jni ($PROFILE) for aarch64-linux-android"
if [[ "$PROFILE" == "release" ]]; then
  cargo build --target=aarch64-linux-android --release
else
  cargo build --target=aarch64-linux-android
fi

# 拷 .so 到 android/fgvad library jniLibs(单点,demo 通过 Gradle project 依赖)
LIB_LIBS="$ROOT/android/fgvad/src/main/jniLibs/arm64-v8a"
mkdir -p "$LIB_LIBS"
cp "$ROOT/examples/android/fgvad-jni/target/aarch64-linux-android/$PROFILE/libfgvad_android.so" "$LIB_LIBS/"
cp "$ROOT/vendor/ten-vad/Android/arm64-v8a/libten_vad.so" "$LIB_LIBS/"

echo
echo "✓ Android .so 已就绪: $LIB_LIBS"
ls -la "$LIB_LIBS"
echo
echo "==> 链接信息(DT_NEEDED 应该看到 libten_vad.so):"
"$TOOLCHAIN_BIN/llvm-readelf" -d "$LIB_LIBS/libfgvad_android.so" | grep NEEDED || true
