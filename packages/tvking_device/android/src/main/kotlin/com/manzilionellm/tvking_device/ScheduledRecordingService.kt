package com.manzilionellm.tvking_device

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
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Service au premier plan qui CAPTE un flux à l'heure programmée.
 *
 * Il vit dans le plugin (pas dans l'overlay Cast) pour exister sur TOUS
 * les builds Android — TV comprise, qui n'applique pas apply_cast_patch.
 * Il est réveillé par [ScheduledRecordingReceiver] (alarme), donc sans
 * Flutter : tout ce dont il a besoin est dans [ScheduledRecordingStore].
 *
 * Pipeline (même logique éprouvée que RecordingForegroundService de
 * l'overlay mobile, réécrite ici pour ne dépendre de rien) :
 *   - MPEG-TS brut : GET continu, écriture au fil de l'eau, reconnexion
 *     automatique quand le serveur coupe (les panels ferment la socket
 *     toutes les quelques minutes ; un EOF n'est PAS une fin d'émission) ;
 *   - HLS (.m3u8) : résolution master → media playlist, poll, segments
 *     concaténés (jamais le texte de la playlist dans le fichier).
 *
 * Un seul enregistrement natif à la fois : les lignes IPTV sont presque
 * toutes « 1 connexion ». Le Dart refuse déjà deux créneaux qui se
 * chevauchent ; ici on refuse aussi, par sécurité.
 *
 * Fin : à `stopMs` (alarme STOP ou garde interne), le service ferme le
 * fichier, note « done » + octets dans le carnet et s'arrête. Le Dart,
 * à son prochain passage (boot ou tick), relit le carnet et crée la
 * fiche dans « Mes enregistrements ».
 */
class ScheduledRecordingService : Service() {

    companion object {
        private const val TAG = "SchedRecSvc"
        private const val NOTIFICATION_ID = 1007
        private const val CHANNEL_ID = "scheduled_recording"
        const val ACTION_START = "com.manzilionellm.tvking.schedrec.svc.START"
        const val ACTION_STOP = "com.manzilionellm.tvking.schedrec.svc.STOP"
        const val EXTRA_ID = "id"

        /** Identifiant de l'enregistrement en cours (null = inactif). */
        @Volatile
        var activeId: String? = null

        @Volatile
        var bytesWritten: Long = 0L
    }

    @Volatile
    private var recording = false
    private var thread: Thread? = null

    @Volatile
    private var activeConn: HttpURLConnection? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var deadlineMs: Long = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getStringExtra(EXTRA_ID)
        when (intent?.action) {
            ACTION_START -> {
                if (id == null) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                val store = ScheduledRecordingStore(this)
                val entry = store.get(id)
                if (entry == null) {
                    Log.w(TAG, "START $id : inconnu du carnet")
                    // startForegroundService exige un startForeground()
                    // rapide, même pour s'arrêter aussitôt.
                    startForeground(NOTIFICATION_ID, buildNotification(entry, "7 MOTION"))
                    finishAndStop()
                    return START_NOT_STICKY
                }
                startForeground(NOTIFICATION_ID, buildNotification(entry, entry.optString("title", "7 MOTION")))
                if (recording) {
                    Log.w(TAG, "START $id refusé : $activeId déjà en cours")
                    store.update(id) { e ->
                        e.put("state", "failed")
                        e.put("error", "busy")
                    }
                    return START_NOT_STICKY
                }
                val stopMs = entry.optLong("stopMs", 0L)
                if (stopMs <= System.currentTimeMillis()) {
                    store.update(id) { e ->
                        e.put("state", "failed")
                        e.put("error", "tooLate")
                    }
                    finishAndStop()
                    return START_NOT_STICKY
                }
                acquireLocks(stopMs - System.currentTimeMillis() + 5 * 60_000L)
                store.update(id) { e ->
                    e.put("state", "recording")
                    e.put("startedAt", System.currentTimeMillis())
                }
                startDownload(id, entry.optString("url"), entry.optString("file"), stopMs)
            }
            ACTION_STOP -> {
                // On n'arrête que SI c'est bien cet enregistrement (une
                // alarme STOP d'un créneau annulé ne doit pas couper le
                // suivant).
                if (id == null || id == activeId || activeId == null) {
                    finishAndStop()
                }
            }
            else -> {
                // Relance par le système sans action exploitable : on
                // s'arrête proprement (le fichier a été fermé dans finally).
                finishAndStop()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopDownload()
        releaseLocks()
        super.onDestroy()
    }

    // ------------------------------------------------------------------
    //  Téléchargement
    // ------------------------------------------------------------------

    private fun startDownload(id: String, url: String, filePath: String, stopMs: Long) {
        if (recording) return
        recording = true
        activeId = id
        bytesWritten = 0L
        deadlineMs = stopMs
        thread = Thread {
            var out: FileOutputStream? = null
            var error: String? = null
            try {
                File(filePath).parentFile?.mkdirs()
                out = FileOutputStream(File(filePath), true)
                if (looksLikeHls(url)) runHlsLoop(url, out) else runRawLoop(url, out)
            } catch (e: Throwable) {
                Log.e(TAG, "download fatal: $e", e)
                error = e.javaClass.simpleName
            } finally {
                try {
                    out?.flush()
                    out?.fd?.sync()
                    out?.close()
                } catch (_: Throwable) {}
                val bytes = bytesWritten
                Log.i(TAG, "terminé $id, octets=$bytes")
                ScheduledRecordingStore(this).update(id) { e ->
                    e.put("state", if (bytes > 0 || error == null) "done" else "failed")
                    e.put("bytes", bytes)
                    e.put("endedAt", System.currentTimeMillis())
                    if (error != null) e.put("error", error)
                }
                recording = false
                activeId = null
                // Fin naturelle (deadline atteinte ou flux mort) → le
                // service se retire lui-même.
                try {
                    stopForegroundCompat()
                    stopSelf()
                } catch (_: Throwable) {}
            }
        }.apply {
            isDaemon = true
            name = "sched-rec-download"
            start()
        }
    }

    private fun stillRunning(): Boolean =
        recording && System.currentTimeMillis() < deadlineMs

    private fun looksLikeHls(url: String): Boolean =
        url.lowercase(java.util.Locale.ROOT).contains(".m3u8")

    private fun runRawLoop(url: String, out: FileOutputStream) {
        val buf = ByteArray(64 * 1024)
        var attempts = 0
        var sniffed = false
        while (stillRunning()) {
            var conn: HttpURLConnection? = null
            try {
                conn = openConn(url)
                activeConn = conn
                val code = conn.responseCode
                if (code !in 200..299) {
                    if (code == 401 || code == 403) {
                        Log.w(TAG, "HTTP $code — arrêt")
                        break
                    }
                    attempts++
                    if (attempts > 30) break
                    Thread.sleep(2000)
                    continue
                }
                attempts = 0
                val input = conn.inputStream
                var first = true
                while (stillRunning()) {
                    val n = input.read(buf)
                    if (n < 0) break
                    if (first && !sniffed) {
                        sniffed = true
                        first = false
                        if (n >= 7 && isM3u8Header(buf, n)) {
                            try { input.close() } catch (_: Throwable) {}
                            try { conn.disconnect() } catch (_: Throwable) {}
                            activeConn = null
                            runHlsLoop(url, out)
                            return
                        }
                    }
                    first = false
                    out.write(buf, 0, n)
                    bytesWritten += n
                }
                try { input.close() } catch (_: Throwable) {}
                if (!stillRunning()) break
                Thread.sleep(500)
            } catch (e: InterruptedException) {
                break
            } catch (e: Throwable) {
                if (!stillRunning()) break
                attempts++
                if (attempts > 30) break
                try { Thread.sleep(2000) } catch (_: Throwable) { break }
            } finally {
                activeConn = null
                try { conn?.disconnect() } catch (_: Throwable) {}
            }
        }
    }

    private fun runHlsLoop(playlistUrl: String, out: FileOutputStream) {
        val seen = HashSet<String>()
        var consecutiveErrors = 0
        var mediaUrl = playlistUrl
        var resolved = false
        while (stillRunning()) {
            try {
                if (!resolved) {
                    val head = fetchText(playlistUrl)
                    mediaUrl = if (isMasterPlaylist(head)) {
                        selectVariant(head, playlistUrl) ?: playlistUrl
                    } else {
                        playlistUrl
                    }
                    resolved = true
                }
                val body = fetchText(mediaUrl)
                if (isMasterPlaylist(body)) {
                    selectVariant(body, mediaUrl)?.let { mediaUrl = it }
                    Thread.sleep(1000)
                    continue
                }
                val segments = parseSegments(body, mediaUrl)
                var newCount = 0
                for (seg in segments) {
                    if (!stillRunning()) break
                    if (!seen.add(seg)) continue
                    downloadSegment(seg, out)
                    newCount++
                }
                // Garde-fou mémoire pour les longues captures.
                if (seen.size > 5000) seen.clear()
                consecutiveErrors = 0
                Thread.sleep(if (newCount > 0) 3000L else 5000L)
            } catch (e: InterruptedException) {
                break
            } catch (e: Throwable) {
                if (!stillRunning()) break
                consecutiveErrors++
                if (consecutiveErrors > 30) break
                val wait = (2000L * consecutiveErrors).coerceAtMost(16000L)
                try { Thread.sleep(wait) } catch (_: Throwable) { break }
            }
        }
    }

    private fun downloadSegment(segUrl: String, out: FileOutputStream) {
        var conn: HttpURLConnection? = null
        try {
            conn = openConn(segUrl)
            activeConn = conn
            if (conn.responseCode !in 200..299) return
            val input = conn.inputStream
            val buf = ByteArray(64 * 1024)
            while (stillRunning()) {
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

    private fun fetchText(urlStr: String): String {
        var conn: HttpURLConnection? = null
        try {
            conn = openConn(urlStr)
            activeConn = conn
            if (conn.responseCode !in 200..299) throw java.io.IOException("HTTP ${conn.responseCode}")
            return conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        } finally {
            activeConn = null
            try { conn?.disconnect() } catch (_: Throwable) {}
        }
    }

    /** Suit les redirections À LA MAIN, y compris http ↔ https (les panels
     *  Xtream renvoient souvent un 302 vers un CDN https ; HttpURLConnection
     *  ne suit jamais un changement de protocole tout seul). */
    private fun openConn(urlStr: String): HttpURLConnection {
        var current = urlStr
        var hops = 0
        while (true) {
            val conn = (URL(current).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15000
                readTimeout = 30000
                instanceFollowRedirects = false
                setRequestProperty("User-Agent", "VLC/3.0.20 LibVLC/3.0.20 (7 MOTION)")
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
            return conn
        }
    }

    private fun isM3u8Header(buf: ByteArray, len: Int): Boolean {
        val n = minOf(len, 16)
        val head = String(buf, 0, n, Charsets.UTF_8).trimStart('﻿', ' ', '\n', '\r', '\t')
        return head.startsWith("#EXTM3U")
    }

    private fun isMasterPlaylist(body: String): Boolean = body.contains("#EXT-X-STREAM-INF")

    private fun selectVariant(masterBody: String, baseUrl: String): String? {
        val lines = masterBody.split("\n")
        var bestBw = -1L
        var bestUri: String? = null
        var i = 0
        while (i < lines.size) {
            val line = lines[i].trim()
            if (line.startsWith("#EXT-X-STREAM-INF")) {
                val bw = Regex("BANDWIDTH=(\\d+)").find(line)?.groupValues?.getOrNull(1)?.toLongOrNull() ?: 0L
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
        URL(URL(baseUrl), ref).toString()
    } catch (e: Throwable) {
        ref
    }

    private fun stopDownload() {
        recording = false
        try { activeConn?.disconnect() } catch (_: Throwable) {}
        try {
            thread?.interrupt()
            thread?.join(3000)
        } catch (_: Throwable) {}
        thread = null
        activeConn = null
    }

    private fun finishAndStop() {
        stopDownload()
        releaseLocks()
        stopForegroundCompat()
        stopSelf()
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    // ------------------------------------------------------------------
    //  Verrous (CPU + Wi-Fi) : la box peut s'assoupir en plein créneau
    // ------------------------------------------------------------------

    private fun acquireLocks(maxMs: Long) {
        try {
            if (wakeLock?.isHeld != true) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "7motion:schedrec").apply {
                    setReferenceCounted(false)
                    acquire(maxMs.coerceIn(60_000L, 12 * 3600_000L))
                }
            }
        } catch (e: Throwable) {
            Log.w(TAG, "wakelock: $e")
        }
        try {
            if (wifiLock?.isHeld != true) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                @Suppress("DEPRECATION")
                wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "7motion:schedrec").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } catch (e: Throwable) {
            Log.w(TAG, "wifilock: $e")
        }
    }

    private fun releaseLocks() {
        try { wakeLock?.takeIf { it.isHeld }?.release() } catch (_: Throwable) {}
        wakeLock = null
        try { wifiLock?.takeIf { it.isHeld }?.release() } catch (_: Throwable) {}
        wifiLock = null
    }

    // ------------------------------------------------------------------
    //  Notification (obligatoire pour un service au premier plan)
    // ------------------------------------------------------------------

    private fun buildNotification(entry: JSONObject?, text: String): Notification {
        val notifTitle = entry?.optString("notifTitle")?.takeIf { it.isNotEmpty() }
            ?: "Enregistrement programmé"
        createChannelIfNeeded(
            entry?.optString("channelName")?.takeIf { it.isNotEmpty() } ?: "Enregistrements programmés",
            entry?.optString("channelDesc")?.takeIf { it.isNotEmpty() }
                ?: "Notification pendant un enregistrement programmé",
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(notifTitle)
            .setContentText(text)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun createChannelIfNeeded(name: String, desc: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_LOW).apply {
            description = desc
            setShowBadge(false)
        }
        mgr.createNotificationChannel(channel)
    }
}
