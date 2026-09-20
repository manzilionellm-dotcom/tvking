package com.manzilionellm.tvking_device

import android.app.ActivityManager
import android.content.Context
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

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
    private var schedulerChannel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.manzilionellm.tvking/device")
        channel?.setMethodCallHandler(this)
        // Canal SÉPARÉ pour l'enregistrement programmé : le canal `/device`
        // est AUSSI enregistré par la MainActivity de l'overlay mobile (le
        // dernier inscrit gagne) — un canal dédié évite toute collision.
        schedulerChannel = MethodChannel(
            binding.binaryMessenger,
            "com.manzilionellm.tvking/recording_scheduler",
        )
        schedulerChannel?.setMethodCallHandler(ScheduledRecordingBridge(binding.applicationContext))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        schedulerChannel?.setMethodCallHandler(null)
        schedulerChannel = null
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
            // Clé de chiffrement des identifiants IPTV (SecretCipher v2) :
            // 32 octets aléatoires (base64), la DEK que le Dart utilise en
            // AES-GCM. Elle est stockée ENVELOPPÉE par une clé matérielle du
            // Keystore (non exportable). Renvoie null si l'appareil ne peut
            // pas (API < 23, Keystore HS) → le Dart retombe sur la dérivation
            // v1 (fail-open, aucune perte de fonction).
            "getCredentialKey" -> {
                val key = try {
                    getOrCreateCredentialKey()
                } catch (e: Exception) {
                    null
                }
                result.success(key)
            }
            // Mode Bouclier (core/privacy/privacy_shield.dart) : un VPN
            // est-il actif sur l'appareil ? Sert au coupe-circuit « aucune
            // lecture réseau sans VPN ». Best-effort : toute erreur → false
            // (le Dart ne bloque jamais une lecture sur un doute natif).
            "isVpnActive" -> result.success(isVpnActive())
            // PASSTHROUGH DOLBY / DTS (19/09/2026) : quels formats compressés
            // la sortie audio ACTUELLE accepte tels quels (HDMI, USB, ARC).
            // Noms au format `audio-spdif` de mpv. Liste vide = on décode
            // nous-mêmes, jamais de silence. Voir audio_passthrough.dart.
            "getAudioPassthrough" -> audioPassthroughAsync(result)
            else -> result.notImplemented()
        }
    }

    // =====================================================================
    //  Passthrough audio (téléphone → ampli / barre de son)
    // =====================================================================
    //  JAMAIS SUR LE FIL PRINCIPAL (20/09/2026). Un MethodChannel répond
    //  sur le fil principal d'Android, et interroger la sortie audio
    //  (isDirectPlaybackSupported, getDevices) passe par le service audio
    //  du système — un appel binder qui, sur certains téléphones, peut
    //  attendre le HAL audio plusieurs secondes. Cinq questions d'affilée
    //  au mauvais moment (une radio qui joue, un ampli qui se réveille) et
    //  Android affiche « The Few ne répond pas ». Photo du propriétaire le
    //  lendemain de la mise à jour. La sonde tourne donc sur son propre
    //  fil ; le fil principal ne fait que rendre la réponse. Et si la
    //  sonde met plus de 1,5 s, on répond « rien » sans l'attendre : le
    //  lecteur décode lui-même, comme avant. Jamais de silence, jamais de
    //  gel.
    private fun audioPassthroughAsync(result: MethodChannel.Result) {
        val principal = Handler(Looper.getMainLooper())
        var repondu = false
        // Une seule réponse, quelle que soit la course entre la sonde et
        // le délai : la première arrivée gagne, l'autre est ignorée.
        fun repondre(valeur: List<String>) {
            principal.post {
                if (repondu) return@post
                repondu = true
                try { result.success(valeur) } catch (_: Throwable) {}
            }
        }
        principal.postDelayed({ repondre(ArrayList()) }, 1500)
        Thread({
            val formats = try { audioPassthrough() } catch (_: Throwable) { ArrayList<String>() }
            repondre(formats)
        }, "tvking-audio-passthrough").apply { isDaemon = true }.start()
    }

    //  La box le fait toute seule : Media3 demande à Android si la sortie
    //  accepte l'E-AC-3, l'AC-3, le DTS, et les lui envoie sans les
    //  décoder. Le lecteur du téléphone (mpv) ne pose pas cette question :
    //  il faut lui dire, par `audio-spdif`, quels formats laisser passer.
    //  C'est cette question qu'on pose ici, à la place de mpv.
    //
    //  DEUX FAÇONS DE DEMANDER, SELON L'ANDROID :
    //   • Android 10+ (API 29) : AudioTrack.isDirectPlaybackSupported —
    //     la réponse officielle, format par format, pour la sortie en
    //     cours. Si le client débranche l'ampli, la réponse change.
    //   • Android 6 → 9 : on lit les encodages déclarés par les sorties
    //     numériques présentes (HDMI, ARC, USB, dock, S/PDIF). Moins
    //     précis, mais honnête : une sortie qui ne déclare rien ne reçoit
    //     rien.
    //
    //  ORDRE FIXE et connu du Dart (ac3, eac3, dts, dts-hd, truehd) : c'est
    //  celui que mpv attend, et un test le verrouille côté Dart.
    private fun audioPassthrough(): List<String> {
        val out = ArrayList<String>()
        val ctx = appContext ?: return out
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return out
        val candidats = LinkedHashMap<String, Int>()
        candidats["ac3"] = AudioFormat.ENCODING_AC3
        candidats["eac3"] = AudioFormat.ENCODING_E_AC3
        candidats["dts"] = AudioFormat.ENCODING_DTS
        candidats["dts-hd"] = AudioFormat.ENCODING_DTS_HD
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            candidats["truehd"] = AudioFormat.ENCODING_DOLBY_TRUEHD
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                    .build()
                for ((nom, encodage) in candidats) {
                    val fmt = AudioFormat.Builder()
                        .setEncoding(encodage)
                        .setSampleRate(48000)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                        .build()
                    if (AudioTrack.isDirectPlaybackSupported(fmt, attrs)) out.add(nom)
                }
            } else {
                val am = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                    ?: return out
                val numeriques = setOf(
                    AudioDeviceInfo.TYPE_HDMI, AudioDeviceInfo.TYPE_HDMI_ARC,
                    AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_ACCESSORY,
                    AudioDeviceInfo.TYPE_DOCK, AudioDeviceInfo.TYPE_LINE_DIGITAL,
                )
                val encodages = HashSet<Int>()
                for (d in am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
                    if (d.type in numeriques) for (e in d.encodings) encodages.add(e)
                }
                for ((nom, encodage) in candidats) {
                    if (encodages.contains(encodage)) out.add(nom)
                }
            }
        } catch (e: Throwable) {
            // Un doute natif ne coupe jamais le son : liste vide = décodage
            // logiciel, comme avant.
            return ArrayList()
        }
        return out
    }

    // =====================================================================
    //  Détection VPN (Mode Bouclier)
    // =====================================================================
    //  On regarde TOUS les réseaux connus du système, pas seulement le
    //  réseau « actif » : un VPN limité à certaines apps (WireGuard en
    //  mode par-app, futur tunnel intégré) n'est pas forcément le réseau
    //  par défaut vu par ConnectivityManager. API < 23 : pas de
    //  NetworkCapabilities fiable → on répond false (le Dart le sait :
    //  minSdk 21 sur les vieilles box, le coupe-circuit y est sans objet).
    private fun isVpnActive(): Boolean {
        return try {
            val cm = appContext?.getSystemService(Context.CONNECTIVITY_SERVICE)
                as? ConnectivityManager ?: return false
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
            val active = cm.activeNetwork
            if (active != null) {
                val caps = cm.getNetworkCapabilities(active)
                if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                    return true
                }
            }
            cm.allNetworks.any { n ->
                cm.getNetworkCapabilities(n)
                    ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
            }
        } catch (e: Exception) {
            false
        }
    }

    // =====================================================================
    //  Clé de chiffrement des identifiants IPTV (SecretCipher v2)
    // =====================================================================
    //  POURQUOI : la v1 dérivait la clé AES de l'ANDROID_ID + un sel connu —
    //  or l'ANDROID_ID est lisible par quiconque a accès à l'appareil (root,
    //  backup), soit EXACTEMENT le modèle de menace visé. La v2 applique le
    //  patron standard DEK/KEK :
    //    - une DEK (Data Encryption Key) de 32 octets ALÉATOIRES est générée
    //      à la première demande — c'est elle que le Dart utilise (AES-GCM) ;
    //    - elle est conservée ENVELOPPÉE (chiffrée) par une KEK AES-256-GCM
    //      créée DANS l'Android Keystore (matériel TEE/StrongBox quand
    //      disponible) : la KEK est NON EXPORTABLE — même root ne peut pas la
    //      lire, seulement demander des opérations au Keystore SUR CET
    //      appareil. Extraire les fichiers de l'app ne suffit donc plus.
    //  API < 23 : Keystore AES/GCM indisponible → on renvoie null (le Dart
    //  garde le schéma v1). Best-effort, jamais lançant vers Flutter.

    private val keyAlias = "tvking.cred.kek.v1"
    private val prefsName = "tvking_secure_v2"
    private val dekPrefKey = "cred_dek_wrapped"

    private fun securePrefs(): SharedPreferences =
        appContext!!.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    /** DEK 32 octets en base64. Créée+enveloppée au 1er appel, puis relue. */
    private fun getOrCreateCredentialKey(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val prefs = securePrefs()
        val wrapped = prefs.getString(dekPrefKey, null)
        if (wrapped != null) {
            return try {
                Base64.encodeToString(kekUnwrap(wrapped), Base64.NO_WRAP)
            } catch (e: Exception) {
                // Blob illisible (KEK effacée, corruption) → on repart d'une
                // DEK neuve plutôt que de bloquer (les anciennes valeurs
                // chiffrées v2 deviennent illisibles, le Dart fail-open les
                // traite comme perdues et le client se ré-authentifie).
                newDek(prefs)
            }
        }
        return newDek(prefs)
    }

    private fun newDek(prefs: SharedPreferences): String {
        val dek = ByteArray(32).also { SecureRandom().nextBytes(it) }
        prefs.edit().putString(dekPrefKey, kekWrap(dek)).apply()
        return Base64.encodeToString(dek, Base64.NO_WRAP)
    }

    /** Récupère (ou crée) la KEK AES-256-GCM non exportable du Keystore. */
    private fun kek(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry(keyAlias, null) as? KeyStore.SecretKeyEntry)?.let {
            return it.secretKey
        }
        val kg = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore",
        )
        kg.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return kg.generateKey()
    }

    /** data → base64( IV(12) ‖ ciphertext+tag ). */
    private fun kekWrap(data: ByteArray): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, kek())
        val iv = cipher.iv
        val ct = cipher.doFinal(data)
        val out = ByteArray(iv.size + ct.size)
        System.arraycopy(iv, 0, out, 0, iv.size)
        System.arraycopy(ct, 0, out, iv.size, ct.size)
        return Base64.encodeToString(out, Base64.NO_WRAP)
    }

    /** base64( IV(12) ‖ ct+tag ) → data. Lève si l'intégrité GCM échoue. */
    private fun kekUnwrap(blobB64: String): ByteArray {
        val blob = Base64.decode(blobB64, Base64.NO_WRAP)
        val iv = blob.copyOfRange(0, 12)
        val ct = blob.copyOfRange(12, blob.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, kek(), GCMParameterSpec(128, iv))
        return cipher.doFinal(ct)
    }
}
