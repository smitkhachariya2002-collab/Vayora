package com.vayora.app

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri

/** Discover every exported UPI handler; package hints are only a fallback. */
object UpiApps {
    // Supplemental visibility only: discovery is never limited to this catalogue.
    // Android package IDs: https://razorpay.com/docs/payments/payment-methods/upi/supported-apps/
    val packageHints = listOf(
        "com.google.android.apps.nbu.paisa.user",
        "com.phonepe.app",
        "net.one97.paytm",
        "in.org.npci.upiapp",
        "in.amazon.mShop.android.shopping",
        "com.dreamplug.androidapp",
        "com.mobikwik_new",
        "com.freecharge.android",
        "com.naviapp",
        "money.super.payments",
        "com.popclub.android",
        "com.csam.icici.bank.imobile",
        "com.icicibank.pockets",
        "com.sbi.upi",
        "com.upi.axispay",
        "com.axis.mobile",
        "com.samsung.android.spay",
        "com.snapwork.hdfc",
        "com.hdfcbank.payzapp",
        "com.bankofbaroda.upi",
        "com.mycompany.kvb",
        "com.fss.jnkpsp",
        "com.fss.idfcpsp",
        "com.idfcfirstbank.optimus",
        "com.YesBank",
        "in.irisbyyes.app",
        "com.upi.federalbank.org.lotza",
        "com.fedmobile",
        "com.mgs.induspsp",
        "com.fss.indus",
        "com.indusind.indie",
        "com.rblbank.mobank",
        "in.bajajfinservmarkets.app",
        "com.fampay.in",
        "com.mgs.pnbupi",
        "com.Version1",
        "com.dbs.in.digitalbank",
        "money.jupiter",
        "indwin.c3.shareapp",
        "com.tatadigital.tcp",
        "com.nextbillion.groww",
        "com.shriram.one",
        "com.pinelabs.fave",
        "com.ultracash.payment.customer",
        "com.npst.timepay.society",
        "com.msf.kbank.mobile",
        "com.kotak811mobilebankingapp.instantsavingsupiscanandpayrecharge",
        "com.fss.ippbpsp",
        "com.iexceed.appzillon.ippbMB",
        "com.canarabank.mobility",
        "com.jio.myjio",
        "com.IndianBank.IndOASIS",
        "com.atyati.tvamapp",
        "com.infrasoft.uboi",
        "com.eroute.omnicard",
        "com.ausmallfinancebank.amb",
        "com.infrasofttech.CentralBank",
        "in.gokiwi.kiwitpap",
        "com.paypointz.wallet",
        "com.whizdm.moneyview.loans",
        "cards.scapia.android",
        "com.lcode.ucoupi",
        "com.euronet.iobupi",
        "com.lcode.csbupi"
    )

    fun discover(pm: PackageManager, uri: Uri): List<ApplicationInfo> {
        val discovered = listOf(uri, Uri.parse("upi://pay"), Uri.parse("upi://pay/"))
            .flatMap { pm.queryIntentActivities(Intent(Intent.ACTION_VIEW, it), PackageManager.MATCH_ALL) }
            .filter { it.activityInfo.exported && it.activityInfo.enabled && it.activityInfo.applicationInfo.enabled }
            .map { it.activityInfo.applicationInfo }
        val hints = packageHints.mapNotNull { name ->
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
