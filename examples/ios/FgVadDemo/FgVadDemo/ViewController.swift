import UIKit
import AVFoundation

/// fgvad iOS Demo 主视图。
///
/// 功能跟 macOS demo 对等的最小子集：
/// - 短/长时模式切换
/// - 各模式的关键参数表单
/// - 开始/停止录音
/// - 实时事件日志（句子开始 / 结束 / ForceCut / HeadSilenceTimeout）
///
/// 布局：纯 frame 算坐标，遵守 [[feedback-ios-frame-layout]] 偏好。
final class ViewController: UIViewController {

    // MARK: - Mode

    private enum Mode: Int { case short = 0, long = 1 }

    private var currentMode: Mode = .short

    // MARK: - Subviews

    private let modeSegmented = UISegmentedControl(items: ["短时 Short", "长时 Long"])
    private let modeHintLabel = UILabel()

    // 短时参数
    private let shortHeadField = ViewController.makeNumField(default: "3000")
    private let shortTailField = ViewController.makeNumField(default: "2000")
    private let shortMaxField  = ViewController.makeNumField(default: "30000")

    // 长时参数
    private let longHeadField        = ViewController.makeNumField(default: "3000")
    private let longMaxSentField     = ViewController.makeNumField(default: "30000")
    private let longTailInitField    = ViewController.makeNumField(default: "2000")
    private let longTailMinField     = ViewController.makeNumField(default: "600")
    private let longDynamicSwitch    = UISwitch()

    private let recordButton = UIButton(type: .system)
    private let loadTestAudioButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    // 处理中遮罩（runAnalyze 期间显示，吃掉点击）
    private let processingOverlay = UIView()
    private let processingIndicator = UIActivityIndicatorView(style: .large)
    private let processingLabel = UILabel()

    // 试听 / 按句切分结果
    private var audioPlayer: AVAudioPlayer?
    private var lastWavURL: URL?
    private var sentenceRecords: [SentenceRecord] = []

    fileprivate struct SentenceRecord {
        let index: Int
        let startSample: UInt64
        let endSample: UInt64
        let endEvent: FgVadEvent
        var startMs: Double { Double(startSample) / 16.0 }
        var endMs: Double { Double(endSample) / 16.0 }
        static func formatMs(_ ms: Double) -> String {
            let total = Int(ms)
            let m = total / 60_000
            let s = (total % 60_000) / 1_000
            let ms = total % 1_000
            return String(format: "%02d:%02d.%03d", m, s, ms)
        }
    }
    private let sentenceTable = UITableView(frame: .zero, style: .plain)
    private let emptyStateLabel = UILabel()
    private let versionLabel = UILabel()

    // MARK: - Models

    private let recorder = FGIOSRecorder()
    private var analyzer: FgVadAnalyzer?
    private var wavWriter: WavWriter?
    private var sentenceCount = 0
    private var isAnalyzing: Bool = false
    private var startDate: Date?
    private var tickTimer: Timer?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "FgVad Demo"
        view.backgroundColor = .systemBackground
        setupSubviews()
        applyMode(.short)
    }

    private func setupSubviews() {
        modeSegmented.selectedSegmentIndex = 0
        modeSegmented.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        view.addSubview(modeSegmented)

        modeHintLabel.font = .systemFont(ofSize: 12)
        modeHintLabel.textColor = .secondaryLabel
        modeHintLabel.numberOfLines = 0
        modeHintLabel.textAlignment = .center
        view.addSubview(modeHintLabel)

        // 短时字段（默认显示）
        addFieldRow(name: "head_silence_timeout", field: shortHeadField, unit: "ms")
        addFieldRow(name: "tail_silence",         field: shortTailField, unit: "ms")
        addFieldRow(name: "max_duration",         field: shortMaxField,  unit: "ms")

        // 长时字段（默认隐藏）
        addFieldRow(name: "head_silence_timeout", field: longHeadField,     unit: "ms")
        addFieldRow(name: "max_sentence_duration", field: longMaxSentField, unit: "ms")
        addFieldRow(name: "tail_silence_initial", field: longTailInitField, unit: "ms")
        addFieldRow(name: "tail_silence_min",     field: longTailMinField,  unit: "ms")

        // 长时独占的动态曲线开关
        let dynLabel = UILabel()
        dynLabel.text = "启用动态尾端点曲线"
        dynLabel.font = .systemFont(ofSize: 13)
        dynLabel.tag = 9001  // 用 tag 找回，hide 用
        view.addSubview(dynLabel)

        longDynamicSwitch.isOn = true
        longDynamicSwitch.tag = 9002
        view.addSubview(longDynamicSwitch)

        recordButton.setTitle("开始录音", for: .normal)
        recordButton.backgroundColor = .systemBlue
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        recordButton.layer.cornerRadius = 12
        recordButton.addTarget(self, action: #selector(toggleRecord), for: .touchUpInside)
        view.addSubview(recordButton)

        loadTestAudioButton.setTitle("加载测试音频", for: .normal)
        loadTestAudioButton.backgroundColor = .systemGray5
        loadTestAudioButton.setTitleColor(.label, for: .normal)
        loadTestAudioButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        loadTestAudioButton.layer.cornerRadius = 10
        loadTestAudioButton.addTarget(self, action: #selector(showTestAudioPicker), for: .touchUpInside)
        view.addSubview(loadTestAudioButton)

        statusLabel.text = "就绪"
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        view.addSubview(statusLabel)

        sentenceTable.dataSource = self
        sentenceTable.delegate = self
        sentenceTable.register(SentenceCell.self, forCellReuseIdentifier: SentenceCell.reuseID)
        sentenceTable.layer.borderColor = UIColor.separator.cgColor
        sentenceTable.layer.borderWidth = 0.5
        sentenceTable.layer.cornerRadius = 8
        sentenceTable.rowHeight = 52
        sentenceTable.separatorInset = .init(top: 0, left: 12, bottom: 0, right: 12)
        view.addSubview(sentenceTable)

        emptyStateLabel.text = "选个测试音频跑一次 VAD 看切分结果\n或开始录音"
        emptyStateLabel.font = .systemFont(ofSize: 13)
        emptyStateLabel.textColor = .tertiaryLabel
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        view.addSubview(emptyStateLabel)

        versionLabel.text = "fgvad iOS demo · ten-vad"
        versionLabel.font = .systemFont(ofSize: 10)
        versionLabel.textColor = .tertiaryLabel
        versionLabel.textAlignment = .center
        view.addSubview(versionLabel)

        // 处理中遮罩
        processingOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        processingOverlay.isHidden = true
        view.addSubview(processingOverlay)

        processingIndicator.color = .white
        processingIndicator.hidesWhenStopped = true
        processingOverlay.addSubview(processingIndicator)

        processingLabel.text = "处理中…"
        processingLabel.textColor = .white
        processingLabel.font = .systemFont(ofSize: 13, weight: .medium)
        processingLabel.textAlignment = .center
        processingOverlay.addSubview(processingLabel)
    }

    private static func makeNumField(default value: String) -> UITextField {
        let f = UITextField()
        f.text = value
        f.borderStyle = .roundedRect
        f.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        f.textAlignment = .right
        f.keyboardType = .numberPad
        return f
    }

    private func addFieldRow(name: String, field: UITextField, unit: String) {
        let label = UILabel()
        label.text = name
        label.font = .systemFont(ofSize: 13)
        label.tag = 0  // 行标签 + 输入框 + 单位用容器组合管理
        view.addSubview(label)

        let unitLabel = UILabel()
        unitLabel.text = unit
        unitLabel.font = .systemFont(ofSize: 11)
        unitLabel.textColor = .tertiaryLabel
        view.addSubview(unitLabel)

        // 通过 field.tag 关联——这里用同名一组三件套靠 layoutSubviews 时按 field 找回
        // 简化：把 label 和 unitLabel 挂到 field 自身的 attached objects（用 ObjC associated 也可以）
        // 这里用更直观的方式：保留为 ivars 太繁琐，直接通过 row 索引在 layoutSubviews 里算坐标
        field.layer.setValue(label, forKey: "fg.label")
        field.layer.setValue(unitLabel, forKey: "fg.unitLabel")
        view.addSubview(field)
    }

    // MARK: - Mode toggle

    @objc private func modeChanged() {
        guard !recorder.isRecording else {
            modeSegmented.selectedSegmentIndex = currentMode.rawValue
            return
        }
        applyMode(Mode(rawValue: modeSegmented.selectedSegmentIndex) ?? .short)
    }

    private func applyMode(_ m: Mode) {
        currentMode = m
        modeSegmented.selectedSegmentIndex = m.rawValue

        let isShort = (m == .short)
        shortHeadField.isHidden = !isShort
        shortTailField.isHidden = !isShort
        shortMaxField.isHidden = !isShort
        longHeadField.isHidden = isShort
        longMaxSentField.isHidden = isShort
        longTailInitField.isHidden = isShort
        longTailMinField.isHidden = isShort
        view.viewWithTag(9001)?.isHidden = isShort
        view.viewWithTag(9002)?.isHidden = isShort

        // 三件套关联标签
        let allFields = [shortHeadField, shortTailField, shortMaxField,
                         longHeadField, longMaxSentField, longTailInitField, longTailMinField]
        for f in allFields {
            (f.layer.value(forKey: "fg.label") as? UIView)?.isHidden = f.isHidden
            (f.layer.value(forKey: "fg.unitLabel") as? UIView)?.isHidden = f.isHidden
        }

        modeHintLabel.text = isShort
            ? "短时：说完自动停止 · 按下后请立即开口（3 秒内无声会取消）"
            : "长时：手动停止 · 多句连续；尾部允许时长随累积说话逐渐收紧"
        statusLabel.text = "就绪"
        view.setNeedsLayout()
    }

    // MARK: - Layout

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        let width = view.bounds.width
        let inset: CGFloat = 16

        modeSegmented.frame = CGRect(
            x: inset, y: safe.top + 12, width: width - inset * 2, height: 36
        )

        modeHintLabel.frame = CGRect(
            x: inset, y: modeSegmented.frame.maxY + 6,
            width: width - inset * 2, height: 32
        )

        // 字段区
        var y = modeHintLabel.frame.maxY + 12
        let isShort = currentMode == .short
        let activeFields: [UITextField] = isShort
            ? [shortHeadField, shortTailField, shortMaxField]
            : [longHeadField, longMaxSentField, longTailInitField, longTailMinField]

        let fieldW: CGFloat = 90
        for f in activeFields {
            let label = f.layer.value(forKey: "fg.label") as? UILabel
            let unit  = f.layer.value(forKey: "fg.unitLabel") as? UILabel
            label?.frame = CGRect(x: inset, y: y, width: width - inset * 2 - fieldW - 30, height: 28)
            f.frame = CGRect(x: width - inset - fieldW - 24, y: y, width: fieldW, height: 28)
            unit?.frame = CGRect(x: width - inset - 22, y: y + 6, width: 22, height: 18)
            y += 36
        }

        // 长时独占的 dynamic 开关
        if !isShort {
            view.viewWithTag(9001)?.frame = CGRect(x: inset, y: y, width: 200, height: 30)
            view.viewWithTag(9002)?.frame = CGRect(x: width - inset - 52, y: y, width: 52, height: 30)
            y += 40
        }

        recordButton.frame = CGRect(x: inset, y: y + 6, width: width - inset * 2, height: 48)
        y = recordButton.frame.maxY + 8

        loadTestAudioButton.frame = CGRect(x: inset, y: y, width: width - inset * 2, height: 36)
        y = loadTestAudioButton.frame.maxY + 12

        statusLabel.frame = CGRect(x: inset, y: y, width: width - inset * 2, height: 38)
        y = statusLabel.frame.maxY + 8

        let tableBottom = view.bounds.height - safe.bottom - 24 - 18
        sentenceTable.frame = CGRect(x: inset, y: y, width: width - inset * 2, height: max(120, tableBottom - y))
        emptyStateLabel.frame = sentenceTable.frame.insetBy(dx: 16, dy: 16)

        versionLabel.frame = CGRect(
            x: inset, y: view.bounds.height - safe.bottom - 18,
            width: width - inset * 2, height: 14
        )

        // 遮罩铺满全屏
        processingOverlay.frame = view.bounds
        let centerX = view.bounds.midX
        let centerY = view.bounds.midY
        processingIndicator.frame = CGRect(x: centerX - 25, y: centerY - 30, width: 50, height: 50)
        processingLabel.frame = CGRect(
            x: centerX - 80, y: centerY + 25, width: 160, height: 20
        )
    }

    // MARK: - Recording

    @objc private func toggleRecord() {
        if recorder.isRecording {
            stopRecording(reason: "手动停止")
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        recorder.requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.statusLabel.text = "麦克风权限被拒绝"
                return
            }
            self.actuallyStart()
        }
    }

    private func actuallyStart() {
        let analyzer: FgVadAnalyzer
        do {
            analyzer = try FgVadAnalyzer(mode: currentAnalyzerMode())
        } catch {
            statusLabel.text = "创建 analyzer 失败：\(error)"
            return
        }
        analyzer.start()
        self.analyzer = analyzer
        sentenceCount = 0
        applySentenceRecords([])  // 录音模式下不维护 sentence list（无源 wav 不能 ▶ 试听）

        recorder.delegate = self
        guard recorder.start() else {
            self.analyzer = nil
            return
        }

        // 创建 WavWriter，tee mic PCM 到 Documents/recordings/
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "recording_\(formatter.string(from: Date())).wav"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let wavURL = docs.appendingPathComponent("recordings/\(filename)")
        do {
            wavWriter = try WavWriter(url: wavURL)
            DemoLogger.shared.i("wav", "WavWriter opened: \(wavURL.lastPathComponent)")
        } catch {
            DemoLogger.shared.w("wav", "WavWriter init failed: \(error) — recording continues without file save")
        }

        startDate = Date()
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateTick()
        }

        recordButton.setTitle("停止录音", for: .normal)
        recordButton.backgroundColor = .systemRed
        modeSegmented.isEnabled = false
        statusLabel.text = currentMode == .short ? "录音中 · 说完自动停" : "录音中 · 手动点停止"
        log("[start] mode=\(currentMode == .short ? "short" : "long")")
    }

    private func stopRecording(reason: String) {
        analyzer?.stop()
        recorder.stop()

        // 收尾 WAV 文件，回填 header size 字段
        do {
            try wavWriter?.finalize()
        } catch {
            DemoLogger.shared.e("wav", "finalize failed: \(error)")
        }
        wavWriter = nil

        let finalState = analyzer?.state ?? FgVadState_Idle
        let endReason = analyzer?.endReason ?? FgVadEndReason_None_
        analyzer = nil

        tickTimer?.invalidate()
        tickTimer = nil
        startDate = nil

        recordButton.setTitle("开始录音", for: .normal)
        recordButton.backgroundColor = .systemBlue
        modeSegmented.isEnabled = true

        statusLabel.text = "已结束 · \(reason) · \(sentenceCount) 句 · \(endReason.label)"
        log("[stop] reason=\(reason) finalState=\(finalState.label) endReason=\(endReason.label)")
    }

    private func updateTick() {
        guard let s = startDate else { return }
        let elapsed = Date().timeIntervalSince(s)
        let stateLabel = analyzer?.state.label ?? "-"
        statusLabel.text = String(
            format: "录音中 · %.1fs · state=%@ · 句数=%d",
            elapsed, stateLabel, sentenceCount
        )
    }

    /// 控制台日志：同时写 Documents/run.log 和 Xcode console。
    private func log(_ msg: String) {
        DemoLogger.shared.i("VC", msg)
    }

    /// 更新 sentenceRecords + 同步 table view + empty state 显示。
    private func applySentenceRecords(_ records: [SentenceRecord]) {
        sentenceRecords = records
        sentenceTable.reloadData()
        emptyStateLabel.isHidden = !records.isEmpty
        if !records.isEmpty {
            sentenceTable.scrollToRow(
                at: IndexPath(row: 0, section: 0),
                at: .top, animated: false)
        }
    }

    private func currentAnalyzerMode() -> FgVadAnalyzer.Mode {
        switch currentMode {
        case .short:
            return .short(FgVadAnalyzer.ShortConfig(
                headSilenceTimeoutMs: parseU32(shortHeadField, 3000),
                tailSilenceMs: parseU32(shortTailField, 2000),
                maxDurationMs: parseU32(shortMaxField, 30000)))
        case .long:
            return .long(FgVadAnalyzer.LongConfig(
                headSilenceTimeoutMs: parseU32(longHeadField, 3000),
                maxSentenceDurationMs: parseU32(longMaxSentField, 30000),
                maxSessionDurationMs: 0,
                tailSilenceMsInitial: parseU32(longTailInitField, 2000),
                tailSilenceMsMin: parseU32(longTailMinField, 600),
                enableDynamicTail: longDynamicSwitch.isOn))
        }
    }

    private func parseU32(_ field: UITextField, _ fallback: UInt32) -> UInt32 {
        UInt32(field.text ?? "") ?? fallback
    }

    /// 处理中遮罩开关——同时禁用关键交互入口。
    private func setProcessing(_ on: Bool, hint: String = "处理中…") {
        if on {
            processingLabel.text = hint
            processingOverlay.isHidden = false
            processingIndicator.startAnimating()
            view.bringSubviewToFront(processingOverlay)
        } else {
            processingIndicator.stopAnimating()
            processingOverlay.isHidden = true
        }
        recordButton.isEnabled = !on
        loadTestAudioButton.isEnabled = !on
        modeSegmented.isEnabled = !on
    }

    /// 简单 toast：底部居中黑色圆角，淡入显示一会儿淡出。
    private func showToast(_ message: String, duration: TimeInterval = 1.6) {
        let toast = UILabel()
        toast.text = message
        toast.textColor = .white
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.textAlignment = .center
        toast.numberOfLines = 0
        toast.layer.cornerRadius = 14
        toast.layer.masksToBounds = true

        let maxW = view.bounds.width - 64
        let textSize = (toast.text ?? "").boundingRect(
            with: CGSize(width: maxW - 32, height: 200),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: toast.font!],
            context: nil
        )
        let toastW = min(maxW, ceil(textSize.width) + 32)
        let toastH = ceil(textSize.height) + 22
        toast.frame = CGRect(
            x: (view.bounds.width - toastW) / 2,
            y: view.bounds.height - view.safeAreaInsets.bottom - 90,
            width: toastW, height: toastH
        )
        toast.alpha = 0
        view.addSubview(toast)

        UIView.animate(withDuration: 0.18, animations: { toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.32, delay: duration, options: [], animations: {
                toast.alpha = 0
            }) { _ in
                toast.removeFromSuperview()
            }
        }
    }

    @objc private func showTestAudioPicker() {
        guard !recorder.isRecording else { return }
        let picker = AudioPickerViewController()
        picker.onPreview = { [weak self] url in
            self?.playOriginal(url: url)
        }
        picker.onAnalyze = { [weak self] url in
            self?.runAnalyze(on: url)
        }
        let nav = UINavigationController(rootViewController: picker)
        present(nav, animated: true)
    }

    /// 直接播放原 WAV（无 analyze）。
    private func playOriginal(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            showToast("▶ 试听 \(url.lastPathComponent)")
        } catch {
            showToast("播放失败：\(error.localizedDescription)")
        }
    }

    private func playSentence(_ record: SentenceRecord) {
        guard let wavURL = lastWavURL else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let allSamples = try WavIO.readMonoInt16(from: wavURL)
                let start = Int(record.startSample)
                let end = min(Int(record.endSample), allSamples.count)
                guard start < end else { return }
                let sentSamples = Array(allSamples[start..<end])
                let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("fgvad_sent_\(record.index).wav")
                try WavIO.writeMonoInt16(sentSamples, sampleRate: 16_000, to: tmpURL)
                DispatchQueue.main.async {
                    do {
                        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                        try AVAudioSession.sharedInstance().setActive(true)
                        self.audioPlayer = try AVAudioPlayer(contentsOf: tmpURL)
                        self.audioPlayer?.play()
                        self.showToast("▶ Sentence \(record.index)")
                    } catch {
                        self.showToast("播放失败：\(error.localizedDescription)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showToast("切片失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func runAnalyze(on url: URL) {
        guard !isAnalyzing else {
            showToast("解析进行中，请稍候")
            return
        }
        isAnalyzing = true
        recordButton.isEnabled = false
        loadTestAudioButton.isEnabled = false

        let filename = url.lastPathComponent
        let modeLabel = currentMode == .short ? "short" : "long"
        log("[rerun] file=\(filename) mode=\(modeLabel)")

        // 主线程：清空结果，更新状态栏，关闭遮罩（流式过程不 block UI）
        sentenceRecords = []
        sentenceTable.reloadData()
        emptyStateLabel.isHidden = false
        statusLabel.text = "状态：解析中… 0 句 (\(filename))"
        lastWavURL = url

        let mode = currentAnalyzerMode()
        let started = Date()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // 读 WAV（快，仅 I/O，几十毫秒）
            let samples: [Int16]
            do {
                samples = try WavIO.readMonoInt16(from: url)
            } catch {
                DispatchQueue.main.async {
                    self.isAnalyzing = false
                    self.recordButton.isEnabled = true
                    self.loadTestAudioButton.isEnabled = true
                    self.statusLabel.text = "失败：\(error.localizedDescription)"
                    self.log("[rerun error] read WAV: \(error)")
                    self.showToast("失败：\(error.localizedDescription)")
                }
                return
            }
            self.log("[rerun] samples=\(samples.count) (\(String(format: "%.1f", Double(samples.count)/16000.0))s)")

            // 流式喂入 VAD
            let vad: FgVadAnalyzer
            do {
                vad = try FgVadAnalyzer(mode: mode)
            } catch {
                DispatchQueue.main.async {
                    self.isAnalyzing = false
                    self.recordButton.isEnabled = true
                    self.loadTestAudioButton.isEnabled = true
                    self.statusLabel.text = "失败：create vad"
                    self.log("[rerun error] create vad: \(error)")
                    self.showToast("失败：无法创建 VAD 实例")
                }
                return
            }
            vad.start()

            // chunk-stream 核心循环
            let chunkSize = 1024
            var sentenceCount = 0      // 背景线程本地计数器
            var forceCutCount = 0
            var curStart: UInt64? = nil
            var offset = 0

            while offset < samples.count {
                let end = min(offset + chunkSize, samples.count)
                let slice = Array(samples[offset..<end])
                offset = end

                let results: [FgVadAnalyzer.Result]
                do {
                    results = try slice.withUnsafeBufferPointer { try vad.feed($0) }
                } catch {
                    DispatchQueue.main.async {
                        self.isAnalyzing = false
                        self.recordButton.isEnabled = true
                        self.loadTestAudioButton.isEnabled = true
                        self.statusLabel.text = "失败：\(error.localizedDescription)"
                        self.log("[rerun error] feed: \(error)")
                        self.showToast("失败：\(error.localizedDescription)")
                    }
                    vad.stop()
                    return
                }

                for r in results {
                    // 记日志（非 None 事件）
                    if r.event != FgVadEvent_None_, let ev = r.event.label {
                        let tStart = Double(r.streamOffsetSample) / 16000.0
                        let tEnd = tStart + Double(r.audioLen) / 16000.0
                        self.log(String(format: "  %.3fs-%.3fs %@", tStart, tEnd, ev))
                    }

                    if r.event == FgVadEvent_SentenceStarted {
                        curStart = r.streamOffsetSample

                    } else if r.event == FgVadEvent_SentenceEnded
                                || r.event == FgVadEvent_SentenceForceCut {
                        if r.event == FgVadEvent_SentenceForceCut { forceCutCount += 1 }
                        if let s = curStart {
                            sentenceCount += 1
                            let record = SentenceRecord(
                                index: sentenceCount,
                                startSample: s,
                                endSample: r.streamOffsetSample + UInt64(r.audioLen),
                                endEvent: r.event)
                            curStart = nil
                            let count = sentenceCount   // capture value
                            // 主线程：单点插入一行，保留滚动状态
                            DispatchQueue.main.async { [weak self] in
                                guard let self else { return }
                                self.sentenceRecords.append(record)
                                let idx = IndexPath(row: self.sentenceRecords.count - 1, section: 0)
                                self.sentenceTable.insertRows(at: [idx], with: .none)
                                self.emptyStateLabel.isHidden = true
                                self.statusLabel.text = "状态：解析中… \(count) 句"
                            }
                        }
                    }
                }
            }

            vad.stop()
            let finalEndReason = vad.endReason
            let finalState = vad.state
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)

            self.log("[rerun done] \(sentenceCount) 句 · \(forceCutCount) ForceCut · "
                + "\(finalState.label)/\(finalEndReason.label) · \(elapsedMs)ms")

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isAnalyzing = false
                self.recordButton.isEnabled = true
                self.loadTestAudioButton.isEnabled = true
                self.statusLabel.text = "重跑完成 · \(sentenceCount) 句 · \(finalEndReason.label)"
                let toastMsg: String
                if forceCutCount > 0 {
                    toastMsg = "✓ \(sentenceCount) 句 · \(forceCutCount) ForceCut\n\(elapsedMs)ms"
                } else {
                    toastMsg = "✓ \(sentenceCount) 句 · \(finalEndReason.label)\n\(elapsedMs)ms"
                }
                self.showToast(toastMsg, duration: 2.2)
            }
        }
    }
}

// MARK: - FGIOSRecorderDelegate

extension ViewController: FGIOSRecorderDelegate {

    func recorder(_ recorder: FGIOSRecorder,
                  didProduceFrames frames: UnsafePointer<Int16>,
                  count: UInt) {
        guard let analyzer else { return }

        // tee PCM 到 WavWriter（失败不影响 analyze 主流程）
        do {
            try wavWriter?.append(samples: frames, count: Int(count))
        } catch {
            DemoLogger.shared.e("wav", "append failed: \(error)")
        }

        let buffer = UnsafeBufferPointer(start: frames, count: Int(count))
        let results: [FgVadAnalyzer.Result]
        do {
            results = try analyzer.feed(buffer)
        } catch {
            log("[error] feed failed: \(error)")
            return
        }

        for r in results {
            if r.event != FgVadEvent_None_, let ev = r.event.label {
                let tStart = Double(r.streamOffsetSample) / 16000.0
                log(String(format: "  %.3fs %@", tStart, ev))
                if r.event == FgVadEvent_SentenceEnded
                    || r.event == FgVadEvent_SentenceForceCut {
                    sentenceCount += 1
                }
            }
        }

        // 短时模式遇 End 自动停
        if currentMode == .short, analyzer.state == FgVadState_End {
            stopRecording(reason: "短时 End")
        }
    }

    func recorderDidStart(_ recorder: FGIOSRecorder) {
        log("[recorder started]")
    }

    func recorderDidStop(_ recorder: FGIOSRecorder) {
        log("[recorder stopped]")
    }

    func recorder(_ recorder: FGIOSRecorder, didFailWithError error: Error) {
        log("[recorder error] \(error)")
        statusLabel.text = "录音失败：\(error.localizedDescription)"
    }
}

// MARK: - UITableViewDataSource / Delegate

extension ViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sentenceRecords.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: SentenceCell.reuseID, for: indexPath) as! SentenceCell
        let r = sentenceRecords[indexPath.row]
        cell.configure(record: r)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = sentenceRecords[indexPath.row]
        playSentence(record)
    }
}

// MARK: - SentenceCell（纯 frame 布局，无约束）

private final class SentenceCell: UITableViewCell {

    static let reuseID = "SentenceCell"

    private let indexLabel = UILabel()
    private let timeLabel = UILabel()
    private let eventLabel = UILabel()
    private let playGlyph = UILabel()  // ▶

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default

        indexLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(indexLabel)

        timeLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        timeLabel.textColor = .secondaryLabel
        contentView.addSubview(timeLabel)

        eventLabel.font = .systemFont(ofSize: 11, weight: .medium)
        contentView.addSubview(eventLabel)

        playGlyph.text = "▶"
        playGlyph.font = .systemFont(ofSize: 18)
        playGlyph.textColor = .systemBlue
        playGlyph.textAlignment = .center
        contentView.addSubview(playGlyph)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(record: ViewController.SentenceRecord) {
        indexLabel.text = "Sentence \(record.index)"
        timeLabel.text = "\(ViewController.SentenceRecord.formatMs(record.startMs)) – "
            + "\(ViewController.SentenceRecord.formatMs(record.endMs))"
        let isForceCut = record.endEvent == FgVadEvent_SentenceForceCut
        eventLabel.text = isForceCut ? "ForceCut" : "SentenceEnded"
        eventLabel.textColor = isForceCut ? .systemOrange : .systemGreen
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let glyphW: CGFloat = 32
        let leftInset: CGFloat = 14
        let rightInset: CGFloat = 12
        let topInset: CGFloat = 6

        playGlyph.frame = CGRect(
            x: bounds.width - rightInset - glyphW,
            y: 0, width: glyphW, height: bounds.height
        )

        let mainW = bounds.width - leftInset - rightInset - glyphW

        // 第一行：Sentence N + 事件 tag（右贴在 ▶ 左边）
        let firstRowH: CGFloat = 18
        let eventW: CGFloat = 100
        indexLabel.frame = CGRect(
            x: leftInset, y: topInset,
            width: mainW - eventW - 8, height: firstRowH
        )
        eventLabel.frame = CGRect(
            x: leftInset + mainW - eventW, y: topInset,
            width: eventW, height: firstRowH
        )
        eventLabel.textAlignment = .right

        // 第二行：时间戳
        timeLabel.frame = CGRect(
            x: leftInset, y: topInset + firstRowH + 2,
            width: mainW, height: 18
        )
    }
}
