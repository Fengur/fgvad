package io.fengur.fgvaddemo

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class SentenceAdapter : RecyclerView.Adapter<SentenceAdapter.VH>() {

    private val items = mutableListOf<Sentence>()

    fun clear() { val n = items.size; items.clear(); notifyItemRangeRemoved(0, n) }
    fun add(s: Sentence) { items.add(s); notifyItemInserted(items.size - 1) }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val v = LayoutInflater.from(parent.context).inflate(R.layout.row_sentence, parent, false)
        return VH(v)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val s = items[position]
        holder.title.text = "Sentence ${s.index} | ${s.endEvent} | ${formatMs(s.startMs)} - ${formatMs(s.endMs)}"
        holder.play.isEnabled = s.audio != null
        holder.play.setOnClickListener {
            s.audio?.let { SentencePlayer.play(it) }
        }
    }

    override fun getItemCount(): Int = items.size

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val title: TextView = view.findViewById(R.id.sentenceTitle)
        val play: Button = view.findViewById(R.id.playBtn)
    }

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
