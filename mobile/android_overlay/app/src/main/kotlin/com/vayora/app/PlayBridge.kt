package com.vayora.app

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.*
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class PlayBridge(private val activity: Activity, channel: MethodChannel) {
    private val store=activity.getSharedPreferences("vayora_play",Context.MODE_PRIVATE)
    private var checkout: MethodChannel.Result?=null
    private var billing: BillingClient?=null
    init {
        channel.setMethodCallHandler { call,result ->
            when(call.method) {
                "integrity" -> {
                    val nonce=call.argument<String>("nonce")?:""
                    val project=call.argument<String>("project_number")?.toLongOrNull()
                    if(project==null||nonce.isBlank())result.error("setup","Play verification is not configured",null)
                    else IntegrityManagerFactory.create(activity).requestIntegrityToken(
                        IntegrityTokenRequest.builder().setNonce(nonce).setCloudProjectNumber(project).build())
                        .addOnSuccessListener { result.success(it.token()) }
                        .addOnFailureListener { result.error("integrity","App verification failed",null) }
                }
                "purchase" -> {
                    if(checkout!=null){result.error("busy","Checkout already open",null);return@setMethodCallHandler}
                    val product=call.argument<String>("product_id")?:""
                    val basePlan=call.argument<String>("base_plan_id")?:""
                    val user=call.argument<String>("user_id")?:""
                    checkout=result
                    connect(true,{
                        val client=billing!!
                        val query=QueryProductDetailsParams.newBuilder().setProductList(listOf(QueryProductDetailsParams.Product.newBuilder()
                            .setProductId(product).setProductType(BillingClient.ProductType.SUBS).build())).build()
                        client.queryProductDetailsAsync(query){ status,details ->
                            val item=details.productDetailsList.firstOrNull{it.productId==product}
                            val offer=item?.subscriptionOfferDetails?.firstOrNull{it.basePlanId==basePlan&&it.offerId==null}
                            if(status.responseCode!=BillingClient.BillingResponseCode.OK||item==null||offer==null){
                                checkout?.error("product","This plan is unavailable on Google Play",null);checkout=null
                            }else{
                                val account=MessageDigest.getInstance("SHA-256").digest(user.toByteArray()).joinToString(""){"%02x".format(it)}
                                val params=BillingFlowParams.newBuilder().setObfuscatedAccountId(account).setProductDetailsParamsList(listOf(
                                    BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(item).setOfferToken(offer.offerToken).build())).build()
                                val launched=client.launchBillingFlow(activity,params)
                                if(launched.responseCode!=BillingClient.BillingResponseCode.OK){checkout?.error("billing","Could not open Google Play",null);checkout=null}
                            }
                        }
                    },{checkout?.error("billing","Google Play is unavailable",null);checkout=null})
                }
                "pending" -> connect(false,{
                    val params=QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build()
                    billing!!.queryPurchasesAsync(params){ _,purchases ->
                        purchases.filter{it.purchaseState==Purchase.PurchaseState.PURCHASED}.forEach{store.edit().putBoolean(it.purchaseToken,true).commit()}
                        result.success(store.all.keys.toList())
                    }
                },{result.success(store.all.keys.toList())})
                "ack" -> {store.edit().remove(call.argument<String>("purchase_token")).commit();result.success(null)}
                else -> result.notImplemented()
            }
        }
    }
    private fun connect(choice:Boolean,ready:()->Unit,failed:()->Unit) {
        billing?.endConnection()
        val builder=BillingClient.newBuilder(activity).enablePendingPurchases(
            PendingPurchasesParams.newBuilder().enableOneTimeProducts().enablePrepaidPlans().build())
            .enableAutoServiceReconnection()
            .setListener { status,purchases ->
                val purchase=purchases?.firstOrNull{it.purchaseState==Purchase.PurchaseState.PURCHASED}
                if(status.responseCode==BillingClient.BillingResponseCode.OK&&purchase!=null){
                    store.edit().putBoolean(purchase.purchaseToken,true).commit()
                    checkout?.success(mapOf("kind" to "google","purchase_token" to purchase.purchaseToken));checkout=null
                }else if(status.responseCode!=BillingClient.BillingResponseCode.OK){
                    checkout?.error("cancelled","Payment not completed",null);checkout=null
                }else{checkout?.error("pending","Google Play payment is pending",null);checkout=null}
            }
        if(choice) builder.enableUserChoiceBilling { details ->
            checkout?.success(mapOf("kind" to "upi","external_token" to details.externalTransactionToken));checkout=null
        }
        billing=builder.build()
        billing!!.startConnection(object:BillingClientStateListener {
            override fun onBillingSetupFinished(result:BillingResult) {if(result.responseCode==BillingClient.BillingResponseCode.OK)ready()else failed()}
            override fun onBillingServiceDisconnected() { }
        })
    }
}
