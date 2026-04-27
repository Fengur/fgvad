import AVFoundation
import Foundation

/// 16 kHz mono i16 录音器。写出 WAV 到 `~/Documents/FgVadDemo/`。
final class Recorder {
    /// 每次录音都重建一个新引擎——停止时整个释放，避免 AudioUnit 残留
    /// 导致其他 app 的音频输出异常。
    private var engine: AVAudioEngine?
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

    /// 每次转换完成一段 i16 chunk 后的回调——用于流式喂给 analyzer。
    /// 在音频线程调用；如需主线程更新 UI 请自行 dispatch。
    var onChunk: ((UnsafeBufferPointer<Int16>) -> Void)?

    /// Warmup 完成后的首帧时刻回调（传入已丢弃的样本数）。主要给 demo 打日志用。
    var onWarmupComplete: ((Int) -> Void)?

    /// AVAudioEngine 刚启动时 HAL 会先喂一段零值 PCM；再之后 AudioUnit 上线
    /// 瞬间常有突发能量（点击声、preamp 抖动），会把神经 VAD 糊弄成 speech。
    /// 策略：丢弃所有全零 chunk，看到第一个非零样本后再继续丢 `postWarmupSkipSamples`
    /// 个样本，才算进入"干净录音"。WAV 和 onChunk 使用同一份干净流，保持 live/rerun
    /// 结果一致。
    private static let postWarmupSkipSamples = 16_000 * 300 / 1000  // 300ms
    private var warmupComplete = false
    private var postWarmupSkipCountdown = 0
    private var totalSkippedSamples = 0

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
        warmupComplete = false
        postWarmupSkipCountdown = 0
        totalSkippedSamples = 0

        let newEngine = AVAudioEngine()
        let input = newEngine.inputNode
        let hwFormat = input.inputFormat(forBus: 0)

        converter = AVAudioConverter(from: hwFormat, to: targetFormat)

        input.installTap(
            onBus: 0, bufferSize: 1024, format: hwFormat
        ) { [weak self] pcmBuffer, _ in
            self?.handleBuffer(pcmBuffer)
        }

        try newEngine.start()
        engine = newEngine
        isRecording = true
    }

    /// 停止录音，保存为 WAV 并返回文件 URL。
    @discardableResult
    func stopAndSave() throws -> URL {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }
        engine = nil  // 释放 AudioUnit，恢复其他 app 的音频路径
        converter = nil
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
        guard count > 0 else { return }
        let chunk = UnsafeBufferPointer(start: i16[0], count: count)

        // Warmup gating —— 决定本 chunk 里哪一段算"干净音频"
        if !warmupComplete {
            // 开头 HAL 投递的零值 chunk 整块丢弃
            var firstNonZeroIdx = -1
            for i in 0..<count where chunk[i] != 0 {
                firstNonZeroIdx = i
                break
            }
            if firstNonZeroIdx < 0 {
                totalSkippedSamples += count
                return
            }
            // 第一个非零样本出现了 —— 标记 warmup 结束，把之前的零头也算进丢弃统计,
            // 剩余 chunk 进入 "post-warmup 额外跳帧" 窗口
            totalSkippedSamples += firstNonZeroIdx
            warmupComplete = true
            postWarmupSkipCountdown = Self.postWarmupSkipSamples
            if let cb = onWarmupComplete { cb(totalSkippedSamples) }
            // 从 firstNonZeroIdx 往后继续走下面的 post-warmup 跳帧逻辑
            let tail = UnsafeBufferPointer(
                start: chunk.baseAddress!.advanced(by: firstNonZeroIdx),
                count: count - firstNonZeroIdx)
            emitAfterPostWarmup(tail)
            return
        }
        emitAfterPostWarmup(chunk)
    }

    /// 在已经进入 post-warmup 区间时处理 chunk：先把 `postWarmupSkipCountdown`
    /// 吃完再把剩余部分喂出去。
    private func emitAfterPostWarmup(_ chunk: UnsafeBufferPointer<Int16>) {
        var start = 0
        if postWarmupSkipCountdown > 0 {
            let skipNow = min(postWarmupSkipCountdown, chunk.count)
            postWarmupSkipCountdown -= skipNow
            totalSkippedSamples += skipNow
            start = skipNow
        }
        if start >= chunk.count { return }
        let kept = UnsafeBufferPointer(
            start: chunk.baseAddress!.advanced(by: start),
            count: chunk.count - start)
        buffer.append(contentsOf: kept)
        onChunk?(kept)
    }
}
