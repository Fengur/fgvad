package io.fengur.fgvaddemo

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetDialogFragment

class AudioPickerSheet : BottomSheetDialogFragment() {

    /** ▶预 触发：把 ShortArray PCM 直接交给宿主播放（host 自己持有 SentencePlayer） */
    var onPreview: ((label: String, samples: ShortArray) -> Unit)? = null

    /** ▶析 触发：sheet 自动 dismiss，host 调 runAnalyze */
    var onAnalyze: ((label: String, samples: ShortArray) -> Unit)? = null

    private val adapter = AudioPickerAdapter(
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
        onDeleteClicked = null,   // recordings 段才有，Android-2 wire
    )

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?,
    ): View {
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

        // bundled 段
        items.add(AudioPickerAdapter.Row.SectionHeader("bundled", showClear = false))
        val ctx = requireContext()
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

        // recordings 段 —— 占位，Android-2 fill
        items.add(AudioPickerAdapter.Row.SectionHeader("recordings", showClear = true))

        adapter.submitList(items)
    }
}
