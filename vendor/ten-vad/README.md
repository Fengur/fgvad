# Vendored ten-vad

此目录下的文件从 [TEN-framework/ten-vad](https://github.com/TEN-framework/ten-vad) 原样拷贝而来。

- **Upstream**: https://github.com/TEN-framework/ten-vad
- **Commit**: `22a3bcd4509d0faaa8eef4881e8af5f39c178950`
- **License**: Apache 2.0（`pitch_est.cc` 含 BSD-2-Clause / BSD-3-Clause 片段，详见 `NOTICES`）

## 目录

- `macOS/ten_vad.framework/` — macOS universal（arm64 + x86_64）动态 framework
- `include/ten_vad.h` — C API 头文件（和 framework 内 Headers 目录里的一致，放在这里方便 `build.rs` / bindgen 引用）
- `LICENSE` / `NOTICES` — 上游许可与声明

## 升级

```bash
git clone --depth 1 https://github.com/TEN-framework/ten-vad /tmp/ten-vad
rm -rf vendor/ten-vad/macOS/ten_vad.framework
cp -a /tmp/ten-vad/lib/macOS/ten_vad.framework vendor/ten-vad/macOS/
cp /tmp/ten-vad/include/ten_vad.h vendor/ten-vad/include/
cp /tmp/ten-vad/LICENSE vendor/ten-vad/LICENSE
cp /tmp/ten-vad/NOTICES vendor/ten-vad/NOTICES
# 更新本 README 里的 commit hash
```
