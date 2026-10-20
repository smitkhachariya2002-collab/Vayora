package com.vayora.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri

/** Package visibility is only a chooser hint. The actual launch decides availability. */
object UpiLaunch {
    fun launch(
        uri: Uri,
        discoverCount: () -> Int,
        open: (Intent) -> Unit,
        failed: (String, String?) -> Unit
    ) {
        val count = try { discoverCount() } catch (_: Exception) { 0 }
        val intent = Intent(Intent.ACTION_VIEW, uri)
        try {
            open(if (count > 1) Intent.createChooser(intent, "Pay with") else intent)
        } catch (e: ActivityNotFoundException) {
            failed("NO_UPI_APP", e.message)
        } catch (e: Exception) {
            failed("LAUNCH_FAILED", e.toString())
        }
    }
}
