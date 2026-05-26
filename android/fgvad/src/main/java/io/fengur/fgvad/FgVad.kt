package io.fengur.fgvad

class FgVad private constructor(private var handle: Long) : AutoCloseable {

    init {
        require(handle != 0L) { "fgvad handle is null" }
    }

    /** 短时模式:命令/查询语义,尾静音到点结束。与 iOS ShortConfig 对齐。 */
    data class ShortConfig(
        /** 开始录音后允许连续静音多久没说话就放弃。 */
        val headSilenceMs: Int = 3_000,
        /** 进入说话后,连续静音多久认为一句话说完。 */
        val tailSilenceMs: Int = 2_000,
        /** 单次会话最长时长上限(含静音),超时强制结束。 */
        val maxDurationMs: Int = 30_000,
    )

    /** 长时模式:连续多句听写,外部不 stop 不结束。与 iOS LongConfig 对齐。 */
    data class LongConfig(
        val headSilenceMs: Int = 3_000,
        val maxSentenceMs: Int = 30_000,
        /** 0 表示不限会话总时长。 */
        val maxSessionMs: Int = 0,
        val tailSilenceMsInitial: Int = 2_000,
        val tailSilenceMsMin: Int = 600,
        val enableDynamicTail: Boolean = true,
    )

    companion object {
        init {
            System.loadLibrary("fgvad_android")  // 触发依赖 libten_vad.so 也加载
        }

        /** 短时模式:推荐 API,传 [ShortConfig] data class。 */
        fun newShort(config: ShortConfig = ShortConfig()): FgVad {
            val h = nativeNewShort(config.headSilenceMs, config.tailSilenceMs, config.maxDurationMs)
            require(h != 0L) { "FgVad.newShort failed" }
            return FgVad(h)
        }

        /** 长时模式:推荐 API,传 [LongConfig] data class。 */
        fun newLong(config: LongConfig = LongConfig()): FgVad {
            val h = nativeNewLong(
                config.headSilenceMs, config.maxSentenceMs, config.maxSessionMs,
                config.tailSilenceMsInitial, config.tailSilenceMsMin, config.enableDynamicTail
            )
            require(h != 0L) { "FgVad.newLong failed" }
            return FgVad(h)
        }

        @JvmStatic external fun nativeVersion(): String

        @JvmStatic external fun nativeNewShort(
            headSilenceMs: Int, tailSilenceMs: Int, maxDurationMs: Int,
        ): Long

        @JvmStatic external fun nativeNewLong(
            headSilenceMs: Int, maxSentenceMs: Int, maxSessionMs: Int,
            tailInitMs: Int, tailMinMs: Int, enableDynamicTail: Boolean,
        ): Long

        @JvmStatic external fun nativeFree(handle: Long)
        @JvmStatic external fun nativeStart(handle: Long)
        @JvmStatic external fun nativeStop(handle: Long)
        @JvmStatic external fun nativeReset(handle: Long)
        @JvmStatic external fun nativeState(handle: Long): Int
        @JvmStatic external fun nativeEndReason(handle: Long): Int
        @JvmStatic external fun nativeProcess(handle: Long, samples: ShortArray, count: Int): Array<Result>?

        fun version(): String = nativeVersion()
    }

    fun start() = nativeStart(handle)
    fun stop() = nativeStop(handle)
    fun reset() = nativeReset(handle)
    fun state(): State = State.values()[nativeState(handle)]
    fun endReason(): EndReason = EndReason.values()[nativeEndReason(handle)]

    fun process(samples: ShortArray, count: Int = samples.size): List<Result> {
        val arr = nativeProcess(handle, samples, count)
            ?: throw IllegalStateException("fgvad process failed")
        return arr.toList()
    }

    override fun close() {
        if (handle != 0L) {
            nativeFree(handle)
            handle = 0L
        }
    }
}
