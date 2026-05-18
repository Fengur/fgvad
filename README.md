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
cargo build       # libfgvad.dylib + 通过 build.rs 链接 ten-vad
cargo test        # 端到端集成测试
```

构建产物：

- `target/debug/libfgvad.dylib`
- `include/fgvad.h`（cbindgen 自动生成）
- 内嵌的 `vendor/ten-vad/macOS/ten_vad.framework`

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

详见 [`test-data/README.md`](./test-data/README.md) 和
[`test-data/short/README.md`](./test-data/short/README.md)。

## 鲁棒性参数（已对齐业界）

| 参数 | 值 | 说明 |
|------|----|----|
| `THRESHOLD` | 0.5 | ten-vad probability 阈值，对齐 Silero 默认 |
| `CONFIRM_FRAMES` | 16 帧 (256ms) | 头端点防抖，对齐 Silero `min_speech_duration_ms` |
| `RESUME_CONFIRM_FRAMES` | 5 帧 (80ms) | 尾端点防抖。**fgvad 原创**——业界 VAD 库做 segmentation 不需要，但 endpointing（tail 1-2s 的语义级判停）必须有 |
| `PRE_ROLL_FRAMES` | 16 帧 (256ms) | SentenceStart 往前带 250ms 音频，给下游识别器留足上下文 |

## 当前状态与限制

- **平台**：macOS arm64 构建脚本就绪。iOS / Linux / Windows / Android / WASM
  待补（ten-vad 这些平台都有预编译库，主要工作量在 build.rs 分支处理 +
  各平台 Recorder 实现）
- **输入**：仅 16 kHz / 单声道 / i16 PCM
- **噪声**：当前对办公室级别（−50 dBFS）背景噪声够用；餐厅/车载/户外场景
  下推荐补一层 energy gate 前置（路线图）

## 路线图

- [ ] 概率曲线 + 动态 tail 曲线 + 角色色带的可视化（Demo）
- [ ] energy gate 前置过滤（噪声鲁棒性）
- [ ] iOS / Linux / Windows / Android / WASM 构建支持
- [ ] CocoaPods / SPM / XCFramework 分发

## License

MIT —— 见 [LICENSE](./LICENSE)。底层 ten-vad 遵循 Apache 2.0。
