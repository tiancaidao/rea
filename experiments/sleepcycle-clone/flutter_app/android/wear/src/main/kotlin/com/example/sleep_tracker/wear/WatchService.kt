package com.example.sleep_tracker.wear

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

/** Phone → watch: state changes, ring / stop ringing, Snore Alert. */
class WatchService : WearableListenerService() {

    override fun onDataChanged(events: DataEventBuffer) {
        events.forEach {
            if (it.dataItem.uri.path == STATE_PATH) {
                WatchStore.update(PhoneState.from(DataMapItem.fromDataItem(it.dataItem).dataMap))
            }
        }
    }

    override fun onMessageReceived(event: MessageEvent) {
        when (event.path) {
            RING_PATH -> Alarm.start(this, vibrate = String(event.data) == "vibrate")
            RING_STOP_PATH -> Alarm.stop(this)
            SNORE_PATH -> {
                Buzzer.snoreNudge(this)
                Phone.request(this, "snore_ack")
            }
        }
    }
}

/** The alarm on the wrist: vibration plus a full-screen Snooze / Stop. */
object Alarm {
    private const val CHANNEL = "alarm"
    private const val ID = 1

    fun start(context: Context, vibrate: Boolean) {
        WatchStore.setRinging(true)
        // silent wake-up: strong vibration; with the melody on the phone, a light tap
        Buzzer.alarm(context, strong = vibrate)
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Alarm", NotificationManager.IMPORTANCE_HIGH))
        val full = PendingIntent.getActivity(
            context, 0, Intent(context, AlarmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        fun action(what: String, label: String, code: Int) = Notification.Action.Builder(
            null, label,
            PendingIntent.getBroadcast(
                context, code, Intent(context, AlarmActionReceiver::class.java).setAction(what),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            ),
        ).build()
        val n = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_watch_app)
            .setContentTitle("Good morning")
            .setContentText("Time to wake up")
            .setCategory(Notification.CATEGORY_ALARM)
            .setFullScreenIntent(full, true)
            .setOngoing(true)
            .addAction(action("snooze", "Snooze", 1))
            .addAction(action("stop_alarm", "Stop", 2))
            .build()
        nm.notify(ID, n)
    }

    fun stop(context: Context) {
        WatchStore.setRinging(false)
        Buzzer.stop(context)
        context.getSystemService(NotificationManager::class.java).cancel(ID)
    }

    /** Snooze or stop from the watch: quiet here, and tell the phone. */
    fun answer(context: Context, what: String) {
        stop(context)
        Phone.request(context, what)
    }
}

class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        intent.action?.let { Alarm.answer(context, it) }
    }
}
