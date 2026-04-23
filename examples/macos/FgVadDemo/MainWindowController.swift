import AppKit
import SnapKit

/// 第一阶段 UI：录音/停止按钮 + 状态标签。
/// 后续阶段会在此基础上加配置、结果列表、波形可视化、试听控制等。
final class MainWindowController: NSWindowController {
    private let recorder = Recorder()
    private let recordButton = NSButton(title: "开始录音", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "就绪")
    private let lastFileLabel = NSTextField(labelWithString: "")
    private let openFolderButton = NSButton(
        title: "打开录音文件夹", target: nil, action: nil)
    private let versionLabel = NSTextField(
        labelWithString: "fgvad \(fgvadVersionString()) · ten-vad \(tenVadVersionString())")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 280),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "FgVadDemo"
        window.center()
        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        recordButton.bezelStyle = .rounded
        recordButton.target = self
        recordButton.action = #selector(toggleRecording(_:))
        recordButton.keyEquivalent = " "

        openFolderButton.bezelStyle = .rounded
        openFolderButton.target = self
        openFolderButton.action = #selector(openRecordingsFolder)

        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)

        lastFileLabel.alignment = .center
        lastFileLabel.font = .systemFont(ofSize: 11)
        lastFileLabel.textColor = .secondaryLabelColor
        lastFileLabel.maximumNumberOfLines = 2

        versionLabel.alignment = .center
        versionLabel.font = .systemFont(ofSize: 10)
        versionLabel.textColor = .tertiaryLabelColor

        content.addSubview(recordButton)
        content.addSubview(openFolderButton)
        content.addSubview(statusLabel)
        content.addSubview(lastFileLabel)
        content.addSubview(versionLabel)

        statusLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(30)
        }
        recordButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(statusLabel.snp.bottom).offset(20)
            make.width.equalTo(180)
            make.height.equalTo(36)
        }
        openFolderButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(recordButton.snp.bottom).offset(14)
            make.height.equalTo(28)
        }
        lastFileLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(openFolderButton.snp.bottom).offset(18)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        versionLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().offset(-12)
        }
    }

    @objc private func toggleRecording(_ sender: Any?) {
        if recorder.isRecording {
            stopAndSave()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        do {
            try recorder.start()
            recordButton.title = "停止录音"
            statusLabel.stringValue = "录音中…"
            lastFileLabel.stringValue = ""
        } catch {
            statusLabel.stringValue = "录音启动失败：\(error)"
        }
    }

    private func stopAndSave() {
        do {
            let url = try recorder.stopAndSave()
            recordButton.title = "开始录音"
            statusLabel.stringValue = "已保存"
            let secs = Double(recorder.lastRecordedSampleCount) / 16000.0
            lastFileLabel.stringValue =
                String(format: "%.2fs · %@", secs, url.lastPathComponent)
        } catch {
            recordButton.title = "开始录音"
            statusLabel.stringValue = "保存失败：\(error)"
        }
    }

    @objc private func openRecordingsFolder() {
        let url = Recorder.recordingsDirectory()
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 版本展示

private func fgvadVersionString() -> String {
    // 未来可以加一个 C 导出 fgvad_version()；目前简单占位。
    "0.1.0"
}

private func tenVadVersionString() -> String {
    // ten-vad 提供 ten_vad_get_version，但 fgvad.h 不再暴露该符号。
    // 暂时占位，可在未来添加一个专门的 C 封装。
    "?"
}
