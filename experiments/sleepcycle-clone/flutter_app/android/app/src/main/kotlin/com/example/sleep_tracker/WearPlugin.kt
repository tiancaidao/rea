package com.example.sleep_tracker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Phone side of the Wear OS companion (android/wear), over the Wearable Data
 * Layer. The phone publishes its state as the data item /sleepclone/state and
 * sends /sleepclone/ring, /sleepclone/ring_stop and /sleepclone/snore_buzz;
 * the watch sends /sleepclone/request/<start|stop|snooze|stop_alarm|sync|
 * alarm_type|snore_ack>, which [PhoneWearService] hands to Dart.
 */
class WearPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        MethodChannel(binding.binaryMessenger, "sleepclone/wear").setMethodCallHandler(this)
        EventChannel(binding.binaryMessenger, "sleepclone/wear/events").setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        sink = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        // requests that arrived while the app wasn't running (e.g. Start)
        synchronized(pending) {
            pending.forEach { events?.success(it) }
            pending.clear()
        }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connected" -> Wearable.getCapabilityClient(context)
                .getCapability(WATCH_CAPABILITY, CapabilityClient.FILTER_REACHABLE)
                .addOnSuccessListener { result.success(it.nodes.isNotEmpty()) }
                .addOnFailureListener { result.success(false) }
            "publish" -> {
                val req = PutDataMapRequest.create(STATE_PATH).apply {
                    dataMap.putBoolean("tracking", call.argument<Boolean>("tracking") == true)
                    dataMap.putLong("since", call.argument<Number>("since")?.toLong() ?: 0)
                    dataMap.putLong("alarmStart", call.argument<Number>("alarmStart")?.toLong() ?: 0)
                    dataMap.putLong("alarmEnd", call.argument<Number>("alarmEnd")?.toLong() ?: 0)
                    dataMap.putString("alarmType", call.argument<String>("alarmType") ?: "Automatic")
                    dataMap.putLong("t", System.currentTimeMillis()) // always a change
                }.asPutDataRequest().setUrgent()
                Wearable.getDataClient(context).putDataItem(req)
                    .addOnSuccessListener { result.success(true) }
                    .addOnFailureListener { result.success(false) }
            }
            "ring" -> send(RING_PATH, if (call.argument<Boolean>("vibrate") == true) "vibrate" else "melody", result)
            "stopRinging" -> send(RING_STOP_PATH, "", result)
            "buzzSnore" -> send(SNORE_PATH, "", result)
            else -> result.notImplemented()
        }
    }

    private fun send(path: String, payload: String, result: MethodChannel.Result) {
        Wearable.getNodeClient(context).connectedNodes
            .addOnSuccessListener { nodes ->
                val messages = Wearable.getMessageClient(context)
                nodes.forEach { messages.sendMessage(it.id, path, payload.toByteArray()) }
                result.success(nodes.isNotEmpty())
            }
            .addOnFailureListener { result.success(false) }
    }

    companion object {
        const val WATCH_CAPABILITY = "sleepclone_watch"
        const val STATE_PATH = "/sleepclone/state"
        const val RING_PATH = "/sleepclone/ring"
        const val RING_STOP_PATH = "/sleepclone/ring_stop"
        const val SNORE_PATH = "/sleepclone/snore_buzz"
        const val REQUEST_PREFIX = "/sleepclone/request/"

        @Volatile
        private var sink: EventChannel.EventSink? = null
        private val pending = mutableListOf<String>()
        private val main = Handler(Looper.getMainLooper())

        /** A watch request: to Dart when the app runs, else queued (and Start opens the app). */
        fun deliver(context: Context, request: String) {
            val s = sink
            if (s != null) {
                main.post { s.success(request) }
                return
            }
            if (request != "start") return // nothing to stop or snooze without the app
            synchronized(pending) { pending.add(request) }
            notifyStart(context)
        }

        // Android doesn't let a background service open an activity, so ask
        // with a notification that opens the app straight into tracking.
        private fun notifyStart(context: Context) {
            val nm = context.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel("watch", "Watch", NotificationManager.IMPORTANCE_HIGH)
            )
            val open = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val n = Notification.Builder(context, "watch")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Start sleeping")
                .setContentText("Your watch asked to start tracking. Tap to start.")
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
            nm.notify(11, n)
        }
    }
}

/** Receives the watch's requests, whether or not the app is running. */
class PhoneWearService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        val path = event.path
        if (!path.startsWith(WearPlugin.REQUEST_PREFIX)) return
        val what = path.removePrefix(WearPlugin.REQUEST_PREFIX)
        val request = if (what == "alarm_type") "alarm_type:${String(event.data)}" else what
        WearPlugin.deliver(applicationContext, request)
    }
}
