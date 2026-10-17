package com.vayora.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import java.io.File
import java.io.ByteArrayOutputStream
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
    private var photoCallback: MethodChannel.Result? = null
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
        MethodChannel(engine.dartExecutor.binaryMessenger, "app/photo").setMethodCallHandler { call, result ->
            if (call.method != "pick") result.notImplemented()
            else if (photoCallback != null) result.error("busy", "Photo picker is already open", null)
            else {
                photoCallback = result
                try {
                    val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        type = "image/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }
                    startActivityForResult(picker, 702)
                } catch (_: Exception) {
                    photoCallback = null
                    result.error("photo_unavailable", "Could not open photos", null)
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
        if (requestCode == 702) {
            val reply = photoCallback
            photoCallback = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) { reply?.success(null); return }
            Thread {
                var source: File? = null
                try {
                    val file = File.createTempFile("channel-photo-", ".img", cacheDir)
                    source = file
                    contentResolver.openInputStream(uri)?.use { input ->
                        file.outputStream().use { output ->
                            val buffer = ByteArray(8192)
                            var total = 0
                            var count = input.read(buffer)
                            while (count != -1) {
                                total += count
                                if (total > 20 * 1024 * 1024) throw IllegalArgumentException("Photo too large")
                                output.write(buffer, 0, count)
                                count = input.read(buffer)
                            }
                        }
                    } ?: throw IllegalArgumentException("Photo unavailable")
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(file.absolutePath, bounds)
                    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw IllegalArgumentException("Not an image")
                    var sample = 1
                    while (bounds.outWidth / sample > 2048 || bounds.outHeight / sample > 2048) sample *= 2
                    val decoded = BitmapFactory.decodeFile(file.absolutePath,
                        BitmapFactory.Options().apply { inSampleSize = sample })
                        ?: throw IllegalArgumentException("Not an image")
                    val scale = minOf(1f, 1024f / maxOf(decoded.width, decoded.height))
                    val resized = Bitmap.createScaledBitmap(decoded, maxOf(1, (decoded.width * scale).toInt()),
                        maxOf(1, (decoded.height * scale).toInt()), true)
                    val orientation = try {
                        ExifInterface(file.absolutePath).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
                    } catch (_: Exception) { ExifInterface.ORIENTATION_NORMAL }
                    val matrix = Matrix()
                    when (orientation) {
                        ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
                        ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
                        ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
                        ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
                        ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
                        ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.setRotate(-90f); matrix.postScale(-1f, 1f) }
                        ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
                    }
                    val upright = Bitmap.createBitmap(resized, 0, 0, resized.width, resized.height, matrix, true)
                    val output = ByteArrayOutputStream()
                    upright.compress(Bitmap.CompressFormat.JPEG, 85, output)
                    if (upright !== resized && upright !== decoded) upright.recycle()
                    if (resized !== decoded) resized.recycle()
                    decoded.recycle()
                    val jpeg = output.toByteArray()
                    runOnUiThread { reply?.success(jpeg) }
                } catch (_: Exception) {
                    runOnUiThread { reply?.error("photo_failed", "Could not read this photo. Choose another image.", null) }
                } finally { source?.delete() }
            }.start()
            return
        }
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
