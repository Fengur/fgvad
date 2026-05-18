# long/ —— 长时模式调参与回归基线

长时模式核心测试集，用于验证多句切分、动态尾端点曲线、SentenceForceCut
触发等长时特有的状态机行为，也是 fgvad 对外展示其核心竞争力（动态曲线）
最具说服力的素材。

所有文件都是 **16kHz 单声道 i16 PCM**。

## 默认长时配置

文档中的实测数据基于 Demo 默认配置：

| 参数 | 值 |
|------|----|
| `head_silence_timeout` | 3000 ms（仅作 notification） |
| `max_sentence_duration` | 30000 ms |
| `max_session_duration` | 0 ms（不限） |
| `tail_silence_initial` | 2000 ms |
| `tail_silence_min` | 600 ms |
| `enable_dynamic_tail` | true |

## 音频详情

### `yixi-zhuzhiwei-typography.wav`

| 字段 | 值 |
|------|----|
| 时长 | 25:33（1533.14s）|
| 大小 | 47 MB |
| 来源 | 一席演讲：朱志偉《字體的力量》|
| YouTube ID | `T6L_5S2KJGE`（频道：一席YiXi） |
| 录音质量 | 工作室级专业制作 |
| 主讲风格 | 字体设计师，普通话标准、节奏成熟、含大段连贯讲述 |

**为什么选这段**：
- 演讲者节奏专业但不死板——既有"逐字推敲"的短停顿，也有"讲到兴起"
  的长段连贯讲述，能完整验证动态曲线的设计意图
- 录音棚环境，背景几乎纯净，能让 VAD 行为评估排除噪声变量
- 时长 25 分钟足以撞多次 30s 单句上限（验证 ForceCut），又不至于太长
  难以管理

## 核心实验：动态尾端点曲线对照

在朱志偉这段音频上跑长时模式两次，唯一变化是"启用动态尾端点曲线"开关：

| 配置 | 句数 | ForceCut | ForceCut 占比 | 平均句长 |
|------|------|----------|---------------|---------|
| 动态 ON（默认）| 85 | 5 | 5.9% | 18.0s |
| 动态 OFF（恒等 2000ms）| 53 | 46 | **87%** | 28.9s |

**关键结论**：关闭动态曲线后，VAD 几乎只能靠 30s 强切来分句，平均句长
贴着上限分布——连续语音场景下基本不可用。**这条曲线是 fgvad 在长时
模式可用性的决定因素**，不是可选优化。

### 怎么复现

1. 启动 Demo（macOS）
2. 切到 **长时 Long**
3. 取消勾选"启用动态尾端点曲线"
4. 点 **加载 WAV 重跑** → 选这个文件 → 等约 45s 处理 → 记录句数 / ForceCut
5. 重新勾选 → 重跑 → 对比两组数字

## 5 个 ForceCut 位置参考（动态 ON）

便于按句听原音频对照 VAD 决策的合理性：

| 句号 | 时间段 | 时长 | 位置语境 |
|------|--------|------|----------|
| Sentence 2  | 00:18.800 - 00:48.816 | 30.0s | 演讲开场段，朱老师热场超 30s |
| Sentence 25 | 07:04.480 - 07:34.496 | 30.0s | 7 分钟讲到一半的密集段 |
| Sentence 67 | 19:53.072 - 20:23.088 | 30.0s | 后段连贯讲述 |
| Sentence 73 | 21:40.096 - 22:10.112 | 30.0s | 后段连贯讲述 |
| Sentence 76 | 22:40.832 - 23:10.848 | 30.0s | 后段连贯讲述 |

5 个 ForceCut 时长都精确为 30.016s（= max_sentence_duration 阈值 + 1
帧 16ms 的量化余量），整齐地说明状态机在该位置确实是因为撞到上限才切。

## 怎么用

**调参回归**：每次改 `tail_silence_min` / `tail_silence_initial` 等参数
后，重跑这段音频，检查：

- 句数是否仍在 85±5 区间（变化大说明分句粒度漂了）
- ForceCut 数量是否仍 ≤ 8（变化大说明动态曲线收紧速率有问题）
- 任意几个 ForceCut 句子点 ▶ 听一下，是否还是"连贯讲述、无明显停顿"
  （若变成"明显能听出有停顿"，说明 VAD 在该位置应该早切但没切）

**人工评估**：把这段音频的"自然分句"标注一遍（拿 sentence list 的时间
戳手工对照原音频），可以衡量任意配置的精确率/召回率，对外公开数据论证。

## 怎么再生成

```bash
# 需要 yt-dlp + ffmpeg
~/Library/Python/3.9/bin/yt-dlp \
  --extractor-args "youtube:player_client=ios,android,tv_embedded" \
  -f "bestaudio/best" \
  -o "/tmp/yixi-zhuzhiwei.%(ext)s" \
  "https://www.youtube.com/watch?v=T6L_5S2KJGE"

ffmpeg -y -i /tmp/yixi-zhuzhiwei.mp4 \
  -vn -ar 16000 -ac 1 -c:a pcm_s16le \
  test-data/long/yixi-zhuzhiwei-typography.wav

rm /tmp/yixi-zhuzhiwei.*
```

YouTube 偶尔会改 SABR 流策略导致 yt-dlp 较旧版本下载失败，遇到时升级
yt-dlp 或换 `--extractor-args` 中的 `player_client` 列表顺序。

## 后续可加的长时素材（路线图）

- **多人对话场景**：会议/播客录音，验证多说话人切换时 fgvad 的行为
- **超长素材（1 小时+）**：验证 `max_session_duration` 路径
- **变速/变调段落**：验证状态机对语速/音量大幅变化的鲁棒性
- **带噪声背景**：见根 README 路线图中"energy gate 前置过滤"
