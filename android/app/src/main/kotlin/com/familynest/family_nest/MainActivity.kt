package com.familynest.family_nest

import android.content.Intent
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
        super.onCreate(savedInstanceState)
    }
}
