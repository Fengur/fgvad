package io.fengur.fgvaddemo

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack

/**
 * 直接播放 16 kHz mono i16 PCM 整段音频。AudioTrack STATIC 模式：
 * 一次性写入全部样本，调用 play() 立即开始放。
 */
object SentencePlayer {
    @Volatile private var current: AudioTrack? = null

    fun play(samples: ShortArray) {
        stop()
        if (samples.isEmpty()) return
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(16_000)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(samples.size * 2)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()
        track.write(samples, 0, samples.size)
        track.play()
        current = track
    }

    fun stop() {
        current?.let {
            try { it.stop() } catch (_: Throwable) {}
            it.release()
        }
        current = null
    }
}
