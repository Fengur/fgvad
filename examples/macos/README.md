# FgVadDemo —— fgvad 的 macOS 测试工具

AppKit + SnapKit。既是对外的使用示例，也是调试/调参的主力工具。

## 构建方式

```bash
# 生成 Xcode 工程（改了 project.yml 后再跑）
cd examples/macos
xcodegen generate

# 用 Xcode 打开，或命令行构建
open FgVadDemo.xcodeproj
# 或
xcodebuild -project FgVadDemo.xcodeproj -scheme FgVadDemo -configuration Debug build
```

**Demo 构建会自动调用 `scripts/build-macos-universal.sh`**——它内部跑两次
`cargo build`（aarch64-apple-darwin + x86_64-apple-darwin）+ `lipo` 合成
universal libfgvad.dylib 到 `target/universal-apple-darwin/debug/`，再被
post-build 脚本拷到 .app/Contents/Frameworks。**Demo 因此能在 Apple Silicon
和 Intel Mac 上都跑**。

首次构建时若缺 x86_64 rustup target，脚本会自动 `rustup target add` 一下。

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

## 当前功能

- **短/长时模式切换**（顶部 segmented control）
- **参数面板**：head_silence_timeout / tail_silence / max_duration / 长时
  独有的 tail_silence_initial / tail_silence_min / 启用动态尾端点曲线
  开关
- **流式录音**：边录边喂 VAD，短时遇 SentenceEnd 自动停
- **加载 WAV 重跑**：用当前模式 + 参数对已有 WAV 批式回灌（处理期间转圈
  + 锁住关键交互入口）
- **句子列表**：每句一行 `Sentence N  mm:ss.mmm – mm:ss.mmm  事件标签 ▶`
  ——ForceCut 橙色、SentenceEnded 绿色，▶ 后台切片 + 临时 WAV +
  AVAudioPlayer 试听
- **录音中实时 tick**：耗时 + state + 累计句数
- **结束原因中文化**："说完了（尾静音达标）"、"未听到说话（头部静音超时）"、
  "达到最大时长上限"、"手动停止"
- **调试日志**：`~/Library/Logs/FgVadDemo/run.log`（每次启动 truncate）

## 待补充

- 概率曲线 + 动态 tail 曲线 + 角色色带的可视化（路线图，可选 polish）

---

> 具体设计参见 [`memory/project_fgvad_demo_design.md`](../../../.claude/...) 笔记
> （用户本地 memory）。
