package io.fengur.fgvaddemo

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import io.fengur.fgvad.FgVad

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        DemoLogger.init(this)
        DemoLogger.get().i("App", "fgvad version=${FgVad.version()}")
    }
}
