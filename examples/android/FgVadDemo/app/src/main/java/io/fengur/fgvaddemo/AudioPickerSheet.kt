package io.fengur.fgvaddemo

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

    /** ▶预 触发：把 ShortArray PCM 直接交给宿主播放（host 自己持有 SentencePlayer） */
    var onPreview: ((label: String, samples: ShortArray) -> Unit)? = null

    /** ▶析 触发：sheet 自动 dismiss，host 调 runAnalyze */
    var onAnalyze: ((label: String, samples: ShortArray) -> Unit)? = null

    private lateinit var adapter: AudioPickerAdapter

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?,
    ): View {
        adapter = AudioPickerAdapter(
            onPreviewClicked = { item ->
                Thread {
                    try {
                        val pcm = item.opener().use { WavReader.read(it) }
                        requireActivity().runOnUiThread {
                            onPreview?.invoke(item.label, pcm)
                        }
                    } catch (t: Throwable) {
                        DemoLogger.get().e("Picker", "preview wav read failed: ${t.message}")
                    }
                }.start()
            },
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
