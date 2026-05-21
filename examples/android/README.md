# fgvad Android Demo

复刻 iOS demo 的 Android 版本。功能：

- 短/长时模式切换 + 参数面板
- 麦克风录音（AudioRecord）+ 实时事件流
- 加载测试 WAV 重跑（assets 自带短 case + adb push 长 yixi）
- Sentence list + 按句试听（AudioTrack 直播 i16 PCM）
- 调试日志写文件：`/sdcard/Android/data/io.fengur.fgvaddemo/files/run.log`

## 复现

见根 `README.md` "跑 Android Demo" 小节。

## 已验证设备

- 小米 luming（25067PYE3C），Android 16，arm64-v8a

## 限制

- 仅 arm64-v8a（armeabi-v7a 32-bit 在路线图）
- min SDK 26
- 录音用 AudioRecord（不用 Oboe）
- 测试音频长 yixi（~47MB）不打进 APK，需 adb push
