package com.example.omed

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// ============================================================
// >>> AJOUT : Chaquopy
// ============================================================

import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform

// ============================================================
// <<< FIN AJOUT : Chaquopy
// ============================================================


class MainActivity : FlutterActivity() {

    // ========================================================
    // >>> AJOUT : canal Flutter <-> Android
    // ========================================================

    private val CHANNEL = "omed/python"

    // ========================================================
    // <<< FIN AJOUT
    // ========================================================


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ====================================================
        // >>> AJOUT : démarrage de Python
        // ====================================================

        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }

        // ====================================================
        // <<< FIN AJOUT
        // ====================================================


        // ====================================================
        // >>> AJOUT : création du MethodChannel
        // ====================================================

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            val python = Python.getInstance()
            val server = python.getModule("server")

            when (call.method) {

                "startServer" -> {
                    server.callAttr("start_server")
                    result.success(true)
                }

                "getLogs" -> {
                    val logs = server
                        .callAttr("get_logs")
                        .asList()

                    result.success(
                        logs.map { it.toString() }
                    )
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        // ====================================================
        // <<< FIN AJOUT : MethodChannel
        // ====================================================
    }
}