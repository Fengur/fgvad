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

| 文件 | 时长 | 来源 | 用途 |
|------|------|------|------|
| `yixi-zhuzhiwei-typography.wav` | 25:33 | 一席 #朱志偉《字體的力量》（YouTube 官方频道） | 长时模式核心基线，动态曲线效果对照集 |

## short/

适合验证：head_silence_timeout 行为、tail_silence 灵敏度、SpeechCompleted vs MaxDurationReached 终止路径。

理想素材的特征：
- 时长 5-30 秒
- 起始有 0.5-2 秒头部静音（验证 head_silence_timeout 行为）
- 单段连续语音（命令/查询式，如"打开支付宝"、"明天上午 10 点提醒我开会"）
- 末尾有 1-3 秒尾静音（验证正常 SpeechCompleted 路径）

暂未入库样本，待补充。

## 添加新样本的注意事项

- **格式**：必须 16kHz 单声道 i16 PCM。可用 `ffmpeg -i <input> -ar 16000 -ac 1 -c:a pcm_s16le <output>.wav` 转换
- **大小**：单文件建议 ≤ 100MB（GitHub 上限）。超过的话考虑 LFS 或裁剪
- **命名**：建议 `<来源>-<说话人>-<主题>.wav` 风格，方便 grep / log 自动展示
