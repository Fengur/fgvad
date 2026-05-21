package io.fengur.fgvaddemo

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.content.ContextCompat

class AudioRecorder(private val onPcm: (samples: ShortArray, count: Int) -> Unit) {

    private var thread: Thread? = null
    @Volatile private var running = false
    private var rec: AudioRecord? = null

    fun isPermissionGranted(ctx: android.content.Context): Boolean =
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    @Suppress("MissingPermission")
    fun start() {
        if (running) return
        val sampleRate = 16_000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBuf = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        val bufBytes = (minBuf * 2).coerceAtLeast(4096)

        rec = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            sampleRate, channelConfig, audioFormat, bufBytes,
        )
        rec?.startRecording()
        running = true

        thread = Thread {
            val chunk = ShortArray(1024)  // 64ms @ 16kHz
            while (running) {
                val n = rec?.read(chunk, 0, chunk.size) ?: 0
                if (n > 0) onPcm(chunk, n)
            }
        }.apply {
            name = "AudioRecorder"
            start()
        }
    }

    fun stop() {
        if (!running) return
        running = false
        rec?.stop()                  // signal blocked read() to return
        thread?.join(500)
        thread = null
        rec?.release()
        rec = null
    }
}
