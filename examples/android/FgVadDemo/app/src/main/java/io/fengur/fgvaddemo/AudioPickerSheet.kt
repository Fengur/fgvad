package io.fengur.fgvaddemo

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.appcompat.app.AlertDialog
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import java.io.File

class AudioPickerSheet : BottomSheetDialogFragment() {

    /** ▶析 触发：sheet 自动 dismiss，host 调 runAnalyze */
    var onAnalyze: ((label: String, samples: ShortArray) -> Unit)? = null

    private lateinit var adapter: AudioPickerAdapter

    // ── 内部 preview 播放器 ──────────────────────────────────────────
    private var previewPlayer: AudioTrack? = null
    private var playingItemId: String? = null

    private fun togglePreview(item: AudioPickerAdapter.Row.Item) {
        val id = item.label
        if (playingItemId == id) {
            stopPreview()
            return
        }
        stopPreview()
        Thread {
            try {
                val pcm = item.opener().use { WavReader.read(it) }
                requireActivity().runOnUiThread { startPlay(pcm, id) }
            } catch (t: Throwable) {
                DemoLogger.get().e("Picker", "preview wav read failed: ${t.message}")
            }
        }.start()
    }

    private fun startPlay(pcm: ShortArray, id: String) {
        val bufBytes = pcm.size * 2
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
            .setBufferSizeInBytes(bufBytes)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()
        track.write(pcm, 0, pcm.size)
        track.setNotificationMarkerPosition(pcm.size)
        track.setPlaybackPositionUpdateListener(object : AudioTrack.OnPlaybackPositionUpdateListener {
            override fun onMarkerReached(t: AudioTrack?) {
                requireActivity().runOnUiThread { stopPreview() }
            }
            override fun onPeriodicNotification(t: AudioTrack?) {}
        })
        track.play()
        previewPlayer = track
        playingItemId = id
        adapter.setPlayingItemId(id)
    }

    private fun stopPreview() {
        previewPlayer?.let {
            try { it.stop() } catch (_: Throwable) {}
            it.release()
        }
        previewPlayer = null
        if (playingItemId != null) {
            playingItemId = null
            adapter.setPlayingItemId(null)
        }
    }
    // ─────────────────────────────────────────────────────────────────

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?,
    ): View {
        adapter = AudioPickerAdapter(
            onPreviewClicked = { item -> togglePreview(item) },
            onAnalyzeClicked = { item ->
                Thread {
                    try {
                        val pcm = item.opener().use { WavReader.read(it) }
                        requireActivity().runOnUiThread {
                            dismiss()
                            onAnalyze?.invoke(item.label, pcm)
                        }
                    } catch (t: Throwable) {
                        DemoLogger.get().e("Picker", "analyze wav read failed: ${t.message}")
                    }
                }.start()
            },
            onDeleteClicked = { item ->
                val recordingsDir = File(requireContext().getExternalFilesDir(null), "recordings")
                val target = File(recordingsDir, item.label)
                val ok = target.delete()
                if (ok) {
                    DemoLogger.get().i("Picker", "deleted ${item.label}")
                    reload()
                } else {
                    DemoLogger.get().w("Picker", "delete failed: ${item.label}")
                }
            },
            onClearClicked = {
                AlertDialog.Builder(requireContext())
                    .setTitle("清空录音?")
                    .setMessage("将删除所有 mic 录音文件。已 adb push 的也会一起删除（同一目录）。")
                    .setNegativeButton("取消", null)
                    .setPositiveButton("清空") { _, _ ->
                        val recordingsDir = File(requireContext().getExternalFilesDir(null), "recordings")
                        val files = recordingsDir.listFiles() ?: emptyArray()
                        var failed = 0
                        for (f in files) {
                            if (!f.delete()) failed += 1
                        }
                        DemoLogger.get().i("Picker", "cleared recordings; failed=$failed")
                        reload()
                    }
                    .show()
            },
        )

        val rv = RecyclerView(requireContext()).apply {
            layoutManager = LinearLayoutManager(context)
            this.adapter = this@AudioPickerSheet.adapter
        }
        return rv
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        reload()
    }

    override fun onPause() {
        super.onPause()
        stopPreview()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        stopPreview()
    }

    fun reload() {
        val items = mutableListOf<AudioPickerAdapter.Row>()
        val ctx = requireContext()

        // bundled 段
        items.add(AudioPickerAdapter.Row.SectionHeader("bundled", showClear = false))
        val list = ctx.assets.list("short")?.sorted() ?: emptyList()
        for (name in list) {
            items.add(
                AudioPickerAdapter.Row.Item(
                    label = "short/$name",
                    opener = { ctx.assets.open("short/$name") },
                    isDeletable = false,
                )
            )
        }

        // recordings 段
        items.add(AudioPickerAdapter.Row.SectionHeader("recordings", showClear = true))
        val recordingsDir = File(ctx.getExternalFilesDir(null), "recordings")
        if (recordingsDir.exists()) {
            val files = recordingsDir.listFiles { _, n -> n.endsWith(".wav") }
                ?.sortedByDescending { it.lastModified() }
                ?: emptyList()
            for (f in files) {
                items.add(
                    AudioPickerAdapter.Row.Item(
                        label = f.name,
                        opener = { f.inputStream() },
                        isDeletable = true,
                    )
                )
            }
        }

        adapter.submitList(items)
    }
}
