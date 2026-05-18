# short/ —— 短时模式合成测试集

每个文件围绕**短时模式状态机的一个特定路径或边界**设计，覆盖：
`HeadSilenceTimeout` / `SpeechCompleted` / `MaxDurationReached` 三条 endReason
路径，外加多停顿合并、极短发声两个边界情形。

所有文件都是 **16kHz 单声道 i16 PCM**。语音段从 `../long/yixi-zhuzhiwei-typography.wav`
切出（19s-54s 区间是长时模式 Sentence 2+3 的连续讲述、无 >2s 自然停顿，
做素材纯净），静音段用 `ffmpeg anullsrc` 滤镜生成，concat 拼接。

## 默认短时配置

文档中"期望行为"基于 Demo 默认配置：

| 参数 | 值 |
|------|----|
| `head_silence_timeout` | 3000 ms |
| `tail_silence` | 2000 ms |
| `max_duration` | 30000 ms |

调参后期望行为会变化，请以当前 Demo UI 上的实际配置为准。

## Case 列表

| 文件 | 时长 | 构成 | 期望 endReason | 验证目标 |
|------|------|------|----------------|----------|
| `01-pure-silence-5s.wav` | 5.0s | 5s 纯静音 | **HeadSilenceTimeout** | head_silence_timeout=3000 真的会在 3s 触发结束 |
| `02-normal-utterance.wav` | 9.0s | 1s 静 + 5s 语音 + 3s 静 | **SpeechCompleted** | 标准路径：头静音 OK、tail_silence=2000 触发正常切句 |
| `03-immediate-speech.wav` | 8.1s | 0.1s 静 + 5s 语音 + 3s 静 | **SpeechCompleted** | 几乎没有头静音、立即开口的快速场景 |
| `04-max-duration-reached.wav` | 36.1s | 0.1s 静 + 35s 连续语音 + 1s 静 | **MaxDurationReached** | 用户一气呵成超过 max_duration 上限，强制结束 |
| `05-short-pauses-merged.wav` | 11.5s | 1s 静 + 3s 语音 + 1.5s 静 + 3s 语音 + 3s 静 | **SpeechCompleted** | 中间 1.5s 短停顿（< 2s tail）不应触发切句，整段合并为单句 |
| `06-very-brief-speech.wav` | 4.3s | 1s 静 + 0.3s 语音 + 3s 静 | **SpeechCompleted** | CONFIRM_FRAMES=256ms 边界——0.3s (300ms) > 256ms 阈值，确认成功，正常切出一句。若改成 < 256ms 则会在 Detecting 卡住直到 HeadSilenceTimeout |

## 怎么用

打开 Demo（macOS），切到 **短时 Short**，点 **加载 WAV 重跑**，选其中一个文件。
对照表里的"期望 endReason"看 `重跑完成` 行的输出是否一致；不一致说明状态机
行为或参数有偏移，往日志里看具体事件序列。

## 怎么再生成

如果改了素材或场景，可以重跑下面这个一键生成脚本（需要 ffmpeg）：

```bash
cd <fgvad repo root>
SRC=test-data/long/yixi-zhuzhiwei-typography.wav
TMP=/tmp/fgvad_short_synth
OUT=test-data/short
mkdir -p $TMP

# 提取 yixi 中段（连续讲述，无 >2s 自然停顿）做素材
ffmpeg -y -loglevel error -ss 19 -t 5    -i $SRC -ar 16000 -ac 1 -c:a pcm_s16le $TMP/speech_5s.wav
ffmpeg -y -loglevel error -ss 19 -t 3    -i $SRC -ar 16000 -ac 1 -c:a pcm_s16le $TMP/speech_3s_a.wav
ffmpeg -y -loglevel error -ss 22 -t 3    -i $SRC -ar 16000 -ac 1 -c:a pcm_s16le $TMP/speech_3s_b.wav
ffmpeg -y -loglevel error -ss 19 -t 35   -i $SRC -ar 16000 -ac 1 -c:a pcm_s16le $TMP/speech_35s.wav
ffmpeg -y -loglevel error -ss 20 -t 0.3  -i $SRC -ar 16000 -ac 1 -c:a pcm_s16le $TMP/speech_0p3s.wav

# 各种长度静音
for d in 5 3 1 1.5 0.1; do
  ffmpeg -y -loglevel error -f lavfi -i anullsrc=r=16000:cl=mono \
    -t $d -c:a pcm_s16le $TMP/silence_$(echo $d | tr . p)s.wav
done

# Concat 出 6 个 case
cp $TMP/silence_5s.wav $OUT/01-pure-silence-5s.wav
ffmpeg -y -loglevel error -i $TMP/silence_1s.wav -i $TMP/speech_5s.wav -i $TMP/silence_3s.wav \
  -filter_complex '[0][1][2]concat=n=3:v=0:a=1' -c:a pcm_s16le $OUT/02-normal-utterance.wav
ffmpeg -y -loglevel error -i $TMP/silence_0p1s.wav -i $TMP/speech_5s.wav -i $TMP/silence_3s.wav \
  -filter_complex '[0][1][2]concat=n=3:v=0:a=1' -c:a pcm_s16le $OUT/03-immediate-speech.wav
ffmpeg -y -loglevel error -i $TMP/silence_0p1s.wav -i $TMP/speech_35s.wav -i $TMP/silence_1s.wav \
  -filter_complex '[0][1][2]concat=n=3:v=0:a=1' -c:a pcm_s16le $OUT/04-max-duration-reached.wav
ffmpeg -y -loglevel error -i $TMP/silence_1s.wav -i $TMP/speech_3s_a.wav -i $TMP/silence_1p5s.wav \
  -i $TMP/speech_3s_b.wav -i $TMP/silence_3s.wav \
  -filter_complex '[0][1][2][3][4]concat=n=5:v=0:a=1' -c:a pcm_s16le $OUT/05-short-pauses-merged.wav
ffmpeg -y -loglevel error -i $TMP/silence_1s.wav -i $TMP/speech_0p3s.wav -i $TMP/silence_3s.wav \
  -filter_complex '[0][1][2]concat=n=3:v=0:a=1' -c:a pcm_s16le $OUT/06-very-brief-speech.wav

rm -rf $TMP
```
