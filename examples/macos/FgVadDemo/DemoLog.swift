import Foundation

/// 调试日志：每次启动 truncate，追加写入 ~/Library/Logs/FgVadDemo/run.log
/// Claude 可以直接 Read 这个文件，无需用户复制控制台。
enum DemoLog {
    static let fileURL: URL = {
        let logs = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Logs/FgVadDemo", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("run.log")
    }()

    /// 启动时调一次，清空旧日志。
    static func resetForNewRun() {
        let header = "=== FgVadDemo run @ \(Date()) ===\n"
        try? header.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func log(_ message: String, file: String = #file, line: Int = #line) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let base = (file as NSString).lastPathComponent
        let line = "[\(ts)] \(base):\(line)  \(message)\n"
        NSLog("%@", line)  // 同时留一份在系统日志
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}
