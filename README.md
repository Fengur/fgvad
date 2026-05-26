# fgvad
> [English](README.en.md) | 中文

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

**公式**（线性递减 + clamp）：

```
tail_ms(t) = max( initial × (1 − t / max_sentence) , min )

t = 当前句已累计毫秒数
initial = tail_silence_initial（典型 2000ms）
min = tail_silence_min（典型 600ms）
max_sentence = max_sentence_duration_ms（典型 30000ms）
```

举例（initial=2000, min=600, max_sentence=30000）：

```
 tail_ms
  2000 ┤●━━┓                  开头宽容（用户刚开口，停顿大概率是想词）
       │   ┃
       │    ╲
       │     ╲
  1000 ┤      ╲
       │       ╲
   600 ┤────────●━━━━━━━━━━━  撞下限后保持（已经讲了 21s+，
       │                       灵敏分句优先）
       └───────────────────── current_sentence_ms
       0       15s   21s    30s
                            (强切)
```

**为什么这条曲线是核心**：用恒等阈值（关掉动态曲线 = `tail_ms` 永远 = 2000ms）跑一席演讲实测，87% 的句子被 30s `max_sentence` 强切——平均句长贴上限分布，VAD 实际失效。开启动态曲线后强切占比降到 5.9%（85 句中 5 句强切），平均句长落在自然语义边界上。

具体推导：人说话的"语义停顿"长度随句子时长缩短（开头犹豫思考几秒，讲到中段停顿往往 < 1s），固定 2000ms 在中段就太宽，必然撞 max；从 initial 线性收到 min 让阈值跟语义停顿一起变化。

源码见 `src/state_machine.rs::current_tail_frames`。`enable_dynamic_tail = false` 时退化为恒等阈值（用于对照实验）。

### `SentenceEnded` vs `SentenceForceCut` —— 两个独立事件

| 事件 | 触发条件 | 业务含义 |
|---|---|---|
| `SentenceEnded` | 尾静音累计 ≥ `tail_ms(t)`（动态曲线当前阈值） | **自然结束**：用户说完了 |
| `SentenceForceCut` | 单句长度 ≥ `max_sentence_duration_ms` | **强切**：用户讲太长被打断 |

两个事件都带这一句的完整 PCM。设计意图是让消费方区分"用户表达完整"和"被库截断"——后者通常意味着句子语义被切坏，下游 ASR 拼接逻辑应特殊处理（比如把这句和下一句拼起来重识别）。

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

## 当前状态

| 平台 | Demo | 库构建脚本 | 公开分发(集成方接入) |
|---|---|---|---|
| **macOS 13+**(arm64 + x86_64 universal) | ✅ AppKit Demo([macOS README](./examples/macos/README.md)) | `build-macos-universal.sh` | SPM URL([v0.1.0+](https://github.com/Fengur/fgvad/releases/tag/v0.1.0))+ 手动 XCFramework |
| **iOS 16+**(device + simulator) | ✅ UIKit Demo([iOS README](./examples/ios/README.md))真机 24 分钟连续录音验过 | `build-ios.sh`(device + sim 双 slice) | SPM URL + CocoaPods([v0.1.0+](https://github.com/Fengur/fgvad/releases/tag/v0.1.0))+ 手动 XCFramework |
| **Android API 26+**(arm64-v8a) | ✅ Views Demo([Android README](./examples/android/README.md)) | `build-android.sh`(NDK + JNI) | JitPack([v0.2.0+](https://jitpack.io/#Fengur/fgvad)) |
| **C/C++**(macOS) | ✅ CMake CLI Demo([C README](./examples/c/README.md)) | `cargo build` + `xcodebuild -create-xcframework` | 仓库内 `examples/c/` 参考接入 |
| Linux / Windows / WASM | — | — | 暂不计划 |

**输入约束**:仅 16 kHz / 单声道 / i16 PCM
**噪声**:办公室级别(−50 dBFS)够用;餐厅/车载/户外推荐补一层 energy gate 前置(路线图)
**v0.1.0** 发布 SPM + Pod + 手动 XCFramework 三种 iOS/macOS 接入;**v0.2.0** 加入 Android 通过 JitPack 一行接入。详见 [Installation](#installation)。

## 路线图

- [ ] 概率曲线 + 动态 tail 曲线 + 角色色带的可视化（Demo）
- [ ] energy gate 前置过滤（噪声鲁棒性）
- [x] iOS 库构建支持（device + simulator）
- [x] iOS Demo（最小录音 + VAD）
- [x] iOS XCFramework 打包脚本（`scripts/build-xcframework.sh`，含 macOS 三 slice）
- [x] Android 构建支持（NDK + JNI bridge）
- [x] Android Demo（含按句试听 + 测试 WAV 重跑）
- [x] CocoaPods / SPM 分发 —— v0.1.0 起，详见 [Installation](#installation)
- [x] Android 分发（JitPack） —— v0.2.0 起，详见 [Installation](#installation)
- [x] 纯 C CLI 集成示例 —— 见 [`examples/c/`](./examples/c/)（macOS 已支持；Linux/embedded 待后续）
- [ ] 底层引擎深度调优 advanced API（按需暴露 ten-vad 内部参数 / 切换 VAD 引擎，详见下节）

## 设计哲学与未来计划

### 核心是思路，不是 ten-vad

fgvad 想传达的是 **做 ASR-friendly VAD 的方法论**，不是"ten-vad 的 Swift / Kotlin 封装层"。三块核心能力其实跟底层引擎选型无关：

- **动态尾端点曲线** —— `tail_ms(t) = max(initial × (1 − t/max), min)` 线性递减，"开头宽容、越说越紧"。任何能输出 voice / silence 帧概率的 VAD 都能套这条曲线
- **状态机** —— Idle / Detecting / Started / Voiced / Trailing / End 六态 + 短/长时双语义，把"端点检测"分解成可观测的事件流
- **通知 vs 控制事件** —— 同一个 endpoint 信号（`HeadSilenceTimeout` 等）在长时/短时下意义完全不同，API 设计上必须区分

如果你选 [Silero VAD](https://github.com/snakers4/silero-vad) / [WebRTC VAD](https://github.com/wiseman/py-webrtcvad) / 自家训练的模型作为底层 voice/silence 帧分类器，把 fgvad 的状态机和动态曲线移植过去，**核心竞争力依然成立**。本仓库的 Rust 状态机（`src/state_machine.rs`）+ 测试集（49 个 cargo test）可以作为参考实现。

ten-vad 是当前默认选择 —— 体积小（~5MB framework）、推理快、五语种通用，且有现成的 macOS / iOS / Android 预编译二进制可 vendor。但它不是这个项目的灵魂。

### 底层引擎参数当前不暴露

`FgVadAnalyzer` 公开的参数**全部是状态机层面的语义参数**（`headSilenceTimeoutMs` / `tailSilenceMsInitial` 等），不直接透传 ten-vad 内部的 threshold / frame size / 模型变体等实现细节。

理由：让集成方专注于"端点策略"调参，不被底层引擎实现细节牵走。fgvad 内部的常量（[鲁棒性参数](#鲁棒性参数已对齐业界)章节列出的 THRESHOLD = 0.5、CONFIRM_FRAMES = 16 等）已经过对照实验收敛，办公室级别噪声场景默认值即可。

未来如果出现"深度调优"需求 —— 比如极端噪声场景需要直接动底层 probability threshold，或者切换到不同 VAD 引擎变体 —— **会通过独立的 advanced API 暴露**（如 `FgVadAnalyzer.Advanced(...)` 或类似），不污染当前主 API。这条对应路线图里 "energy gate 前置过滤" 那项的下游设计空间。

## Installation

### Swift Package Manager（推荐）

支持 **iOS 16+** / **macOS 13+**。

```swift
// Package.swift dependencies:
.package(url: "https://github.com/Fengur/fgvad.git", from: "0.1.0")
```

target 依赖：

```swift
.product(name: "Fgvad", package: "fgvad")
```

Xcode 集成：File → Add Package Dependencies，粘贴 URL `https://github.com/Fengur/fgvad.git`。

**开发期 fgvad 本仓库内** 的 demo / 测试要走本地 dist/ 不走远程下载，跑 `swift build` 前 export：

```bash
export FGVAD_LOCAL_BINARIES=1
```

### CocoaPods（仅 iOS 16+）

```ruby
# Podfile
pod 'Fgvad', :git => 'https://github.com/Fengur/fgvad.git', :tag => 'v0.1.0'
```

`pod install` 时会自动下载 GitHub Release 上的 XCFramework zip 并解压。**macOS 不走 Pod**，请用 SPM 接入（同一个库，同一个 API）。

### Android（JitPack）

支持 **Android API 26+ / arm64-v8a**。集成方在 `settings.gradle.kts` 加 JitPack maven 仓库:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}
```

`app/build.gradle.kts` 加依赖:

```kotlin
dependencies {
    implementation("com.github.Fengur:fgvad:v0.2.0")
}
```

Kotlin 调用示例:

```kotlin
import io.fengur.fgvad.FgVad

val vad = FgVad.newShort(FgVad.ShortConfig(
    headSilenceMs = 3000,
    tailSilenceMs = 2000,
    maxDurationMs = 30000,
))
vad.start()
val results = vad.process(samples)  // ShortArray (16kHz mono i16)
for (r in results) {
    if (r.event == Event.SentenceEnded) {
        // r.audioSamples 是这一句的整段 PCM
    }
}
vad.stop()
vad.close()
```

### 手动 XCFramework

下载 [v0.1.0 Release](https://github.com/Fengur/fgvad/releases/tag/v0.1.0) 的两个 zip：
- `FgvadCore.xcframework.zip`
- `ten_vad.xcframework.zip`

解压后两个 `.xcframework` 拖进 Xcode 项目，Embed & Sign。Swift wrapper 源码也要拷一份（从 [`Sources/Fgvad/FgVadAnalyzer.swift`](./Sources/Fgvad/FgVadAnalyzer.swift) 拷到自己工程）。

### 接入示例

fgvad 是流式 API，调用三段对齐 ASR 客户端的 **begin / 中间包 / 尾包** 心智。**短时和长时两种模式的事件处理逻辑不同，分别给完整示例**：

#### 短时模式（命令 / 查询场景）

一次 `start` 对应**一句话**。VAD 内部判停后 state 自动转 End，外部按 state 收尾即可。

```swift
import Fgvad

// 1. begin
let analyzer = try FgVadAnalyzer(mode: .short(.init(
    headSilenceTimeoutMs: 3_000,    // 没开口超时直接放弃
    tailSilenceMs: 2_000,           // 尾静音 2s 就认为说完了
    maxDurationMs: 30_000,          // 单次最多录 30s
)))
analyzer.start()

// 2. 中间包 —— chunk 持续喂(典型 20-100ms / chunk)
recorder.onChunk = { chunk in
    let results = try chunk.withUnsafeBufferPointer { try analyzer.feed($0) }
    for r in results {
        if r.event == FgVadEvent_SentenceStarted {
            // 启动 ASR 会话(发首包)
        }
        if r.type == FgVadResultType_SentenceEnd {
            // 发尾包 + 等识别结果
            // r.audioLen 个采样是这句完整 PCM
        }
        // 短时下其他事件(HeadSilenceTimeout / MaxDurationReached)
        // 都是控制信号 —— 不用单独处理,下面 state == End 统一收尾
    }

    // 3. end —— 短时所有终止路径汇聚到 state == End
    if analyzer.state == FgVadState_End {
        analyzer.stop()
        recorder.stop()

        // analyzer.endReason 告诉你具体哪种终止:
        //   .speechCompleted   —— 用户正常说完
        //   .headSilenceTimeout —— 没开口就超时放弃
        //   .maxDurationReached —— 撞 30s 上限被强停
        //   .externalStop      —— 外部主动 stop()
    }
}
```

#### 长时模式（连续听写场景）

一次 `start` 对应**多句连续**。state 不会自动转 End，只在外部 `stop()` 或 `max_session_duration` 终止。`HeadSilenceTimeout` 是 prompt 用户的通知，不结束会话。

```swift
import Fgvad

// 1. begin
let analyzer = try FgVadAnalyzer(mode: .long(.init(
    headSilenceTimeoutMs: 3_000,         // 提示用户的间隔(周期性 prompt)
    maxSentenceDurationMs: 30_000,       // 单句撞此值强切(吐 SentenceForceCut)
    maxSessionDurationMs: 0,             // 0 = 整会话不限时长
    tailSilenceMsInitial: 2_000,         // 动态尾端点初始值
    tailSilenceMsMin: 600,               // 动态尾端点下限
    enableDynamicTail: true,             // 启用动态曲线(关掉会让 87% 句子被强切)
)))
analyzer.start()

// 2. 中间包
recorder.onChunk = { chunk in
    let results = try chunk.withUnsafeBufferPointer { try analyzer.feed($0) }
    for r in results {
        if r.event == FgVadEvent_SentenceStarted {
            // 启动新一轮 ASR 会话(每句一轮)
        }
        if r.type == FgVadResultType_SentenceEnd {
            // 发尾包 + 等识别结果(继续等下一句)
            // r.audioLen 是这句完整 PCM
            // r.event == FgVadEvent_SentenceForceCut 时,UX 上提示"被强切"
        }
        if r.event == FgVadEvent_HeadSilenceTimeout {
            // 长时的通知事件:周期性 prompt 用户
            //   例如 UI 上显示"您已经 3 秒没说话了"
            // 不要停录音,会话继续
        }
    }

    // 长时不看 state == End —— 没人主动 stop 它永远不会到 End
    // (除非显式设了 max_session_duration_ms 撞上限)
}

// 3. end —— 长时典型路径:用户主动停录音
recorder.onStop = {
    analyzer.stop()
    // stop() 时如果还在 Active 段,下一次 feed (空 chunk 也行) 会触发
    // ExternalStop 路径吐"人造尾包"。如果 stop 后不再 feed,
    // 那段 audio 就丢了 —— 推荐 stop 前最后喂一次空 chunk:
    //
    //   try [].withUnsafeBufferPointer { try analyzer.feed($0) }
    //   analyzer.stop()
}
```

**关键区别**:

| 关注点 | 短时 | 长时 |
|---|---|---|
| 终止判断 | `state == End`(所有终止都汇聚到这) | 外部 `stop()` / 撞 `max_session` |
| `HeadSilenceTimeout` | 控制信号(state 自动转 End) | 通知事件(prompt 用户,不停) |
| `SentenceEnd` 触发后 | 关录音(单句模式只有一句) | 继续录音等下一句 |
| 典型时长 | 数秒~30s | 数分钟到不限 |

### 事件 → 业务动作映射

同一个事件在两种模式下意义完全不同 —— 这是 fgvad 设计的核心。集成方按下表对接业务：

| 事件 | 短时模式（撞哪个参数） | 长时模式（撞哪个参数） |
|---|---|---|
| `SentenceStarted` | 启动 ASR 识别(发首包) | 启动新一轮 ASR 识别(多句连续,每句一轮) |
| `SentenceEnded` | **关闭录音** + 发尾包 —— 撞 `tailSilenceMs`(默认 2000ms) | 发尾包,**继续录音**等下一句 —— 撞动态曲线(`tailSilenceMsInitial` 2000ms 收到 `tailSilenceMsMin` 600ms) |
| `SentenceForceCut` | (短时不触发,短时只有一句) | 发尾包,**继续录音**(用户讲太长被切) —— 撞 `maxSentenceDurationMs`(默认 30000ms) |
| `HeadSilenceTimeout` | **关闭录音** —— 用户没开口放弃 —— 撞 `headSilenceTimeoutMs`(默认 3000ms,触发即结束) | **提示用户**"您 N 秒没说话了",**不停录音** —— 每 `headSilenceTimeoutMs`(默认 3000ms)周期性提示 |
| `MaxDurationReached` | **关闭录音** —— 撞 `maxDurationMs`(默认 30000ms) | **关闭整个会话** —— 撞 `maxSessionDurationMs`(**默认 0 = 不限,需显式设非零才触发**) |

**判尾包看 `r.type` 不要看 `r.event`**：库把所有"尾包语义"——SentenceEnded（自然）/ SentenceForceCut（单句强切）/ MaxDurationReached + ExternalStop 触发时还在说话的"人造尾包"——统一打到 `r.type == SentenceEnd`。`r.event` 只用来细分**原因**（要不要给用户 UX 提示"被强切了"）。

**核心差异 —— `HeadSilenceTimeout` 在两种模式下天差地别**：
- 短时下是 **控制信号**：state 直接转 End，会话终止 → 你应当关录音
- 长时下是 **通知事件**：state 不变，会话继续 → 你应当 prompt 用户但**不动录音**

短时模式所有终止路径都汇聚到一个观测点：`analyzer.state == FgVadState_End`。判断该不该关录音直接看这个 state，不需要按事件分支。

长时模式的终止只有两条：外部 `stop()`（用户主动停）或 `MaxDurationReached`（会话总时长到）。`HeadSilenceTimeout` 永远只是通知。

### 批式回放

不流式跑也行 —— 调参 / 回归测试常用：

```swift
let (results, finalState, endReason) = try FgVadAnalyzer.analyze(
    samples: pcm, mode: .short(.init())
)
```

整段 PCM 喂进去，吐所有 results + 最终 state + endReason。

## License

MIT —— 见 [LICENSE](./LICENSE)。底层 ten-vad 遵循 Apache 2.0。
