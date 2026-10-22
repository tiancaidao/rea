package com.example.sleep_tracker

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.BatteryManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Battery state (for the low-battery warning while tracking) and the ambient
 * light sensor (the night's "Light" metric), the two device readings the
 * Flutter plugins in use don't cover.
 */
class DevicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler,
    SensorEventListener {

    private lateinit var context: Context
    private lateinit var sensors: SensorManager
    private var sink: EventChannel.EventSink? = null
    private var lastEmit = 0L

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        sensors = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        MethodChannel(binding.binaryMessenger, "sleepclone/device").setMethodCallHandler(this)
        EventChannel(binding.binaryMessenger, "sleepclone/light").setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        sensors.unregisterListener(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "battery" -> {
                val status = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                if (status == null) {
                    result.success(null)
                    return
                }
                val level = status.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = status.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
                val plugged = status.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
                result.success(mapOf("level" to (level * 100 / maxOf(scale, 1)), "charging" to (plugged != 0)))
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val light = sensors.getDefaultSensor(Sensor.TYPE_LIGHT)
        if (light == null) {
            events?.endOfStream()
            return
        }
        sink = events
        sensors.registerListener(this, light, SensorManager.SENSOR_DELAY_NORMAL)
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        sensors.unregisterListener(this)
    }

    override fun onSensorChanged(e: SensorEvent) {
        val now = System.currentTimeMillis()
        if (now - lastEmit < 1000) return // one reading a second is plenty
        lastEmit = now
        sink?.success(e.values[0].toDouble())
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
