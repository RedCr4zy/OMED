package com.example.omed

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ✅ Initialiser Python avec AndroidPlatform AVANT tout autre usage
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "omed/python")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startServer" -> {
                        Python.getInstance().run {
                            getModule("server").callAttr("start_server")
                        }
                        result.success(null)
                    }
                    "getLogs" -> {
                        val logs = Python.getInstance().run {
                            getModule("server").callAttr("get_logs") as? List<*>
                        }
                        result.success(logs?.map { it.toString() })
                    }
                    else -> result.notImplemented()
                }
            }
    }
}