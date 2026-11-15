package com.vayora.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class UpiResultTest {
    @Test fun responseExtraWins() {
        val raw = UpiResult.toRaw(mapOf("response" to "txnId=AX123456&responseCode=00&Status=SUCCESS&txnRef=OB1", "Status" to "FAILURE"), true, false)
        assertEquals("txnId=AX123456&responseCode=00&Status=SUCCESS&txnRef=OB1", raw)
    }
    @Test fun buildsFromAllExtras() {
        val raw = UpiResult.toRaw(mapOf("Status" to "SUCCESS", "ApprovalRefNo" to "998877", "txnRef" to "OB1", "extra" to "x"), true, false)
        assertTrue(raw.contains("Status=SUCCESS")); assertTrue(raw.contains("ApprovalRefNo=998877")); assertTrue(raw.contains("txnRef=OB1")); assertTrue(raw.contains("extra=x"))
    }
    @Test fun lowercaseStatusKept() {
        assertEquals("status=FAILURE", UpiResult.toRaw(mapOf("status" to "FAILURE"), true, false))
    }
    @Test fun nullDataIsNoResponse() {
        assertEquals("NO_RESPONSE", UpiResult.toRaw(null, false, false))
    }
    @Test fun canceledWithoutExtrasIsNoResponse() {
        assertEquals("NO_RESPONSE", UpiResult.toRaw(emptyMap(), true, true))
    }
    @Test fun emptyExtrasIsNoResponse() {
        assertEquals("NO_RESPONSE", UpiResult.toRaw(emptyMap(), true, false))
    }
    @Test fun weirdValuesNeverThrow() {
        val raw = UpiResult.toRaw(mapOf("Status" to null, "txnId" to listOf(1, 2)), true, false)
        assertTrue(raw.isNotEmpty())
    }
}
