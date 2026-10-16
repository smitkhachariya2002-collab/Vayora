package com.vayora.app

import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.net.Uri
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var callback: MethodChannel.Result? = null
    private val store by lazy { getSharedPreferences("vayora_upi", Context.MODE_PRIVATE) }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "app/upi").setMethodCallHandler { call, result ->
            when (call.method) {
                "pay" -> {
                    if (callback != null) {
                        result.error("busy", "A payment is already open", null)
                    } else {
                        val raw = call.argument<String>("uri") ?: ""
                        val order = call.argument<String>("order_id") ?: ""
                        val uri = Uri.parse(raw)
                        if (uri.scheme != "upi" || uri.host != "pay" || order.isBlank()) {
                            result.error("invalid", "Invalid payment request", null)
                        } else {
                            val intent = Intent(Intent.ACTION_VIEW, uri)
                            if (intent.resolveActivity(packageManager) == null) {
                                result.error("no_upi", "No UPI app found", null)
                            } else {
                                // Persist before switching apps; process recreation retains the order ID.
                                store.edit().putString("active_order", order).commit()
                                callback = result
                                try { startActivityForResult(Intent.createChooser(intent, "Pay with UPI"), 701) }
                                catch (_: ActivityNotFoundException) {
                                    callback = null
                                    result.error("no_upi", "No UPI app found", null)
                                }
                            }
                        }
                    }
                }
                "pending" -> {
                    val pending = store.all.filterKeys { it.startsWith("response:") }
                        .mapKeys { it.key.removePrefix("response:") }.mapValues { it.value.toString() }
                    result.success(pending)
                }
                "ack" -> {
                    store.edit().remove("response:" + call.argument<String>("order_id")).commit()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "app/screen").setMethodCallHandler { call, result ->
            if (call.method != "rotation") result.notImplemented()
            else {
                requestedOrientation = when (call.argument<String>("mode")) {
                    "landscape" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    "portrait" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
                    else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                }
                result.success(null)
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "app/download").setMethodCallHandler { call, result ->
            if (call.method != "download") result.notImplemented()
            else {
                val uri = Uri.parse(call.argument<String>("url") ?: "")
                if (uri.scheme != "https" || uri.host != "fzloulsjhkdxwagonsgt.supabase.co") {
                    result.error("invalid", "Invalid download URL", null)
                } else {
                    try {
                        val name = (call.argument<String>("name") ?: "vayora-video.mp4").replace(Regex("[^A-Za-z0-9._-]"), "_")
                        val request = DownloadManager.Request(uri).setTitle(name)
                            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                        if (android.os.Build.VERSION.SDK_INT >= 29) {
                            request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name)
                        } else {
                            request.setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, name)
                        }
                        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                        result.success(manager.enqueue(request))
                    } catch (_: Exception) { result.error("download_failed", "Could not start download", null) }
                }
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "app/share").setMethodCallHandler { call, result ->
            if (call.method != "share") result.notImplemented()
            else {
                val intent = Intent(Intent.ACTION_SEND).setType("text/plain")
                    .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text"))
                startActivity(Intent.createChooser(intent, "Share Vayora"))
                result.success(null)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 701) return
        val order = store.getString("active_order", null)
        val raw = data?.getStringExtra("response") ?: data?.dataString ?: "Status=UNKNOWN"
        if (order != null) {
            // Disk commit happens before Dart callback, so app/process loss cannot erase the answer.
            store.edit().putString("response:$order", raw).remove("active_order").commit()
        }
        callback?.success(raw)
        callback = null
    }
}
