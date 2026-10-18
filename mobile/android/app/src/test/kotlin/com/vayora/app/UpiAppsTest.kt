package com.vayora.app

import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.ResolveInfo
import android.net.Uri
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE)
class UpiAppsTest {
    private val uri = Uri.parse("upi://pay?pa=test@upi&pn=Merchant&tr=VY123&am=1.00&cu=INR")
    private val pm get() = RuntimeEnvironment.getApplication().packageManager

    private fun handler(pkg: String, enabled: Boolean = true, exported: Boolean = true): ResolveInfo {
        val app = ApplicationInfo().apply { packageName = pkg; this.enabled = enabled; nonLocalizedLabel = pkg }
        return ResolveInfo().apply {
            activityInfo = ActivityInfo().apply {
                packageName = pkg; name = "$pkg.Pay"; applicationInfo = app
                this.enabled = enabled; this.exported = exported
            }
        }
    }

    @Test fun discoversAllHandlersIncludingPackagesOutsideTheHints() {
        val packages = (1..8).map { "bank.example.wallet$it" }
        packages.forEach { pkg ->
            shadowOf(pm).addResolveInfoForIntent(Intent(Intent.ACTION_VIEW, uri), handler(pkg))
        }
        assertEquals(packages.toSet(), UpiApps.discover(pm, uri).map { it.packageName }.toSet())
    }

    @Test fun mergesGenericAndFullUriHandlersAndDeduplicates() {
        shadowOf(pm).addResolveInfoForIntent(Intent(Intent.ACTION_VIEW, uri), handler("bank.example.one"))
        shadowOf(pm).addResolveInfoForIntent(Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay")), handler("bank.example.one"))
        shadowOf(pm).addResolveInfoForIntent(Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay/")), handler("bank.example.two"))
        assertEquals(setOf("bank.example.one", "bank.example.two"), UpiApps.discover(pm, uri).map { it.packageName }.toSet())
    }

    @Test fun excludesDisabledAndUnexportedHandlers() {
        shadowOf(pm).addResolveInfoForIntent(Intent(Intent.ACTION_VIEW, uri), handler("bank.disabled", enabled=false))
        shadowOf(pm).addResolveInfoForIntent(Intent(Intent.ACTION_VIEW, uri), handler("bank.private", exported=false))
        assertTrue(UpiApps.discover(pm, uri).isEmpty())
    }

    @Test fun rawResponseIsReturnedUnchanged() {
        val raw = "txnId=SBI123456789&Status=SUCCESS&txnRef=VY123"
        assertEquals(raw, UpiApps.rawResult(Intent().putExtra("response", raw), -1))
    }

    @Test fun separateWalletExtrasKeepStatusReferenceAndTransactionId() {
        val data = Intent().putExtra("STATUS", "SUCCESS").putExtra("txnRef", "VY123").putExtra("txnId", "BANK1234")
        val parsed = Uri.parse("upi://result?" + UpiApps.rawResult(data, -1))
        assertEquals("SUCCESS", parsed.getQueryParameter("STATUS"))
        assertEquals("VY123", parsed.getQueryParameter("txnRef"))
        assertEquals("BANK1234", parsed.getQueryParameter("txnId"))
    }

    @Test fun missingResultIsPendingEvidenceRatherThanSuccess() {
        assertEquals("Status=NO_RESPONSE&resultCode=0", UpiApps.rawResult(null, 0))
    }

    @Test fun chosenAppGetsExactPaymentUriWithoutNewTaskFlag() {
        val intent = UpiApps.paymentIntent(uri, "bank.any.upi")
        assertEquals("bank.any.upi", intent.getPackage())
        assertEquals(uri, intent.data)
        assertEquals(0, intent.flags and Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}
