package io.fengur.fgvaddemo

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import java.io.InputStream

class AudioPickerAdapter(
    private val onPreviewClicked: (Row.Item) -> Unit,
    private val onAnalyzeClicked: (Row.Item) -> Unit,
    private val onDeleteClicked: ((Row.Item) -> Unit)?,
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    sealed class Row {
        data class SectionHeader(val title: String, val showClear: Boolean) : Row()
        data class Item(
            val label: String,
            val opener: () -> InputStream,
            val isDeletable: Boolean,
        ) : Row()
    }

    private var rows: List<Row> = emptyList()

    fun submitList(newRows: List<Row>) {
        rows = newRows
        notifyDataSetChanged()
    }

    override fun getItemViewType(position: Int): Int = when (rows[position]) {
        is Row.SectionHeader -> 0
        is Row.Item -> 1
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        return if (viewType == 0) {
            val v = LayoutInflater.from(parent.context)
                .inflate(R.layout.row_picker_section_header, parent, false)
            HeaderVH(v)
        } else {
            val v = LayoutInflater.from(parent.context)
                .inflate(R.layout.row_picker_item, parent, false)
            ItemVH(v)
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val r = rows[position]) {
            is Row.SectionHeader -> {
                val h = holder as HeaderVH
                h.title.text = r.title
                h.clearBtn.visibility = if (r.showClear) View.VISIBLE else View.GONE
                // Android-1 暂不 wire 清空动作（Android-2 处理）
                h.clearBtn.setOnClickListener(null)
            }
            is Row.Item -> {
                val h = holder as ItemVH
                h.label.text = r.label
                h.previewBtn.setOnClickListener { onPreviewClicked(r) }
                h.analyzeBtn.setOnClickListener { onAnalyzeClicked(r) }
                h.deleteBtn.visibility = if (r.isDeletable) View.VISIBLE else View.GONE
                h.deleteBtn.setOnClickListener {
                    onDeleteClicked?.invoke(r)
                }
            }
        }
    }

    override fun getItemCount(): Int = rows.size

    class HeaderVH(view: View) : RecyclerView.ViewHolder(view) {
        val title: TextView = view.findViewById(R.id.headerTitle)
        val clearBtn: Button = view.findViewById(R.id.clearBtn)
    }

    class ItemVH(view: View) : RecyclerView.ViewHolder(view) {
        val label: TextView = view.findViewById(R.id.itemLabel)
        val previewBtn: Button = view.findViewById(R.id.previewBtn)
        val analyzeBtn: Button = view.findViewById(R.id.analyzeBtn)
        val deleteBtn: Button = view.findViewById(R.id.deleteBtn)
    }
}
