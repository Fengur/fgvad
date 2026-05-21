import UIKit
import AVFoundation

// MARK: - AudioPickerCell

/// 音频列表行：左侧文件名 + 右侧两个操作按钮（▶预 / ▶析）。
/// 布局：纯 frame，layoutSubviews 重排，遵守 [[feedback-ios-frame-layout]]。
final class AudioPickerCell: UITableViewCell {

    static let reuseID = "AudioPickerCell"
    static let rowHeight: CGFloat = 52

    private let nameLabel   = UILabel()
    let previewButton       = UIButton(type: .system)
    let analyzeButton       = UIButton(type: .system)

    /// ViewController 传入的回调，cell 内部 action 调用。
    var onPreview: (() -> Void)?
    var onAnalyze: (() -> Void)?

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
        let btnH : CGFloat = 32
        let btnY = (h - btnH) / 2

        // 右侧两个按钮从右向左排
        analyzeButton.frame = CGRect(x: w - pad - btnW, y: btnY, width: btnW, height: btnH)
        previewButton.frame = CGRect(x: analyzeButton.frame.minX - gap - btnW, y: btnY, width: btnW, height: btnH)

        // 文件名占满剩余空间
        let labelRight = previewButton.frame.minX - gap
        nameLabel.frame = CGRect(x: pad, y: 0, width: labelRight - pad, height: h)
    }

    func configure(name: String) {
        nameLabel.text = name
    }

    @objc private func didTapPreview()  { onPreview?() }
    @objc private func didTapAnalyze() { onAnalyze?() }
}

// MARK: - AudioPickerViewController

/// 音频选择器——展示 bundled（app bundle 内）的短/长测试 WAV。
/// imported 段与 UIDocumentPicker 入口由 iOS-2 补充。
final class AudioPickerViewController: UITableViewController {

    // MARK: - 回调

    /// 外部（ViewController）传入：点击"▶预"时调用，传入对应 URL。
    var onPreview: ((URL) -> Void)?

    /// 外部传入：点击"▶析"时先 dismiss picker，再调用，传入对应 URL。
    var onAnalyze: ((URL) -> Void)?

    // MARK: - 数据

    private var bundledItems: [(displayName: String, url: URL)] = []

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

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(didTapClose))

        bundledItems = loadBundledWAVs()
        tableView.reloadData()
    }

    // MARK: - 数据加载

    /// 读取 app bundle 内的 short/ 和 long/ 测试 WAV。
    /// project.yml 用 folder reference 打包，路径为 .app/short/*.wav 和 .app/long/*.wav。
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

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        bundledItems.count
    }

    override func tableView(_ tableView: UITableView,
                            titleForHeaderInSection section: Int) -> String? {
        "bundled"
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: AudioPickerCell.reuseID, for: indexPath) as! AudioPickerCell
        let item = bundledItems[indexPath.row]
        cell.configure(name: item.displayName)

        cell.onPreview = { [weak self] in
            self?.onPreview?(item.url)
        }
        cell.onAnalyze = { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) {
                self.onAnalyze?(item.url)
            }
        }
        return cell
    }

    // MARK: - Actions

    @objc private func didTapClose() {
        dismiss(animated: true)
    }
}
