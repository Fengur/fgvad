package io.fengur.fgvaddemo

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import io.fengur.fgvad.FgVad

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 烟测：FgVad 类初始化触发 System.loadLibrary("fgvad_android")
        android.util.Log.i("FgVadDemo", "fgvad version=${FgVad.version()}")
    }
}
