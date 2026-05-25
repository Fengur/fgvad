#!/usr/bin/env bash
# 一键 release:跑 build-xcframework.sh --release + zip xcframework + 算 SHA256。
# 输出可直接上传到 GitHub Release 的两个 zip,以及 Package.swift binaryTarget 用的 checksum。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 1) release build
"$ROOT/scripts/build-xcframework.sh" --release

# 2) zip 两个 xcframework
cd "$ROOT/dist"
rm -f FgvadCore.xcframework.zip ten_vad.xcframework.zip

echo "==> zip FgvadCore.xcframework"
zip -ry FgvadCore.xcframework.zip FgvadCore.xcframework

echo "==> zip ten_vad.xcframework"
zip -ry ten_vad.xcframework.zip ten_vad.xcframework

# 3) 算 SHA256 checksum(swift package compute-checksum 用的格式)
echo
echo "===================================="
echo "Release artifacts ready:"
ls -lh "$ROOT/dist"/*.zip
echo
echo "Package.swift 用的 checksum:"
echo "  FgvadCore: $(swift package compute-checksum FgvadCore.xcframework.zip)"
echo "  TenVad:    $(swift package compute-checksum ten_vad.xcframework.zip)"
echo "===================================="
