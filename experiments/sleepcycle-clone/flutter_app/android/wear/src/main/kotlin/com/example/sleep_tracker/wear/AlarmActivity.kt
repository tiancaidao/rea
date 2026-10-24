package com.example.sleep_tracker.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text

/** Full-screen alarm on the wrist: Snooze or Stop, mirrored to the phone. */
class AlarmActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                val ringing by WatchStore.ringing.collectAsStateWithLifecycle()
                LaunchedEffect(ringing) { if (!ringing) finish() }
                Column(
                    Modifier.fillMaxSize(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text("Good morning", fontSize = 18.sp)
                    Spacer(Modifier.height(12.dp))
                    Row {
                        Button(
                            onClick = { Alarm.answer(this@AlarmActivity, "snooze"); finish() },
                            colors = ButtonDefaults.secondaryButtonColors(),
                        ) { Text("Zz") }
                        Spacer(Modifier.width(16.dp))
                        Button(
                            onClick = { Alarm.answer(this@AlarmActivity, "stop_alarm"); finish() },
                            colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFF6E8BFF)),
                        ) { Text("Stop") }
                    }
                }
            }
        }
    }
}
