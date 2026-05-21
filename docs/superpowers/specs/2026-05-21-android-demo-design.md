# Android Demo 设计稿

**目标**：把 fgvad 库跨编到 Android NDK target，写 JNI 桥，做一个 1:1 复刻 iOS demo 交互的 Android demo。

**范围**：覆盖 iOS demo 全部能力——模式切换、参数面板、开始/停止录音、加载测试音频、Sentence list 按句试听。

**非目标**：

- 多 ABI 发布（仅 arm64-v8a）
- XCFramework 等价物（独立 AAR/Maven 发布）
- Compose UI（用 Views）
- Oboe 低延迟录音（用 AudioRecord）
- App finalizer / Cleaner 兜底（显式 `close()`）
- 加载 WAV 重跑时的 UI 进度条精细化（先够用即可）

## 设备 / 工具链

- 真机：小米 luming（型号 25067PYE3C），Android 16 (SDK 36)，arm64-v8a
- Android SDK：`~/Library/Android/sdk`
- NDK：`28.2.13676358`
- Rust target：`aarch64-linux-android`（脚本里自动 `rustup target add`）
- min SDK：26（Android 8.0）；target SDK：36

## ten-vad 上游 Android 支持

ten-vad 上游 [TEN-framework/ten-vad](https://github.com/TEN-framework/ten-vad) 提供
预编 Android `.so`：

| ABI | 大小 |
|---|---|
| arm64-v8a | 532 KB |
| armeabi-v7a | 373 KB |

无 x86_64 Android（模拟器跑不通）。本轮只 vendor `arm64-v8a`。

## 仓库布局

```
fgvad/
├── examples/
│   ├── ios/        ← 已存在
│   ├── macos/      ← 已存在
│   └── android/    ← 新增
│       ├── fgvad-jni/                                    # Rust crate (cdylib)
│       │   ├── Cargo.toml                                # depends on fgvad rlib
│       │   └── src/lib.rs                                # JNI exports
│       ├── FgVadDemo/                                    # Android Studio project
│       │   ├── app/
│       │   │   ├── src/main/
│       │   │   │   ├── java/io/fengur/fgvad/             # Kotlin wrapper
│       │   │   │   │   ├── FgVad.kt
│       │   │   │   │   ├── State.kt / EndReason.kt / Event.kt / ResultType.kt
│       │   │   │   │   └── Result.kt
│       │   │   │   ├── java/io/fengur/fgvaddemo/         # App
│       │   │   │   │   ├── MainActivity.kt
│       │   │   │   │   ├── SentenceAdapter.kt            # RecyclerView adapter
│       │   │   │   │   ├── AudioRecorder.kt              # AudioRecord wrapper
│       │   │   │   │   ├── WavReader.kt
│       │   │   │   │   ├── SentencePlayer.kt             # AudioTrack wrapper
│       │   │   │   │   └── DemoLogger.kt
│       │   │   │   ├── jniLibs/arm64-v8a/                # build script 拷贝产物
│       │   │   │   │   ├── libfgvad_android.so
│       │   │   │   │   └── libten_vad.so
│       │   │   │   ├── assets/short/                     # bundle 短测试 WAV
│       │   │   │   ├── res/layout/                       # XML layouts
│       │   │   │   └── AndroidManifest.xml
│       │   │   └── build.gradle.kts
│       │   ├── settings.gradle.kts
│       │   ├── gradlew / gradlew.bat
│       │   └── gradle/wrapper/
│       └── README.md
├── scripts/
│   └── build-android.sh                                  # 新增
└── vendor/
    └── ten-vad/
        └── Android/arm64-v8a/libten_vad.so               # 新增
```

App package: `io.fengur.fgvaddemo`。Library package: `io.fengur.fgvad`。

## 构建链路

### Rust 端

`fgvad/build.rs` 增加 android 分支，链 `vendor/ten-vad/Android/<abi>/libten_vad.so`：

```rust
"android" => link_android(&target),
```

`fgvad-jni` crate：

```toml
[package]
name = "fgvad-jni"
version = "0.1.0"
edition = "2021"

[lib]
name = "fgvad_android"
crate-type = ["cdylib"]

[dependencies]
fgvad = { path = "../../.." }
jni = "0.21"
```

### `scripts/build-android.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NDK="${ANDROID_NDK_HOME:-$HOME/Library/Android/sdk/ndk/28.2.13676358}"
PROFILE="${1:-debug}"

# 自动装 rustup target
rustup target list --installed | grep -q '^aarch64-linux-android$' || \
  rustup target add aarch64-linux-android

# NDK clang 当 linker（API 26）
TOOLCHAIN_BIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin"
export CC_aarch64_linux_android="$TOOLCHAIN_BIN/aarch64-linux-android26-clang"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$CC_aarch64_linux_android"

cd "$ROOT/examples/android/fgvad-jni"
if [[ "$PROFILE" == "release" ]]; then
  cargo build --target=aarch64-linux-android --release
else
  cargo build --target=aarch64-linux-android
fi

DEMO_LIBS="$ROOT/examples/android/FgVadDemo/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$DEMO_LIBS"
cp "$ROOT/target/aarch64-linux-android/$PROFILE/libfgvad_android.so" "$DEMO_LIBS/"
cp "$ROOT/vendor/ten-vad/Android/arm64-v8a/libten_vad.so"            "$DEMO_LIBS/"

echo "✓ Android .so 已就绪：$DEMO_LIBS"
"$TOOLCHAIN_BIN/llvm-readelf" -d "$DEMO_LIBS/libfgvad_android.so" | grep NEEDED
```

### Gradle 端

`build.gradle.kts` 锁 ABI、关 native build 集成：

```kotlin
android {
    namespace = "io.fengur.fgvaddemo"
    compileSdk = 36
    defaultConfig {
        applicationId = "io.fengur.fgvaddemo"
        minSdk = 26
        targetSdk = 36
        ndk { abiFilters += "arm64-v8a" }
    }
    // 不配 externalNativeBuild —— jniLibs 手工管理
}
```

不用 cargo-ndk / android-gradle-plugin-rust / CMake。Rust 改动手跑 `scripts/build-android.sh`。

### 开发流程

```
改 Rust → ./scripts/build-android.sh → cd examples/android/FgVadDemo && ./gradlew installDebug
改 Kotlin → ./gradlew installDebug
```

## JNI 桥的 API 形状

### Kotlin 端

```kotlin
package io.fengur.fgvad

class FgVad private constructor(private var handle: Long) : AutoCloseable {
    companion object {
        init { System.loadLibrary("fgvad_android") }

        fun newShort(headSilenceMs: Int, tailSilenceMs: Int, maxDurationMs: Int): FgVad
        fun newLong(
            headSilenceMs: Int, maxSentenceMs: Int, maxSessionMs: Int,
            tailInitMs: Int, tailMinMs: Int, enableDynamicTail: Boolean,
        ): FgVad
    }

    fun start()
    fun stop()
    fun reset()
    fun state(): State
    fun endReason(): EndReason
    fun process(samples: ShortArray, count: Int): List<Result>
    override fun close()
}

enum class State { Idle, Detecting, Started, Voiced, Trailing, End }
enum class EndReason { None, SpeechCompleted, HeadSilenceTimeout, MaxDurationReached, ExternalStop }
enum class Event { None, SentenceStarted, SentenceEnded, SentenceForceCut, HeadSilenceTimeout, MaxDurationReached }
enum class ResultType { Silence, SentenceStart, Active, SentenceEnd }

data class Result(
    val type: ResultType,
    val event: Event,
    val state: State,
    val endReason: EndReason,
    val isSentenceBegin: Boolean,
    val isSentenceEnd: Boolean,
    val streamOffsetSample: Long,
    /** 仅 SentenceEnded / SentenceForceCut 时 non-null，含整句 i16 PCM */
    val audioSamples: ShortArray?,
)
```

### Rust 端模式

句柄 = `Box::into_raw(...) as jlong`。`process` 返回 `Object[]`，每个元素是
`io/fengur/fgvad/Result` 的 Java 实例。内存策略：

- 入参 `samples`：`GetShortArrayCritical` 零拷贝读
- `view.audio_ptr/audio_len`：仅 SentenceEnded/SentenceForceCut 路径走
  `NewShortArray + SetShortArrayRegion` 拷贝；其他类型 audioSamples = null
- `FgVadResults` 在 native 函数返回前 `fgvad_results_free` 释放（borrowed 数据
  此时已拷贝完）

### 线程

- `FgVad` 实例非线程安全。Kotlin 端约定：`process()` 全在录音/重跑工作线程
  调用，UI 线程通过 `Handler.post` 回调
- `System.loadLibrary` 在 `companion object init` 触发——App 启动一次

### 生命周期

`AutoCloseable.close()` 显式释放。不依赖 finalizer / Cleaner。
Activity `onDestroy` 中显式调 `vad.close()`。

## UI 设计（1:1 翻 iOS）

UI 框架：**Android Views（XML 布局 + Kotlin）**。不用 Compose。

### 主屏 `activity_main.xml`

```
┌─────────────────────────────────────────┐
│ [短时 Short | 长时 Long]               │  MaterialButtonToggleGroup
│ <模式说明>                              │  TextView (hint)
├─────────────────────────────────────────┤
│ head_silence_timeout [3000]   ms       │  LinearLayout x N
│ tail_silence         [2000]   ms       │
│ max_duration         [30000]  ms       │
│ (长时切换：head/max_sentence/tail_init/tail_min)
│ 启用动态尾端点曲线   [✓]                │  SwitchCompat (long-only)
├─────────────────────────────────────────┤
│ [开始录音]                              │  Button
│ [加载测试音频]                          │  Button
├─────────────────────────────────────────┤
│ 状态：录音中 · 3 句 · ...               │  TextView
├─────────────────────────────────────────┤
│ Sentence 1 │ SentenceEnded ▶ │ ts       │  RecyclerView + item layout
│ Sentence 2 │ ForceCut       ▶ │ ts       │
│ ...                                      │
└─────────────────────────────────────────┘
```

### 控件映射

| iOS | Android |
|---|---|
| `UISegmentedControl` | `MaterialButtonToggleGroup` |
| `UITextField`(numbers) | `EditText` + `inputType="number"` |
| `UISwitch` | `SwitchCompat` |
| `UIButton` | `Button` |
| `UILabel` | `TextView` |
| `UITableView` | `RecyclerView` + `LinearLayoutManager` |
| `AVAudioPlayer` | `AudioTrack`（裸 PCM 直播） |

### 录音

`AudioRecord`，16 kHz mono PCM_16BIT。工作线程 read 进 `ShortArray`，
~64ms/坨（1024 样本），喂 `fgvad.process()`。权限：
`RECORD_AUDIO`，运行时申请。

### 测试音频

| 来源 | 路径 | 用途 |
|---|---|---|
| Assets bundle | `assets/short/01-06-*.wav` | APK 自带，6 个短 case |
| External files | `getExternalFilesDir(null)/long/yixi-*.wav` | adb push，长测试 |

"加载测试音频"按钮里两类并列展示（dialog），用户选哪个跑哪个。

### 按句试听

`SentenceEnded`/`SentenceForceCut` 收到的 `audioSamples` 缓存到
`Sentence` 模型；点 ▶ 时 `AudioTrack.write(samples, ...)` 直播。

## 日志

固定路径：

```
/sdcard/Android/data/io.fengur.fgvaddemo/files/run.log
```

App 启动 truncate。每行 `<timestamp> <level> <event>`。
开发机 `adb pull` 出来 Read。
不依赖 logcat（日志要可持久化、可 grep、可对比 iOS 同 wav 跑出来的事件流）。

## 验证（按实施顺序）

1. **跨编 + load**：APK 装机，logcat 看 `System.loadLibrary("fgvad_android")` 不抛
   `UnsatisfiedLinkError`；`nativeNewLong / nativeFree` 调用一次干净返
2. **录音通链路**：Start 后说"喂喂喂"，run.log 里看到 `SentenceStarted` →
   `SentenceEnded` 序列
3. **iOS 对照硬指标**：长 yixi `adb push` 到设备，长时模式重跑，**期望
   ~85 句，ForceCut ≤ 6 个**（README 里那张 baseline 表）。Android 跑出
   显著不同 = bug
4. **按句试听**：点 ▶，AudioTrack 出声，跟 iOS 同句对比
5. **参数面板生效**：`head_silence_timeout=500` + 不开口 → `HeadSilenceTimeout`
   ~500ms 触发

第 3 项是验收硬指标。

## 风险与已知坑

- **`darwin-x86_64` toolchain 路径**：Apple Silicon Mac 的 NDK 实际是 arm64
  原生，但 toolchain 目录仍叫 `darwin-x86_64`（NDK 沿用旧名）。脚本里写死，
  不要改成 `darwin-arm64`
- **JNI throw 处理**：Rust 里 panic 会冲过 JNI 边界 UB。所有 native 函数包一层
  `catch_unwind`，panic 转 IllegalStateException
- **`System.loadLibrary` 顺序**：`libfgvad_android.so` 依赖 `libten_vad.so`。
  Android linker 自动按 `DT_NEEDED` 解析，**前提是两份 .so 都在 jniLibs 同
  目录**。手工放置时不能漏
- **AudioRecord buffer 欠 read**：read 慢于录音速率会丢数据。工作线程必须
  紧凑，不要在 read 循环里干 UI 或重活（process 已经够快，但仍要警惕）
- **49MB WAV 不能进 APK assets**：assets 单文件 < 4GB 但 APK 总大小受 Play
  Store 限制，且测试音频经常变。固定外部存储路径绕开

## 路线图（本设计稿之外）

- [ ] armeabi-v7a 32-bit 支持（兼容老设备）
- [ ] AAR 发布（独立分发，类似 iOS XCFramework）
- [ ] Oboe 低延迟录音替代 AudioRecord
- [ ] 概率曲线 + 动态 tail 曲线可视化（跟 iOS demo 路线图同步）
