package com.vayora.app

import android.provider.OpenableColumns
import android.content.ClipData
import androidx.core.content.FileProvider
import android.media.MediaMetadataRetriever
import java.net.URL
import java.util.UUID
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import java.io.File
import java.io.ByteArrayOutputStream
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.net.Uri
import android.os.Environment
import io.flutter.embedding.android.FlutterFragmentActivity
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var callback: MethodChannel.Result? = null
    private var photoCallback: MethodChannel.Result? = null
    private var mediaCallback: MethodChannel.Result? = null
    private var requestedKind = "media"
    private var linkChannel: MethodChannel? = null
    private var pendingLink: String? = null
    private val store by lazy { getSharedPreferences("vayora_upi", Context.MODE_PRIVATE) }

    // Register unconditionally and in stable order, before the activity starts.
    private val upiLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { answer ->
        finishUpi(UpiApps.rawResult(answer.data, answer.resultCode))
    }

    private fun finishUpi(raw: String) {
        val order = store.getString("active_order", null)
        if (order != null) store.edit().putString("response:$order", raw).remove("active_order").commit()
        callback?.success(raw)
        callback = null
    }

    private fun pickUpi(uri: Uri) {
        UpiLaunch.launch(
            uri,
            discoverCount = {
                val apps = UpiApps.discover(packageManager, uri, packageName)
                android.util.Log.d("VayoraUpi", "Discovered UPI apps: " + apps.joinToString { it.packageName })
                apps.size
            },
            open = { upiLauncher.launch(it) },
            failed = { code, message ->
                // Launch failures are not payment responses. Keep the order for the UTR fallback.
                store.edit().remove("active_order").commit()
                val reply = callback
                callback = null
                reply?.error(code, message, null)
            }
        )
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        if (BuildConfig.FLAVOR == "play") PlayBridge(this,MethodChannel(engine.dartExecutor.binaryMessenger,"app/play"))
        linkChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "app/links").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "initial") { val raw = pendingLink ?: intent?.dataString; pendingLink = null; result.success(raw) }
                else result.notImplemented()
            }
        }
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
                            store.edit().putString("active_order", order).putString("owner:$order", call.argument<String>("user_id")).commit()
                            callback = result
                            pickUpi(uri)
                        }
                    }
                }
                "pending" -> {
                    val account = call.argument<String>("user_id")
                    val pending = store.all.filterKeys { it.startsWith("response:") && (store.getString("owner:" + it.removePrefix("response:"), null) == account) }
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
        MethodChannel(engine.dartExecutor.binaryMessenger, "app/media").setMethodCallHandler { call, result ->
            if (call.method != "pick") result.notImplemented()
            else if (mediaCallback != null) result.error("busy", "Picker is already open", null)
            else {
                mediaCallback = result
                requestedKind = call.argument<String>("kind") ?: "media"
                try {
                    val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = when (requestedKind) { "image" -> "image/*"; "video" -> "video/*"; else -> "*/*" }
                        if (requestedKind == "media") putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("video/*", "image/*"))
                    }
                    startActivityForResult(picker, 703)
                } catch (_: Exception) { mediaCallback = null; result.error("picker_unavailable", "Could not open files", null) }
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "app/files").setMethodCallHandler { call, result ->
            if (call.method != "open") result.notImplemented()
            else {
                val raw = call.argument<String>("url") ?: ""
                val uri = Uri.parse(raw)
                if (uri.scheme != "https" || uri.host != "fzloulsjhkdxwagonsgt.supabase.co") {
                    result.error("invalid", "Invalid file URL", null)
                } else {
                    val name = (call.argument<String>("name") ?: "file").replace(Regex("[^A-Za-z0-9._-]"), "_")
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    Thread {
                        try {
                            val folder = File(cacheDir, "cloud-open").apply { mkdirs() }
                            val target = File(folder, UUID.randomUUID().toString() + "-" + name)
                            URL(raw).openConnection().apply { connectTimeout = 15000; readTimeout = 60000 }.getInputStream().use { input ->
                                target.outputStream().use { output ->
                                    val buffer = ByteArray(8192); var total = 0; var count = input.read(buffer)
                                    while (count != -1) { total += count; if (total > 52428800) throw IllegalArgumentException("File too large")
                                        output.write(buffer,0,count); count = input.read(buffer) }
                                }
                            }
                            runOnUiThread {
                                try {
                                    val content = FileProvider.getUriForFile(this, packageName + ".files", target)
                                    val intent = Intent(Intent.ACTION_VIEW).setDataAndType(content,mime)
                                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    intent.clipData = ClipData.newRawUri("Vayora file",content)
                                    startActivity(Intent.createChooser(intent,"Open with"))
                                    result.success(null)
                                } catch (_: Exception) { result.error("open_failed","No app could open this file",null) }
                            }
                        } catch (_: Exception) { runOnUiThread { result.error("open_failed","Could not open this file",null) } }
                    }.start()
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val raw = intent.dataString ?: return
        if (linkChannel == null) pendingLink = raw else linkChannel?.invokeMethod("open", raw)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 703) {
            val reply = mediaCallback; mediaCallback = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) { reply?.success(null); return }
            val kind = requestedKind
            Thread {
                var source: File? = null
                try {
                    val mime = contentResolver.getType(uri) ?: "application/octet-stream"
                    if (kind == "media" && !mime.startsWith("video/") && !mime.startsWith("image/")) throw IllegalArgumentException("Choose video or photo")
                    if (kind == "video" && !mime.startsWith("video/")) throw IllegalArgumentException("Choose video")
                    if (kind == "image" && !mime.startsWith("image/")) throw IllegalArgumentException("Choose photo")
                    val file = File.createTempFile("vayora-media-", ".bin", cacheDir); source = file
                    contentResolver.openInputStream(uri)?.use { input ->
                        file.outputStream().use { output ->
                            val buffer = ByteArray(8192); var total = 0; var count = input.read(buffer)
                            while (count != -1) { total += count; if (total > 52428800) throw IllegalArgumentException("50 MB maximum per file")
                                output.write(buffer,0,count); count = input.read(buffer) }
                        }
                    } ?: throw IllegalArgumentException("File unavailable")
                    var name = "file"
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME),null,null,null)?.use { cursor ->
                        if (cursor.moveToFirst()) name = cursor.getString(0) ?: "file"
                    }
                    var thumb: String? = null; var duration: Int? = null; var bitmap: Bitmap? = null
                    try {
                        if (mime.startsWith("video/")) {
                            val retriever = MediaMetadataRetriever()
                            try {
                                retriever.setDataSource(file.absolutePath)
                                duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.div(1000)?.toInt()
                                bitmap = if (android.os.Build.VERSION.SDK_INT >= 27)
                                    retriever.getScaledFrameAtTime(0,MediaMetadataRetriever.OPTION_CLOSEST_SYNC,512,288)
                                    else retriever.getFrameAtTime(0,MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                            } finally { retriever.release() }
                        } else if (mime.startsWith("image/")) {
                            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                            BitmapFactory.decodeFile(file.absolutePath,bounds); var sample = 1
                            while (bounds.outWidth / sample > 1024 || bounds.outHeight / sample > 1024) sample *= 2
                            bitmap = BitmapFactory.decodeFile(file.absolutePath,BitmapFactory.Options().apply { inSampleSize = sample })
                        }
                        bitmap?.let { image ->
                            val scale = minOf(1f,512f/maxOf(image.width,image.height))
                            val small = Bitmap.createScaledBitmap(image,maxOf(1,(image.width*scale).toInt()),maxOf(1,(image.height*scale).toInt()),true)
                            val poster = File.createTempFile("vayora-thumb-",".jpg",cacheDir)
                            poster.outputStream().use { small.compress(Bitmap.CompressFormat.JPEG,85,it) }
                            thumb = poster.absolutePath
                            if (small !== image) small.recycle()
                            image.recycle()
                        }
                    } catch (_: Exception) { /* The user may choose an explicit thumbnail. */ }
                    val result = mapOf("path" to file.absolutePath,"name" to name,"mime" to mime,"size" to file.length(),
                        "thumbnail_path" to thumb,"duration_s" to duration)
                    runOnUiThread { reply?.success(result) }
                } catch (_: Exception) {
                    source?.delete()
                    runOnUiThread { reply?.error("media_failed","Choose a file up to 50 MB.",null) }
                }
            }.start()
            return
        }
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
    }
}
