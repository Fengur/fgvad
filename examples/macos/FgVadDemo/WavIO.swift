import Foundation

/// 极简 WAV 读写：仅 16 kHz mono int16 PCM。
enum WavIO {
    enum WavError: Error {
        case badHeader
        case unsupportedFormat
    }

    /// 把 i16 样本写成 WAV（44-byte header + PCM 数据）。
    static func writeMonoInt16(
        _ samples: [Int16], sampleRate: UInt32, to url: URL
    ) throws {
        let dataSize = UInt32(samples.count * 2)
        let riffSize = 36 + dataSize
        let byteRate = sampleRate * 2  // mono * 2 bytes

        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(uint32LE(riffSize))
        header.append("WAVE".data(using: .ascii)!)

        header.append("fmt ".data(using: .ascii)!)
        header.append(uint32LE(16))            // fmt chunk size
        header.append(uint16LE(1))             // PCM
        header.append(uint16LE(1))             // channels = 1
        header.append(uint32LE(sampleRate))
        header.append(uint32LE(byteRate))
        header.append(uint16LE(2))             // block align = 2
        header.append(uint16LE(16))            // bits per sample = 16

        header.append("data".data(using: .ascii)!)
        header.append(uint32LE(dataSize))

        let samplesData = samples.withUnsafeBufferPointer { buf in
            Data(buffer: buf)
        }
        var file = header
        file.append(samplesData)
        try file.write(to: url, options: .atomic)
    }

    /// 加载 WAV（跳过 header 直到 data chunk），校验格式，返回 i16 样本。
    static func readMonoInt16(from url: URL) throws -> [Int16] {
        let data = try Data(contentsOf: url)
        guard data.count >= 44 else { throw WavError.badHeader }
        guard data.prefix(4) == "RIFF".data(using: .ascii),
              data.subdata(in: 8..<12) == "WAVE".data(using: .ascii)
        else { throw WavError.badHeader }

        var pos = 12
        var sampleRate: UInt32 = 0
        var channels: UInt16 = 0
        var bits: UInt16 = 0
        var dataRange: Range<Int>? = nil

        while pos + 8 <= data.count {
            let id = data.subdata(in: pos..<pos + 4)
            let size = Int(readUInt32LE(data, at: pos + 4))
            let body = (pos + 8)..<(pos + 8 + size)

            if id == "fmt ".data(using: .ascii) {
                channels = readUInt16LE(data, at: body.lowerBound + 2)
                sampleRate = readUInt32LE(data, at: body.lowerBound + 4)
                bits = readUInt16LE(data, at: body.lowerBound + 14)
            } else if id == "data".data(using: .ascii) {
                dataRange = body
                break
            }
            pos = body.upperBound + (size & 1)
        }

        guard sampleRate == 16_000, channels == 1, bits == 16
        else { throw WavError.unsupportedFormat }
        guard let range = dataRange else { throw WavError.badHeader }

        let chunk = data.subdata(in: range)
        return chunk.withUnsafeBytes { raw -> [Int16] in
            let ptr = raw.bindMemory(to: Int16.self)
            return Array(ptr)
        }
    }

    private static func uint32LE(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 4)
    }
    private static func uint16LE(_ v: UInt16) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 2)
    }
    private static func readUInt32LE(_ d: Data, at offset: Int) -> UInt32 {
        var v: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &v) { buf in
            d.copyBytes(to: buf, from: offset..<offset + 4)
        }
        return UInt32(littleEndian: v)
    }
    private static func readUInt16LE(_ d: Data, at offset: Int) -> UInt16 {
        var v: UInt16 = 0
        _ = withUnsafeMutableBytes(of: &v) { buf in
            d.copyBytes(to: buf, from: offset..<offset + 2)
        }
        return UInt16(littleEndian: v)
    }
}
