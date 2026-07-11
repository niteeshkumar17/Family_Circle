package com.familynest.family_nest

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Fix for apps launched directly after install from WhatsApp/file managers
        // This detects if app was launched in a non-standard way and restarts it properly
        if (!isTaskRoot && intent != null) {
            val action = intent.action
            if (intent.hasCategory(Intent.CATEGORY_LAUNCHER) && Intent.ACTION_MAIN == action) {
                finish()
                return
            }
        }

        // Create the notification channel BEFORE Flutter boots up
        // This prevents CannotPostForegroundServiceNotificationException on Android 14+
        createLocationNotificationChannel()

        super.onCreate(savedInstanceState)
    }

    private fun createLocationNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "family_nest_location",
                "Location Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background location tracking"
                setSound(null, null)
                enableVibration(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}
