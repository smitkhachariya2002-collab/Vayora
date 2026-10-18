package com.vayora.app

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import java.util.Locale

/** Discover installed UPI handlers at runtime, without a package catalogue. */
object UpiApps {
    fun discover(pm: PackageManager, uri: Uri, ownPackage: String): List<ApplicationInfo> =
        listOf(uri, Uri.parse("upi://pay"))
            .flatMap { link ->
                val intent = Intent(Intent.ACTION_VIEW, link)
                if (Build.VERSION.SDK_INT >= 33) {
                    pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_ALL.toLong()))
                } else {
                    @Suppress("DEPRECATION")
                    pm.queryIntentActivities(intent, PackageManager.MATCH_ALL)
                }
            }
            .filter { it.activityInfo.exported && it.activityInfo.enabled && it.activityInfo.applicationInfo.enabled }
            .map { it.activityInfo.applicationInfo }
            .filter { it.packageName != ownPackage }
            .distinctBy { it.packageName }
            .sortedBy { it.loadLabel(pm).toString().lowercase(Locale.ROOT) }

    /** Keep an app's raw response intact; support wallets returning separate extras too. */
    fun rawResult(data: Intent?, resultCode: Int): String {
        val extras = data?.extras
        val entries = extras?.keySet()?.map { it to extras.get(it)?.toString().orEmpty() }.orEmpty()
        entries.firstOrNull { it.first.equals("response", true) && it.second.isNotBlank() }
            ?.let { return it.second }
        entries.firstOrNull { it.second.contains("Status=", true) }?.let { return it.second }
        val fields = entries.filter { it.first.lowercase() in setOf("status", "txnref", "txnid", "approvalrefno", "responsecode") }
        if (fields.any { it.first.equals("status", true) }) {
            return fields.joinToString("&") { Uri.encode(it.first) + "=" + Uri.encode(it.second) }
        }
        return "Status=NO_RESPONSE&resultCode=$resultCode"
    }

    fun paymentIntent(uri: Uri, packageName: String): Intent =
        Intent(Intent.ACTION_VIEW, uri).setPackage(packageName)
}
