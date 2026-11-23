package com.vayora.app

import android.app.Application
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions

/** Restore public Firebase options before background notification receivers run. */
class VayoraApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val prefs = getSharedPreferences("vayora_integrations", MODE_PRIVATE)
        if (!prefs.getBoolean("push_enabled", false)) return
        try {
            if (FirebaseApp.getApps(this).isEmpty()) {
                val options = FirebaseOptions.Builder()
                    .setApiKey(prefs.getString("apiKey", "")!!)
                    .setApplicationId(prefs.getString("appId", "")!!)
                    .setGcmSenderId(prefs.getString("messagingSenderId", "")!!)
                    .setProjectId(prefs.getString("projectId", "")!!)
                    .build()
                FirebaseApp.initializeApp(this, options)
            }
        } catch (_: Exception) { /* Missing/deferred configuration must not prevent launch. */ }
    }
}
