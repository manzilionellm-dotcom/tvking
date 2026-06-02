// =========================================================
//  MulticastLockBridge.kt — Lock multicast WiFi pour la découverte
// =========================================================
//  POURQUOI ce fichier existe (le vrai bug du cast) :
//
//  Sur Android, la puce WiFi FILTRE par défaut tous les paquets
//  multicast/broadcast qui ne sont pas destinés directement au
//  téléphone (économie de batterie). Or :
//    - mDNS / Bonjour (`multicast_dns`) écoute sur 224.0.0.251
//      pour trouver les Chromecast / Google TV (`_googlecast._tcp`).
//    - SSDP (UPnP/DLNA) écoute sur 239.255.255.250 pour les TVs.
//
//  Sans un `WifiManager.MulticastLock` ACTIF, ces deux découvertes
//  envoient bien leurs requêtes mais ne REÇOIVENT JAMAIS les
//  réponses → le picker liste 0 appareil → "le cast ne marche pas".
//
//  Ce pont expose 2 méthodes au Dart via le MethodChannel
//  `com.manzilionellm.tvking/multicast` :
//    - acquire() : bool  → prend le lock (idempotent, compté par réf)
//    - release() : void  → relâche quand toutes les découvertes
//      en cours ont fini.
//
//  Le lock est RELÂCHÉ dès que plus personne n'en a besoin, parce
//  que le garder en permanence vide la batterie (la puce WiFi
//  reste en mode "écoute tout").
//
//  Permission requise (ajoutée par apply_cast_patch.sh) :
//    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
// =========================================================

package com.manzilionellm.tvking

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MulticastLockBridge(
    messenger: BinaryMessenger,
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "MulticastLock"
        private const val CHANNEL = "com.manzilionellm.tvking/multicast"
        // Tag visible dans `adb shell dumpsys wifi` pour diagnostiquer
        // les locks orphelins.
        private const val LOCK_TAG = "tvking-discovery"
    }

    private val channel: MethodChannel =
        MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler(this@MulticastLockBridge)
        }

    // Le lock lui-même, créé paresseusement au 1er acquire().
    private var lock: WifiManager.MulticastLock? = null

    // Compteur de réf MANUEL. On gère le ref-count nous-mêmes
    // (setReferenceCounted(false)) plutôt que de laisser Android le
    // faire, parce qu'on peut lancer mDNS ET SSDP en parallèle :
    // chacun acquire() au début et release() à la fin, et on ne
    // veut relâcher le lock physique QUE quand les DEUX ont fini.
    private var refCount = 0

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquire" -> result.success(acquire())
            "release" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    @Synchronized
    private fun acquire(): Boolean {
        return try {
            if (lock == null) {
                val wifi = context.applicationContext
                    .getSystemService(Context.WIFI_SERVICE) as WifiManager
                lock = wifi.createMulticastLock(LOCK_TAG).apply {
                    // On gère le ref-count à la main (cf. refCount).
                    setReferenceCounted(false)
                }
            }
            refCount++
            if (lock?.isHeld != true) {
                lock?.acquire()
                Log.i(TAG, "MulticastLock acquis (refCount=$refCount)")
            }
            true
        } catch (e: Exception) {
            // Pas de permission CHANGE_WIFI_MULTICAST_STATE, ou pas de
            // WiFi → on échoue proprement. La découverte tentera quand
            // même (peut marcher sur certains constructeurs / émulateurs).
            Log.w(TAG, "acquire failed: $e")
            false
        }
    }

    @Synchronized
    private fun release() {
        try {
            if (refCount > 0) refCount--
            if (refCount == 0 && lock?.isHeld == true) {
                lock?.release()
                Log.i(TAG, "MulticastLock relâché")
            }
        } catch (e: Exception) {
            Log.w(TAG, "release failed: $e")
        }
    }
}
