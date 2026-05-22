import AppKit
import AVFoundation

// MARK: - AudioPickerWindowController

/// 音频选择器——bundled（app bundle 内 short/long 测试 WAV）
/// + recordings（麦克风录音自动存档）两段。
/// 作为 sheet 挂在主窗口上呈现。
final class AudioPickerWindowController: NSWindowController {

    // MARK: - 段枚举

    private enum Section: Int, CaseIterable {
        case bundled
        case recordings
    }

    // MARK: - 回调

    /// 外部传入：点击 ▶ 析 时调用，传入对应 URL（picker 不关闭，macOS 习惯）。
    var onAnalyze: ((URL) -> Void)?

    // MARK: - 试听播放器（picker 自持）

    private var previewPlayer: AVAudioPlayer?
    private var playingURL: URL?

    // MARK: - 数据

    private var bundledItems:   [(displayName: String, url: URL)] = []
    private var recordingItems: [(displayName: String, url: URL)] = []

    // MARK: - Views

    private let tableView       = NSTableView()
    private let scrollView      = NSScrollView()
    private let closeButton     = NSButton(title: "关闭", target: nil, action: nil)

    // MARK: - recordings 路径

    /// 无 App Sandbox，走 Recorder 相同目录：~/Documents/FgVadDemo/recordings/
    private var recordingsDirectory: URL {
        Recorder.recordingsDirectory()
            .appendingPathComponent("recordings", isDirectory: true)
    }

    // MARK: - Init

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "测试音频"
        window.appearance = NSAppearance(named: .aqua)
        super.init(window: window)
        setupUI()
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    // MARK: - UI Setup

    private func setupUI() {
        guard let content = window?.contentView else { return }

        // 关闭按钮
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(didClickClose)
        closeButton.keyEquivalent = "\u{1b}"  // ESC
        content.addSubview(closeButton)
        closeButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-16)
            make.bottom.equalToSuperview().offset(-12)
            make.width.equalTo(72)
        }

        // 表格
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AudioRow"))
        col.title = ""
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 44
        tableView.gridStyleMask = .solidHorizontalGridLineMask
        tableView.gridColor = NSColor(white: 0, alpha: 0.08)
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.selectionHighlightStyle = .none

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .lineBorder
        content.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(closeButton.snp.top).offset(-12)
        }
    }

    // MARK: - 数据加载

    func reload() {
        bundledItems   = loadBundledWAVs()
        recordingItems = loadRecordingItems()
        tableView.reloadData()
    }

    /// 读取 app bundle 内的 short/ 和 long/ 测试 WAV。
    private func loadBundledWAVs() -> [(displayName: String, url: URL)] {
        var items: [(displayName: String, url: URL)] = []
        for sub in ["short", "long"] {
            guard let dir = Bundle.main.url(forResource: sub, withExtension: nil) else { continue }
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
            let wavItems = files
                .filter { $0.pathExtension.lowercased() == "wav" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { (displayName: "\(sub)/\($0.lastPathComponent)", url: $0) }
            items.append(contentsOf: wavItems)
        }
        return items
    }

    /// 扫描 recordings 目录加载麦克风录音 WAV。
    private func loadRecordingItems() -> [(displayName: String, url: URL)] {
        let dir = recordingsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }  // 最新在前
            .map { (displayName: $0.lastPathComponent, url: $0) }
    }

    // MARK: - 删除 / 清空

    private func deleteRecordingItem(at index: Int) {
        guard index < recordingItems.count else { return }
        let url = recordingItems[index].url
        do {
            try FileManager.default.removeItem(at: url)
            recordingItems.remove(at: index)
            tableView.removeRows(
                at: IndexSet(integer: absoluteRow(section: .recordings, row: index)),
                withAnimation: .slideUp)
        } catch {
            showAlert(title: "删除失败", message: error.localizedDescription)
        }
    }

    private func confirmClearRecordings() {
        guard !recordingItems.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "清空录音"
        alert.informativeText = "将删除所有 \(recordingItems.count) 个录音 WAV，不可恢复。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        guard let parentWindow = window else { return }
        alert.beginSheetModal(for: parentWindow) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.clearRecordings()
            }
        }
    }

    private func clearRecordings() {
        let fm = FileManager.default
        for item in recordingItems {
            try? fm.removeItem(at: item.url)
        }
        recordingItems = loadRecordingItems()
        tableView.reloadData()
    }

    // MARK: - Row index helpers

    /// section header 在 row 坐标中的绝对行号。
    private func absoluteRow(section: Section, row: Int) -> Int {
        switch section {
        case .bundled:
            return 1 + row   // row 0 = bundled header
        case .recordings:
            return 1 + bundledItems.count + 1 + row  // bundled header + bundled rows + recordings header
        }
    }

    // MARK: - Helpers

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        if let w = window { alert.beginSheetModal(for: w) }
    }

    // MARK: - 试听控制

    private func togglePreview(url: URL) {
        if playingURL == url {
            stopPreview()
            return
        }
        stopPreview()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            previewPlayer = player
            playingURL = url
            DemoLog.log("[Picker] preview start: \(url.lastPathComponent)")
        } catch {
            DemoLog.log("[Picker] preview failed: \(error)")
            return
        }
        tableView.reloadData()
    }

    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        if playingURL != nil {
            playingURL = nil
            tableView.reloadData()
        }
    }

    // MARK: - Actions

    @objc private func didClickClose() {
        stopPreview()
        if let parent = window?.sheetParent {
            parent.endSheet(window!)
        } else {
            window?.close()
        }
    }

    override func close() {
        stopPreview()
        super.close()
    }

    deinit {
        previewPlayer?.stop()
    }
}

// MARK: - NSTableViewDataSource

extension AudioPickerWindowController: NSTableViewDataSource {

    /// 总行数 = bundled header(1) + bundled rows + recordings header(1) + recordings rows
    func numberOfRows(in tableView: NSTableView) -> Int {
        1 + bundledItems.count + 1 + recordingItems.count
    }
}

// MARK: - NSTableViewDelegate

extension AudioPickerWindowController: NSTableViewDelegate {

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let (section, kind) = rowKind(row)

        switch kind {
        case .sectionHeader:
            return makeSectionHeader(section: section)
        case .dataRow(let idx):
            return makeDataRow(section: section, index: idx)
        }
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .sectionHeader = rowKind(row).1 { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .sectionHeader = rowKind(row).1 { return 28 }
        return 44
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }
}

// MARK: - Row kind helpers

extension AudioPickerWindowController {

    private enum RowKind {
        case sectionHeader
        case dataRow(Int)
    }

    private func rowKind(_ row: Int) -> (Section, RowKind) {
        // row 0: bundled header
        if row == 0 { return (.bundled, .sectionHeader) }
        let bundledEnd = 1 + bundledItems.count
        if row < bundledEnd { return (.bundled, .dataRow(row - 1)) }
        // row bundledEnd: recordings header
        if row == bundledEnd { return (.recordings, .sectionHeader) }
        let recIdx = row - bundledEnd - 1
        return (.recordings, .dataRow(recIdx))
    }
}

// MARK: - Row view factories

extension AudioPickerWindowController {

    private func makeSectionHeader(section: Section) -> NSView {
        let container = NSView()

        let label = NSTextField(
            labelWithString: section == .bundled ? "bundled" : "recordings")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        container.addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
        }

        if section == .recordings {
            let clearBtn = ActionButton(title: "清空") { [weak self] in
                self?.confirmClearRecordings()
            }
            clearBtn.bezelStyle = .inline
            clearBtn.controlSize = .small
            (clearBtn as NSButton).contentTintColor = .systemRed
            container.addSubview(clearBtn)
            clearBtn.snp.makeConstraints { make in
                make.trailing.equalToSuperview().offset(-12)
                make.centerY.equalToSuperview()
            }
        }

        return container
    }

    private func makeDataRow(section: Section, index: Int) -> NSView {
        let item: (displayName: String, url: URL)
        let isBundled = (section == .bundled)
        if isBundled {
            guard index < bundledItems.count else { return NSView() }
            item = bundledItems[index]
        } else {
            guard index < recordingItems.count else { return NSView() }
            item = recordingItems[index]
        }

        let container = NSView()

        // ▶ 析 按钮（最右）
        let analyzeBtn = ActionButton(title: "▶ 析") { [weak self] in
            self?.onAnalyze?(item.url)
        }
        styleActionButton(analyzeBtn)
        container.addSubview(analyzeBtn)
        analyzeBtn.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
            make.width.equalTo(52)
            make.height.equalTo(26)
        }

        // ▶ 预 按钮（析的左侧）；播放中显示 ⏸ 停
        let previewTitle = (playingURL == item.url) ? "⏸ 停" : "▶ 预"
        let previewBtn = ActionButton(title: previewTitle) { [weak self] in
            self?.togglePreview(url: item.url)
        }
        styleActionButton(previewBtn)
        container.addSubview(previewBtn)
        previewBtn.snp.makeConstraints { make in
            make.trailing.equalTo(analyzeBtn.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
            make.width.equalTo(52)
            make.height.equalTo(26)
        }

        var rightAnchorView: NSView = previewBtn

        // × 删除按钮（仅 recordings）
        if !isBundled {
            let idx = index
            let deleteBtn = ActionButton(title: "×") { [weak self] in
                self?.deleteRecordingItem(at: idx)
            }
            deleteBtn.bezelStyle = .rounded
            deleteBtn.contentTintColor = .systemRed
            deleteBtn.font = .systemFont(ofSize: 13, weight: .medium)
            deleteBtn.isBordered = true
            deleteBtn.controlSize = .small
            container.addSubview(deleteBtn)
            deleteBtn.snp.makeConstraints { make in
                make.trailing.equalTo(previewBtn.snp.leading).offset(-8)
                make.centerY.equalToSuperview()
                make.width.equalTo(30)
                make.height.equalTo(26)
            }
            rightAnchorView = deleteBtn
        }

        // 文件名 label
        let nameLabel = NSTextField(labelWithString: item.displayName)
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        container.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.trailing.lessThanOrEqualTo(rightAnchorView.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }

        return container
    }

    private func styleActionButton(_ btn: NSButton) {
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        btn.font = .systemFont(ofSize: 12, weight: .medium)
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPickerWindowController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.stopPreview()
        }
    }
}

// MARK: - ActionButton

private final class ActionButton: NSButton {
    private var clickHandler: (() -> Void)?

    init(title: String, _ handler: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title
        self.clickHandler = handler
        self.target = self
        self.action = #selector(handleClick)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleClick() { clickHandler?() }
}
