package com.manzilionellm.tvking_device

import android.app.Activity
import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.media.AudioManager
import android.os.StatFs
import android.os.Build
import android.os.Debug
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import android.view.InputDevice
import android.view.KeyCharacterMap
import android.view.KeyEvent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
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
 *   remoteKey        -> envoie UNE touche (liste fermée : D-pad, OK, Retour,
 *                       Chaîne) à NOTRE activité. Ce n'est pas une injection vers
 *                       les autres applications.
 *   remoteVolume     -> monte ou baisse d'UN cran le volume MÉDIA du système
 *                       (AudioManager). Ne passe pas par le lecteur vidéo.
 *
 * Mêmes clés que la MainActivity du build mobile (android_overlay/), pour que
 * le backend voie des données cohérentes quel que soit le build.
 *
 * S'auto-enregistre via GeneratedPluginRegistrant : TOUJOURS présent, même sur
 * le build TV qui n'applique pas apply_cast_patch.sh.
 */
class TvkingDevicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var activity: Activity? = null

    // Touches que la télécommande du téléphone a le droit d'envoyer.
    // Pas de volume ici : le volume est le cran système (remoteVolume),
    // pour ne pas le confondre avec le son interne du lecteur.
    private val allowedRemoteKeys = setOf(
        KeyEvent.KEYCODE_DPAD_UP,
        KeyEvent.KEYCODE_DPAD_DOWN,
        KeyEvent.KEYCODE_DPAD_LEFT,
        KeyEvent.KEYCODE_DPAD_RIGHT,
        KeyEvent.KEYCODE_DPAD_CENTER,
        KeyEvent.KEYCODE_BACK,
        KeyEvent.KEYCODE_CHANNEL_UP,
        KeyEvent.KEYCODE_CHANNEL_DOWN,
    )

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
            // Espace LIBRE (octets) sur le volume qui contient [path] : le module
            // Cinéma refuse un téléchargement qui remplirait la box (un film
            // HD = 1 à 4 Go ; une box = souvent 8 Go au total).
            "getFreeBytes" -> {
                val path = call.argument<String>("path")
                val free = try {
                    if (path.isNullOrEmpty()) -1L else StatFs(path).availableBytes
                } catch (e: Exception) {
                    -1L
                }
                result.success(free)
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
            // Télécommande du téléphone : une touche de la liste, vers
            // CETTE activité seulement (dispatchKeyEvent ne quitte pas l'app).
            "remoteKey" -> dispatchRemoteKey(call, result)
            // Volume SYSTÈME (barre Android), +1 ou -1. Jamais une valeur
            // absolue, pour qu'une requête ne puisse pas coller le son à fond.
            "remoteVolume" -> adjustRemoteVolume(call, result)
            // Mise à jour : Zuno a-t-il le droit d'installer un APK ?
            // Android 8+ (API 26) demande l'autorisation « applications
            // inconnues » PAR APPLICATION. Avant, c'était un réglage global
            // que l'installateur système gère lui-même : on répond vrai.
            "canInstallPackages" -> {
                val ok = try {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                        true
                    } else {
                        appContext?.packageManager?.canRequestPackageInstalls() ?: false
                    }
                } catch (e: Exception) {
                    // Doute : on laisse l'installateur système décider.
                    true
                }
                result.success(ok)
            }
            // Ouvre l'écran où l'on autorise Zuno à installer des applications.
            // Repli : les réglages de sécurité (anciennes box, Fire TV).
            "openInstallPermission" -> result.success(openInstallPermission())
            else -> result.notImplemented()
        }
    }

    /// Vrai si un écran de réglage a pu s'ouvrir.
    private fun openInstallPermission(): Boolean {
        val ctx: Context = activity ?: appContext ?: return false
        val pkg = ctx.packageName
        val intents = mutableListOf<android.content.Intent>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intents.add(
                android.content.Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    android.net.Uri.parse("package:$pkg"),
                ),
            )
        }
        intents.add(android.content.Intent(Settings.ACTION_SECURITY_SETTINGS))
        intents.add(android.content.Intent(Settings.ACTION_SETTINGS))
        for (intent in intents) {
            try {
                if (activity == null) {
                    intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                ctx.startActivity(intent)
                return true
            } catch (e: Exception) {
                // Écran absent sur cette box : on essaie le suivant.
            }
        }
        return false
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private fun dispatchRemoteKey(call: MethodCall, result: MethodChannel.Result) {
        val code = call.argument<Int>("code")
        val act = activity
        if (code == null || act == null || code !in allowedRemoteKeys) {
            result.success(false)
            return
        }
        act.runOnUiThread {
            try {
                val now = SystemClock.uptimeMillis()
                act.dispatchKeyEvent(keyEvent(now, KeyEvent.ACTION_DOWN, code))
                act.dispatchKeyEvent(keyEvent(now, KeyEvent.ACTION_UP, code))
                result.success(true)
            } catch (e: Exception) {
                result.success(false)
            }
        }
    }

    private fun keyEvent(now: Long, action: Int, code: Int): KeyEvent {
        return KeyEvent(
            now,
            now,
            action,
            code,
            0,
            0,
            KeyCharacterMap.VIRTUAL_KEYBOARD,
            0,
            0,
            InputDevice.SOURCE_DPAD,
        )
    }

    private fun adjustRemoteVolume(call: MethodCall, result: MethodChannel.Result) {
        val dir = call.argument<Int>("dir")
        if (dir != 1 && dir != -1) {
            result.success(false)
            return
        }
        val am = appContext?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (am == null) {
            result.success(false)
            return
        }
        try {
            am.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                if (dir == 1) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                AudioManager.FLAG_SHOW_UI,
            )
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
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
