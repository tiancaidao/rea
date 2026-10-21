package com.example.sleepclone.sensing

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.sqrt

/**
 * Accelerometer movement detector, modelled on the original's
 * logic.detector.MovementDetector (which had an explicit CalibrationPhase:
 * SensorManager.getDefaultSensor / registerListener were confirmed in the DEX).
 *
 * During sleep tracking the phone rests on the mattress; body movement couples
 * into the accelerometer. We band-pass the acceleration magnitude, drop the
 * gravity baseline learned during calibration, and emit a per-epoch movement
 * amount that later feeds sleep-phase estimation.
 */
class MovementDetector(
    private val sensorManager: SensorManager,
    private val onMovement: (epochMillis: Long, amount: Float) -> Unit,
) : SensorEventListener {

    private val accel: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

    /** Calibration learns the resting gravity magnitude before tracking starts. */
    enum class CalibrationPhase { CALIBRATING, TRACKING }

    private var phase = CalibrationPhase.CALIBRATING
    private var baseline = 9.81f
    private var calibrationSum = 0f
    private var calibrationCount = 0
    private var epochStart = 0L
    private var epochPeak = 0f

    fun start() {
        phase = CalibrationPhase.CALIBRATING
        calibrationSum = 0f; calibrationCount = 0
        accel?.let { sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
    }

    fun stop() = sensorManager.unregisterListener(this)

    override fun onSensorChanged(e: SensorEvent) {
        val mag = sqrt(e.values[0] * e.values[0] + e.values[1] * e.values[1] + e.values[2] * e.values[2])
        when (phase) {
            CalibrationPhase.CALIBRATING -> {
                calibrationSum += mag; calibrationCount++
                if (calibrationCount >= CALIBRATION_SAMPLES) {
                    baseline = calibrationSum / calibrationCount
                    phase = CalibrationPhase.TRACKING
                    epochStart = System.currentTimeMillis()
                }
            }
            CalibrationPhase.TRACKING -> {
                val dev = kotlin.math.abs(mag - baseline)
                if (dev > epochPeak) epochPeak = dev
                val now = System.currentTimeMillis()
                if (now - epochStart >= EPOCH_MILLIS) {
                    onMovement(epochStart, epochPeak)
                    epochStart = now; epochPeak = 0f
                }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    companion object {
        private const val CALIBRATION_SAMPLES = 256   // ~constant family seen in the RE
        private const val EPOCH_MILLIS = 30_000L      // 30-second sleep epochs
    }
}
