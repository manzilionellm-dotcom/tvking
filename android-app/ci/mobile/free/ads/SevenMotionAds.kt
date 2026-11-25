package com.manzilionellm.tvking

import android.content.Context
import android.content.res.Configuration
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.MobileAds
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Pont exclusif au paquet 7 MOTION Play. Les sources IPTV restent hors du SDK. */
internal class SevenMotionAds(
    private val activity: FragmentActivity,
    engine: FlutterEngine
) : DefaultLifecycleObserver {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "7motion/admob")
    private val consent = UserMessagingPlatform.getConsentInformation(activity)
    private val pending = mutableListOf<MethodChannel.Result>()
    private var consentUpdated = false
    private var sdkReady = false
    private var privacyOpen = false
    private var destroyed = false

    init {
        activity.lifecycle.addObserver(this)
        channel.setMethodCallHandler { call, result ->
            val mode = activity.resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
            if (mode == Configuration.UI_MODE_TYPE_TELEVISION || destroyed) {
                result.success(emptyMap<String, Boolean>())
            } else when (call.method) {
                "prepare" -> prepare(result)
                "privacy" -> openPrivacy(result)
                else -> result.notImplemented()
            }
        }
        engine.platformViewsController.registry.registerViewFactory(
            "7motion/admob/banner",
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, id: Int, args: Any?): PlatformView {
                    // Le second contrôle couvre un changement de consentement
                    // entre le dessin du widget Flutter et la création native.
                    return Banner(context, sdkReady && consent.canRequestAds() && !privacyOpen)
                }
            }
        )
    }

    private fun state(): Map<String, Boolean> = mapOf(
        "banner" to (sdkReady && consent.canRequestAds() && !privacyOpen),
        "privacy" to (consent.privacyOptionsRequirementStatus ==
            ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED)
    )

    private fun finish() {
        val replies = pending.toList()
        pending.clear()
        replies.forEach { it.success(if (destroyed) emptyMap<String, Boolean>() else state()) }
    }

    private fun afterConsent() {
        if (destroyed || !consentUpdated || !consent.canRequestAds() || sdkReady) {
            finish()
            return
        }
        MobileAds.initialize(activity.applicationContext) {
            Handler(Looper.getMainLooper()).post {
                sdkReady = !destroyed
                finish()
            }
        }
    }

    private fun prepare(result: MethodChannel.Result) {
        pending.add(result)
        if (pending.size > 1) return
        if (consentUpdated) {
            afterConsent()
            return
        }
        consent.requestConsentInfoUpdate(activity, ConsentRequestParameters.Builder().build(), {
            if (destroyed) {
                finish()
            } else {
                UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) { error ->
                    consentUpdated = error == null
                    afterConsent()
                }
            }
        }, { finish() })
    }

    private fun openPrivacy(result: MethodChannel.Result) {
        if (privacyOpen || !consentUpdated || pending.isNotEmpty() ||
            consent.privacyOptionsRequirementStatus != ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED) {
            result.success(state())
            return
        }
        privacyOpen = true
        UserMessagingPlatform.showPrivacyOptionsForm(activity) {
            privacyOpen = false
            if (destroyed) {
                result.success(emptyMap<String, Boolean>())
            } else {
                prepare(result)
            }
        }
    }

    override fun onDestroy(owner: LifecycleOwner) {
        destroyed = true
        finish()
        channel.setMethodCallHandler(null)
        owner.lifecycle.removeObserver(this)
    }

    /** Le lecteur ne monte jamais cette vue. Elle est détruite en quittant les réglages. */
    private inner class Banner(context: Context, allowed: Boolean) : PlatformView, DefaultLifecycleObserver {
        private val container = FrameLayout(context)
        private val ad = if (allowed) AdView(context) else null

        init {
            ad?.apply {
                adUnitId = "__SEVEN_BANNER_ID__"
                setAdSize(AdSize.BANNER)
                container.addView(this)
                loadAd(AdRequest.Builder().build())
            }
            activity.lifecycle.addObserver(this)
        }

        override fun getView(): View = container
        override fun onResume(owner: LifecycleOwner) { ad?.resume() }
        override fun onPause(owner: LifecycleOwner) { ad?.pause() }
        override fun dispose() {
            activity.lifecycle.removeObserver(this)
            container.removeAllViews()
            ad?.destroy()
        }
    }
}
