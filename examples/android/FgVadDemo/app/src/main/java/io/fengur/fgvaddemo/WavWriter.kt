package io.fengur.fgvaddemo

import java.io.File
import java.io.RandomAccessFile

/**
 * 流式写 16 kHz mono PCM-16 WAV。
 * 用法：
 *   val w = WavWriter(file)
 *   w.append(samples, count)  // 多次
 *   w.finalize()              // 必调
 */
class WavWriter(private val file: File) {

    private val raf: RandomAccessFile
    private var samplesWritten: Int = 0

    init {
        file.parentFile?.mkdirs()
        if (file.exists()) file.delete()
        raf = RandomAccessFile(file, "rw")
        raf.write(placeholderHeader())   // 占位 header，finalize 时回填
    }

    fun append(samples: ShortArray, count: Int) {
        val n = count.coerceAtMost(samples.size)
        val bytes = ByteArray(n * 2)
        for (i in 0 until n) {
            val s = samples[i].toInt()
            bytes[2 * i] = (s and 0xff).toByte()
            bytes[2 * i + 1] = ((s shr 8) and 0xff).toByte()
        }
        raf.write(bytes)
        samplesWritten += n
    }

    fun finalize() {
        val dataBytes = samplesWritten * 2
        val riffSize = 36 + dataBytes
        // RIFF size at offset 4
        raf.seek(4); raf.write(le32(riffSize))
        // data size at offset 40
        raf.seek(40); raf.write(le32(dataBytes))
        raf.close()
    }

    private fun placeholderHeader(): ByteArray {
        val out = java.io.ByteArrayOutputStream(44)
        out.write("RIFF".toByteArray(Charsets.US_ASCII))
        out.write(le32(0))                         // riff size, finalize 回填
        out.write("WAVE".toByteArray(Charsets.US_ASCII))
        out.write("fmt ".toByteArray(Charsets.US_ASCII))
        out.write(le32(16))                        // fmt chunk size
        out.write(le16(1))                         // audio format = PCM
        out.write(le16(1))                         // channels
        out.write(le32(16000))                     // sample rate
        out.write(le32(16000 * 2))                 // byte rate
        out.write(le16(2))                         // block align
        out.write(le16(16))                        // bits per sample
        out.write("data".toByteArray(Charsets.US_ASCII))
        out.write(le32(0))                         // data size, finalize 回填
        return out.toByteArray()
    }

    private fun le32(v: Int): ByteArray = byteArrayOf(
        (v and 0xff).toByte(),
        ((v shr 8) and 0xff).toByte(),
        ((v shr 16) and 0xff).toByte(),
        ((v shr 24) and 0xff).toByte(),
    )
    private fun le16(v: Int): ByteArray = byteArrayOf(
        (v and 0xff).toByte(),
        ((v shr 8) and 0xff).toByte(),
    )
}
