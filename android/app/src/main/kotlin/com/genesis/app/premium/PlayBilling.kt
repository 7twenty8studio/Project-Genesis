package com.genesis.app.premium

import android.app.Activity
import android.util.Log
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import com.genesis.app.VerselyApplication
import com.genesis.app.settings.Entitlements
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Versely Premium on Google Play, as EntitlementService's StoreKit side on
 * iOS: one subscription (PREMIUM_PRODUCT) with monthly and yearly base plans
 * (a free trial is an offer on them, made in the Play Console). Purchases
 * are acknowledged here and sent to premium-sync (playPurchaseToken), which
 * checks them with Google and records them for the signed-in account, so
 * the server knows too. Until the Play Console has the product, nothing is
 * offered and the Premium screen says so.
 */
class PlayBilling(private val app: VerselyApplication) : PurchasesUpdatedListener {
    enum class Outcome { PURCHASED, PENDING, CANCELLED, FAILED }

    data class Plan(val yearly: Boolean, val price: String, val trialDays: Int?, val offerToken: String)

    data class State(
        val connected: Boolean = false,
        val loaded: Boolean = false,
        val plans: List<Plan> = emptyList(),
        val activeToken: String? = null,
        val activeYearly: Boolean? = null,
        val isPurchasing: Boolean = false,
    ) {
        val isAvailable: Boolean get() = plans.isNotEmpty()
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    private var details: ProductDetails? = null
    private var pendingPurchase: CompletableDeferred<Outcome>? = null

    private val client: BillingClient = BillingClient.newBuilder(app)
        .setListener(this)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    /** Connects (once), loads the plans and what this Google account already has. */
    fun start() {
        if (client.isReady) {
            app.scope.launch { refresh() }
            return
        }
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                val ok = result.responseCode == BillingClient.BillingResponseCode.OK
                _state.update { it.copy(connected = ok, loaded = !ok) }
                if (ok) app.scope.launch { refresh() }
            }

            override fun onBillingServiceDisconnected() {
                _state.update { it.copy(connected = false) }
            }
        })
    }

    /** The plans' prices, and the active subscription (restore is the same: Play remembers it). */
    suspend fun refresh(): Boolean {
        if (!client.isReady) return false
        val product = QueryProductDetailsParams.Product.newBuilder()
            .setProductId(PREMIUM_PRODUCT)
            .setProductType(BillingClient.ProductType.SUBS)
            .build()
        val result = withContext(Dispatchers.IO) {
            client.queryProductDetails(QueryProductDetailsParams.newBuilder().setProductList(listOf(product)).build())
        }
        details = result.productDetailsList?.firstOrNull()
        val plans = details?.let(::plansOf).orEmpty()
        val purchases = withContext(Dispatchers.IO) {
            client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build())
        }.purchasesList
        val active = purchases.firstOrNull { PREMIUM_PRODUCT in it.products && it.purchaseState == Purchase.PurchaseState.PURCHASED }
        _state.update { it.copy(loaded = true, plans = plans, activeToken = active?.purchaseToken) }
        Entitlements.setPlaySubscription(active != null)
        active?.let { handle(it) }
        return active != null
    }

    /** Opens Google Play's purchase sheet for the yearly or monthly plan. */
    suspend fun purchase(activity: Activity, yearly: Boolean): Outcome {
        val product = details ?: return Outcome.FAILED
        val plan = _state.value.plans.firstOrNull { it.yearly == yearly } ?: return Outcome.FAILED
        val params = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(product).setOfferToken(plan.offerToken).build()
        val flow = BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(params))
        // The account it's for, as iOS's appAccountToken: the server keeps it with that account only.
        app.account.state.value.user?.id?.lowercase()?.let(flow::setObfuscatedAccountId)
        // Switching between monthly and yearly replaces the current subscription.
        _state.value.activeToken?.let { token ->
            flow.setSubscriptionUpdateParams(
                BillingFlowParams.SubscriptionUpdateParams.newBuilder()
                    .setOldPurchaseToken(token)
                    .setSubscriptionReplacementMode(BillingFlowParams.SubscriptionUpdateParams.ReplacementMode.WITH_TIME_PRORATION)
                    .build(),
            )
        }
        val waiting = CompletableDeferred<Outcome>()
        pendingPurchase = waiting
        _state.update { it.copy(isPurchasing = true) }
        val launched = withContext(Dispatchers.Main) { client.launchBillingFlow(activity, flow.build()) }
        if (launched.responseCode != BillingClient.BillingResponseCode.OK) {
            pendingPurchase = null
            _state.update { it.copy(isPurchasing = false) }
            return if (launched.responseCode == BillingClient.BillingResponseCode.USER_CANCELED) Outcome.CANCELLED else Outcome.FAILED
        }
        return waiting.await().also { _state.update { state -> state.copy(isPurchasing = false) } }
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        val outcome = when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                val purchase = purchases?.firstOrNull { PREMIUM_PRODUCT in it.products }
                when (purchase?.purchaseState) {
                    Purchase.PurchaseState.PURCHASED -> {
                        _state.update { it.copy(activeToken = purchase.purchaseToken) }
                        Entitlements.setPlaySubscription(true)
                        app.scope.launch { handle(purchase) }
                        Outcome.PURCHASED
                    }
                    Purchase.PurchaseState.PENDING -> Outcome.PENDING
                    else -> Outcome.FAILED
                }
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> Outcome.CANCELLED
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                app.scope.launch { refresh() }
                Outcome.PURCHASED
            }
            else -> Outcome.FAILED
        }
        pendingPurchase?.complete(outcome)
        pendingPurchase = null
    }

    /** Acknowledges a new purchase (Play refunds it otherwise) and tells the server. */
    private suspend fun handle(purchase: Purchase) {
        if (!purchase.isAcknowledged) {
            val params = AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()
            val result = withContext(Dispatchers.IO) { client.acknowledgePurchase(params) }
            if (result.responseCode != BillingClient.BillingResponseCode.OK) Log.w(TAG, "Acknowledge: ${result.debugMessage}")
        }
        syncWithServer(purchase.purchaseToken)
    }

    /** Sends the purchase to premium-sync for the signed-in account; failures are retried next time. */
    suspend fun syncWithServer(token: String? = _state.value.activeToken) {
        val client = app.account.client ?: return
        if (token == null || app.account.state.value.user == null) return
        runCatching {
            val access = app.account.accessToken()
            withContext(Dispatchers.IO) {
                client.callFunction("premium-sync", buildJsonObject { put("playPurchaseToken", token) }.toString(), access)
            }
        }.onFailure { Log.w(TAG, "premium-sync", it) }
    }

    private fun plansOf(product: ProductDetails): List<Plan> {
        val offers = product.subscriptionOfferDetails.orEmpty()
        return listOf(true, false).mapNotNull { yearly ->
            val basePlan = if (yearly) "yearly" else "monthly"
            val forPlan = offers.filter { it.basePlanId == basePlan }
            if (forPlan.isEmpty()) return@mapNotNull null
            // A free-trial offer when this Google account can still have one, else the base plan.
            val trial = forPlan.firstOrNull { offer -> offer.pricingPhases.pricingPhaseList.any { it.priceAmountMicros == 0L } }
            val chosen = trial ?: forPlan.firstOrNull { it.offerId == null } ?: forPlan.first()
            val paid = chosen.pricingPhases.pricingPhaseList.lastOrNull { it.priceAmountMicros > 0L } ?: return@mapNotNull null
            val trialDays = trial?.pricingPhases?.pricingPhaseList?.firstOrNull { it.priceAmountMicros == 0L }?.billingPeriod?.let(::days)
            Plan(yearly, paid.formattedPrice, trialDays, chosen.offerToken)
        }
    }

    companion object {
        private const val TAG = "PlayBilling"

        /** The Play Console subscription (base plans "monthly" and "yearly"); the server accepts it too (_shared/play.ts). */
        const val PREMIUM_PRODUCT = "com.7twenty8studio.versely.premium"

        /** Days in an ISO 8601 period such as P7D, P1W or P1M. */
        fun days(period: String): Int? {
            val match = Regex("^P(?:(\\d+)Y)?(?:(\\d+)M)?(?:(\\d+)W)?(?:(\\d+)D)?$").matchEntire(period) ?: return null
            val (years, months, weeks, days) = match.destructured
            val total = (years.toIntOrNull() ?: 0) * 365 + (months.toIntOrNull() ?: 0) * 30 + (weeks.toIntOrNull() ?: 0) * 7 + (days.toIntOrNull() ?: 0)
            return total.takeIf { it > 0 }
        }

        fun manageURL(packageName: String): String =
            "https://play.google.com/store/account/subscriptions?sku=$PREMIUM_PRODUCT&package=$packageName"
    }
}
