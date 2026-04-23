import AVFoundation
import Foundation

/// 16 kHz mono i16 录音器。写出 WAV 到 `~/Documents/FgVadDemo/`。
final class Recorder {
    private let engine = AVAudioEngine()
    /// ten-vad 要求的目标格式：16 kHz mono int16 little-endian。
    private lazy var targetFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true)!
    }()

    private var converter: AVAudioConverter?
    private var buffer: [Int16] = []
    private(set) var isRecording = false
    private(set) var lastRecordedSampleCount = 0

    /// 录音文件存放目录：`~/Documents/FgVadDemo/`。
    static func recordingsDirectory() -> URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        return docs.appendingPathComponent("FgVadDemo", isDirectory: true)
    }

    func start() throws {
        guard !isRecording else { return }
        buffer.removeAll(keepingCapacity: true)

        let input = engine.inputNode
        let hwFormat = input.inputFormat(forBus: 0)

        converter = AVAudioConverter(from: hwFormat, to: targetFormat)

        input.installTap(
            onBus: 0, bufferSize: 1024, format: hwFormat
        ) { [weak self] pcmBuffer, _ in
            self?.handleBuffer(pcmBuffer)
        }

        try engine.start()
        isRecording = true
    }

    /// 停止录音，保存为 WAV 并返回文件 URL。
    @discardableResult
    func stopAndSave() throws -> URL {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        lastRecordedSampleCount = buffer.count

        let dir = Recorder.recordingsDirectory()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let name = "rec-\(df.string(from: Date())).wav"
        let url = dir.appendingPathComponent(name)
        try WavIO.writeMonoInt16(buffer, sampleRate: 16_000, to: url)
        return url
    }

    // MARK: - 硬件采样率 -> 16kHz mono int16 转换

    private func handleBuffer(_ source: AVAudioPCMBuffer) {
        guard let converter else { return }
        let outCapacity = AVAudioFrameCount(
            Double(source.frameLength) * targetFormat.sampleRate
                / source.format.sampleRate) + 1024
        guard
            let output = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outCapacity)
        else { return }

        var givenSource = false
        let status = converter.convert(
            to: output, error: nil
        ) { _, inputStatus in
            if givenSource {
                inputStatus.pointee = .noDataNow
                return nil
            }
            givenSource = true
            inputStatus.pointee = .haveData
            return source
        }

        guard status != .error else { return }
        guard let i16 = output.int16ChannelData else { return }
        let count = Int(output.frameLength)
        buffer.append(contentsOf: UnsafeBufferPointer(start: i16[0], count: count))
    }
}
