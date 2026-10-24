package com.example.sleep_tracker.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import java.text.DateFormat
import java.util.Date

private val Night = Color(0xFF0B1033)
private val Accent = Color(0xFF6E8BFF)

/** Start / stop the night and pick the alarm type; the phone does the rest. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme { Home() } }
    }

    override fun onResume() {
        super.onResume()
        WatchStore.refresh(this)
    }
}

private fun clock(t: Long) = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(t))

private val types = listOf("Automatic", "Melody", "Vibrate")

@Composable
private fun Home() {
    val context = LocalContext.current
    val s by WatchStore.state.collectAsStateWithLifecycle()
    val reachable by WatchStore.reachable.collectAsStateWithLifecycle()
    val alarm = when {
        s.alarmEnd == 0L -> "No alarm"
        s.alarmStart in 1 until s.alarmEnd -> "Wake up ${clock(s.alarmStart)}–${clock(s.alarmEnd)}"
        else -> "Alarm ${clock(s.alarmEnd)}"
    }
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 18.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            if (s.tracking) "Sleeping since ${clock(s.since)}" else "Lullwake",
            fontSize = 14.sp, textAlign = TextAlign.Center,
        )
        Text(alarm, fontSize = 12.sp, color = Color.LightGray, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Button(
            onClick = { Phone.request(context, if (s.tracking) "stop" else "start") },
            modifier = Modifier.size(ButtonDefaults.LargeButtonSize),
            colors = ButtonDefaults.buttonColors(backgroundColor = if (s.tracking) Night else Accent),
        ) { Text(if (s.tracking) "Stop" else "Start") }
        Spacer(Modifier.height(8.dp))
        Chip(
            onClick = {
                val next = types[(types.indexOf(s.alarmType) + 1) % types.size]
                WatchStore.update(s.copy(alarmType = next))
                Phone.request(context, "alarm_type", next)
            },
            label = { Text("Alarm: ${s.alarmType}", fontSize = 12.sp) },
            colors = ChipDefaults.secondaryChipColors(),
        )
        if (!reachable) {
            Text(
                "Open the app on your phone", fontSize = 11.sp, color = Color(0xFFFFB74D),
                textAlign = TextAlign.Center,
            )
        }
    }
}
