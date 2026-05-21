package io.fengur.fgvaddemo

import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

object WavReader {

    /**
     * 读 WAV 文件成 i16 mono PCM（16 kHz）。不支持转换——文件本身必须是
     * RIFF / 16 kHz / mono / 16-bit PCM，否则抛 [IllegalArgumentException]。
     */
    fun read(input: InputStream): ShortArray {
        val all = input.readBytes()
        require(all.size >= 44) { "wav too short" }
        val bb = ByteBuffer.wrap(all).order(ByteOrder.LITTLE_ENDIAN)
        require(String(all, 0, 4) == "RIFF") { "not RIFF" }
        require(String(all, 8, 4) == "WAVE") { "not WAVE" }

        // fmt chunk starts at byte 12
        require(String(all, 12, 4) == "fmt ") { "expected fmt at 12" }
        val fmtSize = bb.getInt(16)
        val audioFormat = bb.getShort(20).toInt() and 0xFFFF
        val channels = bb.getShort(22).toInt() and 0xFFFF
        val sampleRate = bb.getInt(24)
        val bitsPerSample = bb.getShort(34).toInt() and 0xFFFF
        require(audioFormat == 1) { "audioFormat=$audioFormat (must be PCM=1)" }
        require(channels == 1) { "channels=$channels (must be 1)" }
        require(sampleRate == 16_000) { "sampleRate=$sampleRate (must be 16000)" }
        require(bitsPerSample == 16) { "bitsPerSample=$bitsPerSample (must be 16)" }

        // Walk chunks looking for "data"
        var pos = 20 + fmtSize
        while (pos + 8 <= all.size) {
            val id = String(all, pos, 4)
            val size = bb.getInt(pos + 4)
            if (id == "data") {
                val nBytes = size.coerceAtMost(all.size - pos - 8)
                val nSamples = nBytes / 2
                val out = ShortArray(nSamples)
                val sb = bb.duplicate().order(ByteOrder.LITTLE_ENDIAN)
                sb.position(pos + 8)
                sb.asShortBuffer().get(out)
                return out
            }
            pos += 8 + size
        }
        throw IllegalArgumentException("no data chunk")
    }
}
