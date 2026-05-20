# Vendored ten-vad

此目录下的文件从 [TEN-framework/ten-vad](https://github.com/TEN-framework/ten-vad) 原样拷贝而来。

- **Upstream**: https://github.com/TEN-framework/ten-vad
- **Commit**: `22a3bcd4509d0faaa8eef4881e8af5f39c178950`
- **License**: Apache 2.0（`pitch_est.cc` 含 BSD-2-Clause / BSD-3-Clause 片段，详见 `NOTICES`）

## 目录

```
vendor/ten-vad/
├── include/ten_vad.h         通用头文件（与 framework 内 Headers 一致，build.rs 用此处）
├── macOS/
│   └── ten_vad.framework     universal (x86_64 + arm64)，上游原版
├── iOS/
│   ├── device/
│   │   └── ten_vad.framework arm64，iOS device，上游原版
│   └── simulator/
│       └── ten_vad.framework arm64，iOS Simulator——见下方注解
├── LICENSE
└── NOTICES
```

## iOS simulator framework 注解

**上游 `lib/iOS/ten_vad.framework` 只提供 device arm64 slice**，没有 simulator
版本。直接用 device framework 链接 iOS Simulator target 会报 platform mismatch。

我们把同一份 device 二进制用 `vtool` 重新打 platform 标记，得到 simulator 版本：

```bash
vtool -arch arm64 \
  -set-build-version 7 14.0 17.2 \
  -replace \
  -output simulator/ten_vad.framework/ten_vad \
  device/ten_vad.framework/ten_vad
# (platform 7 = ios-simulator)
```

物理上同一份 arm64 二进制在 Apple Silicon Mac 模拟器和真机上行为一致——只是
Mach-O 头部的 `LC_BUILD_VERSION` 标识被改写。**iOS Simulator 在 Apple Silicon
Mac 上原生就是 arm64**，不需要 x86_64 slice（如未来要支持 Intel Mac 上的
模拟器，需要从源码 build x86_64 simulator slice）。

如果上游将来正式提供 simulator framework，应直接替换 `simulator/ten_vad.framework`
并同步更新本 README。

## 升级 ten-vad 上游版本

```bash
git clone --depth 1 https://github.com/TEN-framework/ten-vad /tmp/ten-vad

# macOS universal
rm -rf vendor/ten-vad/macOS/ten_vad.framework
cp -a /tmp/ten-vad/lib/macOS/ten_vad.framework vendor/ten-vad/macOS/

# iOS device
rm -rf vendor/ten-vad/iOS/device/ten_vad.framework
cp -a /tmp/ten-vad/lib/iOS/ten_vad.framework vendor/ten-vad/iOS/device/

# iOS simulator（基于 device 二进制 + vtool 重打 platform）
rm -rf vendor/ten-vad/iOS/simulator/ten_vad.framework
mkdir -p vendor/ten-vad/iOS/simulator
cp -a vendor/ten-vad/iOS/device/ten_vad.framework vendor/ten-vad/iOS/simulator/
vtool -arch arm64 -set-build-version 7 14.0 17.2 -replace \
  -output vendor/ten-vad/iOS/simulator/ten_vad.framework/ten_vad \
  vendor/ten-vad/iOS/device/ten_vad.framework/ten_vad

# 通用资源
cp /tmp/ten-vad/include/ten_vad.h vendor/ten-vad/include/
cp /tmp/ten-vad/LICENSE vendor/ten-vad/LICENSE
cp /tmp/ten-vad/NOTICES vendor/ten-vad/NOTICES

# 更新本 README 里的 commit hash + 跑全套验证
./scripts/build-macos-universal.sh
./scripts/build-ios.sh
cargo test
```
