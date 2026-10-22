package com.example.sleep_tracker

import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FragmentActivity is required by the health plugin's permission flow.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(DevicePlugin())
        // While the alarm rings, show over the lock screen and wake the display.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sleepclone/window")
            .setMethodCallHandler { call, result ->
                if (call.method == "showOverLock") {
                    showOverLock(call.argument<Boolean>("on") == true)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun showOverLock(on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(on)
            setTurnScreenOn(on)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (on) window.addFlags(flags) else window.clearFlags(flags)
        }
    }
}
