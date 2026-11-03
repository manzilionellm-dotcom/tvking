package com.manzilionellm.native_video_player

import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import com.manzilionellm.native_video_player.logic.AppForeground
import com.manzilionellm.native_video_player.logic.ReconnectGate
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.Closeable
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.net.SocketException
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import kotlin.math.abs
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Le vrai NativeVideoView traverse une panne HTTP 502, son délai de reconnexion,
 * puis un MP4 décodé par Media3. Seul le transport Flutter est remplacé.
 * Le serveur ne quitte jamais 127.0.0.1 ; aucune playlist ni API client.
 */
@UnstableApi
@RunWith(AndroidJUnit4::class)
@SdkSuppress(minSdkVersion = 29)
class NativeRecoveryPlaybackTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private lateinit var activity: ContrastTestActivity
    private lateinit var fixture: File

    @Test
    fun pauseDuringHttp502Retry_staysPausedAndKeepsVodPosition() = withPlayer("pause-502") { proof ->
        LoopbackVideo(fixture.readBytes()).use { server ->
            val startMs = 7_000L
            open(server.url, startMs)
            awaitRetry()
            assertTrue("une véritable réponse 502 a précédé la reconnexion", server.failures.get() > 0)
            // La pause arrive APRÈS la panne et AVANT le délai natif d'une seconde.
            // La prise de décision ne doit donc pas relire l'intention d'avant.
            invoke("pause")
            val pausedAt = activity.messenger.events.size
            server.fail = false
            await("reconnexion HTTP réussie, lecteur prêt") {
                server.successes.get() > 0 && onMain { player().playbackState == Player.STATE_READY }
            }
            val positions = mutableListOf<Long>()
            repeat(20) {
                onMain {
                    assertFalse("RETRY_RESUMED_USER_PAUSE", player().playWhenReady)
                    assertFalse("la panne ne donne pas l'ordre Lecture", player().isPlaying)
                    positions.add(player().currentPosition)
                }
                SystemClock.sleep(100)
            }
            assertTrue("la reprise garde les 7 secondes demandées : $positions",
                positions.all { abs(it - startMs) <= 250 })
            assertFalse("aucun événement Lecture pendant la pause", activity.messenger.events
                .drop(pausedAt).any { it.method == "playing" && it.arguments == true })
            invoke("play")
            await("le bouton Lecture reprend le film") {
                onMain { player().isPlaying && player().currentPosition > startMs + 500 }
            }
            proof.put("http502Responses", server.failures.get())
                .put("successfulReads", server.successes.get())
                .put("positionsWhilePausedMs", JSONArray(positions))
        }
    }

    @Test
    fun sourceChangeSilenceBackgroundCastAndDispose_cancelPendingRetry() {
        // Chaque cas repart d'une activité et d'un serveur neufs : un passage
        // précédent ne peut fournir ni trame ni callback au cas suivant.
        for (leave in listOf("new-url", "silence", "background", "suspendForCast", "dispose")) {
            withPlayer("cancel-$leave") { proof ->
                LoopbackVideo(fixture.readBytes()).use { server ->
                    open(server.url)
                    awaitRetry()
                    val count = server.requests.get()
                    when (leave) {
                        "new-url" -> open(Uri.fromFile(fixture).toString())
                        "background" -> onMain { AppForeground.onStop() }
                        else -> invoke(leave)
                    }
                    val afterLeaving = activity.messenger.events.size
                    server.fail = false
                    // Plus long que le premier retry (1 s), sans réinitialiser
                    // son compteur ni supprimer ses messages dans le test.
                    SystemClock.sleep(2_500)
                    assertEquals("STALE_RETRY_AFTER_$leave", count, server.requests.get())
                    if (leave == "new-url") {
                        await("la nouvelle source joue") { onMain { player().isPlaying } }
                    } else {
                        assertFalse("aucune reprise après $leave", activity.messenger.events
                            .drop(afterLeaving).any { it.method == "playing" && it.arguments == true })
                    }
                    proof.put("http502Responses", server.failures.get())
                        .put("requestsAtLeave", count).put("requestsAfterWait", server.requests.get())
                }
            }
        }
    }

    @Test
    fun sameSourceDirectRebuild_keepsTrackPreferences_newUrlClearsOverrides() = withPlayer("track-rebuild") { proof ->
        open(Uri.fromFile(fixture).toString(), audio = "sv", text = "fr")
        await("première image et pistes vidéo") {
            activity.messenger.events.any { it.method == "firstFrame" } &&
                onMain { player().currentTracks.groups.any { it.type == C.TRACK_TYPE_VIDEO } }
        }
        val group = onMain { player().currentTracks.groups.indexOfFirst { it.type == C.TRACK_TYPE_VIDEO } }
        invoke("selectTrack", mapOf("group" to group, "index" to 0))
        invoke("disableText")
        invoke("pause")
        val old = onMain { player() }
        val before = onMain { old.trackSelectionParameters }
        assertTrue("la piste de la vraie mire est sélectionnée explicitement", before.overrides.isNotEmpty())
        assertEquals(listOf("fr"), before.preferredTextLanguages.toList())
        assertTrue(before.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))

        // Déclencher le vrai chemin complet de repli. Il ne s'agit PAS d'une
        // preuve de rendu HDR : seule la conservation de l'état est testée.
        val requested = onMain {
            val method = NativeVideoView::class.java.getDeclaredMethod("requestContrastDirectFallback", String::class.java)
            method.isAccessible = true
            method.invoke(activity.nativeView, "instrumented_state_check") as Boolean
        }
        assertTrue("reconstruction directe demandée", requested)
        await("nouveau lecteur préparé sur la même source") {
            onMain { player() !== old && player().playbackState == Player.STATE_READY }
        }
        onMain {
            assertEquals("TRACK_PREFERENCES_LOST_ON_REBUILD", before, player().trackSelectionParameters)
            assertFalse("la reconstruction respecte la pause", player().playWhenReady)
        }
        val other = File(activity.cacheDir, "different-source.mp4")
        fixture.copyTo(other, overwrite = true)
        open(Uri.fromFile(other).toString(), audio = "en", text = "en")
        await("nouvelle URL prête") { onMain { player().isPlaying } }
        onMain {
            assertTrue("aucun ancien groupe imposé à la nouvelle URL", player().trackSelectionParameters.overrides.isEmpty())
            assertEquals(listOf("en"), player().trackSelectionParameters.preferredTextLanguages.toList())
        }
        proof.put("preferredTextBeforeAndAfter", "fr")
            .put("textDisabledBeforeAndAfter", true)
            .put("newSourceOverrides", 0)
    }

    private fun withPlayer(name: String, exercise: (JSONObject) -> Unit) {
        onMain { AppForeground.debugReset() }
        val intent = Intent(instrumentation.context, ContrastTestActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val scenario = ActivityScenario.launch<ContrastTestActivity>(intent)
        val proof = JSONObject().put("case", name).put("passed", false)
        var output: File? = null
        try {
            scenario.onActivity { activity = it }
            output = File(activity.getExternalFilesDir(null), "contrast-pixels/recovery").apply { mkdirs() }
            fixture = File(activity.cacheDir, "contrast_sdr.mp4")
            instrumentation.context.assets.open("contrast_sdr.mp4").use { source ->
                fixture.outputStream().use { target -> source.copyTo(target) }
            }
            exercise(proof)
            proof.put("passed", true)
        } finally {
            if (::activity.isInitialized) {
                proof.put("events", JSONArray(activity.messenger.events.map {
                    JSONObject().put("method", it.method).put("arguments", it.arguments?.toString())
                }))
            }
            output?.let { File(it, "$name.json").writeText(proof.toString(2)) }
            scenario.close()
            onMain { AppForeground.debugReset() }
        }
    }

    private fun open(url: String, startMs: Long = 0, audio: String? = null, text: String? = null) {
        invoke("setUrl", mapOf("url" to url, "vod" to true, "startMs" to startMs, "epoch" to 1,
            "preferredAudio" to audio, "preferredText" to text))
    }

    private fun invoke(method: String, arguments: Any? = null) = onMain {
        var answered = false
        var failure: String? = null
        activity.nativeView.onMethodCall(MethodCall(method, arguments), object : MethodChannel.Result {
            override fun success(result: Any?) { answered = true }
            override fun error(code: String, message: String?, details: Any?) { failure = "$code : $message" }
            override fun notImplemented() { failure = "commande inconnue : $method" }
        })
        assertEquals("commande $method", null, failure)
        // La mire est muette : dispose ne doit pas attendre d'AudioTrack.
        assertTrue("réponse à $method", answered)
    }

    private fun awaitRetry() = await("l'erreur 502 atteint le retry NATIF") {
        activity.messenger.events.any { it.method == "reconnecting" && it.arguments == true } && onMain {
            // Le message peut déjà dater d'un essai : viser une attente encore
            // armée, pas la requête interne Media3 qui vient de repartir.
            val field = NativeVideoView::class.java.getDeclaredField("reconnect")
            field.isAccessible = true
            (field.get(activity.nativeView) as ReconnectGate).retryPending
        }
    }

    private fun await(label: String, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 60_000
        while (SystemClock.elapsedRealtime() < deadline) {
            assertFalse("moteurs épuisés pendant $label", activity.messenger.events.any { it.method == "engineExhausted" })
            if (condition()) return
            SystemClock.sleep(25)
        }
        throw AssertionError("Délai dépassé : $label")
    }

    private fun player(): ExoPlayer = NativeVideoView::class.java.getDeclaredField("player").run {
        isAccessible = true
        get(activity.nativeView) as ExoPlayer
    }

    private fun <T> onMain(action: () -> T): T {
        val result = AtomicReference<T>()
        val failure = AtomicReference<Throwable>()
        // Une assertion reste une erreur JUnit, elle ne doit pas tuer le main
        // thread de l'activité et se déguiser en crash de l'instrumentation.
        instrumentation.runOnMainSync {
            try { result.set(action()) } catch (error: Throwable) { failure.set(error) }
        }
        failure.get()?.let { throw it }
        return result.get()
    }
}

/** Serveur de test borné au loopback, réponses 502 puis MP4 avec Range. */
private class LoopbackVideo(private val video: ByteArray) : Closeable {
    private val socket = ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))
    @Volatile var fail = true
    val requests = AtomicInteger()
    val failures = AtomicInteger()
    val successes = AtomicInteger()
    val url = "http://127.0.0.1:${socket.localPort}/video.mp4"
    private val errors = CopyOnWriteArrayList<Exception>()
    private val worker = thread(name = "zuno-loopback-video", isDaemon = true) {
        while (!socket.isClosed) {
            try {
                socket.accept().use { client ->
                    client.soTimeout = 3_000
                    val input = client.getInputStream().bufferedReader(Charsets.US_ASCII)
                    input.readLine() ?: return@use
                    var offset = 0
                    while (true) {
                        val line = input.readLine() ?: break
                        if (line.isEmpty()) break
                        if (line.startsWith("Range:", ignoreCase = true)) {
                            offset = Regex("bytes=(\\d+)-").find(line)?.groupValues?.get(1)?.toInt() ?: 0
                        }
                    }
                    requests.incrementAndGet()
                    val output = client.getOutputStream()
                    if (fail) {
                        failures.incrementAndGet()
                        output.write("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray(Charsets.US_ASCII))
                    } else {
                        offset = offset.coerceIn(0, video.size - 1)
                        val status = if (offset > 0) "206 Partial Content" else "200 OK"
                        val range = if (offset > 0) "Content-Range: bytes $offset-${video.size - 1}/${video.size}\r\n" else ""
                        output.write(("HTTP/1.1 $status\r\nContent-Type: video/mp4\r\nAccept-Ranges: bytes\r\n" +
                            "Content-Length: ${video.size - offset}\r\n${range}Connection: close\r\n\r\n").toByteArray(Charsets.US_ASCII))
                        output.write(video, offset, video.size - offset)
                        successes.incrementAndGet()
                    }
                    output.flush()
                }
            } catch (error: SocketException) {
                if (!socket.isClosed) errors.add(error)
            } catch (error: Exception) {
                errors.add(error)
            }
        }
    }

    override fun close() {
        socket.close()
        worker.join(4_000)
        check(!worker.isAlive) { "Serveur loopback non arrêté." }
        // Une fermeture de lecture par ExoPlayer au zap peut rompre la socket ;
        // les assertions portent sur requêtes, reprises et état du vrai lecteur.
    }
}
