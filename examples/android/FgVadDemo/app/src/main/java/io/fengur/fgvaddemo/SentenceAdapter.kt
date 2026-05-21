package io.fengur.fgvaddemo

import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class SentenceAdapter : RecyclerView.Adapter<SentenceAdapter.VH>() {

    private val items = mutableListOf<Sentence>()

    fun clear() { val n = items.size; items.clear(); notifyItemRangeRemoved(0, n) }
    fun add(s: Sentence) { items.add(s); notifyItemInserted(items.size - 1) }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val tv = TextView(parent.context).apply {
            textSize = 13f
            setPadding(8, 12, 8, 12)
        }
        return VH(tv)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val s = items[position]
        holder.tv.text = "Sentence ${s.index} | ${s.endEvent} | ${formatMs(s.startMs)} - ${formatMs(s.endMs)}"
    }

    override fun getItemCount(): Int = items.size

    class VH(val tv: TextView) : RecyclerView.ViewHolder(tv)

    companion object {
        fun formatMs(ms: Double): String {
            val total = ms.toInt()
            val m = total / 60_000
            val s = (total % 60_000) / 1_000
            val mil = total % 1_000
            return "%02d:%02d.%03d".format(m, s, mil)
        }
    }
}
