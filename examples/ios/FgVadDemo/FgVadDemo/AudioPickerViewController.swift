import UIKit

// MARK: - AudioPickerCell

/// 音频列表行：左侧文件名 + 右侧操作按钮（▶预 / ▶析，recordings 行额外带 × 删除）。
/// 布局：纯 frame，layoutSubviews 重排，遵守 [[feedback-ios-frame-layout]]。
final class AudioPickerCell: UITableViewCell {

    static let reuseID = "AudioPickerCell"
    static let rowHeight: CGFloat = 52

    private let nameLabel    = UILabel()
    let previewButton        = UIButton(type: .system)
    let analyzeButton        = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)

    /// ViewController 传入的回调，cell 内部 action 调用。
    var onPreview: (() -> Void)?
    var onAnalyze: (() -> Void)?
    /// 非 nil 时显示删除按钮；bundled 行不传，置 nil。
    var onDelete: (() -> Void)? {
        didSet { deleteButton.isHidden = (onDelete == nil); setNeedsLayout() }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        nameLabel.font = .systemFont(ofSize: 14, weight: .regular)
        nameLabel.textColor = .label
        nameLabel.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(nameLabel)

        styleActionButton(previewButton, title: "▶ 预")
        previewButton.addTarget(self, action: #selector(didTapPreview), for: .touchUpInside)
        contentView.addSubview(previewButton)

        styleActionButton(analyzeButton, title: "▶ 析")
        analyzeButton.addTarget(self, action: #selector(didTapAnalyze), for: .touchUpInside)
        contentView.addSubview(analyzeButton)

        deleteButton.setTitle("×", for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        deleteButton.backgroundColor = .systemRed.withAlphaComponent(0.15)
        deleteButton.setTitleColor(.systemRed, for: .normal)
        deleteButton.layer.cornerRadius = 8
        deleteButton.isHidden = true
        deleteButton.addTarget(self, action: #selector(didTapDelete), for: .touchUpInside)
        contentView.addSubview(deleteButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func styleActionButton(_ btn: UIButton, title: String) {
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        btn.backgroundColor = .systemGray5
        btn.setTitleColor(.label, for: .normal)
        btn.layer.cornerRadius = 8
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w    = contentView.bounds.width
        let h    = contentView.bounds.height
        let pad  : CGFloat = 16
        let gap  : CGFloat = 8
        let btnW : CGFloat = 54
        let delW : CGFloat = 36
        let btnH : CGFloat = 32
        let btnY = (h - btnH) / 2

        if deleteButton.isHidden {
            // bundled 行：右侧两个按钮从右向左排
            analyzeButton.frame = CGRect(x: w - pad - btnW, y: btnY, width: btnW, height: btnH)
            previewButton.frame = CGRect(x: analyzeButton.frame.minX - gap - btnW, y: btnY, width: btnW, height: btnH)
        } else {
            // recordings 行：× / ▶析 / ▶预 从右向左排
            deleteButton.frame  = CGRect(x: w - pad - delW, y: btnY, width: delW, height: btnH)
            analyzeButton.frame = CGRect(x: deleteButton.frame.minX - gap - btnW, y: btnY, width: btnW, height: btnH)
            previewButton.frame = CGRect(x: analyzeButton.frame.minX - gap - btnW, y: btnY, width: btnW, height: btnH)
        }

        // 文件名占满剩余空间
        let labelRight = previewButton.frame.minX - gap
        nameLabel.frame = CGRect(x: pad, y: 0, width: max(0, labelRight - pad), height: h)
    }

    func configure(name: String) {
        nameLabel.text = name
    }

    /// 复用前重置状态，避免旧闭包残留。
    override func prepareForReuse() {
        super.prepareForReuse()
        onPreview = nil
        onAnalyze = nil
        onDelete  = nil
    }

    @objc private func didTapPreview()  { onPreview?() }
    @objc private func didTapAnalyze() { onAnalyze?() }
    @objc private func didTapDelete()  { onDelete?() }
}

// MARK: - SectionHeaderView

/// 自定义 section header：左边标题，右侧可选"清空"按钮（recordings 段用）。
private final class SectionHeaderView: UIView {

    private let titleLabel   = UILabel()
    private let clearButton  = UIButton(type: .system)

    var onClear: (() -> Void)?

    init(title: String, showClear: Bool) {
        super.init(frame: .zero)
        backgroundColor = .systemGroupedBackground

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        addSubview(titleLabel)

        if showClear {
            clearButton.setTitle("清空", for: .normal)
            clearButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .regular)
            clearButton.setTitleColor(.systemRed, for: .normal)
            clearButton.addTarget(self, action: #selector(didTapClear), for: .touchUpInside)
            addSubview(clearButton)
        } else {
            clearButton.isHidden = true
            addSubview(clearButton)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w   = bounds.width
        let h   = bounds.height
        let pad : CGFloat = 16

        if !clearButton.isHidden {
            let clearW: CGFloat = 44
            clearButton.frame = CGRect(x: w - pad - clearW, y: 0, width: clearW, height: h)
            titleLabel.frame  = CGRect(x: pad, y: 0, width: clearButton.frame.minX - pad - 8, height: h)
        } else {
            titleLabel.frame = CGRect(x: pad, y: 0, width: w - pad * 2, height: h)
        }
    }

    @objc private func didTapClear() { onClear?() }
}

// MARK: - AudioPickerViewController

/// 音频选择器——bundled（app bundle 内短/长测试 WAV）+ recordings（麦克风录音自动存档）两段。
final class AudioPickerViewController: UITableViewController {

    // MARK: - 段枚举

    private enum Section: Int, CaseIterable {
        case bundled, recordings
    }

    // MARK: - 回调

    /// 外部（ViewController）传入：点击"▶预"时调用，传入对应 URL。
    var onPreview: ((URL) -> Void)?

    /// 外部传入：点击"▶析"时先 dismiss picker，再调用，传入对应 URL。
    var onAnalyze: ((URL) -> Void)?

    // MARK: - 数据

    private var bundledItems:   [(displayName: String, url: URL)] = []
    private var recordingItems: [(displayName: String, url: URL)] = []

    // MARK: - 沙盒路径

    private var recordingsDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("recordings", isDirectory: true)
    }

    // MARK: - 生命周期

    init() {
        super.init(style: .plain)
        title = "测试音频"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(AudioPickerCell.self, forCellReuseIdentifier: AudioPickerCell.reuseID)
        tableView.rowHeight = AudioPickerCell.rowHeight
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        tableView.tableHeaderView = nil

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "导出日志",
            style: .plain,
            target: self,
            action: #selector(exportLog))

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(didTapClose))

        bundledItems   = loadBundledWAVs()
        recordingItems = loadRecordings()
        tableView.reloadData()
    }

    // MARK: - 数据加载

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

    /// 扫描沙盒 Documents/recordings/ 目录加载麦克风录音 WAV。
    private func loadRecordings() -> [(displayName: String, url: URL)] {
        let dir = recordingsDirectoryURL
        // 目录不存在则创建
        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }  // 最新在前
            .map { (displayName: $0.lastPathComponent, url: $0) }
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView,
                            numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .bundled:    return bundledItems.count
        case .recordings: return recordingItems.count
        }
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: AudioPickerCell.reuseID, for: indexPath) as! AudioPickerCell

        switch Section(rawValue: indexPath.section)! {
        case .bundled:
            let item = bundledItems[indexPath.row]
            cell.configure(name: item.displayName)
            cell.onDelete = nil
            cell.onPreview = { [weak self] in
                self?.onPreview?(item.url)
            }
            cell.onAnalyze = { [weak self] in
                guard let self else { return }
                self.dismiss(animated: true) { self.onAnalyze?(item.url) }
            }

        case .recordings:
            let item = recordingItems[indexPath.row]
            cell.configure(name: item.displayName)
            cell.onPreview = { [weak self] in
                self?.onPreview?(item.url)
            }
            cell.onAnalyze = { [weak self] in
                guard let self else { return }
                self.dismiss(animated: true) { self.onAnalyze?(item.url) }
            }
            let url = item.url
            cell.onDelete = { [weak self] in
                self?.deleteRecordingItem(url: url)
            }
        }

        return cell
    }

    // MARK: - Section Header

    override func tableView(_ tableView: UITableView,
                            viewForHeaderInSection section: Int) -> UIView? {
        switch Section(rawValue: section)! {
        case .bundled:
            return SectionHeaderView(title: "bundled", showClear: false)

        case .recordings:
            let header = SectionHeaderView(title: "recordings", showClear: true)
            header.onClear = { [weak self] in self?.confirmClearRecordings() }
            return header
        }
    }

    override func tableView(_ tableView: UITableView,
                            heightForHeaderInSection section: Int) -> CGFloat {
        32
    }

    // MARK: - 删除 / 清空

    private func deleteRecordingItem(url: URL) {
        guard let index = recordingItems.firstIndex(where: { $0.url == url }) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            recordingItems.remove(at: index)
            let ip = IndexPath(row: index, section: Section.recordings.rawValue)
            tableView.deleteRows(at: [ip], with: .automatic)
        } catch {
            showAlert(title: "删除失败", message: error.localizedDescription)
        }
    }

    private func confirmClearRecordings() {
        guard !recordingItems.isEmpty else { return }
        let alert = UIAlertController(
            title: "清空录音",
            message: "将删除所有 \(recordingItems.count) 个录音 WAV，不可恢复。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in
            self?.clearRecordings()
        })
        present(alert, animated: true)
    }

    private func clearRecordings() {
        let fm = FileManager.default
        var failedURLs: [URL] = []
        for item in recordingItems {
            do {
                try fm.removeItem(at: item.url)
            } catch {
                failedURLs.append(item.url)
            }
        }
        recordingItems = loadRecordings()  // 重新扫，让 UI 反映真实状态
        tableView.reloadSections(IndexSet(integer: Section.recordings.rawValue), with: .automatic)
        if !failedURLs.isEmpty {
            let names = failedURLs.map { $0.lastPathComponent }.joined(separator: ", ")
            let alert = UIAlertController(title: "部分文件未能删除",
                                          message: names,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
        }
    }

    // MARK: - Helpers

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Actions

    @objc private func exportLog() {
        let url = DemoLogger.shared.logFileURL
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = activity.popoverPresentationController {
            pop.barButtonItem = navigationItem.leftBarButtonItem
        }
        present(activity, animated: true)
    }

    @objc private func didTapClose() {
        dismiss(animated: true)
    }
}
