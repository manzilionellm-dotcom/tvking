package com.manzilionellm.native_video_player

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.ViewGroup
import android.view.WindowManager
import androidx.media3.common.util.UnstableApi
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import com.manzilionellm.native_video_player.logic.AppForeground
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs
import kotlin.math.min
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Le transport Flutter est remplacé ; le lecteur, MediaCodec et Media3 restent réels. */
internal class CaptureMessenger : BinaryMessenger {
    val events = CopyOnWriteArrayList<MethodCall>()

    override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)

    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
        if (message != null) {
            val bytes = message.duplicate()
            // encodeMethodCall laisse la position à la fin, comme attendu par FlutterJNI.
            if (bytes.position() > 0) bytes.flip()
            events.add(StandardMethodCodec.INSTANCE.decodeMethodCall(bytes))
        }
        callback?.reply(StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(null))
    }

    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit
}

/** Activité embarquée uniquement dans l'APK de test, sans moteur Flutter ni réseau. */
@UnstableApi
class ContrastTestActivity : Activity() {
    internal val messenger = CaptureMessenger()
    internal lateinit var nativeView: NativeVideoView
    internal lateinit var surface: SurfaceView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or WindowManager.LayoutParams.FLAG_FULLSCREEN)
        nativeView = NativeVideoView(this, messenger, 91001)
        val root = nativeView.getView() as ViewGroup
        surface = (0 until root.childCount).map(root::getChildAt).filterIsInstance<SurfaceView>().single()
        setContentView(root)
    }

    override fun onResume() {
        super.onResume()
        AppForeground.onResume()
    }

    override fun onDestroy() {
        if (::nativeView.isInitialized) nativeView.dispose()
        super.onDestroy()
    }
}

/**
 * Régression du chemin de production, pas de la valeur d'un interrupteur.
 * Le premier rendu est capturé SANS setContrast : sortie directe du
 * décodeur, aucun graphe GL. Allumer le contraste rouvre la chaîne avec le
 * graphe GL et doit changer les vrais pixels ; le couper rouvre en direct
 * et rend la même image qu'au départ. Un retour au vieux
 * hardwareAllows=false laisse ON et OFF identiques et fait échouer ce test.
 */
@UnstableApi
@RunWith(AndroidJUnit4::class)
@SdkSuppress(minSdkVersion = 29)
class NativeContrastPixelTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val main = Handler(Looper.getMainLooper())
    private lateinit var activity: ContrastTestActivity
    private lateinit var evidence: File
    private val measures = JSONObject()

    // Chaque bascule du graphe GL rouvre la chaîne une fois. Un repli
    // (graphe bloqué, image noire) ajouterait une réouverture de plus.
    private var expectedReopens = 0

    @Test
    fun defaultOff_directPixels_onChangesRealPixels_offRestoresTheSameFrame() {
        val intent = Intent(instrumentation.context, ContrastTestActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val scenario = ActivityScenario.launch<ContrastTestActivity>(intent)
        try {
            scenario.onActivity { activity = it }
            evidence = File(activity.getExternalFilesDir(null), "contrast-pixels").apply { mkdirs() }
            val fixture = File(activity.cacheDir, "contrast_sdr.mp4")
            instrumentation.context.assets.open("contrast_sdr.mp4").use { source ->
                fixture.outputStream().use { target -> source.copyTo(target) }
            }
            invoke("setUrl", mapOf("url" to Uri.fromFile(fixture).toString(), "vod" to true, "epoch" to 1))
            await("première image native") { activity.messenger.events.any { it.method == "firstFrame" } }
            await("dimensions du décodeur en sortie directe") { sizeOriginSince(0, "renderer_callback") }
            assertFalse("sortie directe par défaut, sans graphe GL", glPipelineInstalled())

            val defaultOff = captureWhen("01-default-off") { it.visible() }
            assertFalse("aucune sortie GL sans contraste", sizeOriginSince(0, "gl_output"))

            val onAt = switchContrast(true)
            await("dimensions de sortie GL réelles") { sizeOriginSince(onAt, "gl_output") }
            // Le contraste positif assombrit les basses lumières et éclaircit les hautes.
            // Aucun calcul reproduisant la matrice Media3 : on mesure les pixels affichés.
            val on = captureWhen("02-on", failureLabel = "PIXEL_CONTRAST_NOT_APPLIED") {
                it.visible() && it.dark < defaultOff.dark - 2.0 && it.bright > defaultOff.bright + 2.0
            }
            val offAt = switchContrast(false)
            await("dimensions du décodeur après retour direct") { sizeOriginSince(offAt, "renderer_callback") }
            val offAgain = captureWhen("03-off-again") {
                it.visible() && it.dark > on.dark + 2.0 && it.bright < on.bright - 2.0
            }
            val onAgainAt = switchContrast(true)
            await("dimensions de sortie GL après rallumage") { sizeOriginSince(onAgainAt, "gl_output") }
            val onAgain = captureWhen("04-on-again") {
                it.visible() && it.dark < offAgain.dark - 2.0 && it.bright > offAgain.bright + 2.0
            }

            listOf(on, offAgain, onAgain).forEach {
                assertEquals("largeur conservée", defaultOff.bitmap.width, it.bitmap.width)
                assertEquals("hauteur conservée", defaultOff.bitmap.height, it.bitmap.height)
            }
            val offDifference = averageDifference(defaultOff.bitmap, offAgain.bitmap)
            val onDifference = averageDifference(on.bitmap, onAgain.bitmap)
            measures.put("default_off_vs_off_again_mean_absolute_rgb", offDifference)
            measures.put("on_vs_on_again_mean_absolute_rgb", onDifference)
            assertTrue("OFF restaure l'image directe de départ : $offDifference", offDifference <= 2.0)
            assertTrue("ON reproduit le premier rendu contrasté : $onDifference", onDifference <= 2.0)
            assertNoPlayerFailure()
            assertEquals("une réouverture par bascule du graphe GL", expectedReopens,
                activity.messenger.events.count { it.method == "reopen" })
            val sizes = activity.messenger.events.filter { it.method == "videoSize" }
                .mapNotNull { it.arguments as? Map<*, *> }
            for (origin in listOf("renderer_callback", "gl_output")) {
                assertTrue("la sortie $origin de la mire garde ses 256 × 144 pixels", sizes.any {
                    (it["width"] as? Number)?.toInt() == 256 &&
                        (it["height"] as? Number)?.toInt() == 144 && it["origin"] == origin
                })
            }
            val sources = activity.messenger.events.filter { it.method == "videoSource" }
                .mapNotNull { it.arguments as? Map<*, *> }
            assertTrue("le format source reste une information distincte de la sortie", sources.any {
                (it["width"] as? Number)?.toInt() == 256 &&
                    (it["height"] as? Number)?.toInt() == 144 && it["mimeType"] == "video/avc"
            })
            measures.put("passed", true)
        } finally {
            if (::evidence.isInitialized) {
                measures.put("events", JSONArray(activity.messenger.events.map {
                    JSONObject().put("method", it.method).put("arguments", it.arguments?.toString())
                }))
                File(evidence, "measurements.json").writeText(measures.toString(2))
            }
            scenario.close()
        }
    }

    private fun invoke(method: String, arguments: Any?) {
        val done = CountDownLatch(1)
        var failure: String? = null
        instrumentation.runOnMainSync {
            activity.nativeView.onMethodCall(MethodCall(method, arguments), object : MethodChannel.Result {
                override fun success(result: Any?) { done.countDown() }
                override fun error(code: String, message: String?, details: Any?) {
                    failure = "$code : $message"
                    done.countDown()
                }
                override fun notImplemented() {
                    failure = "commande inconnue : $method"
                    done.countDown()
                }
            })
        }
        assertTrue("réponse native à $method", done.await(10, TimeUnit.SECONDS))
        assertEquals("commande $method", null, failure)
    }

    private fun assertNoPlayerFailure() {
        val failures = activity.messenger.events.filter {
            it.method == "error" || it.method == "engineExhausted" ||
                (it.method == "reconnecting" && it.arguments == true)
        }
        assertTrue("aucune erreur/reconnexion : ${failures.map { it.method to it.arguments }}", failures.isEmpty())
        val reopens = activity.messenger.events.count { it.method == "reopen" }
        assertTrue("reconstruction imprévue : $reopens pour $expectedReopens bascules", reopens <= expectedReopens)
    }

    /** @return l'index des événements à partir duquel lire le nouveau lecteur. */
    private fun switchContrast(enabled: Boolean): Int {
        val from = activity.messenger.events.size
        expectedReopens++
        invoke("setContrast", enabled)
        await("lecteur rouvert ${if (enabled) "avec" else "sans"} graphe GL") {
            activity.messenger.events.drop(from).any { it.method == "reopen" } &&
                glPipelineInstalled() == enabled
        }
        return from
    }

    private fun sizeOriginSince(from: Int, origin: String): Boolean =
        activity.messenger.events.drop(from).any {
            it.method == "videoSize" && (it.arguments as? Map<*, *>)?.get("origin") == origin
        }

    private fun glPipelineInstalled(): Boolean {
        var installed = false
        instrumentation.runOnMainSync {
            val field = NativeVideoView::class.java.getDeclaredField("contrastPipelineInstalled")
            field.isAccessible = true
            installed = field.getBoolean(activity.nativeView)
        }
        return installed
    }

    private fun await(label: String, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 20_000
        while (SystemClock.elapsedRealtime() < deadline) {
            assertNoPlayerFailure()
            if (condition()) return
            SystemClock.sleep(100)
        }
        throw AssertionError("Délai dépassé : $label")
    }

    private data class Pixels(val bitmap: Bitmap, val patches: List<Double>) {
        val dark get() = patches.first()
        val bright get() = patches.last()
        fun visible() = bright > 150 && bright - dark > 100
    }

    private fun captureWhen(label: String, failureLabel: String = "pixels $label", accept: (Pixels) -> Boolean): Pixels {
        var accepted: Pixels? = null
        var previous: Pixels? = null
        var stable = 0
        await(failureLabel) {
            val bitmap = copySurface() ?: return@await false
            val pixels = Pixels(bitmap, patchMeans(bitmap))
            val before = previous
            stable = if (accept(pixels) && before != null &&
                pixels.patches.zip(before.patches).all { (a, b) -> abs(a - b) <= 1.0 }) stable + 1 else 0
            previous = pixels
            before?.bitmap?.recycle()
            // Conserve aussi le dernier résultat en cas d'échec (mire identique ou noire).
            File(evidence, "$label.png").outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
            measures.put(label, JSONObject().put("width", bitmap.width).put("height", bitmap.height)
                .put("patch_mean_rgb", JSONArray(pixels.patches)))
            if (stable >= 3) accepted = pixels
            accepted != null
        }
        return checkNotNull(accepted)
    }

    private fun copySurface(): Bitmap? {
        var bitmap: Bitmap? = null
        val done = CountDownLatch(1)
        val status = AtomicInteger(PixelCopy.ERROR_SOURCE_NO_DATA)
        instrumentation.runOnMainSync {
            val surface = activity.surface
            if (surface.width <= 0 || surface.height <= 0 || !surface.holder.surface.isValid) {
                done.countDown()
                return@runOnMainSync
            }
            bitmap = Bitmap.createBitmap(surface.width, surface.height, Bitmap.Config.ARGB_8888)
            PixelCopy.request(surface, bitmap!!, { result -> status.set(result); done.countDown() }, main)
        }
        assertTrue("PixelCopy répond", done.await(5, TimeUnit.SECONDS))
        if (status.get() != PixelCopy.SUCCESS) {
            bitmap?.recycle()
            return null
        }
        return bitmap
    }

    private fun patchMeans(bitmap: Bitmap): List<Double> {
        // SCALE_TO_FIT peut ajouter des bandes noires : on reste au centre de la vidéo.
        val videoWidth = min(bitmap.width.toDouble(), bitmap.height * 256.0 / 144.0)
        val left = (bitmap.width - videoWidth) / 2
        return (0..3).map { patch ->
            val x = (left + videoWidth * (patch + 0.5) / 4).toInt()
            val y = bitmap.height / 2
            var sum = 0.0
            for (dy in -4..4) for (dx in -4..4) {
                val pixel = bitmap.getPixel(x + dx, y + dy)
                sum += (Color.red(pixel) + Color.green(pixel) + Color.blue(pixel)) / 3.0
            }
            sum / 81
        }
    }

    private fun averageDifference(a: Bitmap, b: Bitmap): Double {
        assertFalse("image lisible", a.isRecycled || b.isRecycled)
        var sum = 0.0
        var count = 0
        // Échantillonnage uniforme, comprenant aussi les contours et les bandes noires.
        for (y in 0 until a.height step 4) for (x in 0 until a.width step 4) {
            val p = a.getPixel(x, y)
            val q = b.getPixel(x, y)
            sum += abs(Color.red(p) - Color.red(q)) + abs(Color.green(p) - Color.green(q)) +
                abs(Color.blue(p) - Color.blue(q))
            count += 3
        }
        return sum / count
    }
}
