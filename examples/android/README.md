# fgvad Android Demo
> English | [中文](README_CN.md)

The Android counterpart to the iOS demo — Views (XML + Kotlin) + AudioRecord for recording + AudioTrack for playback. Serves both as an external usage example and as an Android debugging / parameter-tuning tool.

## Current Features

- Short / Long Mode toggle + parameter panel
- Microphone recording (AudioRecord) + real-time event stream
- Load test WAV for replay (short cases bundled in assets + long yixi via adb push)
- Sentence list + per-sentence playback (AudioTrack streams i16 PCM directly)
- Debug log written to file: `/sdcard/Android/data/io.fengur.fgvaddemo/files/run.log`
- Portrait-only (debugging tool, no landscape support)

## Reproduce

```bash
cd examples/android/FgVadDemo
../../../scripts/build-android.sh           # build fgvad-jni and copy .so to android/fgvad/jniLibs
adb push ../../../test-data/long/yixi-zhuzhiwei-typography.wav \
  /sdcard/Android/data/io.fengur.fgvaddemo/files/long/
./gradlew :app:installDebug
adb shell am start -n io.fengur.fgvaddemo/.MainActivity
```

After launch: Long Mode → Load Test Audio → `[external] long/yixi-...` → wait for parsing to complete.

## How the Demo Integrates fgvad (Dev Workflow)

The Demo consumes fgvad via **Gradle multi-project `project(":fgvad")` cross-directory dependency** — it does **not** use the public JitPack URL:

```kotlin
// examples/android/FgVadDemo/settings.gradle.kts
include(":fgvad")
project(":fgvad").projectDir = file("../../../android/fgvad")

// app/build.gradle.kts
dependencies {
    implementation(project(":fgvad"))
}
```

During development, changes to the Kotlin wrapper (`android/fgvad/src/main/java/io/fengur/fgvad/*.kt`) are immediately visible on the next demo build. Changes to Rust code (`examples/android/fgvad-jni/src/lib.rs`) require re-running `./scripts/build-android.sh` to regenerate the `.so` files at `android/fgvad/src/main/jniLibs/` before the demo picks them up.

Integrators using **JitPack URL mode** (v0.2.0+):

```kotlin
// Integrator's settings.gradle.kts
maven { url = uri("https://jitpack.io") }
// Integrator's app/build.gradle.kts
implementation("com.github.Fengur:fgvad:v0.2.0")
```

See the root [README Installation section](../../../README.md#installation).

## Verified Devices

- Xiaomi Luming (25067PYE3C), Android 16, arm64-v8a
- Long Mode yixi baseline: N=85, ForceCut=5 (consistent with iOS / macOS / C demo / cargo test across all platforms)

## Limitations

- arm64-v8a only (armeabi-v7a 32-bit is on the roadmap; current coverage is 95%+ of modern devices)
- min SDK 26
- Recording uses AudioRecord (not Oboe)
- Long yixi test audio (~47MB) is not bundled in the APK; must be pushed via adb
