package com.manzilionellm.tvking_device

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build

/** Une source commune au plugin et à l'ancienne MainActivity mobile.
 * Aucun appel au SDK Cast : sa décision dépend de l'édition signée de l'app,
 * tandis que le panel doit recevoir le matériel réellement déclaré par l'OS. */
object DeviceHardwareInfo {
    fun read(context: Context?): Map<String, String> = mapOf(
        "model" to Build.MODEL,
        "manufacturer" to Build.MANUFACTURER,
        "release" to Build.VERSION.RELEASE,
        "sdk" to Build.VERSION.SDK_INT.toString(),
        "build" to Build.DISPLAY,
        "deviceKind" to kind(context),
    )

    private fun kind(context: Context?): String {
        if (context == null) return "unknown"
        return try {
            val app = context.applicationContext
            val manager = app.packageManager
            val config = app.resources.configuration
            val mode = app.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
            val modeType = mode?.currentModeType
                ?: (config.uiMode and Configuration.UI_MODE_TYPE_MASK)
            DeviceHardwareKind.classify(
                // Nom documenté par Amazon, valable aussi chez ses partenaires.
                manager.hasSystemFeature("amazon.hardware.fire_tv"),
                modeType == Configuration.UI_MODE_TYPE_TELEVISION ||
                    manager.hasSystemFeature(PackageManager.FEATURE_TELEVISION),
                manager.hasSystemFeature(PackageManager.FEATURE_LEANBACK),
                manager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN),
                config.smallestScreenWidthDp,
                modeType == Configuration.UI_MODE_TYPE_WATCH ||
                    modeType == Configuration.UI_MODE_TYPE_CAR ||
                    manager.hasSystemFeature("android.hardware.type.watch") ||
                    manager.hasSystemFeature("android.hardware.type.automotive") ||
                    manager.hasSystemFeature("android.hardware.type.pc"),
            )
        } catch (_: Exception) {
            // Un OS incomplet ne doit ni bloquer le heartbeat ni inventer un type.
            "unknown"
        }
    }
}
