# FgVadDemo —— fgvad 的 macOS 测试工具

AppKit + SnapKit。既是对外的使用示例，也是调试/调参的主力工具。

## 构建方式

```bash
# 先构建 fgvad（每次改动 Rust 代码都需要重新跑）
cd <repo root>
cargo build

# 生成 Xcode 工程（改了 project.yml 后再跑）
cd examples/macos
xcodegen generate

# 用 Xcode 打开，或命令行构建
open FgVadDemo.xcodeproj
# 或
xcodebuild -project FgVadDemo.xcodeproj -scheme FgVadDemo -configuration Debug build
```

运行一次会在 `~/Documents/FgVadDemo/` 下留下以 `rec-YYYY-MM-DD-HH-MM-SS.wav` 命名的
录音文件。

## 工具链

```
Rust fgvad (target/debug/libfgvad.dylib) ─┐
                                          ├─ 链接 + 嵌入 Frameworks/
ten_vad.framework (vendor/ten-vad/macOS/)─┘
                  ↓
       Xcode 编译 FgVadDemo.app

Swift 通过 FgVadDemo-Bridging-Header.h 导入 fgvad.h (include/)
运行时通过 @rpath/@executable_path/../Frameworks 加载
```

## 依赖

- Xcode 15+ / macOS 13+
- Rust toolchain（`rustup`）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- SnapKit（通过 SPM 自动拉取）

## 当前进度

此版本（7a）只有**录音 + 存 WAV**。后续阶段会加入：

- 停止录音后自动跑 VAD 分析
- 概率曲线 + 角色色带可视化
- 原始录音 / 过滤后结果 / 按句 三层试听
- 配置面板（head/tail/max 等参数）+ 重跑按钮
- 加载历史 WAV 回灌分析
- 短/长时模式切换

---

> 具体设计参见 [`memory/project_fgvad_demo_design.md`](../../../.claude/...) 笔记
> （用户本地 memory）。
