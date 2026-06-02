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
    //  Deux pipelines, choisis automatiquement :
    //    1. MPEG-TS brut (.ts / .mp4 direct) : streaming pur
    //       HttpURLConnection -> fichier, avec reconnexion automatique
    //       (les serveurs IPTV ferment periodiquement la socket en
    //       envoyant un EOF ; on rouvre et on append au lieu d'arreter).
    //    2. HLS (.m3u8) : on resout la media playlist (en gerant les
    //       MASTER playlists via BANDWIDTH), on polle, et on concatene
    //       les SEGMENTS .ts. CORRECTIF de l'ecran noir : avant, une URL
    //       .m3u8 faisait ecrire le TEXTE de la playlist dans le fichier
    //       (illisible). Un sniff #EXTM3U rattrape aussi les playlists
    //       servies sans extension .m3u8.

    private fun startDownload(url: String, filePath: String) {
        if (recording) return
        recording = true
        currentUrl = url
        currentFile = filePath
        bytesWritten = 0L
        downloadThread = Thread {
            var out: java.io.FileOutputStream? = null
            try {
                // append=true : si l'OS a redemarre le service, on
                // continue le meme fichier au lieu de l'ecraser.
                out = java.io.FileOutputStream(java.io.File(filePath), true)

                // AIGUILLAGE DU PIPELINE (correctif "ecran noir") :
                //   - HLS (.m3u8) : on NE telecharge PAS le texte de la
                //     playlist (= l'ancien bug qui donnait un fichier de
                //     texte illisible -> ecran noir). On resout la media
                //     playlist (en gerant les MASTER playlists), on polle
                //     et on concatene les SEGMENTS .ts -> vraie video.
                //   - sinon : flux MPEG-TS brut, streaming direct (comme
                //     avant), avec un sniff de securite au cas ou l'URL
                //     ne finit pas par .m3u8 mais renvoie quand meme une
                //     playlist (#EXTM3U).
                if (looksLikeHls(url)) {
                    runHlsLoop(url, out)
                } else {
                    runRawLoop(url, out)
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

    /// Heuristique d'extension. Le sniff de contenu dans runRawLoop
    /// rattrape les URLs HLS sans extension explicite.
    private fun looksLikeHls(url: String): Boolean =
        url.lowercase(java.util.Locale.ROOT).contains(".m3u8")

    // ---------------------------------------------------------------
    //  Pipeline MPEG-TS brut (inchangé fonctionnellement) + sniff HLS
    // ---------------------------------------------------------------
    private fun runRawLoop(url: String, out: java.io.FileOutputStream) {
        val buf = ByteArray(64 * 1024)
        var attempts = 0
        var sniffed = false
        while (recording) {
            var conn: java.net.HttpURLConnection? = null
            try {
                conn = openConn(url)
                activeConn = conn
                val code = conn.responseCode
                if (code !in 200..299) {
                    // IMPORTANT : on NE casse PLUS immediatement sur 401/403.
                    // Juste apres avoir coupe la lecture, un fournisseur
                    // "1 connexion" renvoie souvent 403 (ou 401) le temps
                    // que SA connexion precedente (le lecteur) se libere
                    // cote serveur. On RETENTE donc quelques fois : dans la
                    // quasi-totalite des cas le creneau se libere en quelques
                    // secondes et l'enregistrement demarre. On n'abandonne
                    // qu'apres ~60 s d'echecs consecutifs (vraie erreur
                    // d'abonnement ou serveur mort).
                    attempts++
                    if (attempts > 30) {
                        Log.w(TAG, "HTTP $code persistant apres $attempts essais — abandon")
                        break
                    }
                    Log.w(TAG, "HTTP $code (#$attempts) — creneau pas encore libre, on retente")
                    Thread.sleep(2000)
                    continue
                }
                attempts = 0
                val input = conn.inputStream
                var first = true
                while (recording) {
                    val n = input.read(buf)
                    if (n < 0) break // EOF → reconnecter
                    // Sniff de securite : si le tout 1er bloc commence par
                    // "#EXTM3U", l'URL "brute" est en fait une playlist HLS
                    // → on bascule sur le pipeline HLS (sinon on ecrirait du
                    // texte = ecran noir). On ne le fait qu'une fois.
                    if (first && !sniffed) {
                        sniffed = true
                        first = false
                        if (n >= 7 && isM3u8Header(buf, n)) {
                            try { input.close() } catch (_: Throwable) {}
                            try { conn.disconnect() } catch (_: Throwable) {}
                            activeConn = null
                            Log.i(TAG, "sniff: l'URL brute est une playlist HLS → bascule HLS")
                            runHlsLoop(url, out)
                            return
                        }
                    }
                    first = false
                    out.write(buf, 0, n)
                    bytesWritten += n
                }
                try { input.close() } catch (_: Throwable) {}
                if (!recording) break
                // EOF mais on enregistre toujours : le serveur a coupe →
                // petite pause puis reconnexion.
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
    }

    // ---------------------------------------------------------------
    //  Pipeline HLS : master → media playlist → segments concaténés
    // ---------------------------------------------------------------
    private fun runHlsLoop(playlistUrl: String, out: java.io.FileOutputStream) {
        val seen = HashSet<String>()
        var consecutiveErrors = 0
        // URL de la media playlist effective (resolue depuis la master
        // au 1er tour). On la re-resout si jamais la variante pointe
        // encore vers une master (cas tres rare de master imbriquee).
        var mediaUrl = playlistUrl
        var resolved = false

        while (recording) {
            try {
                if (!resolved) {
                    val head = fetchText(playlistUrl)
                    mediaUrl = if (isMasterPlaylist(head)) {
                        val v = selectVariant(head, playlistUrl)
                        Log.i(TAG, "master playlist → variante choisie: $v")
                        v ?: playlistUrl
                    } else {
                        playlistUrl
                    }
                    resolved = true
                }

                val body = fetchText(mediaUrl)
                if (isMasterPlaylist(body)) {
                    // La "variante" est elle-meme une master → on descend.
                    selectVariant(body, mediaUrl)?.let { mediaUrl = it }
                    Thread.sleep(1000)
                    continue
                }

                val segments = parseSegments(body, mediaUrl)
                var newCount = 0
                for (seg in segments) {
                    if (!recording) break
                    if (seen.contains(seg)) continue
                    seen.add(seg)
                    downloadSegment(seg, out)
                    newCount++
                }
                consecutiveErrors = 0
                // Re-poll au ~demi target-duration (3s si on rattrape, 5s
                // si rien de neuf), comme ffmpeg/TiviMate.
                Thread.sleep(if (newCount > 0) 3000L else 5000L)
            } catch (e: InterruptedException) {
                break
            } catch (e: Throwable) {
                if (!recording) break
                consecutiveErrors++
                if (consecutiveErrors > 30) {
                    Log.w(TAG, "serveur HLS injoignable, abandon")
                    break
                }
                val wait = (2000L * consecutiveErrors).coerceAtMost(16000L)
                try { Thread.sleep(wait) } catch (_: Throwable) { break }
            }
        }
    }

    /// Telecharge UN segment .ts et l'append au fichier. Une erreur sur
    /// un segment ne tue pas l'enregistrement (segment perdu ≠ rec perdu).
    private fun downloadSegment(segUrl: String, out: java.io.FileOutputStream) {
        var conn: java.net.HttpURLConnection? = null
        try {
            conn = openConn(segUrl)
            activeConn = conn
            val code = conn.responseCode
            if (code !in 200..299) return
            val input = conn.inputStream
            val buf = ByteArray(64 * 1024)
            while (recording) {
                val n = input.read(buf)
                if (n < 0) break
                out.write(buf, 0, n)
                bytesWritten += n
            }
            try { input.close() } catch (_: Throwable) {}
        } catch (e: Throwable) {
            Log.w(TAG, "segment KO: ${e.message}")
        } finally {
            activeConn = null
            try { conn?.disconnect() } catch (_: Throwable) {}
        }
    }

    /// Recupere le corps texte d'une URL (playlist). Utilise pour les
    /// .m3u8 uniquement (petits fichiers texte).
    private fun fetchText(urlStr: String): String {
        var conn: java.net.HttpURLConnection? = null
        try {
            conn = openConn(urlStr)
            activeConn = conn
            val code = conn.responseCode
            if (code !in 200..299) throw java.io.IOException("HTTP $code")
            return conn.inputStream.bufferedReader(Charsets.UTF_8)
                .use { it.readText() }
        } finally {
            activeConn = null
            try { conn?.disconnect() } catch (_: Throwable) {}
        }
    }

    /// Ouvre une connexion HTTP en suivant NOUS-MEMES les redirections,
    /// y compris CROSS-PROTOCOLE (http -> https et inversement).
    ///
    /// POURQUOI c'est critique : `HttpURLConnection.instanceFollowRedirects`
    /// ne suit JAMAIS un redirect qui change de protocole (limitation
    /// historique de Java, pour raisons de securite). Or les serveurs
    /// Xtream renvoient tres souvent un `302` d'une URL `.ts` en http vers
    /// leur CDN en https. Avec l'ancien code (`= true`), la reponse restait
    /// un 302 jamais suivi -> aucun octet lu -> fichier 0 octet ->
    /// "Enregistrement vide". On boucle donc a la main sur les en-tetes
    /// `Location` (jusqu'a 8 sauts) pour atterrir sur la vraie ressource.
    private fun openConn(urlStr: String): java.net.HttpURLConnection {
        var current = urlStr
        var hops = 0
        while (true) {
            val conn = (java.net.URL(current).openConnection() as java.net.HttpURLConnection).apply {
                connectTimeout = 15000
                readTimeout = 30000
                // On desactive le suivi auto : on gere TOUTES les redirections
                // a la main pour couvrir le cas cross-protocole.
                instanceFollowRedirects = false
                // CRITIQUE : on utilise EXACTEMENT le meme User-Agent que le
                // lecteur (cf. video_player_screen.dart -> mpv 'user-agent').
                // Beaucoup de serveurs Xtream font du whitelisting strict du
                // UA : si la lecture passe mais l'enregistrement utilise un UA
                // different (autre version, ou suffixe "(7 MOTION)"), le
                // serveur renvoie 403 -> fichier 0 octet ("enregistrement
                // vide"). Garder ces deux UA identiques est ESSENTIEL.
                setRequestProperty("User-Agent", "VLC/3.0.18 LibVLC/3.0.18")
                setRequestProperty("Accept", "*/*")
            }
            val code = conn.responseCode
            if (code in 300..399 && hops < 8) {
                val loc = conn.getHeaderField("Location")
                if (!loc.isNullOrBlank()) {
                    try { conn.disconnect() } catch (_: Throwable) {}
                    current = resolveUrl(current, loc)
                    hops++
                    continue
                }
            }
            // 2xx, ou 3xx sans Location exploitable, ou plafond de sauts
            // atteint : on rend la connexion telle quelle. L'appelant lit
            // `responseCode` et decide (2xx = on lit, sinon retry/abandon).
            return conn
        }
    }

    private fun isM3u8Header(buf: ByteArray, len: Int): Boolean {
        val n = minOf(len, 16)
        val head = String(buf, 0, n, Charsets.UTF_8)
            .trimStart('﻿', ' ', '\n', '\r', '\t')
        return head.startsWith("#EXTM3U")
    }

    private fun isMasterPlaylist(body: String): Boolean =
        body.contains("#EXT-X-STREAM-INF")

    /// Choisit la variante de PLUS HAUTE bande passante (attribut
    /// BANDWIDTH) d'une master playlist et resout son URL.
    private fun selectVariant(masterBody: String, baseUrl: String): String? {
        val lines = masterBody.split("\n")
        var bestBw = -1L
        var bestUri: String? = null
        var i = 0
        while (i < lines.size) {
            val line = lines[i].trim()
            if (line.startsWith("#EXT-X-STREAM-INF")) {
                val bw = Regex("BANDWIDTH=(\\d+)")
                    .find(line)?.groupValues?.getOrNull(1)?.toLongOrNull() ?: 0L
                // L'URI suit sur la 1re ligne non vide / non commentaire.
                var j = i + 1
                while (j < lines.size) {
                    val cand = lines[j].trim()
                    if (cand.isNotEmpty() && !cand.startsWith("#")) {
                        if (bw > bestBw) {
                            bestBw = bw
                            bestUri = cand
                        }
                        break
                    }
                    j++
                }
                i = j + 1
            } else {
                i++
            }
        }
        return bestUri?.let { resolveUrl(baseUrl, it) }
    }

    /// Extrait les URLs absolues des segments d'une MEDIA playlist
    /// (lignes non commentees), en resolvant les chemins relatifs.
    private fun parseSegments(mediaBody: String, baseUrl: String): List<String> {
        val out = ArrayList<String>()
        for (raw in mediaBody.split("\n")) {
            val line = raw.trim()
            if (line.isEmpty() || line.startsWith("#")) continue
            out.add(resolveUrl(baseUrl, line))
        }
        return out
    }

    private fun resolveUrl(baseUrl: String, ref: String): String = try {
        java.net.URL(java.net.URL(baseUrl), ref).toString()
    } catch (e: Throwable) {
        ref
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
