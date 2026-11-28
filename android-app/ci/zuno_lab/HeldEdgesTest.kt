package com.manzilionellm.native_video_player

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.SystemClock
import androidx.media3.common.util.UnstableApi
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith

/** Exerce la copie de la vraie surface vidéo sur une mire aux quatre coins distincts. */
@UnstableApi
@RunWith(AndroidJUnit4::class)
class HeldEdgesTest {
    @Test fun quatreBordsDeLaMire() {
        val inst = InstrumentationRegistry.getInstrumentation()
        val launch = Intent(inst.context, ContrastTestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ActivityScenario.launch<ContrastTestActivity>(launch).use { scenario ->
            scenario.onActivity { act ->
                val movie = File(act.cacheDir, "edges.mp4")
                inst.context.assets.open(movie.name).use { input ->
                    movie.outputStream().use { output -> input.copyTo(output) }
                }
                val args = mapOf("url" to Uri.fromFile(movie).toString(), "vod" to true, "epoch" to 1)
                act.nativeView.onMethodCall(MethodCall("setUrl", args), object : MethodChannel.Result {
                    override fun success(result: Any?) {}
                    override fun error(code: String, msg: String?, details: Any?) { throw AssertionError(code) }
                    override fun notImplemented() { throw AssertionError("setUrl") }
                })
            }
            val end = SystemClock.elapsedRealtime() + 45000
            var samples: List<Int>? = null
            while (samples == null && SystemClock.elapsedRealtime() < end) {
                SystemClock.sleep(100)
                scenario.onActivity { act ->
                    val field = NativeVideoView::class.java.getDeclaredField("heldBitmap")
                    field.isAccessible = true
                    val bmp = field.get(act.nativeView) as? Bitmap ?: return@onActivity
                    if (bmp.isRecycled) return@onActivity
                    val w = bmp.width
                    val h = bmp.height
                    val pixels = listOf(bmp.getPixel(w/20, h/20), bmp.getPixel(w*19/20, h/20),
                        bmp.getPixel(w/20, h*19/20), bmp.getPixel(w*19/20, h*19/20))
                    val dir = File(act.getExternalFilesDir(null), "held-edges").apply { mkdirs() }
                    File(dir, "held.png").outputStream().use { output ->
                        bmp.compress(Bitmap.CompressFormat.PNG, 100, output)
                    }
                    samples = pixels
                    File(dir, "pixel-rgb.txt").writeText(pixels.joinToString(" ") { color ->
                        "%02x%02x%02x".format(Color.red(color), Color.green(color), Color.blue(color))
                    } + "\n")
                }
            }
            assertNotNull("Aucune copie exploitable rendue par Android", samples)
            val signature = samples!!.map { c ->
                val r = Color.red(c); val g = Color.green(c); val b = Color.blue(c)
                when {
                    r > g + 50 && r > b + 50 -> "R"
                    g > r + 40 && g > b + 40 -> "G"
                    b > r + 50 && b > g + 50 -> "B"
                    r > b + 60 && g > b + 60 -> "Y"
                    else -> "?"
                }
            }
            assertEquals("ZUNO_HELD_CORNERS", listOf("R", "G", "B", "Y"), signature)
        }
    }
}
