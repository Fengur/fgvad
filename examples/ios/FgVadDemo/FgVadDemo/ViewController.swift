import UIKit

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
    private let logView = UITextView()
    private let versionLabel = UILabel()

    // MARK: - Models

    private let recorder = FGIOSRecorder()
    private var analyzer: FgVadAnalyzer?
    private var sentenceCount = 0
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

        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.isEditable = false
        logView.layer.borderColor = UIColor.separator.cgColor
        logView.layer.borderWidth = 0.5
        logView.layer.cornerRadius = 8
        view.addSubview(logView)

        versionLabel.text = "fgvad iOS demo · ten-vad"
        versionLabel.font = .systemFont(ofSize: 10)
        versionLabel.textColor = .tertiaryLabel
        versionLabel.textAlignment = .center
        view.addSubview(versionLabel)
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

        let logBottom = view.bounds.height - safe.bottom - 24 - 18
        logView.frame = CGRect(x: inset, y: y, width: width - inset * 2, height: max(80, logBottom - y))

        versionLabel.frame = CGRect(
            x: inset, y: view.bounds.height - safe.bottom - 18,
            width: width - inset * 2, height: 14
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

        recorder.delegate = self
        guard recorder.start() else {
            self.analyzer = nil
            return
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
        logView.text = ""
        appendLog("[start] mode=\(currentMode == .short ? "short" : "long")")
    }

    private func stopRecording(reason: String) {
        analyzer?.stop()
        recorder.stop()

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
        appendLog("[stop] reason=\(reason) finalState=\(finalState.label) endReason=\(endReason.label)")
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

    private func appendLog(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logView.text += "[\(ts)] \(msg)\n"
        // 滚到最底
        let len = logView.text.utf16.count
        if len > 0 {
            logView.scrollRangeToVisible(NSRange(location: len - 1, length: 1))
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

    // MARK: - Test audio picker (batch analyze on bundled WAVs)

    private func bundledTestAudioURLs() -> [URL] {
        // project.yml 把 test-data/short/ 当 folder reference 打成 .app/short/
        // （folder reference 保留源目录名 "short"）
        guard let testDir = Bundle.main.url(forResource: "short", withExtension: nil) else {
            return []
        }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: testDir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @objc private func showTestAudioPicker() {
        guard !recorder.isRecording else { return }
        let urls = bundledTestAudioURLs()
        guard !urls.isEmpty else {
            statusLabel.text = "未找到 bundled 测试音频"
            return
        }

        let sheet = UIAlertController(
            title: "选一个测试音频跑批式 analyze",
            message: "用当前模式 + 参数。短时素材建议在短时模式下跑。",
            preferredStyle: .actionSheet)

        for url in urls {
            sheet.addAction(UIAlertAction(title: url.lastPathComponent, style: .default) { [weak self] _ in
                self?.runAnalyze(on: url)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))

        // iPad popover
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = loadTestAudioButton
            pop.sourceRect = loadTestAudioButton.bounds
        }
        present(sheet, animated: true)
    }

    private func runAnalyze(on url: URL) {
        statusLabel.text = "读取 \(url.lastPathComponent)…"
        logView.text = ""
        appendLog("[rerun] file=\(url.lastPathComponent) mode=\(currentMode == .short ? "short" : "long")")

        let mode = currentAnalyzerMode()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result: (results: [FgVadAnalyzer.Result], finalState: FgVadState, endReason: FgVadEndReason)
            do {
                let samples = try WavIO.readMonoInt16(from: url)
                result = try FgVadAnalyzer.analyze(samples: samples, mode: mode)
            } catch {
                DispatchQueue.main.async {
                    self.statusLabel.text = "失败：\(error)"
                    self.appendLog("[rerun error] \(error)")
                }
                return
            }

            // 统计
            var sentenceCount = 0
            var lines: [String] = []
            for r in result.results {
                if r.event != FgVadEvent_None_, let ev = r.event.label {
                    let tStart = Double(r.streamOffsetSample) / 16000.0
                    let tEnd = tStart + Double(r.audioLen) / 16000.0
                    lines.append(String(format: "  %.3fs-%.3fs %@", tStart, tEnd, ev))
                    if r.event == FgVadEvent_SentenceStarted { sentenceCount += 1 }
                }
            }

            DispatchQueue.main.async {
                for l in lines { self.appendLog(l) }
                self.appendLog("[rerun done] \(sentenceCount) 句 · \(result.finalState.label)/\(result.endReason.label)")
                self.statusLabel.text = "重跑完成 · \(sentenceCount) 句 · \(result.endReason.label)"
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
        let buffer = UnsafeBufferPointer(start: frames, count: Int(count))
        let results: [FgVadAnalyzer.Result]
        do {
            results = try analyzer.feed(buffer)
        } catch {
            appendLog("[error] feed failed: \(error)")
            return
        }

        for r in results {
            if r.event != FgVadEvent_None_, let ev = r.event.label {
                let tStart = Double(r.streamOffsetSample) / 16000.0
                appendLog(String(format: "  %.3fs %@", tStart, ev))
                if r.event == FgVadEvent_SentenceStarted {
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
        appendLog("[recorder started]")
    }

    func recorderDidStop(_ recorder: FGIOSRecorder) {
        appendLog("[recorder stopped]")
    }

    func recorder(_ recorder: FGIOSRecorder, didFailWithError error: Error) {
        appendLog("[recorder error] \(error)")
        statusLabel.text = "录音失败：\(error.localizedDescription)"
    }
}
