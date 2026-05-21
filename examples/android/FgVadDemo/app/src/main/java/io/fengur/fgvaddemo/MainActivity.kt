package io.fengur.fgvaddemo

import android.Manifest
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.button.MaterialButtonToggleGroup
import io.fengur.fgvad.EndReason
import io.fengur.fgvad.Event
import io.fengur.fgvad.FgVad

class MainActivity : AppCompatActivity() {

    private enum class Mode { SHORT, LONG }
    private var currentMode = Mode.SHORT

    private lateinit var logger: DemoLogger
    private val ui = Handler(Looper.getMainLooper())

    private var vad: FgVad? = null
    private var sentenceCount = 0

    // 短时参数
    private val shortHead = NumField("head_silence_timeout", "3000")
    private val shortTail = NumField("tail_silence", "2000")
    private val shortMax  = NumField("max_duration", "30000")

    // 长时参数
    private val longHead     = NumField("head_silence_timeout", "3000")
    private val longMaxSent  = NumField("max_sentence_duration", "30000")
    private val longTailInit = NumField("tail_silence_initial", "2000")
    private val longTailMin  = NumField("tail_silence_min", "600")
    private var longDynamic  = true

    private lateinit var paramsContainer: LinearLayout
    private lateinit var modeHint: TextView
    private lateinit var statusLabel: TextView
    private lateinit var recordBtn: Button
    private lateinit var loadAudioBtn: Button
    private lateinit var sentenceList: RecyclerView

    private val sentenceAdapter = SentenceAdapter()
    private val recorder = AudioRecorder { samples, count -> onPcm(samples, count) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        logger = DemoLogger.init(this)
        logger.i("App", "fgvad version=${FgVad.version()}")
        setContentView(R.layout.activity_main)

        // 让内容避开 status bar（设备是 edge-to-edge）
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(android.R.id.content)) { v, insets ->
            val top = insets.getInsets(WindowInsetsCompat.Type.systemBars()).top
            v.setPadding(v.paddingLeft, top, v.paddingRight, v.paddingBottom)
            insets
        }

        modeHint = findViewById(R.id.modeHint)
        paramsContainer = findViewById(R.id.paramsContainer)
        statusLabel = findViewById(R.id.statusLabel)
        recordBtn = findViewById(R.id.recordBtn)
        loadAudioBtn = findViewById(R.id.loadAudioBtn)
        sentenceList = findViewById(R.id.sentenceList)
        sentenceList.layoutManager = LinearLayoutManager(this)
        sentenceList.adapter = sentenceAdapter

        val modeGroup: MaterialButtonToggleGroup = findViewById(R.id.modeGroup)
        modeGroup.check(R.id.modeShort)
        modeGroup.addOnButtonCheckedListener { _, id, isChecked ->
            if (!isChecked) return@addOnButtonCheckedListener
            currentMode = if (id == R.id.modeShort) Mode.SHORT else Mode.LONG
            applyMode()
        }
        applyMode()

        recordBtn.setOnClickListener { toggleRecord() }
        loadAudioBtn.setOnClickListener { showLoadAudioDialog() }

        if (!recorder.isPermissionGranted(this)) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.RECORD_AUDIO), 1,
            )
        }

        statusLabel.text = "状态：就绪"
    }

    private fun applyMode() {
        paramsContainer.removeAllViews()
        when (currentMode) {
            Mode.SHORT -> {
                modeHint.text = "短时：尾静音达标即结束整个会话；适合命令/查询"
                addRow(shortHead)
                addRow(shortTail)
                addRow(shortMax)
            }
            Mode.LONG -> {
                modeHint.text = "长时：自动切句，外部 stop 才结束；适合听写/连续口述"
                addRow(longHead)
                addRow(longMaxSent)
                addRow(longTailInit)
                addRow(longTailMin)
                addDynamicSwitch()
            }
        }
    }

    private fun addRow(field: NumField) {
        val row = layoutInflater.inflate(R.layout.row_param, paramsContainer, false)
        row.findViewById<TextView>(R.id.paramName).text = field.name
        val edit = row.findViewById<EditText>(R.id.paramValue)
        edit.setText(field.value)
        edit.inputType = InputType.TYPE_CLASS_NUMBER
        edit.addTextChangedListener(object : android.text.TextWatcher {
            override fun afterTextChanged(s: android.text.Editable?) {
                field.value = s?.toString() ?: ""
            }
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
        })
        row.findViewById<TextView>(R.id.paramUnit).text = "ms"
        paramsContainer.addView(row)
    }

    private fun addDynamicSwitch() {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(4, 4, 4, 4)
        }
        val label = TextView(this).apply { text = "启用动态尾端点曲线"; textSize = 13f }
        val sw = androidx.appcompat.widget.SwitchCompat(this).apply {
            isChecked = longDynamic
            setOnCheckedChangeListener { _, checked -> longDynamic = checked }
        }
        row.addView(label, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(sw)
        paramsContainer.addView(row)
    }

    private fun toggleRecord() {
        if (vad == null) startSession()
        else stopSession(reason = "ExternalStop")
    }

    private fun startSession() {
        sentenceCount = 0
        sentenceAdapter.clear()

        vad = when (currentMode) {
            Mode.SHORT -> FgVad.newShort(
                shortHead.intValue(3000),
                shortTail.intValue(2000),
                shortMax.intValue(30_000),
            )
            Mode.LONG -> FgVad.newLong(
                longHead.intValue(3000),
                longMaxSent.intValue(30_000),
                0,
                longTailInit.intValue(2000),
                longTailMin.intValue(600),
                longDynamic,
            )
        }
        vad!!.start()
        recorder.start()
        recordBtn.text = "停止录音"
        statusLabel.text = "状态：录音中 · 0 句"
        logger.i("App", "session start mode=$currentMode")
    }

    private fun stopSession(reason: String) {
        recorder.stop()
        vad?.stop()
        val end = vad?.endReason() ?: EndReason.None
        logger.i("App", "session stop endReason=$end ($reason)")
        vad?.close()
        vad = null
        recordBtn.text = "开始录音"
        ui.post { statusLabel.text = "状态：${reasonText(end)} · $sentenceCount 句" }
    }

    private fun reasonText(r: EndReason): String = when (r) {
        EndReason.None -> "已停止"
        EndReason.SpeechCompleted -> "完成"
        EndReason.HeadSilenceTimeout -> "头部超时"
        EndReason.MaxDurationReached -> "时长上限"
        EndReason.ExternalStop -> "用户停止"
    }

    private fun onPcm(samples: ShortArray, count: Int) {
        val v = vad ?: return
        val results = v.process(samples, count)
        if (results.isEmpty()) return
        ui.post { handleResults(results) }
    }

    private fun handleResults(results: List<io.fengur.fgvad.Result>) {
        for (r in results) {
            if (r.event != Event.None) {
                logger.i("VAD", "event=${r.event} state=${r.state} startMs=${r.startMs.toInt()}")
            }
            if (r.event == Event.SentenceEnded || r.event == Event.SentenceForceCut) {
                sentenceCount += 1
                sentenceAdapter.add(
                    Sentence(
                        index = sentenceCount,
                        startMs = r.startMs,
                        endMs = r.endMs,
                        endEvent = r.event,
                        audio = r.audioSamples,
                    )
                )
                statusLabel.text = "状态：录音中 · $sentenceCount 句"
            }
            if (r.state == io.fengur.fgvad.State.End) {
                stopSession(reason = "natural-end")
            }
        }
    }

    private fun showLoadAudioDialog() {
        // Task 18 实现
        Toast.makeText(this, "TODO: load audio dialog (Task 18)", Toast.LENGTH_SHORT).show()
    }

    override fun onDestroy() {
        super.onDestroy()
        recorder.stop()
        vad?.stop()
        vad?.close()
        vad = null
    }
}

private class NumField(val name: String, var value: String) {
    fun intValue(default: Int): Int = value.toIntOrNull() ?: default
}
