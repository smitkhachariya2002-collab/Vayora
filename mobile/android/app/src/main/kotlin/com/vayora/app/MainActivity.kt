package com.vayora.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * UPI intent launcher. Never decides "no UPI app" from queryIntentActivities (unreliable on
 * Android 11+); only an ActivityNotFoundException means there is no handler.
 */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val requestCode = 7011

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The Play Store supplies the *actual* referrer and timestamps. Direct APKs
        // do not use this API and instead use the explicit build-time referrer.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/install-referrer").setMethodCallHandler { call, result ->
            if (call.method != "read") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val client = InstallReferrerClient.newBuilder(applicationContext).build()
            var completed = false
            fun finish(data: Map<String, Any?>) {
                if (completed) return
                completed = true
                result.success(data)
                try { client.endConnection() } catch (_: Exception) {}
            }
            try {
                client.startConnection(object : InstallReferrerStateListener {
                    override fun onInstallReferrerSetupFinished(responseCode: Int) {
                        if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                            try {
                                val details = client.installReferrer
                                finish(mapOf(
                                    "status" to "ok",
                                    "raw_referrer" to details.installReferrer,
                                    "click_ts" to details.referrerClickTimestampSeconds,
                                    "install_ts" to details.installBeginTimestampSeconds
                                ))
                            } catch (_: Exception) {
                                finish(mapOf("status" to "unavailable"))
                            }
                        } else {
                            finish(mapOf("status" to if (responseCode == InstallReferrerClient.InstallReferrerResponse.FEATURE_NOT_SUPPORTED) "not_available" else "unavailable"))
                        }
                    }
                    override fun onInstallReferrerServiceDisconnected() {
                        finish(mapOf("status" to "unavailable"))
                    }
                })
            } catch (_: Exception) {
                finish(mapOf("status" to "unavailable"))
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/measurement").setMethodCallHandler { call, result ->
            if (call.method == "context") result.success(mapOf("os" to android.os.Build.VERSION.RELEASE, "model" to android.os.Build.MODEL, "cores" to Runtime.getRuntime().availableProcessors())) else result.notImplemented()
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/upi").setMethodCallHandler { call, result ->
            if (call.method != "pay") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val uri = call.argument<String>("uri")
            if (uri == null || !uri.startsWith("upi://pay")) {
                result.error("BAD_URI", "Not a UPI pay URI", null)
                return@setMethodCallHandler
            }
            if (pending != null) {
                result.error("BUSY", "A payment is already in progress", null)
                return@setMethodCallHandler
            }
            try {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
                val chooser = Intent.createChooser(intent, "Pay with")
                pending = result
                startActivityForResult(chooser, requestCode)
            } catch (e: ActivityNotFoundException) {
                pending = null
                result.error("NO_APP", "No UPI app can handle this payment", null)
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(code: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(code, resultCode, data)
        if (code != requestCode) return
        val r = pending ?: return
        pending = null
        val extras = try {
            data?.extras?.let { b -> b.keySet().associateWith { k -> b.get(k) } }
        } catch (t: Throwable) {
            null
        }
        r.success(UpiResult.toRaw(extras, hasData = data != null, canceled = resultCode == Activity.RESULT_CANCELED))
    }
}
