package io.fengur.fgvaddemo

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 把调试日志写到固定文件路径：
 *   /sdcard/Android/data/io.fengur.fgvaddemo/files/run.log
 *
 * App 启动 truncate。Claude 端 `adb pull` 出来 Read。
 * 不依赖 logcat（要可持久化、可跨 iOS/Android 比对）。
 */
class DemoLogger private constructor(private val file: File) {

    private val fmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    fun i(tag: String, msg: String) = write("I", tag, msg)
    fun w(tag: String, msg: String) = write("W", tag, msg)
    fun e(tag: String, msg: String) = write("E", tag, msg)

    @Synchronized
    private fun write(level: String, tag: String, msg: String) {
        val line = "${fmt.format(Date())} $level/$tag: $msg\n"
        file.appendText(line)
        when (level) {
            "I" -> android.util.Log.i(tag, msg)
            "W" -> android.util.Log.w(tag, msg)
            "E" -> android.util.Log.e(tag, msg)
        }
    }

    companion object {
        @Volatile private var instance: DemoLogger? = null

        fun init(ctx: Context): DemoLogger {
            val existing = instance
            if (existing != null) return existing
            synchronized(this) {
                val again = instance
                if (again != null) return again
                val f = File(ctx.getExternalFilesDir(null), "run.log")
                f.parentFile?.mkdirs()
                f.writeText("")  // truncate on app start
                val l = DemoLogger(f)
                instance = l
                return l
            }
        }

        fun get(): DemoLogger = instance!!
    }
}
