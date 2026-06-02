// =========================================================
//  RecordingForegroundService.kt — Service Android pour
//  enregistrements en arrière-plan
// =========================================================
//  Quand l'utilisateur lance un enregistrement IPTV puis quitte
//  l'app (lit un SMS, prend un appel, etc.), Android peut tuer
//  notre process pour libérer de la mémoire — ce qui interrompt
//  l'enregistrement libmpv et donne un fichier tronqué.
//
//  Ce ForegroundService dit à Android "ne me tue pas, je fais
//  quelque chose d'important". En contrepartie il DOIT afficher
//  une notification persistante (impossible de cacher un foreground
//  service depuis Android 8.0 sans).
//
//  Cycle de vie :
//    1. Dart appelle `start(title)` → MethodChannel → on lance le
//       service avec ACTION_START + le titre du programme.
//    2. Le service appelle startForeground() + crée la notification.
//       Android garantit alors la survie du process tant que le
//       service n'a pas appelé stopForeground/stopSelf.
//    3. Dart appelle `stop()` à la fin de l'enregistrement →
//       MethodChannel → ACTION_STOP → stopForeground + stopSelf.
//
//  Pourquoi pas un plugin Flutter ?
//    - flutter_foreground_task / flutter_background : APIs lourdes,
//      isolate séparé, complexité inutile pour notre cas (un
//      simple "tiens-moi en vie").
//    - Le pattern MethodChannel custom est déjà rodé dans ce projet
//      (Cast SDK, Gallery export), même architecture.
// =========================================================

package com.manzilionellm.tvking

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

class RecordingForegroundService : Service() {

    companion object {
        private const val TAG = "RecForegroundSvc"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "recording_channel"
        private const val WAKE_LOCK_TAG = "7motion:recording_wake_lock"
        private const val WIFI_LOCK_TAG = "7motion:recording_wifi_lock"

        const val ACTION_START = "com.manzilionellm.tvking.recording.START"
        const val ACTION_STOP = "com.manzilionellm.tvking.recording.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_URL = "url"
        const val EXTRA_FILE = "file"

        /// Octets écrits par l'enregistrement natif en cours. Lu en
        /// best-effort par Dart si besoin. 0 = inactif.
        @Volatile
        var bytesWritten: Long = 0L
    }

    /// Flag de vie du thread de téléchargement natif. `false` = arrêt
    /// propre demandé (flush + close du fichier).
    @Volatile
    private var recording = false
    private var downloadThread: Thread? = null
    // Connexion HTTP en cours : gardee pour pouvoir la couper net
    // depuis stopDownload() (debloque un read() bloque sur la socket).
    @Volatile
    private var activeConn: java.net.HttpURLConnection? = null
    // Mémorisés pour re-livraison si l'OS redémarre le service.
    private var currentUrl: String? = null
    private var currentFile: String? = null

    /// PartialWakeLock = garde le CPU actif même quand l'écran s'éteint.
    /// CRITIQUE pour que le Dart isolate continue de tourner et que
    /// les requêtes HTTP du downloader ne soient pas suspendues quand
    /// l'utilisateur appuie HOME ou ferme l'écran.
    private var wakeLock: PowerManager.WakeLock? = null

    /// WifiLock niveau HIGH_PERF = empêche Android de mettre le WiFi
    /// en mode 'sleep' (économie d'énergie) quand l'écran s'éteint.
    /// Sans ça, en 30 s d'écran éteint, le WiFi peut être suspendu →
    /// les sockets HTTP du downloader sont fermées par le système.
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "7 MOTION"
                val url = intent.getStringExtra(EXTRA_URL)
                val file = intent.getStringExtra(EXTRA_FILE)
                Log.i(TAG, "START foreground: $title (url=${url != null})")
                createChannelIfNeeded()
                startForeground(NOTIFICATION_ID, buildNotification(title))
                acquireLocks()
                // Si une URL + un fichier sont fournis, on enregistre
                // NATIVEMENT (le telechargement vit dans CE service, donc
                // il survit a la fermeture de l'app par l'utilisateur).
                if (url != null && file != null) {
                    startDownload(url, file)
                }
            }
            ACTION_STOP -> {
                Log.i(TAG, "STOP foreground")
                stopDownload()
                releaseLocks()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
            }
            else -> {
                // Service redémarré par le système après un kill mémoire
                // (START_REDELIVER_INTENT re-livre normalement l'intent
                // d'origine — ici pas d'action exploitable → on s'arrête).
                Log.w(TAG, "onStartCommand sans action — stop")
                stopDownload()
                releaseLocks()
                stopSelf()
            }
        }
        // START_REDELIVER_INTENT : si l'OS tue le service par pression
        // memoire, il le relance avec le DERNIER intent (URL + fichier),
        // et l'enregistrement reprend (append au fichier). Combine au
        // foreground + wakelock, ca rend l'enregistrement resilient.
        return START_REDELIVER_INTENT
    }

    /// L'utilisateur a "swipe" l'app hors des recents. On NE STOPPE PAS
    /// l'enregistrement : c'est tout l'interet du natif. Le service
    /// foreground continue de tourner et d'ecrire le fichier.
    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "onTaskRemoved — app fermee, l'enregistrement CONTINUE")
        // Volontairement vide (pas de stopSelf) → survie au swipe.
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        // Sécurité : si le service est détruit sans ACTION_STOP propre
        // (kill par l'OS, crash, etc.), on arrête le download + libère
        // les locks pour ne pas laisser le tel surchauffer.
        stopDownload()
        releaseLocks()
        super.onDestroy()
    }

    // =========================================================
    //  Téléchargement natif (survit a la fermeture de l'app)
    // =========================================================
    //  Streaming pur HttpURLConnection -> fichier, avec reconnexion
    //  automatique : les serveurs IPTV ferment periodiquement la
    //  socket (idle/keepalive) en envoyant un EOF ; on rouvre et on
    //  continue d'ecrire (append) au lieu d'arreter. Couvre les flux
    //  bruts MPEG-TS (.ts) et les fichiers directs (.mp4/.mkv).

    private fun startDownload(url: String, filePath: String) {
        if (recording) return
        recording = true
        currentUrl = url
        currentFile = filePath
        bytesWritten = 0L
        downloadThread = Thread {
            var out: java.io.FileOutputStream? = null
            var attempts = 0
            try {
                // append=true : si l'OS a redemarre le service, on
                // continue le meme fichier au lieu de l'ecraser.
                out = java.io.FileOutputStream(java.io.File(filePath), true)
                val buf = ByteArray(64 * 1024)
                while (recording) {
                    var conn: java.net.HttpURLConnection? = null
                    try {
                        conn = (java.net.URL(url).openConnection()
                                as java.net.HttpURLConnection).apply {
                            connectTimeout = 15000
                            readTimeout = 30000
                            instanceFollowRedirects = true
                            setRequestProperty(
                                "User-Agent",
                                "VLC/3.0.20 LibVLC/3.0.20 (7 MOTION)",
                            )
                        }
                        activeConn = conn
                        val code = conn.responseCode
                        if (code !in 200..299) {
                            // 401/403 = abonnement/credentials → inutile
                            // d'insister. Autres 4xx/5xx → backoff + retry.
                            if (code == 401 || code == 403) {
                                Log.w(TAG, "HTTP $code — arret recording")
                                break
                            }
                            attempts++
                            if (attempts > 30) break
                            Thread.sleep(2000)
                            continue
                        }
                        attempts = 0
                        val input = conn.inputStream
                        while (recording) {
                            val n = input.read(buf)
                            if (n < 0) break // EOF → reconnecter
                            out.write(buf, 0, n)
                            bytesWritten += n
                        }
                        try { input.close() } catch (_: Throwable) {}
                        if (!recording) break
                        // EOF mais on enregistre toujours : le serveur a
                        // coupe → petite pause puis reconnexion.
                        Thread.sleep(500)
                    } catch (e: InterruptedException) {
                        break
                    } catch (e: Throwable) {
                        if (!recording) break
                        attempts++
                        if (attempts > 30) break
                        Log.w(TAG, "reconnect (#$attempts) apres: ${e.message}")
                        try { Thread.sleep(2000) } catch (_: Throwable) { break }
                    } finally {
                        activeConn = null
                        try { conn?.disconnect() } catch (_: Throwable) {}
                    }
                }
            } catch (e: Throwable) {
                Log.e(TAG, "download fatal: $e", e)
            } finally {
                try {
                    out?.flush()
                    out?.fd?.sync()
                    out?.close()
                } catch (_: Throwable) {}
                Log.i(TAG, "download termine, octets=$bytesWritten")
            }
        }.apply {
            isDaemon = true
            name = "rec-download"
            start()
        }
    }

    private fun stopDownload() {
        recording = false
        // Couper la socket en cours pour debloquer un read() bloque.
        try { activeConn?.disconnect() } catch (_: Throwable) {}
        try {
            downloadThread?.interrupt()
            downloadThread?.join(3000)
        } catch (_: Throwable) {}
        downloadThread = null
        activeConn = null
        currentUrl = null
        currentFile = null
    }

    /// Acquiert PartialWakeLock (CPU) + WifiLock (réseau). À appeler
    /// EXACTEMENT une fois — la flag `referenceCounted = false` côté
    /// PowerManager garantit l'idempotence, mais on évite quand même
    /// les acquisitions multiples par safety.
    private fun acquireLocks() {
        try {
            if (wakeLock == null || !wakeLock!!.isHeld) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    WAKE_LOCK_TAG,
                ).apply {
                    setReferenceCounted(false)
                    acquire(12 * 60 * 60 * 1000L) // 12h max safety timeout
                }
                Log.i(TAG, "WakeLock acquired (CPU stays awake)")
            }
        } catch (e: Throwable) {
            Log.e(TAG, "WakeLock acquire failed: $e", e)
        }

        try {
            if (wifiLock == null || !wifiLock!!.isHeld) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                // HIGH_PERF garantit pas de WiFi sleep + débit max
                // (vs FULL qui économise plus mais peut couper).
                wifiLock = wm.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    WIFI_LOCK_TAG,
                ).apply {
                    setReferenceCounted(false)
                    acquire()
                }
                Log.i(TAG, "WifiLock acquired (WiFi stays awake)")
            }
        } catch (e: Throwable) {
            Log.e(TAG, "WifiLock acquire failed: $e", e)
        }
    }

    private fun releaseLocks() {
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
            wakeLock = null
            Log.i(TAG, "WakeLock released")
        } catch (e: Throwable) {
            Log.w(TAG, "WakeLock release failed: $e")
        }
        try {
            wifiLock?.takeIf { it.isHeld }?.release()
            wifiLock = null
            Log.i(TAG, "WifiLock released")
        } catch (e: Throwable) {
            Log.w(TAG, "WifiLock release failed: $e")
        }
    }

    private fun buildNotification(title: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Enregistrement en cours")
            .setContentText(title)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            // Notification "discrete" : pas de son, pas de vibration.
            // L'utilisateur sait qu'un enregistrement tourne sans être
            // interrompu visuellement.
            .setSilent(true)
            .setForegroundServiceBehavior(
                NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE,
            )
            .build()
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (mgr.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Enregistrements",
            // LOW = pas de son ni de heads-up, juste l'icône dans la
            // barre de statut. Le user n'a pas envie d'être harcelé
            // pendant son match de foot.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Notification persistante pendant un enregistrement"
            setShowBadge(false)
        }
        mgr.createNotificationChannel(channel)
    }
}
