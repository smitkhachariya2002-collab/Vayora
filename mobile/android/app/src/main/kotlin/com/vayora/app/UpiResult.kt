package com.vayora.app

/** Turns whatever a UPI app returned into one raw string for the server. Pure Kotlin: unit-tested, never throws. */
object UpiResult {
    const val NO_RESPONSE = "NO_RESPONSE"
    private val preferred = listOf("txnId", "responseCode", "Status", "status", "txnRef", "ApprovalRefNo", "TrtxnRef")

    fun toRaw(extras: Map<String, Any?>?, hasData: Boolean, canceled: Boolean): String {
        return try {
            val e = extras ?: emptyMap()
            if (!hasData || (canceled && e.isEmpty())) return NO_RESPONSE
            // 1) extras "response" (the whole query string, used by GPay/PhonePe/BHIM).
            val response = e["response"]?.toString()
            if (!response.isNullOrBlank()) return response
            // 2) Status/status and 3) everything else: build one query string from ALL extras.
            val keys = preferred.filter { e.containsKey(it) } + e.keys.filter { it !in preferred && it != "response" }
            val raw = keys.joinToString("&") { "$it=${e[it]}" }
            if (raw.isBlank()) NO_RESPONSE else raw
        } catch (t: Throwable) {
            NO_RESPONSE
        }
    }
}
