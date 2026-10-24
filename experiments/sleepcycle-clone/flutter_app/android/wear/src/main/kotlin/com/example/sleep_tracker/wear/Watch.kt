package com.example.sleep_tracker.wear

import android.content.Context
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** What the phone last published at /sleepclone/state. */
data class PhoneState(
    val tracking: Boolean = false,
    val since: Long = 0,
    val alarmStart: Long = 0,
    val alarmEnd: Long = 0,
    val alarmType: String = "Automatic",
) {
    companion object {
        fun from(m: DataMap) = PhoneState(
            tracking = m.getBoolean("tracking"),
            since = m.getLong("since"),
            alarmStart = m.getLong("alarmStart"),
            alarmEnd = m.getLong("alarmEnd"),
            alarmType = m.getString("alarmType") ?: "Automatic",
        )
    }
}

/** The phone's state and whether it's reachable, shared by the screens. */
object WatchStore {
    private val _state = MutableStateFlow(PhoneState())
    val state: StateFlow<PhoneState> = _state
    private val _reachable = MutableStateFlow(true)
    val reachable: StateFlow<Boolean> = _reachable
    private val _ringing = MutableStateFlow(false)
    val ringing: StateFlow<Boolean> = _ringing

    fun update(s: PhoneState) {
        _state.value = s
    }

    fun setReachable(on: Boolean) {
        _reachable.value = on
    }

    fun setRinging(on: Boolean) {
        _ringing.value = on
    }

    /** Read the latest state item (e.g. when the app opens). */
    fun refresh(context: Context) {
        Wearable.getDataClient(context).dataItems.addOnSuccessListener { items ->
            items.forEach {
                if (it.uri.path == STATE_PATH) update(PhoneState.from(com.google.android.gms.wearable.DataMapItem.fromDataItem(it).dataMap))
            }
            items.release()
        }
        Phone.request(context, "sync")
    }
}

const val STATE_PATH = "/sleepclone/state"
const val RING_PATH = "/sleepclone/ring"
const val RING_STOP_PATH = "/sleepclone/ring_stop"
const val SNORE_PATH = "/sleepclone/snore_buzz"
const val REQUEST_PREFIX = "/sleepclone/request/"
const val PHONE_CAPABILITY = "sleepclone_phone"

/** Requests to the phone app. */
object Phone {
    fun request(context: Context, what: String, payload: String = "") {
        val app = context.applicationContext
        Wearable.getCapabilityClient(app)
            .getCapability(PHONE_CAPABILITY, CapabilityClient.FILTER_REACHABLE)
            .addOnSuccessListener { info ->
                WatchStore.setReachable(info.nodes.isNotEmpty())
                val messages = Wearable.getMessageClient(app)
                info.nodes.forEach { messages.sendMessage(it.id, REQUEST_PREFIX + what, payload.toByteArray()) }
            }
            .addOnFailureListener { WatchStore.setReachable(false) }
    }
}

/** Wrist vibration: the repeating alarm and the short Snore Alert nudge. */
object Buzzer {
    private fun vibrator(context: Context): Vibrator =
        context.getSystemService(VibratorManager::class.java).defaultVibrator

    /** Repeats until [stop]; gentle at first for a melody alarm on the phone. */
    fun alarm(context: Context, strong: Boolean) {
        val timings = if (strong) longArrayOf(0, 600, 400, 600, 1200) else longArrayOf(0, 200, 2800)
        val amps = if (strong) intArrayOf(0, 255, 0, 255, 0) else intArrayOf(0, 120, 0)
        vibrator(context).vibrate(VibrationEffect.createWaveform(timings, amps, 0))
    }

    fun snoreNudge(context: Context) {
        vibrator(context).vibrate(
            VibrationEffect.createWaveform(longArrayOf(0, 150, 150, 150, 150, 150), intArrayOf(0, 200, 0, 200, 0, 200), -1)
        )
    }

    fun stop(context: Context) = vibrator(context).cancel()
}
