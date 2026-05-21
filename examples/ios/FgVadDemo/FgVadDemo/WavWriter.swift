import Foundation

/// 流式写 16 kHz mono PCM-16 WAV。
/// 用法：
///   let w = try WavWriter(url: url)
///   w.append(samples: [Int16])  // 多次
///   try w.finalize()             // 必调，否则 header size 字段是 0，文件不可读
final class WavWriter {

    private let handle: FileHandle
    private var samplesWritten: UInt32 = 0

    init(url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        fm.createFile(atPath: url.path, contents: nil)
        self.handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: WavWriter.placeholderHeader())
    }

    func append(samples: UnsafePointer<Int16>, count: Int) throws {
        let bytes = count * MemoryLayout<Int16>.size
        let data = Data(bytes: samples, count: bytes)
        try handle.write(contentsOf: data)
        samplesWritten += UInt32(count)
    }

    func append(samples: [Int16]) throws {
        try samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            try append(samples: base, count: buf.count)
        }
    }

    func finalize() throws {
        // 回填 RIFF chunk size + data chunk size
        let dataBytes = samplesWritten * 2
        let riffSize = 36 + dataBytes
        try handle.seek(toOffset: 4)
        try handle.write(contentsOf: WavWriter.le32(riffSize))
        try handle.seek(toOffset: 40)
        try handle.write(contentsOf: WavWriter.le32(dataBytes))
        try handle.close()
    }

    private static func placeholderHeader() -> Data {
        var d = Data()
        d.append("RIFF".data(using: .ascii)!)
        d.append(le32(0))                       // riff size, finalize 时回填
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!)
        d.append(le32(16))                      // fmt chunk size
        d.append(le16(1))                       // audio format = PCM
        d.append(le16(1))                       // channels = 1
        d.append(le32(16000))                   // sample rate
        d.append(le32(16000 * 2))               // byte rate = sample rate * block align
        d.append(le16(2))                       // block align = channels * bits/8
        d.append(le16(16))                      // bits per sample
        d.append("data".data(using: .ascii)!)
        d.append(le32(0))                       // data size, finalize 时回填
        return d
    }

    private static func le32(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 4)
    }
    private static func le16(_ v: UInt16) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 2)
    }
    private static func le32(_ v: Int) -> Data { le32(UInt32(v)) }
    private static func le16(_ v: Int) -> Data { le16(UInt16(v)) }
}
