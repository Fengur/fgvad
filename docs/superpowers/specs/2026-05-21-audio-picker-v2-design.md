# 三平台 Audio Picker v2 设计稿

**目标**：把 iOS / macOS / Android demo 的"加载测试音频"交互统一到同一个心智模型——**单层选择器、每行双按钮（▶ 预 / ▶ 析）、一键直达**——并把 iOS / macOS 的 analyze 流程从阻塞 spinner 改成**流式增量**（已在 Android 上验过体验更好）。

## 核心交互模型（三平台对齐）

**revised 2026-05-21**：取消 imported 段和文件导入入口，改为 recordings 段（mic 录音另存的原始 WAV）。Android 上 `adb push` 直接落到 recordings 目录，不再单独分 external 段。

```
┌────────────────────────────────────────────────────┐
│ — bundled —                                        │
│ short/01-pure-silence-5s.wav    [▶ 预] [▶ 析]      │  read-only
│ short/02-...                    [▶ 预] [▶ 析]      │
│ long/yixi-zhuzhiwei.wav         [▶ 预] [▶ 析]      │  iOS / macOS bundle 进 app
│ ...                                                │
├────────────────────────────────────────────────────┤
│ — recordings —                  [清空]             │
│ recording_2026-05-21_19-30-45.wav [▶ 预] [▶ 析] [×]│  app mic 录的
│ yixi-zhuzhiwei.wav              [▶ 预] [▶ 析] [×]  │  Android 上 adb push 也进这里
│ ...                                                │
└────────────────────────────────────────────────────┘
```

**两个按钮语义：**

- **▶ 预**：直接在原 PCM 上播放，不经过 fgvad。再点同一个 ▶ 预 → 停止；点别的 ▶ 预 → 切换到那条
- **▶ 析**：触发 fgvad 跑批。点了之后选择器关闭（移动端）或停留（macOS），主界面 sentence list 增量出结果

**禁用规则：**

- analyze 进行中：所有 ▶ 析 灰掉，▶ 预 仍可用
- 录音模式（mic）启动时：整个选择器入口禁用

## mic 录音另存原始 WAV（recordings 段的数据来源）

要让 recordings 段有内容可选，mic 录音必须把原始 PCM 也写一份到沙盒：

- 文件命名：`recording_<yyyy-MM-dd_HH-mm-ss>.wav`
- 录音 start 时打开 WavWriter，写好 header（采样率 16kHz、mono、16-bit），录音 stop 时 finalize（回填 RIFF / data chunk size）
- 写文件的 PCM tee 自现有的"喂 fgvad 的"那一路，单文件 IO 在录音线程或独立写文件线程都可
- 三平台都做这件事——Android、iOS、macOS

## iOS log 抽出方案

macOS 我直接 Read `~/Library/Logs/FgVadDemo/run.log`，Android 我 `adb pull` 或 `adb logcat`。iOS 真机 log 没现成路径——本设计把它对齐其他两端：

- iOS DemoLogger 复刻 Android 模式：`Documents/run.log`，app 启动 truncate
- 加一个"导出日志"button 到主界面/picker 工具栏，触发 `UIActivityViewController` → 用户 Airdrop 给 Mac → Claude `Read` 落到 Mac 的文件
- Info.plist 开 `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`：Documents 在 Files app 里可见，免按钮入口（同时 recordings 也能从这里 share 出去）

## 各平台实现要点

### iOS（UIKit）

- `AudioPickerViewController`：UITableViewController，两段（bundled / recordings），自定义 cell `AudioPickerCell`：title + 两个按钮（recordings 段额外多 × 按钮）+ recordings section header 的 `[清空]`
- 现 `loadTestAudioButton` 触发 modal present
- recordings 数据源：mic 录音另存的 `Documents/recordings/<timestamp>.wav`。**没有** UIDocumentPicker / 文件导入入口
- 重构 `runAnalyze`：从同步 + processingOverlay 改成后台 dispatch + 主线程增量 reload。spinner 删掉
- 文件管理：`Documents/recordings/` 列表、删除单条、清空整段
- WavWriter：mic 录音时 tee PCM 写文件，stop 时 finalize header
- DemoLogger（新建，对齐 Android）：`Documents/run.log`，"导出日志"按钮 + UIFileSharingEnabled

### macOS（AppKit）

- 新建 `AudioPickerWindowController` 或在主窗内嵌一个 NSTableView 段
- bundled 段唯一来源：`Bundle.main.url(forResource: ..., withExtension: "wav")` 拿 `examples/macos` 工程里 bundle 进的 short test-data
- 不做 imported 段 —— macOS 已有的 NSOpenPanel"打开测试音频"是任意路径访问，不必往沙盒搬
- 重构 `runAnalyze` 同 iOS：后台 + 主线程增量 reloadData

### Android（Views + RecyclerView）

- 新建 `AudioPickerSheet`：`BottomSheetDialogFragment` 或 `Dialog`，RecyclerView 多 section adapter
- 两段：bundled（assets/short/）/ recordings（`getExternalFilesDir(null)/recordings/`）
- recordings 数据源：① mic 录音 tee 原始 PCM → WAV ② `adb push` 也直接打到这个目录（取代之前的 long/ 单独段）
- **没有** SAF 导入入口（用户要测自定义音频走 adb push 同一目录）
- analyze 已经是流式，本轮不动

## 数据 / 文件布局

| 平台 | bundled 来源 | recordings 写到哪 |
|---|---|---|
| iOS | `App.app/short/*.wav` + `App.app/long/yixi-...wav` | `Documents/recordings/` |
| macOS | `App.app/Contents/Resources/short/*.wav` + `App.app/Contents/Resources/long/yixi-...wav` | `~/Library/Containers/.../Documents/recordings/`（沙盒）或 `~/Documents/FgVadDemo/recordings/`（无沙盒） |
| Android | `assets/short/*.wav` | `getExternalFilesDir(null)/recordings/`（同时也是 adb push 的目标） |

## 不在本轮范围

- macOS 旧 NSOpenPanel"打开任意 WAV"保留，不动
- waveform / 概率曲线可视化（路线图另一项）
- 选择器内嵌主界面方案（短期还是用 sheet/dialog 形态）

## 验证

1. iOS：选 bundled / imported / 系统选 WAV → 预试听 / 析；析过程主线程不卡，UITableView 增量出句
2. macOS：选 bundled，析过程窗口可拖动、可点其他按钮（不阻塞）
3. Android：sheet 打开，三段可见，导入新 WAV 后 imported 段刷新；× 删除单条；清空确认弹窗
4. 三平台 yixi 长 mode 跑出来还是 ~85 句（确保 analyze 重构没改坏）
