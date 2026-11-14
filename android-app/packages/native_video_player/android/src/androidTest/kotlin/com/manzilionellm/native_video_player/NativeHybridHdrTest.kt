package com.manzilionellm.native_video_player

import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import com.manzilionellm.native_video_player.logic.AppForeground
import com.manzilionellm.native_video_player.logic.HybridHdr
import com.manzilionellm.native_video_player.logic.HybridHdrFilter
import com.manzilionellm.native_video_player.logic.HybridHdrScope
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Film « Dolby Vision + HDR10+ » dans le VRAI lecteur : NativeVideoView,
 * Media3, l'extracteur Matroska et un vrai décodeur HEVC Android. Seul le
 * transport Flutter est remplacé.
 *
 * La mire (ci/generate_hybrid_hdr_fixture.py) porte un message HDR10+ et
 * une unité Dolby Vision sur CHAQUE image, comme les films 4K récents.
 * L'émulateur n'est pas une clé Amazon : [HybridHdr.forcedScope] dit au
 * lecteur de se comporter comme sur l'appareil en défaut.
 *
 * Ce test prouve que le filtre est bien branché avant le décodeur, qu'il
 * retire les deux jeux sur toutes les images et que la lecture continue.
 * Il ne prouve PAS l'image d'une clé Amazon MT8696 : aucun émulateur n'a
 * sa sortie HDMI. Ce qui part au décodeur est comparé octet par octet
 * dans logic-test (HybridHdrTest).
 */
@UnstableApi
@RunWith(AndroidJUnit4::class)
@SdkSuppress(minSdkVersion = 29)
class NativeHybridHdrTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private lateinit var activity: ContrastTestActivity
    private lateinit var fixture: File

    @Test
    fun autoFix_removesBothBeforeTheDecoder_playbackContinues() =
        withPlayer("hybrid-auto", HybridHdrScope.FIX) { proof ->
            open()
            val filter = awaitCleaning()
            assertEquals("niveau automatique", "AUTO", filter.mode.name)
            assertEquals("décodeur HEVC ordinaire", "HEVC_DECODER", filter.path.name)
            val lines = diagLines()
            assertTrue("HYBRID_CONTENT_NOT_REPORTED $lines", lines.any {
                it.startsWith("HDR du flux : Dolby Vision oui, HDR10+ oui (film hybride).")
            })
            assertTrue("HYBRID_FIX_NOT_REPORTED $lines", lines.any {
                it.startsWith("Correctif HDR (automatique) : Dolby Vision et HDR10+ retirés avant le décodeur HEVC")
            })
            assertTrue("ligne IMAGE du format et du décodeur $lines", lines.any {
                it.startsWith("Vidéo : video/hevc") && it.contains("256×144") && it.contains("Décodeur ")
            })
            // SAUT dans le film, comme le client : le décodeur est vidé puis
            // repart sur une image clé. Le nettoyage doit continuer après,
            // et le journal dit sur quelle image la lecture est repartie.
            val removedBefore = filter.removedDolbyVision
            invoke("seekTo", mapOf("ms" to 20_000L))
            await("lecture repartie après le saut à 20 s") {
                onMain { player().isPlaying && player().currentPosition >= 21_500 }
            }
            await("le filtre retire encore les deux jeux après le saut") {
                // Même décodeur vidé (cas courant) : le compteur continue.
                // Décodeur recréé par l'appareil : un filtre neuf repart de zéro.
                onMain { filterNow() }?.let {
                    it.removedDolbyVision >= (if (it === filter) removedBefore + 20L else 20L)
                } == true
            }
            // La mire x265 a des images clés ouvertes (type 21) après la première.
            assertTrue("SEEK_RESTART_NOT_REPORTED ${diagLines()}", diagLines().any {
                it == "Après un saut : reprise sur une image clé ouverte (type 21)."
            })
            proof.put("positionAfterSeek", onMain { player().currentPosition })
            finish(proof, filter)
        }

    @Test
    fun manualSetting_removesBothOnAnyDevice() =
        withPlayer("hybrid-manual", HybridHdrScope.NONE) { proof ->
            // Box ordinaire : rien d'automatique, la personne allume le réglage.
            invoke("setHdrCompat", true)
            open()
            val filter = awaitCleaning()
            assertEquals("niveau du réglage", "STRICT", filter.mode.name)
            val lines = diagLines()
            assertTrue("MANUAL_FIX_NOT_REPORTED $lines", lines.any {
                it.startsWith("Correctif HDR (réglage) : Dolby Vision et HDR10+ retirés avant le décodeur HEVC")
            })
            finish(proof, filter)
        }

    @Test
    fun fallbackSwitch_leavesTheStreamUntouched() =
        withPlayer("hybrid-off", HybridHdrScope.FIX) { proof ->
            // Interrupteur de repli : même sur l'appareil en défaut, le flux
            // part tel quel, comme avant ce correctif.
            invoke("setHybridHdrOff", true)
            open()
            awaitPlayback()
            assertNull("FILTER_ACTIVE_DESPITE_FALLBACK", onMain { filterNow() })
            val lines = diagLines()
            assertFalse("aucune ligne du correctif quand il est désarmé : $lines", lines.any {
                it.startsWith("HDR du flux") || it.startsWith("Correctif HDR")
            })
            assertTrue("la ligne IMAGE générale reste écrite $lines", lines.any { it.startsWith("Vidéo : video/hevc") })
            proof.put("position", onMain { player().currentPosition })
                .put("decoder", decoderName())
                .put("lines", JSONArray(lines))
        }

    /** Les deux compteurs montent ensemble, image après image, sans erreur. */
    private fun awaitCleaning(): HybridHdrFilter {
        awaitPlayback()
        await("le filtre retire les deux jeux sur les images en cours") {
            onMain { filterNow() }?.let { it.removedDolbyVision >= 30 && it.removedHdr10Plus >= 30 } == true
        }
        val filter = onMain { filterNow() } ?: throw AssertionError("HYBRID_FILTER_GONE")
        assertTrue("les deux jeux ont été vus", filter.sawDolbyVision && filter.sawHdr10Plus)
        // Une unité Dolby Vision et un message HDR10+ par image : aucun
        // n'est passé au travers (écart d'une image possible entre deux lectures).
        val gap = filter.removedDolbyVision - filter.removedHdr10Plus
        assertTrue(
            "HYBRID_COUNTS_DIVERGE ${filter.removedDolbyVision} / ${filter.removedHdr10Plus}",
            gap >= -1L && gap <= 1L,
        )
        return filter
    }

    private fun finish(proof: JSONObject, filter: HybridHdrFilter) {
        // La lecture continue APRÈS le nettoyage : l'image n'a pas été abîmée.
        val before = onMain { rendered() }
        val position = onMain { player().currentPosition }
        await("la lecture avance encore, images rendues") {
            onMain { rendered() >= before + 15 && player().currentPosition >= position + 1_000 }
        }
        assertNoFailure()
        proof.put("removedDolbyVision", filter.removedDolbyVision)
            .put("removedHdr10Plus", filter.removedHdr10Plus)
            .put("renderedFrames", onMain { rendered() })
            .put("position", onMain { player().currentPosition })
            .put("decoder", decoderName())
            .put("lines", JSONArray(diagLines()))
    }

    private fun awaitPlayback() {
        await("première image de la mire hybride") {
            activity.messenger.events.any { it.method == "firstFrame" }
        }
        await("trois secondes de lecture") { onMain { player().currentPosition >= 3_000 && rendered() >= 30 } }
        assertNoFailure()
    }

    private fun assertNoFailure() {
        val events = activity.messenger.events
        assertFalse("erreur de lecture", events.any { it.method == "error" })
        assertFalse("reconnexion pendant la mire locale", events.any {
            it.method == "reconnecting" && it.arguments == true
        })
        assertFalse("changement de moteur vidéo", events.any { it.method == "reopen" })
        assertFalse("filtre arrêté sur une image illisible", diagLines().any { it.startsWith("Correctif HDR arrêté") })
    }

    private fun diagLines(): List<String> =
        activity.messenger.events.filter { it.method == "videoDiag" }.map { it.arguments.toString() }

    private fun decoderName(): String =
        activity.messenger.events.lastOrNull { it.method == "videoDecoder" }?.arguments?.toString().orEmpty()

    private fun rendered(): Int = player().videoDecoderCounters?.let {
        it.ensureUpdated()
        it.renderedOutputBufferCount
    } ?: 0

    /** Filtre du rendu vidéo en cours, ou null s'il n'est pas actif. */
    private fun filterNow(): HybridHdrFilter? {
        val exo = player()
        for (index in 0 until exo.rendererCount) {
            val renderer = exo.getRenderer(index)
            if (renderer.javaClass.simpleName != "HybridHdrVideoRenderer") continue
            val field = renderer.javaClass.getDeclaredField("filter")
            field.isAccessible = true
            return field.get(renderer) as HybridHdrFilter?
        }
        throw AssertionError("HYBRID_RENDERER_NOT_INSTALLED")
    }

    private fun withPlayer(name: String, scope: HybridHdrScope, exercise: (JSONObject) -> Unit) {
        onMain { AppForeground.debugReset() }
        // Avant l'activité : le lecteur lit l'appareil à sa construction.
        HybridHdr.forcedScope = scope
        HybridHdr.manual = false
        HybridHdr.autoOff = false
        val intent = Intent(instrumentation.context, ContrastTestActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val scenario = ActivityScenario.launch<ContrastTestActivity>(intent)
        val proof = JSONObject().put("case", name).put("passed", false)
        var output: File? = null
        try {
            scenario.onActivity { activity = it }
            output = File(activity.getExternalFilesDir(null), "contrast-pixels/hybrid-hdr").apply { mkdirs() }
            fixture = File(activity.cacheDir, "hybrid_hdr.mkv")
            instrumentation.context.assets.open("hybrid_hdr.mkv").use { source ->
                fixture.outputStream().use { target -> source.copyTo(target) }
            }
            exercise(proof)
            proof.put("passed", true)
        } finally {
            if (::activity.isInitialized) {
                proof.put("events", JSONArray(activity.messenger.events
                    .filter { it.method != "position" && it.method != "videoCadence" }
                    .map { JSONObject().put("method", it.method).put("arguments", it.arguments?.toString()) }))
            }
            output?.let { File(it, "$name.json").writeText(proof.toString(2)) }
            scenario.close()
            // Réglages du processus : les autres classes de test repartent
            // d'une box ordinaire, correctif armé, réglage coupé.
            HybridHdr.forcedScope = null
            HybridHdr.manual = false
            HybridHdr.autoOff = false
            onMain { AppForeground.debugReset() }
        }
    }

    private fun open() {
        invoke("setUrl", mapOf("url" to Uri.fromFile(fixture).toString(), "vod" to true, "startMs" to 0L, "epoch" to 1))
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
        assertTrue("réponse à $method", answered)
    }

    private fun await(label: String, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 60_000
        while (SystemClock.elapsedRealtime() < deadline) {
            assertFalse("moteurs épuisés pendant $label", activity.messenger.events.any { it.method == "engineExhausted" })
            if (condition()) return
            SystemClock.sleep(25)
        }
        throw AssertionError("Délai dépassé : $label · lignes : ${diagLines()}")
    }

    private fun player(): ExoPlayer = NativeVideoView::class.java.getDeclaredField("player").run {
        isAccessible = true
        get(activity.nativeView) as ExoPlayer
    }

    private fun <T> onMain(action: () -> T): T {
        val result = AtomicReference<T>()
        val failure = AtomicReference<Throwable>()
        instrumentation.runOnMainSync {
            try { result.set(action()) } catch (error: Throwable) { failure.set(error) }
        }
        failure.get()?.let { throw it }
        return result.get()
    }
}
