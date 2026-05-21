# 三平台 Audio Picker v2 设计稿

**目标**：把 iOS / macOS / Android demo 的"加载测试音频"交互统一到同一个心智模型——**单层选择器、每行双按钮（▶ 预 / ▶ 析）、一键直达**——并把 iOS / macOS 的 analyze 流程从阻塞 spinner 改成**流式增量**（已在 Android 上验过体验更好）。

## 核心交互模型（三平台对齐）

```
┌────────────────────────────────────────────────────┐
│ [+ 导入 WAV]                                       │  iOS / Android only
├────────────────────────────────────────────────────┤
│ — bundled —                                        │
│ short/01-pure-silence-5s.wav    [▶ 预] [▶ 析]      │  read-only
│ short/02-...                    [▶ 预] [▶ 析]      │
│ ...                                                │
├────────────────────────────────────────────────────┤
│ — imported —    [清空]                             │  iOS / Android only
│ my-recording.wav                [▶ 预] [▶ 析] [×]  │
│ ...                                                │
├────────────────────────────────────────────────────┤
│ — external (adb push) —                            │  Android only
│ long/yixi-...                   [▶ 预] [▶ 析]      │
└────────────────────────────────────────────────────┘
```

**两个按钮语义：**

- **▶ 预**：直接在原 PCM 上播放，不经过 fgvad。再点同一个 ▶ 预 → 停止；点别的 ▶ 预 → 切换到那条
- **▶ 析**：触发 fgvad 跑批。点了之后选择器关闭（移动端）或停留（macOS），主界面 sentence list 增量出结果

**禁用规则：**

- analyze 进行中：所有 ▶ 析 灰掉，▶ 预 仍可用
- 录音模式（mic）启动时：整个选择器入口禁用

## 各平台实现要点

### iOS（UIKit）

- 新建 `AudioPickerViewController`：UITableViewController，三段（bundled / imported），自定义 cell `AudioPickerCell`：title + 两个按钮（imported 段额外多 × 按钮）+ 段头的 `[+ 导入]` / `[清空]`
- 现 `loadTestAudioButton` 触发 modal present
- 系统文件选择：`UIDocumentPickerViewController(forOpeningContentTypes: [.wav, .audio])`，用户选完后把 NSURL 内容 copy 到 `Documents/imported/<name>.wav`。Files app 的 "On My iPhone → FgVad" 也能看到，是个意外加分入口
- 重构 `runAnalyze`：从同步 + processingOverlay 改成后台 dispatch + 主线程增量 reload。spinner 删掉
- 文件管理：`Documents/imported/` 列表、删除单条、清空整段

### macOS（AppKit）

- 新建 `AudioPickerWindowController` 或在主窗内嵌一个 NSTableView 段
- bundled 段唯一来源：`Bundle.main.url(forResource: ..., withExtension: "wav")` 拿 `examples/macos` 工程里 bundle 进的 short test-data
- 不做 imported 段 —— macOS 已有的 NSOpenPanel"打开测试音频"是任意路径访问，不必往沙盒搬
- 重构 `runAnalyze` 同 iOS：后台 + 主线程增量 reloadData

### Android（Views + RecyclerView）

- 新建 `AudioPickerSheet`：`BottomSheetDialogFragment` 或 `Dialog` 自管理，里面 RecyclerView 多 section adapter
- bundled / imported / external 三段，每段 header + items
- 系统文件选择：`Intent(Intent.ACTION_OPEN_DOCUMENT).setType("audio/*")` + ActivityResult，回来把 InputStream copy 到 `getExternalFilesDir(null)/imported/<name>.wav`
- external 段保留（adb push 路径不变），用得不多但留着不碍事
- analyze 已经是流式，本轮不动

## 数据 / 文件布局

| 平台 | bundled 来源 | imported 写到哪 | external |
|---|---|---|---|
| iOS | `App.app/short/*.wav`（Xcode resource bundle） | `Documents/imported/` | — |
| macOS | `App.app/Contents/Resources/short/*.wav` | — | — |
| Android | `assets/short/*.wav` | `getExternalFilesDir(null)/imported/` | `getExternalFilesDir(null)/long/` |

## 不在本轮范围

- macOS 旧 NSOpenPanel"打开任意 WAV"保留，不动
- waveform / 概率曲线可视化（路线图另一项）
- 选择器内嵌主界面方案（短期还是用 sheet/dialog 形态）

## 验证

1. iOS：选 bundled / imported / 系统选 WAV → 预试听 / 析；析过程主线程不卡，UITableView 增量出句
2. macOS：选 bundled，析过程窗口可拖动、可点其他按钮（不阻塞）
3. Android：sheet 打开，三段可见，导入新 WAV 后 imported 段刷新；× 删除单条；清空确认弹窗
4. 三平台 yixi 长 mode 跑出来还是 ~85 句（确保 analyze 重构没改坏）
