package com.example.sleepclone.domain

import com.example.sleepclone.data.PhasePoint
import com.example.sleepclone.data.SleepPhase

/**
 * Fuses per-epoch movement (accelerometer) and snore activity (audio embedding
 * similarity) into a sleep-phase timeline and a smart-alarm wake window.
 *
 * This is a transparent, replaceable heuristic that mirrors the *shape* of what
 * the original does in sleepanalysis / sleepstaging (movement + audio features
 * per epoch). Swap it for a learned stager once you have labelled data; the
 * original's exact scoring lives in Kotlin we can decompile with jadx on-device.
 */
class SleepPhaseEstimator(
    private val epochMinutes: Int = 1,
) {
    data class Epoch(val tMinute: Int, val movement: Float, val snore: Boolean)

    fun classify(epochs: List<Epoch>): List<PhasePoint> {
        if (epochs.isEmpty()) return emptyList()
        val maxMove = epochs.maxOf { it.movement }.coerceAtLeast(1e-3f)
        return epochs.map { e ->
            val m = e.movement / maxMove
            val phase = when {
                m > 0.6f -> SleepPhase.AWAKE
                m > 0.25f -> SleepPhase.LIGHT
                m > 0.08f -> SleepPhase.REM     // low movement but not fully still
                else -> SleepPhase.DEEP
            }
            PhasePoint(e.tMinute, phase.name.lowercase())
        }
    }

    /**
     * Smart-alarm: within [windowStartMin, alarmMin], wake at the lightest sleep
     * (highest recent movement) rather than jolting the user out of deep sleep.
     */
    fun bestWakeMinute(epochs: List<Epoch>, windowStartMin: Int, alarmMin: Int): Int {
        val inWindow = epochs.filter { it.tMinute in windowStartMin..alarmMin }
        return inWindow.maxByOrNull { it.movement }?.tMinute ?: alarmMin
    }
}
