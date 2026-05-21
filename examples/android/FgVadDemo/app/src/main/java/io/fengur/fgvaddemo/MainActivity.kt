package io.fengur.fgvaddemo

import android.Manifest
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import io.fengur.fgvad.Event
import io.fengur.fgvad.FgVad

class MainActivity : AppCompatActivity() {

    private lateinit var logger: DemoLogger
    private var vad: FgVad? = null
    private val recorder = AudioRecorder { samples, count ->
        val v = vad ?: return@AudioRecorder
        val results = v.process(samples, count)
        for (r in results) {
            if (r.event != Event.None) {
                logger.i(
                    "VAD",
                    "event=${r.event} state=${r.state} startMs=${r.startMs.toInt()} dur=${r.durationMs.toInt()}ms",
                )
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        logger = DemoLogger.init(this)
        logger.i("App", "fgvad version=${FgVad.version()}")

        if (!recorder.isPermissionGranted(this)) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.RECORD_AUDIO), 1,
            )
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
        val startBtn = Button(this).apply { text = "Start (long mode)" }
        val stopBtn = Button(this).apply { text = "Stop" }
        root.addView(startBtn)
        root.addView(stopBtn)
        setContentView(root)

        // Push content below the status bar so buttons are not obscured
        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }

        startBtn.setOnClickListener {
            vad = FgVad.newLong(3000, 30_000, 0, 2000, 600, true)
            vad!!.start()
            recorder.start()
            logger.i("App", "started")
        }
        stopBtn.setOnClickListener {
            recorder.stop()
            vad?.stop()
            logger.i("App", "stopped, endReason=${vad?.endReason()}")
            vad?.close()
            vad = null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        recorder.stop()
        vad?.close()
        vad = null
    }
}
