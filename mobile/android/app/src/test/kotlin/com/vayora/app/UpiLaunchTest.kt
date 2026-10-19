package com.vayora.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30, 34], manifest = Config.NONE)
class UpiLaunchTest {
    private val uri = Uri.parse("upi://pay?pa=test@upi&pn=Merchant&tr=VY123&am=1.00&cu=INR")

    @Test fun emptyDiscoveryStillAttemptsTheExactUpiIntent() {
        var opened: Intent? = null
        UpiLaunch.launch(uri, { 0 }, { opened = it }, { code, _ -> fail(code) })
        assertEquals(Intent.ACTION_VIEW, opened?.action)
        assertEquals(uri, opened?.data)
        assertNull(opened?.getPackage())
        assertEquals(0, opened!!.flags and Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    @Test fun brokenDiscoveryStillAttemptsLaunch() {
        var attempts = 0
        UpiLaunch.launch(uri, { throw SecurityException("OEM visibility") }, { attempts++ }, { code, _ -> fail(code) })
        assertEquals(1, attempts)
    }

    @Test fun oneHandlerUsesDirectLaunchAndManyUseChooser() {
        for (count in listOf(1, 3)) {
            var opened: Intent? = null
            UpiLaunch.launch(uri, { count }, { opened = it }, { code, _ -> fail(code) })
            if (count == 1) {
                assertEquals(Intent.ACTION_VIEW, opened?.action)
                assertEquals(uri, opened?.data)
            } else {
                assertEquals(Intent.ACTION_CHOOSER, opened?.action)
                @Suppress("DEPRECATION")
                val target = opened!!.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                assertEquals(uri, target?.data)
                assertEquals(Intent.ACTION_VIEW, target?.action)
            }
        }
    }

    @Test fun onlyActualActivityNotFoundProducesNoUpiApp() {
        var error: String? = null
        var attempts = 0
        UpiLaunch.launch(uri, { 0 }, { attempts++; throw ActivityNotFoundException("absent") }, { code, _ -> error = code })
        assertEquals(1, attempts)
        assertEquals("NO_UPI_APP", error)
        UpiLaunch.launch(uri, { 2 }, { throw SecurityException("blocked launch") }, { code, _ -> error = code })
        assertEquals("LAUNCH_FAILED", error)
    }
}
