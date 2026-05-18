# test-data —— fgvad 调参与回归用音频

本目录里的所有 WAV 都是 **16kHz 单声道 i16 PCM**，可以直接被 Demo 的"加载 WAV 重跑"
入口或者库的批式 analyze 接口吃掉，无需转码。

## 子目录结构

```
test-data/
├── long/   长时模式样本——多句连续讲述，几分钟至几十分钟
└── short/  短时模式样本——单段命令/查询式发声，5-30 秒为典型
```

## long/

适合验证：动态尾端点曲线、多句切分、ForceCut 触发、长时间会话稳定性。

| 文件 | 时长 | 用途 |
|------|------|------|
| `yixi-zhuzhiwei-typography.wav` | 25:33 | 长时模式核心基线，动态曲线效果对照集（85/5 vs 53/46）|

详见 [`long/README.md`](long/README.md)，包含音频详情、动态曲线对照实验
完整数据、5 个 ForceCut 位置参考、再生成脚本。

## short/

合成测试集，覆盖短时模式 3 条 endReason 路径 + 2 个边界情形：

| 文件 | 验证目标 |
|------|----------|
| `01-pure-silence-5s.wav` | HeadSilenceTimeout |
| `02-normal-utterance.wav` | SpeechCompleted（标准路径） |
| `03-immediate-speech.wav` | SpeechCompleted（无头静音） |
| `04-max-duration-reached.wav` | MaxDurationReached |
| `05-short-pauses-merged.wav` | 短停顿不切句、整段合并 |
| `06-very-brief-speech.wav` | CONFIRM_FRAMES 边界（0.3s 语音是否够触发 SentenceStarted） |

详见 [`short/README.md`](short/README.md)，包含每个 case 的构成、预期 endReason、
以及一键再生成脚本。

## 添加新样本的注意事项

- **格式**：必须 16kHz 单声道 i16 PCM。可用 `ffmpeg -i <input> -ar 16000 -ac 1 -c:a pcm_s16le <output>.wav` 转换
- **大小**：单文件建议 ≤ 100MB（GitHub 上限）。超过的话考虑 LFS 或裁剪
- **命名**：建议 `<来源>-<说话人>-<主题>.wav` 风格，方便 grep / log 自动展示
