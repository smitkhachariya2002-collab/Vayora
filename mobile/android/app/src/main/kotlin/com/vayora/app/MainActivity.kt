package com.vayora.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener

/**
 * UPI intent launcher. Never decides "no UPI app" from queryIntentActivities (unreliable on
 * Android 11+); only an ActivityNotFoundException means there is no handler.
 */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val requestCode = 7011

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/install-referrer").setMethodCallHandler { call, result ->
            if (call.method == "read") readInstallReferrer(result) else result.notImplemented()
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

    private fun readInstallReferrer(result: MethodChannel.Result) {
        val installer = try {
            if (android.os.Build.VERSION.SDK_INT >= 30) packageManager.getInstallSourceInfo(packageName).installingPackageName
            else @Suppress("DEPRECATION") packageManager.getInstallerPackageName(packageName)
        } catch (_: Exception) { null }
        // The Play variant must not fall back to the ads APK build flag.
        val isPlay = installer == "com.android.vending" || packageName == "com.vayora.play"
        if (!isPlay) { result.success(mapOf("status" to "not_play", "is_play" to false, "installer" to installer)); return }
        val client = InstallReferrerClient.newBuilder(this).build()
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        var done = false
        fun finish(data: Map<String, Any?>) {
            if (done) return
            done = true
            try { client.endConnection() } catch (_: Exception) { }
            result.success(data + mapOf("is_play" to true, "installer" to installer))
        }
        handler.postDelayed({ finish(mapOf("status" to "timeout")) }, 6000)
        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(code: Int) {
                    handler.post {
                        if (!done) {
                            try {
                                if (code == InstallReferrerClient.InstallReferrerResponse.OK) {
                                    val referrer = client.installReferrer
                                    finish(mapOf("status" to "ok", "referrer" to referrer.installReferrer,
                                        "click_timestamp" to referrer.referrerClickTimestampSeconds,
                                        "install_timestamp" to referrer.installBeginTimestampSeconds))
                                } else finish(mapOf("status" to "unavailable", "response_code" to code))
                            } catch (_: Exception) { finish(mapOf("status" to "unavailable")) }
                        }
                    }
                }
                override fun onInstallReferrerServiceDisconnected() {
                    handler.post { finish(mapOf("status" to "disconnected")) }
                }
            })
        } catch (_: Exception) { finish(mapOf("status" to "unavailable")) }
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
