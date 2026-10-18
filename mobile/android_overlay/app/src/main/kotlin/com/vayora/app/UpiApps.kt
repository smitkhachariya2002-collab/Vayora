package com.vayora.app

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri

/** Discover every exported UPI handler; package hints are only a fallback. */
object UpiApps {
    fun discover(pm: PackageManager, uri: Uri): List<ApplicationInfo> {
        val discovered = listOf(uri, Uri.parse("upi://pay"), Uri.parse("upi://pay/"))
            .flatMap { pm.queryIntentActivities(Intent(Intent.ACTION_VIEW, it), PackageManager.MATCH_ALL) }
            .filter { it.activityInfo.exported && it.activityInfo.enabled && it.activityInfo.applicationInfo.enabled }
            .map { it.activityInfo.applicationInfo }
        val hints = listOf("com.google.android.apps.nbu.paisa.user", "com.phonepe.app",
            "net.one97.paytm", "in.org.npci.upiapp").mapNotNull { name ->
                try { pm.getApplicationInfo(name, 0).takeIf { it.enabled } }
                catch (_: PackageManager.NameNotFoundException) { null }
            }
        return (discovered + hints).distinctBy { it.packageName }
            .sortedBy { it.loadLabel(pm).toString().lowercase() }
    }

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
