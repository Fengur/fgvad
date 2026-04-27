import Foundation

/// fgvad C API 的 Swift 封装。
/// - 实例版（`init(mode:)` → `start` → `feed` → `stop`）用于录音时流式喂入
/// - static `analyze(...)` 用于对已录好的整段 PCM 做批式回灌（调参重跑）
final class FgVadAnalyzer {

    enum Mode {
        case short(ShortConfig)
        case long(LongConfig)
    }

    /// 短时模式：命令/查询式单次交互，尾静音一到就结束整个会话。
    struct ShortConfig {
        /// 开始录音后，允许连续静音多久没检测到说话就放弃。
        /// 适合防止用户按了录音又啥都不说的情况。
        var headSilenceTimeoutMs: UInt32 = 3_000
        /// 进入说话状态后，连续静音多久就认为一句话说完、会话结束。
        /// 是短时模式最关键的参数——太短会切掉正常停顿，太长会让体验显得迟钝。
        var tailSilenceMs: UInt32 = 2_000
        /// 单次会话最长时长上限（含静音部分），超时强制结束。
        var maxDurationMs: UInt32 = 30_000
    }

    /// 长时模式：连续听写式多句交互，外部不 stop 就一直跑。
    struct LongConfig {
        /// 开始录音后允许的最长头部静音（同 ShortConfig.headSilenceTimeoutMs）。
        var headSilenceTimeoutMs: UInt32 = 3_000
        /// 单句最长时长；超过强制切出一句（SentenceForceCut 事件），
        /// 避免用户一口气说太长导致识别器内存/延迟爆炸。
        var maxSentenceDurationMs: UInt32 = 30_000
        /// 整个会话最长时长；0 表示不限。到点强制结束。
        var maxSessionDurationMs: UInt32 = 0
        /// 动态尾端点曲线的初始值——会话刚开始时用这个（较宽容）。
        var tailSilenceMsInitial: UInt32 = 2_000
        /// 动态尾端点曲线的下限——说得越久会向这个值收紧，但不会低于它。
        var tailSilenceMsMin: UInt32 = 600
        /// 是否启用动态尾端点。关掉则尾静音恒等于 tailSilenceMsInitial。
        /// fgvad 的核心竞争力就是这条曲线，建议保持开启。
        var enableDynamicTail: Bool = true
    }

    struct Result {
        var type: FgVadResultType
        var event: FgVadEvent
        var state: FgVadState
        var endReason: FgVadEndReason
        var streamOffsetSample: UInt64
        var frameCount: Int
        var audioLen: Int
    }

    enum AnalyzerError: Error {
        case createFailed
        case processFailed
    }

    // MARK: - 实例：流式

    private let vad: OpaquePointer

    init(mode: Mode) throws {
        let handle: OpaquePointer?
        switch mode {
        case .short(let c):
            handle = fgvad_new_short(c.headSilenceTimeoutMs, c.tailSilenceMs, c.maxDurationMs)
        case .long(let c):
            handle = fgvad_new_long(
                c.headSilenceTimeoutMs,
                c.maxSentenceDurationMs,
                c.maxSessionDurationMs,
                c.tailSilenceMsInitial,
                c.tailSilenceMsMin,
                c.enableDynamicTail)
        }
        guard let handle else { throw AnalyzerError.createFailed }
        self.vad = handle
    }

    deinit { fgvad_free(vad) }

    func start() { fgvad_start(vad) }
    func stop() { fgvad_stop(vad) }

    /// 喂入一段 i16 PCM chunk，返回本次 chunk 产生的所有 VadResult 段。
    func feed(_ samples: UnsafeBufferPointer<Int16>) throws -> [Result] {
        guard let handle = fgvad_process(vad, samples.baseAddress, UInt(samples.count)) else {
            throw AnalyzerError.processFailed
        }
        defer { fgvad_results_free(handle) }
        let count = Int(fgvad_results_count(handle))
        var out: [Result] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let v = fgvad_result_view(handle, UInt(i))
            out.append(Result(
                type: v.result_type,
                event: v.event,
                state: v.state,
                endReason: v.end_reason,
                streamOffsetSample: v.stream_offset_sample,
                frameCount: Int(v.frames_count),
                audioLen: Int(v.audio_len)))
        }
        return out
    }

    var state: FgVadState { fgvad_state(vad) }
    var endReason: FgVadEndReason { fgvad_end_reason(vad) }

    // MARK: - 静态：批式回灌（重跑同一段 PCM）

    static func analyze(
        samples: [Int16], mode: Mode
    ) throws -> (results: [Result], finalState: FgVadState, endReason: FgVadEndReason) {
        let a = try FgVadAnalyzer(mode: mode)
        a.start()
        let results = try samples.withUnsafeBufferPointer { try a.feed($0) }
        a.stop()
        return (results, a.state, a.endReason)
    }
}

// MARK: - 枚举人类可读文本（log 用）

extension FgVadResultType {
    var label: String {
        switch self {
        case FgVadResultType_Silence: return "Silence"
        case FgVadResultType_SentenceStart: return "SentenceStart"
        case FgVadResultType_Active: return "Active"
        case FgVadResultType_SentenceEnd: return "SentenceEnd"
        default: return "Unknown(\(rawValue))"
        }
    }
}

extension FgVadEvent {
    var label: String? {
        switch self {
        case FgVadEvent_None_: return nil
        case FgVadEvent_SentenceStarted: return "SentenceStarted"
        case FgVadEvent_SentenceEnded: return "SentenceEnded"
        case FgVadEvent_SentenceForceCut: return "SentenceForceCut"
        case FgVadEvent_HeadSilenceTimeout: return "HeadSilenceTimeout"
        case FgVadEvent_MaxDurationReached: return "MaxDurationReached"
        default: return "Event(\(rawValue))"
        }
    }
}

extension FgVadState {
    var label: String {
        switch self {
        case FgVadState_Idle: return "Idle"
        case FgVadState_Detecting: return "Detecting"
        case FgVadState_Started: return "Started"
        case FgVadState_Voiced: return "Voiced"
        case FgVadState_Trailing: return "Trailing"
        case FgVadState_End: return "End"
        default: return "State(\(rawValue))"
        }
    }
}

extension FgVadEndReason {
    var label: String {
        switch self {
        case FgVadEndReason_None_: return "None"
        case FgVadEndReason_SpeechCompleted: return "SpeechCompleted"
        case FgVadEndReason_HeadSilenceTimeout: return "HeadSilenceTimeout"
        case FgVadEndReason_MaxDurationReached: return "MaxDurationReached"
        case FgVadEndReason_ExternalStop: return "ExternalStop"
        default: return "EndReason(\(rawValue))"
        }
    }
}
