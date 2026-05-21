import Foundation
import os.log

/// iOS demo 文件日志：写到 Documents/run.log。
/// app 启动 truncate。Mac 端通过 Airdrop / Files app 拿到文件后 Read 看。
final class DemoLogger {

    static let shared = DemoLogger()

    private let url: URL
    private let queue = DispatchQueue(label: "io.fengur.fgvaddemo.logger")
    private let formatter: DateFormatter
    private var handle: FileHandle?

    private init() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.url = docs.appendingPathComponent("run.log")
        self.formatter = DateFormatter()
        self.formatter.dateFormat = "HH:mm:ss.SSS"
        self.formatter.locale = Locale(identifier: "en_US_POSIX")
        truncateAndOpen()
    }

    private func truncateAndOpen() {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        fm.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    func i(_ tag: String, _ msg: String) { write("I", tag, msg) }
    func w(_ tag: String, _ msg: String) { write("W", tag, msg) }
    func e(_ tag: String, _ msg: String) { write("E", tag, msg) }

    private func write(_ level: String, _ tag: String, _ msg: String) {
        let line = "\(formatter.string(from: Date())) \(level)/\(tag): \(msg)\n"
        let data = Data(line.utf8)
        queue.async { [weak self] in
            try? self?.handle?.write(contentsOf: data)
        }
        // 同时让 Xcode console 看得到
        switch level {
        case "I": NSLog("[\(tag)] \(msg)")
        case "W": NSLog("[W][\(tag)] \(msg)")
        case "E": NSLog("[E][\(tag)] \(msg)")
        default: break
        }
    }

    var logFileURL: URL { url }
}
