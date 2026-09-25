package com.manzilionellm.tvking_device

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Debug
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Enregistre le channel `com.manzilionellm.tvking/device` (le MÊME que le code
 * Dart `DeviceIdentity` appelle déjà) et expose :
 *
 *   getAndroidId     -> Settings.Secure.ANDROID_ID (String, peut être null)
 *                       = identifiant STABLE par appareil+clé de signature, qui
 *                       survit aux réinstallations. C'est la graine de la « MAC »
 *                       virtuelle DÉTERMINISTE → l'activation du client ne se perd
 *                       plus à la réinstallation.
 *   getDeviceInfo    -> modèle / fabricant / version Android / build (pour que le
 *                       panel recense chaque Android).
 *   getMemoryInfo    -> RAM totale + flag « low RAM » (adaptation du cache images).
 *   getProcessMemory -> mémoire RÉELLE du process (PSS) + RAM disponible + seuil
 *                       « mémoire basse » du système : c'est ce que la BOÎTE NOIRE
 *                       échantillonne pour voir venir un kill mémoire.
 *   getLastExitInfo  -> POURQUOI le process est mort la dernière fois (API 30+ :
 *                       ActivityManager.getHistoricalProcessExitReasons). C'est la
 *                       seule source fiable pour distinguer un kill mémoire (LOW_MEMORY),
 *                       un ANR, un crash natif ou un simple arrêt par l'utilisateur.
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
            // RAM de l'appareil → permet à l'app d'ADAPTER son empreinte
            // (cache d'images) : petite box = léger, grande box = pleine qualité.
            "getMemoryInfo" -> {
                val am = appContext?.getSystemService(Context.ACTIVITY_SERVICE)
                    as? ActivityManager
                val mi = ActivityManager.MemoryInfo()
                am?.getMemoryInfo(mi)
                val totalMb = (mi.totalMem / (1024L * 1024L)).toInt()
                val lowRam = am?.isLowRamDevice ?: false
                result.success(
                    hashMapOf(
                        "totalMb" to totalMb,
                        "lowRam" to lowRam,
                    ),
                )
            }
            // ---- BOÎTE NOIRE : mémoire réelle du process, à l'instant t ----
            "getProcessMemory" -> {
                try {
                    val am = appContext?.getSystemService(Context.ACTIVITY_SERVICE)
                        as? ActivityManager
                    val mi = ActivityManager.MemoryInfo()
                    am?.getMemoryInfo(mi)
                    // PSS du process courant (Ko) : la mesure que lowmemorykiller regarde.
                    val pssKb: Int = try {
                        val infos = am?.getProcessMemoryInfo(intArrayOf(Process.myPid()))
                        infos?.firstOrNull()?.totalPss ?: (Debug.getPss() / 1024L).toInt()
                    } catch (e: Exception) {
                        (Debug.getPss() / 1024L).toInt()
                    }
                    result.success(
                        hashMapOf(
                            "pssMb" to pssKb / 1024,
                            "nativeHeapMb" to (Debug.getNativeHeapAllocatedSize() / (1024L * 1024L)).toInt(),
                            "availMb" to (mi.availMem / (1024L * 1024L)).toInt(),
                            "totalMb" to (mi.totalMem / (1024L * 1024L)).toInt(),
                            "thresholdMb" to (mi.threshold / (1024L * 1024L)).toInt(),
                            "lowMemory" to mi.lowMemory,
                        ),
                    )
                } catch (e: Exception) {
                    result.success(null)
                }
            }
            // ---- BOÎTE NOIRE : raison de la DERNIÈRE mort du process ----
            // Android (API 30+) garde l'historique des sorties de chaque app :
            // reason = LOW_MEMORY (tué par manque de RAM), ANR, CRASH,
            // CRASH_NATIVE, SIGNALED, EXCESSIVE_RESOURCE_USAGE, USER_REQUESTED…
            // + la mémoire (PSS/RSS) au moment de la mort. Sans ça, on ne peut que
            // deviner. Sous API 30 : liste vide (l'app se rabat sur son journal).
            "getLastExitInfo" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                    result.success(emptyList<Map<String, Any?>>())
                    return
                }
                try {
                    val ctx = appContext
                    val am = ctx?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                    val list = am?.getHistoricalProcessExitReasons(ctx.packageName, 0, 5)
                        ?: emptyList()
                    result.success(
                        list.map { info ->
                            hashMapOf(
                                "reason" to info.reason,
                                "reasonName" to reasonName(info.reason),
                                "description" to (info.description ?: ""),
                                "timestamp" to info.timestamp,
                                "pssMb" to (info.pss / 1024L).toInt(),
                                "rssMb" to (info.rss / 1024L).toInt(),
                                "status" to info.status,
                                "importance" to info.importance,
                                "process" to (info.processName ?: ""),
                            )
                        },
                    )
                } catch (e: Exception) {
                    result.success(emptyList<Map<String, Any?>>())
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF (l'app s'est fermée elle-même)"
        ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED (tuée par un signal)"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY (tuée : mémoire insuffisante)"
        ApplicationExitInfo.REASON_CRASH -> "CRASH (exception Java non rattrapée)"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE (plantage natif)"
        ApplicationExitInfo.REASON_ANR -> "ANR (app figée, tuée par Android)"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE (trop de ressources)"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED (arrêt demandé par l'utilisateur)"
        ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        ApplicationExitInfo.REASON_OTHER -> "OTHER (système)"
        else -> "UNKNOWN($reason)"
    }
}
