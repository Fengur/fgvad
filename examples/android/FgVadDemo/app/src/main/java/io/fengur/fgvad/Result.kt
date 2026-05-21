package io.fengur.fgvad

/**
 * VAD 处理结果。一次 [FgVad.process] 返回 0..N 条。
 *
 * 构造器签名 `(IIIIZZJ[S)V` 与 fgvad-jni `nativeProcess` 内的
 * `env.new_object("io/fengur/fgvad/Result", ...)` 调用严格对齐。
 *
 * @property audioSamples 仅 SentenceEnded / SentenceForceCut 时 non-null，
 *                       含整句 16 kHz mono i16 PCM。其他事件为 null。
 */
class Result(
    type: Int,
    event: Int,
    state: Int,
    endReason: Int,
    val isSentenceBegin: Boolean,
    val isSentenceEnd: Boolean,
    val streamOffsetSample: Long,
    val audioSamples: ShortArray?,
) {
    val type: ResultType = ResultType.values()[type]
    val event: Event = Event.values()[event]
    val state: State = State.values()[state]
    val endReason: EndReason = EndReason.values()[endReason]

    /** 起始时间（毫秒，自 start 起）。基于 16 kHz 采样率换算。 */
    val startMs: Double get() = streamOffsetSample.toDouble() / 16.0

    val durationMs: Double get() = (audioSamples?.size?.toDouble() ?: 0.0) / 16.0

    val endMs: Double get() = startMs + durationMs
}
