package com.example.sleep_tracker

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Streams accelerometer samples to Flutter over an EventChannel, and starts/stops
 * on a MethodChannel. In a production build the sampling would run inside a
 * foreground Service (FOREGROUND_SERVICE_MICROPHONE / health) so it survives the
 * screen being off overnight; this shows the channel wiring and the sensor loop.
 */
class SensingPlugin : FlutterPlugin, EventChannel.StreamHandler, SensorEventListener,
    MethodChannel.MethodCallHandler {

    private lateinit var sensorManager: SensorManager
    private var accel: Sensor? = null
    private var events: EventChannel.EventSink? = null
    private var sampleHz = 50
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val ctx = binding.applicationContext
        sensorManager = ctx.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accel = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        EventChannel(binding.binaryMessenger, "sleepclone/accelerometer").setStreamHandler(this)
        MethodChannel(binding.binaryMessenger, "sleepclone/sensing").setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        sensorManager.unregisterListener(this)
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                sampleHz = call.argument<Int>("sampleHz") ?: 50
                register()
                result.success(null)
            }
            "stop" -> {
                sensorManager.unregisterListener(this)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun register() {
        accel?.let {
            val periodUs = 1_000_000 / sampleHz
            sensorManager.registerListener(this, it, periodUs)
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
        register()
    }

    override fun onCancel(arguments: Any?) {
        events = null
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(e: SensorEvent) {
        val sink = events ?: return
        val v = listOf(e.values[0], e.values[1], e.values[2])
        main.post { sink.success(v) }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
