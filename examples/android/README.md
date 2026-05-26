# fgvad Android Demo
> [English](README.en.md) | 中文

复刻 iOS demo 的 Android 版本,Views(XML + Kotlin)+ AudioRecord 录音 + AudioTrack 试听。既是对外的使用示例,也是 Android 端调试 / 调参的工具。

## 当前功能

- 短/长时模式切换 + 参数面板
- 麦克风录音(AudioRecord)+ 实时事件流
- 加载测试 WAV 重跑(assets 自带短 case + adb push 长 yixi)
- Sentence list + 按句试听(AudioTrack 直播 i16 PCM)
- 调试日志写文件:`/sdcard/Android/data/io.fengur.fgvaddemo/files/run.log`
- 锁竖屏(调试工具不做横屏适配)

## 复现

```bash
cd examples/android/FgVadDemo
../../../scripts/build-android.sh           # 编 fgvad-jni 并把 .so 拷到 android/fgvad/jniLibs
adb push ../../../test-data/long/yixi-zhuzhiwei-typography.wav \
  /sdcard/Android/data/io.fengur.fgvaddemo/files/long/
./gradlew :app:installDebug
adb shell am start -n io.fengur.fgvaddemo/.MainActivity
```

启动后:长时模式 → 加载测试音频 → `[external] long/yixi-...` → 等解析完成。

## Demo 接入 fgvad 的方式(dev 工作流)

Demo 通过 **Gradle multi-project `project(":fgvad")` 跨目录依赖**消费仓库内 fgvad library,**不走公开 JitPack URL**:

```kotlin
// examples/android/FgVadDemo/settings.gradle.kts
include(":fgvad")
project(":fgvad").projectDir = file("../../../android/fgvad")

// app/build.gradle.kts
dependencies {
    implementation(project(":fgvad"))
}
```

dev 期改 Kotlin wrapper(`android/fgvad/src/main/java/io/fengur/fgvad/*.kt`)立即在 demo build 看到。改 Rust 代码(`examples/android/fgvad-jni/src/lib.rs`)需要重跑 `./scripts/build-android.sh` 重生成 `.so` 到 `android/fgvad/src/main/jniLibs/`,demo 才能看到。

集成方真要接入用的是 **JitPack URL 模式**(v0.2.0+):

```kotlin
// 集成方 settings.gradle.kts
maven { url = uri("https://jitpack.io") }
// 集成方 app/build.gradle.kts
implementation("com.github.Fengur:fgvad:v0.2.0")
```

详见根 [README Installation 章节](../../../README.md#installation)。

## 已验证设备

- 小米 luming(25067PYE3C),Android 16,arm64-v8a
- 长时模式 yixi baseline:N=85, ForceCut=5(与 iOS / macOS / C demo / cargo test 全平台一致)

## 限制

- 仅 arm64-v8a(armeabi-v7a 32-bit 在路线图,目前覆盖 95%+ 现代设备)
- min SDK 26
- 录音用 AudioRecord(不用 Oboe)
- 测试音频长 yixi(~47MB)不打进 APK,需 adb push
