package com.musync.mimo

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.musync.mimo/foreground"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForeground" -> {
                        val title = call.argument<String>("title") ?: "MusyncMIMO"
                        MusyncForegroundService.start(this, title)
                        result.success(true)
                    }
                    "stopForeground" -> {
                        MusyncForegroundService.stop(this)
                        result.success(true)
                    }
                    "getApkPath" -> {
                        try {
                            val apkPath = context.packageManager
                                .getApplicationInfo(context.packageName, 0)
                                .sourceDir
                            result.success(apkPath)
                        } catch (e: Exception) {
                            result.error("APK_ERROR", "Failed to get APK path: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
