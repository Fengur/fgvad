# fgvad
> English | [中文](README.md)

An intelligent VAD library — wraps a state machine and **dynamic endpoint strategy** on top of [ten-vad](https://github.com/TEN-framework/ten-vad) neural-network VAD, so both "short command" and "long dictation" use cases get sensible semantic segmentation.

The design draws on past speech SDK work experience.

## What It Solves

ten-vad on its own only outputs per-frame voice probability. Turning that into "sentence segmentation" requires an endpoint strategy layer. The challenge:

- **Short mode** (commands, queries) — a few seconds of tail silence should confidently end the session
- **Long mode** (dictation, continuous narration) — must not cut on brief pauses, but must segment accurately at sufficiently long pauses

fgvad handles both scenarios with a single **Dynamic Tail Endpoint Curve**. Real-world test on the Yixi talk by Zhu Zhiwei (25:30, long mode):

| Config | Sentences | ForceCut | ForceCut ratio |
|---|---|---|---|
| Dynamic curve enabled | 85 | 5 | 5.9% |
| Disabled (constant `tail_silence_initial=2000ms`) | 53 | 46 | **87%** |

With the dynamic curve off, VAD can only segment via the 30s force-cut — average sentence length clusters at the ceiling, making it **essentially unusable for continuous speech**. This curve is fgvad's core value.

To reproduce:

```bash
cd examples/macos
xcodegen generate && xcodebuild -scheme FgVadDemo build
# After launching the Demo: Long Mode → Load WAV → select test-data/long/yixi-zhuzhiwei-typography.wav
# Toggle "Enable Dynamic Tail Endpoint Curve" to compare both results
```

## Core Concepts

### Short Mode (Commands / Queries)

- One `start` → single semantic segment → session ends when tail silence threshold is met
- `head_silence_timeout` is a **control signal** — silence at the beginning ends the session immediately (`HeadSilenceTimeout`)
- `tail_silence` is a fixed threshold (typical: 2000ms)
- `max_duration` is the session total length cap (typical: 30000ms); triggers a force cut when reached (`MaxDurationReached`)

### Long Mode (Dictation / Continuous Narration)

- One `start` → multiple continuous segments → session does not end until external `stop()` or `max_session_duration`
- `head_silence_timeout` is a **notification event** — periodically prompts the consumer; session does not end
- `max_sentence_duration` is the **per-sentence** cap — triggers `SentenceForceCut` and the session continues
- Tail silence threshold is a dynamic curve (see below)

### Dynamic Tail Endpoint Curve (Long Mode Core)

**Formula** (linear decay + clamp):

```
tail_ms(t) = max( initial × (1 − t / max_sentence) , min )

t = elapsed milliseconds in the current sentence
initial = tail_silence_initial (typical: 2000ms)
min = tail_silence_min (typical: 600ms)
max_sentence = max_sentence_duration_ms (typical: 30000ms)
```

Example (initial=2000, min=600, max_sentence=30000):

```
 tail_ms
  2000 ┤●━━┓                  Generous at the start (user just began speaking, pauses likely mean searching for words)
       │   ┃
       │    ╲
       │     ╲
  1000 ┤      ╲
       │       ╲
   600 ┤────────●━━━━━━━━━━━  Holds at floor (21s+ elapsed,
       │                       sensitive segmentation takes priority)
       └───────────────────── current_sentence_ms
       0       15s   21s    30s
                            (force cut)
```

**Why this curve is the core**: running the Yixi talk with a constant threshold (dynamic curve off = `tail_ms` always 2000ms), 87% of sentences are force-cut by the 30s `max_sentence` — average sentence length clusters at the ceiling and VAD effectively fails. With the dynamic curve, the force-cut ratio drops to 5.9% (5 out of 85 sentences), and average sentence length lands at natural semantic boundaries.

Reasoning: the "semantic pause" length in human speech shrinks as sentence length grows (early hesitation can be several seconds; mid-sentence pauses are often < 1s). A fixed 2000ms is too generous in the middle of a sentence and inevitably hits max; linearly decaying from `initial` to `min` keeps the threshold in sync with semantic pauses.

Source: `src/state_machine.rs::current_tail_frames`. With `enable_dynamic_tail = false` it degrades to a constant threshold (for controlled experiments).

### `SentenceEnded` vs `SentenceForceCut` — Two Independent Events

| Event | Trigger | Business meaning |
|---|---|---|
| `SentenceEnded` | Tail silence accumulated ≥ `tail_ms(t)` (dynamic curve current threshold) | **Natural end**: user finished speaking |
| `SentenceForceCut` | Sentence length ≥ `max_sentence_duration_ms` | **Force cut**: user spoke too long and was interrupted |

Both events carry the full PCM of that sentence. The intent is to let the consumer distinguish "user expressed completely" from "cut by the library" — the latter usually means the sentence was semantically broken, and downstream ASR stitching logic should handle it specially (e.g., concatenate this sentence with the next one for re-recognition).

## Quick Start

### Build

```bash
# macOS: build for current host architecture (Apple Silicon → arm64; Intel Mac → x86_64)
cargo build

# macOS universal binary (arm64 + x86_64 lipo)
./scripts/build-macos-universal.sh             # debug
./scripts/build-macos-universal.sh --release   # release

# iOS (device + simulator, separate slices)
./scripts/build-ios.sh                         # debug
./scripts/build-ios.sh --release               # release

cargo test                                     # end-to-end integration tests (macOS only)
```

Build artifacts:

- `target/<host>/debug/libfgvad.dylib` — single-arch (default `cargo build`)
- `target/universal-apple-darwin/debug/libfgvad.{dylib,a}` — dual-arch universal (script output)
- `target/aarch64-apple-ios/debug/libfgvad.{dylib,a}` — iOS device
- `target/aarch64-apple-ios-sim/debug/libfgvad.{dylib,a}` — iOS Simulator
- `include/fgvad.h` (auto-generated by cbindgen)
- Bundled ten-vad frameworks:
  - `vendor/ten-vad/macOS/ten_vad.framework` (universal)
  - `vendor/ten-vad/iOS/device/ten_vad.framework` (arm64 device)
  - `vendor/ten-vad/iOS/simulator/ten_vad.framework` (arm64 simulator, platform tag rewritten with vtool; see vendor README)

### Run the macOS Demo

```bash
cd examples/macos
xcodegen generate
xcodebuild -scheme FgVadDemo -configuration Debug build
open $(find ~/Library/Developer/Xcode/DerivedData -name FgVadDemo.app | head -1)
```

The Demo provides: Short/Long mode toggle, real-time parameter adjustment, streaming audio recording, load WAV for replay, sentence list with per-sentence playback, and debug logs at `~/Library/Logs/FgVadDemo/run.log`. See [`examples/macos/README.en.md`](./examples/macos/README.en.md).

### Run the Android Demo

```bash
cd examples/android/FgVadDemo
../../../scripts/build-android.sh           # build fgvad-jni and copy .so files
adb push ../../../test-data/long/yixi-zhuzhiwei-typography.wav \
  /sdcard/Android/data/io.fengur.fgvaddemo/files/long/
./gradlew :app:installDebug
adb shell am start -n io.fengur.fgvaddemo/.MainActivity
```

After launch: Long Mode → Load Test Audio → `[external] long/yixi-...` → wait for parsing to complete.

### Minimal C Integration Example

```c
#include "fgvad.h"

// Long mode instance
struct FgVad* vad = fgvad_new_long(
    /* head_silence_timeout_ms  */ 3000,
    /* max_sentence_duration_ms */ 30000,
    /* max_session_duration_ms  */ 0,        // 0 = no limit
    /* tail_silence_ms_initial  */ 2000,
    /* tail_silence_ms_min      */ 600,
    /* enable_dynamic_tail      */ true
);
fgvad_start(vad);

// Feed PCM (16 kHz mono i16)
int16_t pcm[16000];  // 1 second
struct FgVadResults* results = fgvad_process(vad, pcm, 16000);

for (uintptr_t i = 0; i < fgvad_results_count(results); i++) {
    struct FgVadResultView v = fgvad_result_view(results, i);
    if (v.event == FgVadEvent_SentenceEnded || v.event == FgVadEvent_SentenceForceCut) {
        // Complete speech segment: v.audio_ptr [0, v.audio_len)
        // Timestamp reference: v.stream_offset_sample (sample count since start)
    }
}
fgvad_results_free(results);

fgvad_stop(vad);
fgvad_free(vad);
```

The Short Mode constructor is `fgvad_new_short(head_silence_timeout, tail_silence, max_duration)`. Full API in [`include/fgvad.h`](./include/fgvad.h).

## Test Data

`test-data/` contains real audio files committed to the repository — clone and reproduce experiments immediately:

- **`long/yixi-zhuzhiwei-typography.wav`** — 25:33 Yixi talk (Zhu Zhiwei, "The Power of Typography"), the core baseline for long mode and the dynamic curve controlled experiment
- **`short/01-06-*.wav`** — 6 synthesized short-mode cases, covering all three `endReason` paths (`HeadSilenceTimeout` / `SpeechCompleted` / `MaxDurationReached`) plus 2 edge cases (brief-pause merge, `CONFIRM_FRAMES` boundary)

See [`test-data/README.md`](./test-data/README.md), [`test-data/long/README.md`](./test-data/long/README.md), and [`test-data/short/README.md`](./test-data/short/README.md).

## Tests

`cargo test` runs the full suite of 49 tests (unit + integration):

| Test file | Count | Content |
|---------|------|------|
| `src/lib.rs` (`#[test]`) | 32 | State machine / dynamic curve / FFI unit tests |
| `tests/real_audio.rs` | 4 | Short mode end-to-end (ten-vad official fixture) |
| `tests/long_mode.rs` | 4 | Long mode + ForceCut + ExternalStop |
| `tests/short_mode_cases.rs` | 6 | Short mode 6 synthesized cases asserting endReason |
| `tests/long_mode_yixi.rs` | 3 | Long mode dynamic curve controlled experiment (25-min Yixi talk) |

The most critical contract-level assertion is `dynamic_curve_substantially_reduces_force_cut_ratio` — if the dynamic curve formula is broken, the ForceCut ratio in ON mode will exceed 10% or will no longer be significantly lower than OFF, and `cargo test` will catch it immediately. This assertion corresponds to the design intent in the 85/5 vs 53/46 table in "What It Solves."

Performance: the 3 yixi long-mode tests feed 24M samples into ten-vad each run — single-threaded, roughly 2–3 minutes. All other tests are sub-second. Running the full `cargo test` in CI is acceptable.

## Robustness Parameters (Aligned with Industry Defaults)

| Parameter | Value | Notes |
|------|----|----|
| `THRESHOLD` | 0.5 | ten-vad probability threshold, aligned with Silero default |
| `CONFIRM_FRAMES` | 16 frames (256ms) | Head endpoint debounce, aligned with Silero `min_speech_duration_ms` |
| `RESUME_CONFIRM_FRAMES` | 5 frames (80ms) | Tail endpoint debounce. **fgvad original** — not needed by segmentation-only VAD libraries, but required for endpointing (semantic-level stop detection with a 1–2s tail) |
| `PRE_ROLL_FRAMES` | 16 frames (256ms) | SentenceStart carries 250ms of pre-roll audio, giving downstream recognizers sufficient context |

## Current Status

| Platform | Demo | Library Build Script | Public Distribution (integrator access) |
|---|---|---|---|
| **macOS 13+** (arm64 + x86_64 universal) | ✅ AppKit Demo ([macOS README](./examples/macos/README.en.md)) | `build-macos-universal.sh` | SPM URL ([v0.1.0+](https://github.com/Fengur/fgvad/releases/tag/v0.1.0)) + manual XCFramework |
| **iOS 16+** (device + simulator) | ✅ UIKit Demo ([iOS README](./examples/ios/README.en.md)), 24-min continuous recording verified on device | `build-ios.sh` (device + sim dual slice) | SPM URL + CocoaPods ([v0.1.0+](https://github.com/Fengur/fgvad/releases/tag/v0.1.0)) + manual XCFramework |
| **Android API 26+** (arm64-v8a) | ✅ Views Demo ([Android README](./examples/android/README.en.md)) | `build-android.sh` (NDK + JNI) | JitPack ([v0.2.0+](https://jitpack.io/#Fengur/fgvad)) |
| **C/C++** (macOS) | ✅ CMake CLI Demo ([C README](./examples/c/README.en.md)) | `cargo build` + `xcodebuild -create-xcframework` | Repository `examples/c/` as reference integration |
| Linux / Windows / WASM | — | — | Not planned |

**Input constraints**: 16 kHz / mono / i16 PCM only
**Noise**: office-level (−50 dBFS) works fine; for restaurant / in-car / outdoor scenarios, an energy gate pre-filter is recommended (roadmap)
**v0.1.0** released SPM + Pod + manual XCFramework for iOS/macOS; **v0.2.0** added Android via single-line JitPack integration. See [Installation](#installation).

## Roadmap

- [ ] Visualization of probability curve + dynamic tail curve + role color bands (Demo)
- [ ] Energy gate pre-filter (noise robustness)
- [x] iOS library build support (device + simulator)
- [x] iOS Demo (minimal recording + VAD)
- [x] iOS XCFramework packaging script (`scripts/build-xcframework.sh`, includes macOS three slices)
- [x] Android build support (NDK + JNI bridge)
- [x] Android Demo (with per-sentence playback + test WAV replay)
- [x] CocoaPods / SPM distribution — from v0.1.0, see [Installation](#installation)
- [x] Android distribution (JitPack) — from v0.2.0, see [Installation](#installation)
- [x] Pure C CLI integration example — see [`examples/c/`](./examples/c/) (macOS supported; Linux/embedded pending)
- [ ] Deep tuning advanced API (expose ten-vad internal parameters / switch VAD engine on demand, see next section)

## Design Philosophy and Future Plans

### The Core Is the Approach, Not ten-vad

What fgvad aims to convey is the **methodology for building ASR-friendly VAD**, not "a Swift / Kotlin wrapper for ten-vad." The three core capabilities are actually independent of the underlying engine choice:

- **Dynamic Tail Endpoint Curve** — `tail_ms(t) = max(initial × (1 − t/max), min)` linear decay, "generous at the start, tighter as speech continues." Any VAD that outputs per-frame voice/silence probability can use this curve.
- **State Machine** — Idle / Detecting / Started / Voiced / Trailing / End six states + short/long dual semantics, decomposing "endpoint detection" into an observable event stream.
- **Notification vs Control Events** — the same endpoint signal (`HeadSilenceTimeout`, etc.) has completely different meaning in long/short mode; the API design must distinguish them.

If you choose [Silero VAD](https://github.com/snakers4/silero-vad) / [WebRTC VAD](https://github.com/wiseman/py-webrtcvad) / a proprietary trained model as the underlying voice/silence frame classifier, porting fgvad's state machine and dynamic curve to it keeps the **core value intact**. The Rust state machine in this repo (`src/state_machine.rs`) + the test suite (49 `cargo test` cases) serve as a reference implementation.

ten-vad is the current default — small footprint (~5MB framework), fast inference, supports five languages, and has pre-compiled binaries for macOS / iOS / Android ready to vendor. But it is not the soul of this project.

### Underlying Engine Parameters Are Not Exposed

The parameters exposed by `FgVadAnalyzer` are **all state-machine-level semantic parameters** (`headSilenceTimeoutMs` / `tailSilenceMsInitial` etc.); ten-vad's internal threshold / frame size / model variant details are not passed through.

Rationale: let the integrator focus on tuning "endpoint strategy" without being pulled into underlying engine details. The internal constants in fgvad (listed in the [Robustness Parameters](#robustness-parameters-aligned-with-industry-defaults) section — THRESHOLD = 0.5, CONFIRM_FRAMES = 16, etc.) have been converged through controlled experiments, and the defaults work well for office-level noise.

If "deep tuning" becomes necessary in the future — e.g., extreme noise scenarios requiring direct access to the underlying probability threshold, or switching to a different VAD engine variant — **it will be exposed via a separate advanced API** (such as `FgVadAnalyzer.Advanced(...)` or similar) without polluting the current main API. This corresponds to the design space downstream of the "energy gate pre-filter" item in the roadmap.

## Installation

### Swift Package Manager (Recommended)

Supports **iOS 16+** / **macOS 13+**.

```swift
// Package.swift dependencies:
.package(url: "https://github.com/Fengur/fgvad.git", from: "0.1.0")
```

Target dependency:

```swift
.product(name: "Fgvad", package: "fgvad")
```

Xcode integration: File → Add Package Dependencies, paste URL `https://github.com/Fengur/fgvad.git`.

**For development within this repo** — demos and tests use a local `dist/` rather than a remote download; before running `swift build`, export:

```bash
export FGVAD_LOCAL_BINARIES=1
```

### CocoaPods (iOS 16+ only)

```ruby
# Podfile
pod 'Fgvad', :git => 'https://github.com/Fengur/fgvad.git', :tag => 'v0.1.0'
```

`pod install` will automatically download and unzip the XCFramework from the GitHub Release. **macOS does not use Pod** — use SPM instead (same library, same API).

### Android (JitPack)

Supports **Android API 26+ / arm64-v8a**. Add the JitPack maven repository to `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}
```

Add the dependency to `app/build.gradle.kts`:

```kotlin
dependencies {
    implementation("com.github.Fengur:fgvad:v0.2.0")
}
```

Kotlin usage example:

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
        // r.audioSamples contains the full PCM for this sentence
    }
}
vad.stop()
vad.close()
```

### Manual XCFramework

Download both zips from [v0.1.0 Release](https://github.com/Fengur/fgvad/releases/tag/v0.1.0):
- `FgvadCore.xcframework.zip`
- `ten_vad.xcframework.zip`

Unzip both and drag the two `.xcframework` bundles into your Xcode project. Set to Embed & Sign. Also copy the Swift wrapper source (from [`Sources/Fgvad/FgVadAnalyzer.swift`](./Sources/Fgvad/FgVadAnalyzer.swift) into your project).

### Integration Examples

fgvad is a streaming API whose three-phase call pattern maps to the **begin / middle packets / end packet** mental model of an ASR client. **Short Mode and Long Mode have different event handling logic — complete examples for both:**

#### Short Mode (Commands / Queries)

One `start` corresponds to **one utterance**. VAD transitions state to End internally after detecting the endpoint; the external caller just checks state to wrap up.

```swift
import Fgvad

// 1. begin
let analyzer = try FgVadAnalyzer(mode: .short(.init(
    headSilenceTimeoutMs: 3_000,    // No speech → timeout and give up
    tailSilenceMs: 2_000,           // 2s tail silence means speech is complete
    maxDurationMs: 30_000,          // Record at most 30s per session
)))
analyzer.start()

// 2. Middle packets — keep feeding chunks (typical 20-100ms / chunk)
recorder.onChunk = { chunk in
    let results = try chunk.withUnsafeBufferPointer { try analyzer.feed($0) }
    for r in results {
        if r.event == FgVadEvent_SentenceStarted {
            // Start ASR session (send begin packet)
        }
        if r.type == FgVadResultType_SentenceEnd {
            // Send end packet + wait for recognition result
            // r.audioLen samples are the complete PCM for this sentence
        }
        // In short mode, other events (HeadSilenceTimeout / MaxDurationReached)
        // are control signals — no need to handle separately;
        // state == End below unifies all termination paths
    }

    // 3. end — all short-mode termination paths converge at state == End
    if analyzer.state == FgVadState_End {
        analyzer.stop()
        recorder.stop()

        // analyzer.endReason tells you the specific termination cause:
        //   .speechCompleted    — user finished speaking normally
        //   .headSilenceTimeout — no speech detected, timed out
        //   .maxDurationReached — hit the 30s cap
        //   .externalStop       — externally triggered stop()
    }
}
```

#### Long Mode (Continuous Dictation)

One `start` corresponds to **multiple continuous sentences**. State does not automatically transition to End; it only terminates via external `stop()` or `max_session_duration`. `HeadSilenceTimeout` is a notification to prompt the user, not a session terminator.

```swift
import Fgvad

// 1. begin
let analyzer = try FgVadAnalyzer(mode: .long(.init(
    headSilenceTimeoutMs: 3_000,         // Interval for prompting the user (periodic)
    maxSentenceDurationMs: 30_000,       // Per-sentence cap; triggers SentenceForceCut
    maxSessionDurationMs: 0,             // 0 = no session time limit
    tailSilenceMsInitial: 2_000,         // Dynamic tail endpoint initial value
    tailSilenceMsMin: 600,               // Dynamic tail endpoint floor
    enableDynamicTail: true,             // Enable dynamic curve (disabling causes 87% force-cut)
)))
analyzer.start()

// 2. Middle packets
recorder.onChunk = { chunk in
    let results = try chunk.withUnsafeBufferPointer { try analyzer.feed($0) }
    for r in results {
        if r.event == FgVadEvent_SentenceStarted {
            // Start a new ASR session (one session per sentence)
        }
        if r.type == FgVadResultType_SentenceEnd {
            // Send end packet + wait for recognition result (continue waiting for next sentence)
            // r.audioLen is the full PCM for this sentence
            // If r.event == FgVadEvent_SentenceForceCut, show "force cut" in UX
        }
        if r.event == FgVadEvent_HeadSilenceTimeout {
            // Long-mode notification event: periodic user prompt
            //   e.g., show "You haven't spoken for 3 seconds" in the UI
            // Do not stop recording; session continues
        }
    }

    // Long mode does not watch state == End — without an explicit stop it never reaches End
    // (unless max_session_duration_ms was set and reached)
}

// 3. end — typical long-mode path: user actively stops recording
recorder.onStop = {
    analyzer.stop()
    // If stop() is called while still in an Active segment, the next feed (even an empty chunk)
    // will trigger the ExternalStop path and emit a "synthesized end packet."
    // If no more feed after stop(), that audio segment is lost.
    // Recommended: feed one empty chunk before stop():
    //
    //   try [].withUnsafeBufferPointer { try analyzer.feed($0) }
    //   analyzer.stop()
}
```

**Key differences**:

| Concern | Short Mode | Long Mode |
|---|---|---|
| Termination check | `state == End` (all termination paths converge here) | External `stop()` / reaching `max_session` |
| `HeadSilenceTimeout` | Control signal (state auto-transitions to End) | Notification event (prompt user, no stop) |
| After `SentenceEnd` fires | Stop recording (single-sentence mode has only one sentence) | Continue recording for next sentence |
| Typical duration | A few seconds to 30s | Minutes to unlimited |

### Event → Business Action Mapping

The same event has completely different meaning in the two modes — this is the core of fgvad's design. Integrators should wire up business logic according to the table below:

| Event | Short Mode | Long Mode |
|---|---|---|
| `SentenceStarted` | Start ASR recognition (send Begin Packet) | Start a new ASR session (multi-sentence continuous, one session per sentence) |
| `SentenceEnded` | **Stop recording** + send End Packet, wait for result | Send End Packet, **continue recording** for next sentence |
| `SentenceForceCut` | **Stop recording** + send End Packet (single sentence hit max) | Send End Packet, **continue recording** (user spoke too long) |
| `HeadSilenceTimeout` | **Stop recording** — user pressed record but said nothing | **Prompt user** "You haven't spoken for N seconds," **do not stop recording** |
| `MaxDurationReached` | **Stop recording** — single-session total duration cap | **End the entire session** — session total duration cap |

**Check `r.type` for end packets, not `r.event`**: the library unifies all "end packet semantics" — SentenceEnded (natural) / SentenceForceCut (per-sentence force cut) / the "synthesized end packet" emitted when MaxDurationReached or ExternalStop fires while speech is active — all tagged as `r.type == SentenceEnd`. `r.event` is used only to distinguish the **reason** (whether to show the user a "force cut" UX notice).

**Critical difference — `HeadSilenceTimeout` behaves completely differently across modes**:
- In Short Mode: **control signal** — state transitions directly to End, session terminates → you should stop recording
- In Long Mode: **notification event** — state unchanged, session continues → you should prompt the user but **leave recording alone**

In Short Mode, all termination paths converge at a single observation point: `analyzer.state == FgVadState_End`. Check this state to decide whether to stop recording; no need for per-event branching.

In Long Mode, there are only two termination paths: external `stop()` (user actively stops) or `MaxDurationReached` (session total duration reached). `HeadSilenceTimeout` is always just a notification.

### Batch Replay

Streaming is not required — batch mode is commonly used for parameter tuning and regression testing:

```swift
let (results, finalState, endReason) = try FgVadAnalyzer.analyze(
    samples: pcm, mode: .short(.init())
)
```

Feed in the entire PCM at once; receive all results + final state + endReason.

## License

MIT — see [LICENSE](./LICENSE). The underlying ten-vad follows Apache 2.0.
