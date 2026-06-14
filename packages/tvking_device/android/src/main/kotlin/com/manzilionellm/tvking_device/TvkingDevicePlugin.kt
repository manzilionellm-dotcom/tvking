package com.manzilionellm.tvking_device

import android.content.Context
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Enregistre le channel `com.manzilionellm.tvking/device` (le MÊME que le code
 * Dart `DeviceIdentity` appelle déjà) et expose :
 *
 *   getAndroidId  -> Settings.Secure.ANDROID_ID (String, peut être null)
 *                    = identifiant STABLE par appareil+clé de signature, qui
 *                    survit aux réinstallations. C'est la graine de la « MAC »
 *                    virtuelle DÉTERMINISTE → l'activation du client ne se perd
 *                    plus à la réinstallation.
 *   getDeviceInfo -> modèle / fabricant / version Android / build (pour que le
 *                    panel recense chaque Android).
 *
 * Mêmes clés que la MainActivity du build mobile (android_overlay/), pour que
 * le backend voie des données cohérentes quel que soit le build.
 *
 * S'auto-enregistre via GeneratedPluginRegistrant : TOUJOURS présent, même sur
 * le build TV qui n'applique pas apply_cast_patch.sh.
 */
class TvkingDevicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.manzilionellm.tvking/device")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAndroidId" -> {
                val id = try {
                    Settings.Secure.getString(
                        appContext?.contentResolver,
                        Settings.Secure.ANDROID_ID,
                    )
                } catch (e: Exception) {
                    null
                }
                result.success(id)
            }
            "getDeviceInfo" -> {
                result.success(
                    hashMapOf(
                        "model" to Build.MODEL,
                        "manufacturer" to Build.MANUFACTURER,
                        "release" to Build.VERSION.RELEASE,
                        "sdk" to Build.VERSION.SDK_INT.toString(),
                        "build" to Build.DISPLAY,
                    ),
                )
            }
            else -> result.notImplemented()
        }
    }
}
