package com.example.updater_app

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "playstore_status"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isPlayStoreDisabled") {
                try {
                    val pm = context.packageManager
                    val info = pm.getApplicationInfo("com.android.vending", 0)
                    result.success(!info.enabled)
                } catch (e: PackageManager.NameNotFoundException) {
                    result.success(true)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
