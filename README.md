# fgvad

智能 VAD 库——在 [ten-vad](https://github.com/TEN-framework/ten-vad) 神经网络
VAD 之上封装状态机和**动态端点策略**，让"短时命令"和"长时听写"两种使用
场景都有合理的语义切分。

设计思路来源于作者过去做语音 SDK 的工作经验。

## 它解决什么

ten-vad 本身只输出"这一帧是不是 voice"的概率，要做"切句"还需要一层端点
策略。难点在于：

- **短时**（命令、查询）希望尾静音几秒就果断结束
- **长时**（听写、连续口述）不能因为短停顿就切断，但又得在足够久的停顿处
  准确分句

fgvad 用一条**动态尾端点曲线**统一处理这两种场景。在朱志偉一席演讲
25:30 长时模式实测：

| 配置 | 句数 | ForceCut | ForceCut 占比 |
|---|---|---|---|
| 启用动态曲线 | 85 | 5 | 5.9% |
| 关闭（恒等 `tail_silence_initial=2000ms`） | 53 | 46 | **87%** |

关闭动态曲线时，VAD 几乎只能靠 30s 强切来分句，平均句长贴着上限分布
——**连续语音场景下基本不可用**。这条曲线是 fgvad 的核心竞争力。

复现方法：

```bash
cd examples/macos
xcodegen generate && xcodebuild -scheme FgVadDemo build
# Demo 启动后，长时模式 → 加载 WAV 重跑 → 选 test-data/long/yixi-zhuzhiwei-typography.wav
# 切换"启用动态尾端点曲线"对比两次结果
```

## 核心概念

### 短时模式（命令/查询）

- 一次 `start` → 单段语义 → 尾静音达标即结束整个会话
- `head_silence_timeout` 是 **控制信号**——不开口直接结束（`HeadSilenceTimeout`）
- `tail_silence` 是固定阈值（典型 2000ms）
- `max_duration` 是会话总长上限（典型 30000ms），到点强切（`MaxDurationReached`）

### 长时模式（听写/连续口述）

- 一次 `start` → 多段连续切分 → 不结束直到外部 `stop()` 或 `max_session_duration`
- `head_silence_timeout` 只是 **通知事件**——周期性提示 consumer，会话不结束
- `max_sentence_duration` 是 **单句** 上限——撞到则切出一句（`SentenceForceCut`），
  会话继续
- 尾静音阈值是动态曲线（见下）

### 动态尾端点曲线（长时核心）

随说话累积时长，尾静音阈值从 `tail_silence_initial`（如 2000ms）逐步收紧
到 `tail_silence_min`（如 600ms）。**开始宽容、越说越紧**，兼顾"开头别切
早"和"中段灵敏分句"。

## 快速上手

### 构建

```bash
# macOS：当前主机架构构建（Apple Silicon → arm64；Intel Mac → x86_64）
cargo build

# macOS universal binary（arm64 + x86_64 lipo）
./scripts/build-macos-universal.sh             # debug
./scripts/build-macos-universal.sh --release   # release

# iOS（device + simulator 各编一份）
./scripts/build-ios.sh                         # debug
./scripts/build-ios.sh --release               # release

cargo test                                     # 端到端集成测试（macOS only）
```

构建产物：

- `target/<host>/debug/libfgvad.dylib` —— 单架构（默认 cargo build）
- `target/universal-apple-darwin/debug/libfgvad.{dylib,a}` —— 双架构 universal（脚本产物）
- `target/aarch64-apple-ios/debug/libfgvad.{dylib,a}` —— iOS device
- `target/aarch64-apple-ios-sim/debug/libfgvad.{dylib,a}` —— iOS Simulator
- `include/fgvad.h`（cbindgen 自动生成）
- 内嵌的 ten-vad framework：
  - `vendor/ten-vad/macOS/ten_vad.framework`（universal）
  - `vendor/ten-vad/iOS/device/ten_vad.framework`（arm64 device）
  - `vendor/ten-vad/iOS/simulator/ten_vad.framework`（arm64 simulator，vtool 重打 platform 标记，详见 vendor 内 README）

### 跑 macOS Demo

```bash
cd examples/macos
xcodegen generate
xcodebuild -scheme FgVadDemo -configuration Debug build
open $(find ~/Library/Developer/Xcode/DerivedData -name FgVadDemo.app | head -1)
```

Demo 提供：短/长模式切换、参数实时调节、流式录音、加载 WAV 重跑、句子
列表 + 按句试听、调试日志写到 `~/Library/Logs/FgVadDemo/run.log`。详见
[`examples/macos/README.md`](./examples/macos/README.md)。

### 跑 Android Demo

```bash
cd examples/android/FgVadDemo
../../../scripts/build-android.sh           # 编 fgvad-jni 并拷 .so
adb push ../../../test-data/long/yixi-zhuzhiwei-typography.wav \
  /sdcard/Android/data/io.fengur.fgvaddemo/files/long/
./gradlew :app:installDebug
adb shell am start -n io.fengur.fgvaddemo/.MainActivity
```

启动后：长时模式 → 加载测试音频 → `[external] long/yixi-...` → 等解析完成。

### C 接入最小例子

```c
#include "fgvad.h"

// 长时模式实例
struct FgVad* vad = fgvad_new_long(
    /* head_silence_timeout_ms  */ 3000,
    /* max_sentence_duration_ms */ 30000,
    /* max_session_duration_ms  */ 0,        // 0 = 不限
    /* tail_silence_ms_initial  */ 2000,
    /* tail_silence_ms_min      */ 600,
    /* enable_dynamic_tail      */ true
);
fgvad_start(vad);

// 喂 PCM（16 kHz mono i16）
int16_t pcm[16000];  // 1 秒
struct FgVadResults* results = fgvad_process(vad, pcm, 16000);

for (uintptr_t i = 0; i < fgvad_results_count(results); i++) {
    struct FgVadResultView v = fgvad_result_view(results, i);
    if (v.event == FgVadEvent_SentenceEnded || v.event == FgVadEvent_SentenceForceCut) {
        // 一段完整语音：v.audio_ptr [0, v.audio_len)
        // 时间戳基准：v.stream_offset_sample（自 start 起的样本数）
    }
}
fgvad_results_free(results);

fgvad_stop(vad);
fgvad_free(vad);
```

短时模式构造函数是 `fgvad_new_short(head_silence_timeout, tail_silence,
max_duration)`。完整 API 见 [`include/fgvad.h`](./include/fgvad.h)。

## 测试集

`test-data/` 下提供已落库的真实音频，clone 完直接可复现实验：

- **`long/yixi-zhuzhiwei-typography.wav`** —— 25:33 一席演讲（朱志偉
  《字體的力量》），长时模式核心基线，动态曲线对照实验素材
- **`short/01-06-*.wav`** —— 短时模式 6 个合成 case，覆盖
  `HeadSilenceTimeout` / `SpeechCompleted` / `MaxDurationReached` 三条
  endReason 路径加 2 个边界（短停顿合并、CONFIRM_FRAMES 边界）

详见 [`test-data/README.md`](./test-data/README.md)、
[`test-data/long/README.md`](./test-data/long/README.md) 和
[`test-data/short/README.md`](./test-data/short/README.md)。

## 测试

`cargo test` 跑全套 49 个测试（含 unit + 集成两层）：

| 测试文件 | 数量 | 内容 |
|---------|------|------|
| `src/lib.rs` (`#[test]`) | 32 | 状态机 / 动态曲线 / FFI 等单元测试 |
| `tests/real_audio.rs` | 4 | 短时模式端到端（ten-vad 官方 fixture） |
| `tests/long_mode.rs` | 4 | 长时模式 + ForceCut + ExternalStop |
| `tests/short_mode_cases.rs` | 6 | 短时 6 个合成 case 一一断言 endReason |
| `tests/long_mode_yixi.rs` | 3 | 长时动态曲线对照实验（25 分钟一席演讲）|

最关键的契约级断言是 `dynamic_curve_substantially_reduces_force_cut_ratio`
——若动态曲线公式被改坏，ON 模式 ForceCut 占比会超 10% 或不再显著低于
OFF，cargo test 当场拦下。这条断言对应"它解决什么"那张
85/5 vs 53/46 表里的设计意图。

性能：yixi 长时 3 个测试需要每次把 24M sample 喂进 ten-vad，单线程
~2-3 分钟；其他全部秒级。CI 上跑完整 cargo test 可接受。

## 鲁棒性参数（已对齐业界）

| 参数 | 值 | 说明 |
|------|----|----|
| `THRESHOLD` | 0.5 | ten-vad probability 阈值，对齐 Silero 默认 |
| `CONFIRM_FRAMES` | 16 帧 (256ms) | 头端点防抖，对齐 Silero `min_speech_duration_ms` |
| `RESUME_CONFIRM_FRAMES` | 5 帧 (80ms) | 尾端点防抖。**fgvad 原创**——业界 VAD 库做 segmentation 不需要，但 endpointing（tail 1-2s 的语义级判停）必须有 |
| `PRE_ROLL_FRAMES` | 16 帧 (256ms) | SentenceStart 往前带 250ms 音频，给下游识别器留足上下文 |

## 当前状态与限制

- **macOS universal（arm64 + x86_64）**：✅ 已支持。`scripts/build-macos-universal.sh`
  双架构 lipo，单产物兼容 Apple Silicon 和 Intel Mac。Demo bundle 嵌入的 fgvad
  已是 universal
- **iOS（device + simulator）**：✅ 库构建链路 + Demo 都已通。`scripts/build-ios.sh`
  同时产出 `aarch64-apple-ios`（device）和 `aarch64-apple-ios-sim`（simulator）
  两份产物，链接对应平台的 ten_vad.framework。`examples/ios/FgVadDemo/` 是
  最小录音 demo，UIKit + 复用 OC RemoteIO AU 录音器，已验证在 iPhone 17 Pro
  Simulator 跑得起来。**XCFramework 打包脚本待补**
- **Android（arm64-v8a）**：✅ 已支持。`scripts/build-android.sh` 交叉编译 + JNI bridge，
  min SDK 26。`examples/android/FgVadDemo/` 功能对齐 iOS Demo（录音、加载 WAV 重跑、
  按句试听、日志写文件）。详见 [`examples/android/README.md`](./examples/android/README.md)
- **Linux / Windows / WASM**：暂不计划
- **输入**：仅 16 kHz / 单声道 / i16 PCM
- **噪声**：当前对办公室级别（−50 dBFS）背景噪声够用；餐厅/车载/户外场景
  下推荐补一层 energy gate 前置（路线图）

## 路线图

- [ ] 概率曲线 + 动态 tail 曲线 + 角色色带的可视化（Demo）
- [ ] energy gate 前置过滤（噪声鲁棒性）
- [x] iOS 库构建支持（device + simulator）
- [x] iOS Demo（最小录音 + VAD）
- [ ] iOS XCFramework 打包脚本（用于对外分发）
- [x] Android 构建支持（NDK + JNI bridge）
- [x] Android Demo（含按句试听 + 测试 WAV 重跑）
- [ ] CocoaPods / SPM 分发
- [ ] 纯 C CLI 集成示例（验证 cbindgen 头文件在真实 C 编译里没 bug，给 Linux/embedded/C++ 集成方留个参考样板）

## License

MIT —— 见 [LICENSE](./LICENSE)。底层 ten-vad 遵循 Apache 2.0。
