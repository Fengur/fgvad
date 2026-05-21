package io.fengur.fgvad

class FgVad private constructor(private var handle: Long) : AutoCloseable {

    init {
        require(handle != 0L) { "fgvad handle is null" }
    }

    companion object {
        init {
            System.loadLibrary("fgvad_android")  // 触发依赖 libten_vad.so 也加载
        }

        fun newShort(headSilenceMs: Int, tailSilenceMs: Int, maxDurationMs: Int): FgVad {
            val h = nativeNewShort(headSilenceMs, tailSilenceMs, maxDurationMs)
            require(h != 0L) { "FgVad.newShort failed" }
            return FgVad(h)
        }

        fun newLong(
            headSilenceMs: Int,
            maxSentenceMs: Int,
            maxSessionMs: Int,
            tailInitMs: Int,
            tailMinMs: Int,
            enableDynamicTail: Boolean,
        ): FgVad {
            val h = nativeNewLong(
                headSilenceMs, maxSentenceMs, maxSessionMs,
                tailInitMs, tailMinMs, enableDynamicTail
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
