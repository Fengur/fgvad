import AppKit
import SnapKit

/// 主窗口：顶部 mode toggle、config 表单、录音/重跑按钮、状态显示。
/// 录音进行中走流式（实时喂 analyzer），短时遇到 SentenceEnd 自动停止。
/// 重跑按钮打开已存 WAV，用当前 mode 批式回灌。
final class MainWindowController: NSWindowController {

    private enum Mode: Int { case short = 0, long = 1 }

    // MARK: - Models
    private let recorder = Recorder()
    private var analyzer: FgVadAnalyzer?
    private var mode: Mode = .short
    private var sentenceCount = 0

    // MARK: - Views
    private let modeSegmented = NSSegmentedControl(
        labels: ["短时 Short", "长时 Long"],
        trackingMode: .selectOne,
        target: nil, action: nil)

    // 短时 config 字段
    private let shortHead = MainWindowController.numField(default: 3000)
    private let shortTail = MainWindowController.numField(default: 2000)
    private let shortMax = MainWindowController.numField(default: 30000)

    // 长时 config 字段
    private let longHead = MainWindowController.numField(default: 3000)
    private let longMaxSent = MainWindowController.numField(default: 30000)
    private let longMaxSess = MainWindowController.numField(default: 0)
    private let longTailInit = MainWindowController.numField(default: 2000)
    private let longTailMin = MainWindowController.numField(default: 600)
    private let longDynamic = NSButton(
        checkboxWithTitle: "启用动态尾端点曲线", target: nil, action: nil)

    private let shortConfigBox = CardView()
    private let longConfigBox = CardView()
    private let configStack = NSStackView()
    private let modeHintLabel = NSTextField(labelWithString: "")

    // 操作按钮 & 状态
    private let recordButton = NSButton(title: "开始录音", target: nil, action: nil)
    private let loadWavButton = NSButton(title: "加载 WAV 重跑", target: nil, action: nil)
    private let openFolderButton = NSButton(title: "录音目录", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "就绪")
    private let liveStateLabel = NSTextField(labelWithString: "")
    private let lastFileLabel = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(
        labelWithString: "fgvad 0.1.0 · ten-vad")

    // MARK: - Recording timer
    private var recordingStartDate: Date?
    private var tickTimer: Timer?

    // MARK: - Init
    init() {
        DemoLog.log("MainWindowController.init")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "FgVadDemo"
        // 强制 aqua(亮色)，保险起见 NSApp 和 window 都各自 set 一次
        window.appearance = NSAppearance(named: .aqua)
        // 浅灰背景(类似 macOS 系统设置窗口)，配白色 CardView 形成层次
        window.backgroundColor = NSColor.windowBackgroundColor
        window.center()
        super.init(window: window)
        setupUI()
        applyMode(.short)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    private static func numField(default value: UInt32) -> NSTextField {
        let f = NSTextField()
        f.stringValue = String(value)
        f.alignment = .right
        return f
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        // mode segmented
        modeSegmented.selectedSegment = 0
        modeSegmented.target = self
        modeSegmented.action = #selector(modeChanged(_:))
        content.addSubview(modeSegmented)
        modeSegmented.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(20)
            make.centerX.equalToSuperview()
            make.width.equalTo(320)
        }

        // mode hint —— 一眼能看懂两种模式行为差异
        modeHintLabel.font = .systemFont(ofSize: 11)
        modeHintLabel.textColor = .secondaryLabelColor
        modeHintLabel.alignment = .center
        content.addSubview(modeHintLabel)
        modeHintLabel.snp.makeConstraints { make in
            make.top.equalTo(modeSegmented.snp.bottom).offset(8)
            make.centerX.equalToSuperview()
        }

        setupConfigBoxes(content)

        // 操作按钮
        recordButton.bezelStyle = .rounded
        recordButton.target = self
        recordButton.action = #selector(toggleRecording(_:))
        recordButton.keyEquivalent = " "
        recordButton.controlSize = .large
        loadWavButton.bezelStyle = .rounded
        loadWavButton.target = self
        loadWavButton.action = #selector(loadWavAndRerun(_:))
        openFolderButton.bezelStyle = .rounded
        openFolderButton.target = self
        openFolderButton.action = #selector(openRecordingsFolder)
        let buttonsRow = NSStackView(views: [recordButton, loadWavButton, openFolderButton])
        buttonsRow.orientation = .horizontal
        buttonsRow.spacing = 12
        content.addSubview(buttonsRow)
        buttonsRow.snp.makeConstraints { make in
            make.top.equalTo(configStack.snp.bottom).offset(20)
            make.centerX.equalToSuperview()
        }

        // 状态区
        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping
        liveStateLabel.alignment = .center
        liveStateLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        liveStateLabel.textColor = .secondaryLabelColor
        lastFileLabel.alignment = .center
        lastFileLabel.font = .systemFont(ofSize: 11)
        lastFileLabel.textColor = .tertiaryLabelColor
        lastFileLabel.maximumNumberOfLines = 1
        lastFileLabel.lineBreakMode = .byTruncatingMiddle
        let statusStack = NSStackView(
            views: [statusLabel, liveStateLabel, lastFileLabel])
        statusStack.orientation = .vertical
        statusStack.alignment = .centerX
        statusStack.spacing = 4
        content.addSubview(statusStack)
        statusStack.snp.makeConstraints { make in
            make.top.equalTo(buttonsRow.snp.bottom).offset(18)
            make.leading.trailing.equalToSuperview().inset(24)
        }

        versionLabel.alignment = .center
        versionLabel.font = .systemFont(ofSize: 10)
        versionLabel.textColor = .tertiaryLabelColor
        content.addSubview(versionLabel)
        versionLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().offset(-16)
        }
    }

    private func setupConfigBoxes(_ content: NSView) {
        // 短时
        shortConfigBox.title = "短时参数 · 单位 ms"
        shortConfigBox.contentView = Self.configRows([
            ("head_silence_timeout",
             "按下录音后，多久没听到说话就放弃（防手滑开了不说话）",
             shortHead),
            ("tail_silence",
             "说完后连续静音多久判定一句完整 · 短时最关键参数",
             shortTail),
            ("max_duration",
             "单次录音时长硬上限；到了强制结束",
             shortMax),
        ])

        // 长时
        longConfigBox.title = "长时参数 · 单位 ms(max_session=0 表示不限)"
        let longGrid = Self.configRows([
            ("head_silence_timeout",
             "按下录音后，多久没听到说话就放弃",
             longHead),
            ("max_sentence_duration",
             "单句最长时长；超了强制切一句，防一口气说太长",
             longMaxSent),
            ("max_session_duration",
             "整个会话最长时长；0 = 不限",
             longMaxSess),
            ("tail_silence_initial",
             "动态尾端点初始值 —— 刚开始录音时用这个(较宽容)",
             longTailInit),
            ("tail_silence_min",
             "动态尾端点下限 —— 说得越久向这个值收紧",
             longTailMin),
        ])
        let longContainer = NSView()
        longContainer.addSubview(longGrid)
        longContainer.addSubview(longDynamic)
        longGrid.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        longDynamic.state = .on
        longDynamic.toolTip = "关掉则尾静音恒等于 initial 值；fgvad 的核心就是这条动态曲线"
        longDynamic.snp.makeConstraints { make in
            make.top.equalTo(longGrid.snp.bottom).offset(8)
            make.leading.equalToSuperview().offset(16)
            make.bottom.equalToSuperview().offset(-4)
        }
        longConfigBox.contentView = longContainer

        // 两个 box 放进 configStack——isHidden 时 NSStackView 自动 collapse。
        configStack.orientation = .vertical
        configStack.spacing = 0
        configStack.addArrangedSubview(shortConfigBox)
        configStack.addArrangedSubview(longConfigBox)
        content.addSubview(configStack)
        configStack.snp.makeConstraints { make in
            make.top.equalTo(modeHintLabel.snp.bottom).offset(14)
            make.leading.trailing.equalToSuperview().inset(24)
        }
    }

    /// 每行：name(加粗，左) + 输入框(80w，右对齐) + ms 单位；下一行是 desc 小灰字。
    private static func configRows(_ rows: [(name: String, desc: String, field: NSTextField)]) -> NSView {
        let container = NSView()
        var prev: NSView?
        for row in rows {
            let name = NSTextField(labelWithString: row.name)
            name.font = .systemFont(ofSize: 13, weight: .semibold)
            let desc = NSTextField(labelWithString: row.desc)
            desc.font = .systemFont(ofSize: 11)
            desc.textColor = .secondaryLabelColor
            desc.maximumNumberOfLines = 2
            desc.lineBreakMode = .byWordWrapping
            let unit = NSTextField(labelWithString: "ms")
            unit.font = .systemFont(ofSize: 11)
            unit.textColor = .tertiaryLabelColor
            row.field.alignment = .right
            container.addSubview(name)
            container.addSubview(row.field)
            container.addSubview(unit)
            container.addSubview(desc)

            row.field.snp.makeConstraints { make in
                if let p = prev {
                    make.top.equalTo(p.snp.bottom).offset(14)
                } else {
                    make.top.equalToSuperview().offset(10)
                }
                make.trailing.equalTo(unit.snp.leading).offset(-6)
                make.width.equalTo(80)
                make.height.equalTo(22)
            }
            unit.snp.makeConstraints { make in
                make.centerY.equalTo(row.field)
                make.trailing.equalToSuperview().offset(-16)
                make.width.equalTo(20)
            }
            name.snp.makeConstraints { make in
                make.centerY.equalTo(row.field)
                make.leading.equalToSuperview().offset(16)
                make.trailing.lessThanOrEqualTo(row.field.snp.leading).offset(-12)
            }
            desc.snp.makeConstraints { make in
                make.top.equalTo(row.field.snp.bottom).offset(4)
                make.leading.equalToSuperview().offset(16)
                make.trailing.equalToSuperview().offset(-16)
            }
            prev = desc
        }
        prev?.snp.makeConstraints { make in
            make.bottom.equalToSuperview().offset(-12)
        }
        return container
    }

    // MARK: - Mode toggle

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        guard !recorder.isRecording else {
            // 防止录音中切 mode
            sender.selectedSegment = mode.rawValue
            return
        }
        applyMode(Mode(rawValue: sender.selectedSegment) ?? .short)
    }

    private func applyMode(_ m: Mode) {
        mode = m
        modeSegmented.selectedSegment = m.rawValue
        shortConfigBox.isHidden = (m != .short)
        longConfigBox.isHidden = (m != .long)
        modeHintLabel.stringValue = m == .short
            ? "说完自动停止 · 按下后请立即开口（3 秒内无声会取消）"
            : "需手动停止 · 支持多句连续；尾部允许时长随说话累积逐渐收紧"
        statusLabel.stringValue = "就绪"
        liveStateLabel.stringValue = ""
    }

    // MARK: - Record

    @objc private func toggleRecording(_ sender: Any?) {
        if recorder.isRecording {
            manualStop()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let analyzer: FgVadAnalyzer
        do {
            analyzer = try FgVadAnalyzer(mode: currentAnalyzerMode())
        } catch {
            statusLabel.stringValue = "创建 analyzer 失败：\(error)"
            return
        }
        analyzer.start()
        self.analyzer = analyzer
        sentenceCount = 0

        recorder.onChunk = { [weak self] chunk in
            self?.handleChunk(chunk)
        }
        recorder.onWarmupComplete = { skipped in
            let ms = Double(skipped) / 16.0
            DemoLog.log(String(format: "warmup complete · skipped %d samples (~%.0fms)", skipped, ms))
        }

        do {
            try recorder.start()
        } catch {
            statusLabel.stringValue = "录音启动失败：\(error)"
            self.analyzer = nil
            return
        }

        recordButton.title = "停止录音"
        modeSegmented.isEnabled = false
        shortConfigBox.isHidden = true  // 录音中隐藏 config 防止误改
        longConfigBox.isHidden = true
        statusLabel.stringValue = mode == .short ? "录音中 · 说完会自动结束" : "录音中 · 手动点停止结束"
        liveStateLabel.stringValue = "0.0s · state=Idle"
        lastFileLabel.stringValue = ""
        recordingStartDate = Date()
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateLiveLabel()
        }
        DemoLog.log("startRecording: mode=\(mode == .short ? "short" : "long")")
    }

    private func updateLiveLabel() {
        guard recorder.isRecording, let start = recordingStartDate else { return }
        let elapsed = Date().timeIntervalSince(start)
        let state = analyzer?.state.label ?? "-"
        liveStateLabel.stringValue = String(
            format: "%.1fs · state=%@ · 句数=%d", elapsed, state, sentenceCount)
    }

    private func handleChunk(_ chunk: UnsafeBufferPointer<Int16>) {
        guard let analyzer else { return }
        let results: [FgVadAnalyzer.Result]
        do {
            results = try analyzer.feed(chunk)
        } catch {
            DemoLog.log("feed failed: \(error)")
            return
        }
        let state = analyzer.state
        let shouldAutoStop = (mode == .short && state == FgVadState_End)

        DispatchQueue.main.async { [weak self] in
            self?.applyStreamingResults(results, state: state)
            if shouldAutoStop {
                self?.autoStopAfterShortEnd()
            }
        }
    }

    private func applyStreamingResults(
        _ results: [FgVadAnalyzer.Result], state: FgVadState
    ) {
        for r in results {
            if r.event != FgVadEvent_None_, let ev = r.event.label {
                DemoLog.log(Self.formatResult(r))
                if r.event == FgVadEvent_SentenceStarted {
                    sentenceCount += 1
                }
                _ = ev  // silence warning
            } else {
                // 非事件段（Silence / Active）每 16ms 一个，太啰嗦，不 log
            }
        }
        // liveStateLabel 由 tickTimer 每 250ms 统一刷新，这里不抢
        _ = state
    }

    private func autoStopAfterShortEnd() {
        DemoLog.log("short mode auto-stop (state=End)")
        finishRecording(reason: "自动停止")
    }

    private func manualStop() {
        analyzer?.stop()  // 对应长时：让 fgvad 内部 flush trailing
        finishRecording(reason: "手动停止")
    }

    private func finishRecording(reason: String) {
        // 先摘掉 onChunk，避免停机后再喂
        recorder.onChunk = nil
        tickTimer?.invalidate()
        tickTimer = nil
        recordingStartDate = nil
        let duration: Double
        do {
            let url = try recorder.stopAndSave()
            duration = Double(recorder.lastRecordedSampleCount) / 16000.0
            lastFileLabel.stringValue = String(
                format: "%.2fs · %@", duration, url.lastPathComponent)
        } catch {
            duration = 0
            lastFileLabel.stringValue = "保存失败：\(error)"
        }

        let finalState = analyzer?.state ?? FgVadState_Idle
        let endReason = analyzer?.endReason ?? FgVadEndReason_None_
        analyzer = nil

        recordButton.title = "开始录音"
        modeSegmented.isEnabled = true
        applyMode(mode)  // 恢复 config 可见性
        statusLabel.stringValue = Self.summaryText(
            fallbackTrigger: reason, endReason: endReason,
            sentenceCount: sentenceCount, durationSec: duration)
        liveStateLabel.stringValue = ""
        DemoLog.log("finished: sentenceCount=\(sentenceCount) "
            + "finalState=\(finalState.label) endReason=\(endReason.label)")
    }

    /// 把 FgVadEndReason 翻译成中文一句话，消除 "End/HeadSilenceTimeout" 这种
    /// 让用户一脸问号的输出。fallbackTrigger 只在 endReason=None 时用得上。
    private static func summaryText(
        fallbackTrigger: String, endReason: FgVadEndReason,
        sentenceCount: Int, durationSec: Double
    ) -> String {
        let why: String
        switch endReason {
        case FgVadEndReason_SpeechCompleted:
            why = "说完了（尾静音达标）"
        case FgVadEndReason_HeadSilenceTimeout:
            why = "未听到说话（头部静音超时）"
        case FgVadEndReason_MaxDurationReached:
            why = "达到最大时长上限"
        case FgVadEndReason_ExternalStop:
            why = "手动停止"
        default:
            why = fallbackTrigger
        }
        return String(
            format: "已结束 · %@ · %d 句 · %.1fs",
            why, sentenceCount, durationSec)
    }

    // MARK: - Rerun on file

    @objc private func loadWavAndRerun(_ sender: Any?) {
        guard !recorder.isRecording else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav]
        panel.directoryURL = Recorder.recordingsDirectory()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rerunOnFile(url)
    }

    private func rerunOnFile(_ url: URL) {
        statusLabel.stringValue = "读取 WAV…"
        liveStateLabel.stringValue = ""
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let summary: String
            do {
                let samples = try WavIO.readMonoInt16(from: url)
                DemoLog.log("rerun: file=\(url.lastPathComponent) "
                    + "samples=\(samples.count) "
                    + "(\(String(format: "%.2f", Double(samples.count)/16000.0))s) "
                    + "mode=\(self.mode == .short ? "short" : "long")")
                let analyzerMode = self.currentAnalyzerMode()
                let (results, finalState, endReason) =
                    try FgVadAnalyzer.analyze(samples: samples, mode: analyzerMode)
                var sent = 0
                for (i, r) in results.enumerated() {
                    if r.event == FgVadEvent_SentenceStarted { sent += 1 }
                    DemoLog.log("[#\(i)] " + Self.formatResult(r))
                }
                DemoLog.log("rerun done: \(sent) 句 finalState=\(finalState.label) "
                    + "endReason=\(endReason.label)")
                summary = "重跑完成 · \(sent) 句 · "
                    + "\(finalState.label)/\(endReason.label)"
            } catch {
                DemoLog.log("rerun failed: \(error)")
                summary = "重跑失败：\(error)"
            }
            DispatchQueue.main.async {
                self.statusLabel.stringValue = summary
                self.lastFileLabel.stringValue = url.lastPathComponent
            }
        }
    }

    // MARK: - Helpers

    private func currentAnalyzerMode() -> FgVadAnalyzer.Mode {
        switch mode {
        case .short:
            return .short(FgVadAnalyzer.ShortConfig(
                headSilenceTimeoutMs: Self.parseU32(shortHead, 3000),
                tailSilenceMs: Self.parseU32(shortTail, 2000),
                maxDurationMs: Self.parseU32(shortMax, 30000)))
        case .long:
            return .long(FgVadAnalyzer.LongConfig(
                headSilenceTimeoutMs: Self.parseU32(longHead, 3000),
                maxSentenceDurationMs: Self.parseU32(longMaxSent, 30000),
                maxSessionDurationMs: Self.parseU32(longMaxSess, 0),
                tailSilenceMsInitial: Self.parseU32(longTailInit, 2000),
                tailSilenceMsMin: Self.parseU32(longTailMin, 600),
                enableDynamicTail: longDynamic.state == .on))
        }
    }

    private static func parseU32(_ field: NSTextField, _ fallback: UInt32) -> UInt32 {
        UInt32(field.stringValue) ?? fallback
    }

    private static func formatResult(_ r: FgVadAnalyzer.Result) -> String {
        let tStart = Double(r.streamOffsetSample) / 16000.0
        let tEnd = tStart + Double(r.audioLen) / 16000.0
        var bits = [
            String(format: "%.3fs-%.3fs", tStart, tEnd),
            r.type.label,
            "state=\(r.state.label)"
        ]
        if let ev = r.event.label { bits.append("event=\(ev)") }
        if r.endReason != FgVadEndReason_None_ {
            bits.append("endReason=\(r.endReason.label)")
        }
        return bits.joined(separator: " ")
    }

    @objc private func openRecordingsFolder() {
        let url = Recorder.recordingsDirectory()
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - CardView

/// NSBox 在 dark 模式下的 `.primary` 样式太素、缺层次，用自绘的圆角卡片替代。
/// API 保留 `title` 与 `contentView`，可无缝替换 NSBox。
final class CardView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let contentHost = NSView()

    var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    var contentView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            guard let v = contentView else { return }
            contentHost.addSubview(v)
            v.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        }
    }

    init() {
        super.init(frame: .zero)
        // 强制这棵子树走 aqua —— init 阶段还没进 view hierarchy，如果不显式设，
        // 系统 dark mode 用户会看到 `.secondaryLabelColor` 等 dynamic 色按 dark
        // 解析，导致标题文字浅灰、难看清。
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        // layer 的背景/边框用硬编码，不走 dynamic 色的 .cgColor 提取 —— 因为
        // CGColor 是从当前线程 drawing context 的 appearance 提取的静态值，
        // init 时 detach 状态下往往拿到系统 appearance (dark) 下的深色。
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 0, alpha: 0.1).cgColor

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        addSubview(titleLabel)
        addSubview(contentHost)

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.equalToSuperview().offset(18)
            make.trailing.lessThanOrEqualToSuperview().offset(-18)
        }
        contentHost.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }
}
