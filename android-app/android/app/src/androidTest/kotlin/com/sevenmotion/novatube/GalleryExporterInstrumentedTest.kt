package com.sevenmotion.novatube

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.provider.MediaStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.DataInputStream
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Vérification sur Android réel (émulateur CI) : aucun flux ni contenu tiers.
 * Les deux clips sont créés par ffmpeg à partir d'une mire et d'une sinusoïde.
 * On passe par le même MethodCall que Flutter puis on relit le fichier public
 * avec MediaExtractor. Un nom terminé par .mp4 ne suffit pas à réussir.
 */
@RunWith(AndroidJUnit4::class)
class GalleryExporterInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext
    private val files = mutableListOf<File>()
    private val publicNames = mutableListOf<String>()

    private class Outcome(val value: Any?, val error: String?)

    // Le transport Flutter n'est pas lancé : seul le message public du bridge
    // est appelé, avec les vraies API Android, les vrais codecs et MediaStore.
    private val messenger = object : BinaryMessenger {
        override fun send(channel: String, message: ByteBuffer?) = Unit
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            callback?.reply(null)
        }
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit
    }

    private fun source(asset: String): File {
        val file = File(context.cacheDir, "novatube-export-test-${System.nanoTime()}.ts")
        instrumentation.context.assets.open(asset).use { input ->
            file.outputStream().use { output -> input.copyTo(output) }
        }
        files.add(file)
        return file
    }

    private fun export(file: File): Pair<String, Outcome> {
        val name = "NOVATUBE_CI_EXPORT_${System.nanoTime()}.mp4"
        publicNames.add(name)
        val latch = CountDownLatch(1)
        val outcome = AtomicReference<Outcome>()
        instrumentation.runOnMainSync {
            GalleryExporter(messenger, context).onMethodCall(
                MethodCall("exportVideo", mapOf("srcPath" to file.absolutePath, "displayName" to name)),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        outcome.set(Outcome(result, null)); latch.countDown()
                    }
                    override fun error(code: String, message: String?, details: Any?) {
                        outcome.set(Outcome(null, code)); latch.countDown()
                    }
                    override fun notImplemented() {
                        outcome.set(Outcome(null, "NOT_IMPLEMENTED")); latch.countDown()
                    }
                },
            )
        }
        assertTrue("L'export Android doit se terminer", latch.await(90, TimeUnit.SECONDS))
        return name to outcome.get()
    }

    private fun exportedRows(name: String): List<Uri> {
        val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val result = mutableListOf<Uri>()
        context.contentResolver.query(
            collection, arrayOf(MediaStore.Video.Media._ID),
            "${MediaStore.Video.Media.DISPLAY_NAME} = ?", arrayOf(name), null,
        )!!.use { cursor ->
            while (cursor.moveToNext()) {
                result.add(Uri.withAppendedPath(collection, cursor.getLong(0).toString()))
            }
        }
        return result
    }

    private fun assertCompatibleVideo(name: String) {
        val rows = exportedRows(name)
        assertEquals("Une seule vidéo publique doit être créée", 1, rows.size)
        val uri = rows.single()
        context.contentResolver.query(
            uri, arrayOf(MediaStore.Video.Media.MIME_TYPE, MediaStore.Video.Media.IS_PENDING,
                MediaStore.Video.Media.SIZE), null, null, null,
        )!!.use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("video/mp4", cursor.getString(0))
            assertEquals("Le fichier doit être visible après copie complète", 0, cursor.getInt(1))
        }
        context.contentResolver.openAssetFileDescriptor(uri, "r")!!.use { descriptor ->
            assertTrue("La copie publique doit contenir des octets", descriptor.length > 0L)
        }
        context.contentResolver.openInputStream(uri)!!.use { input ->
            val header = ByteArray(12)
            DataInputStream(input).readFully(header)
            assertEquals("Vrai conteneur MP4", "ftyp", String(header, 4, 4, Charsets.US_ASCII))
        }
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(context, uri, null)
            val formats = (0 until extractor.trackCount).map { extractor.getTrackFormat(it) }
            val video = formats.single { it.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true }
            val audio = formats.single { it.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true }
            assertEquals(MediaFormat.MIMETYPE_VIDEO_AVC, video.getString(MediaFormat.KEY_MIME))
            assertEquals(MediaFormat.MIMETYPE_AUDIO_AAC, audio.getString(MediaFormat.KEY_MIME))
            assertEquals("Largeur source conservée", 160, video.getInteger(MediaFormat.KEY_WIDTH))
            assertEquals("Hauteur source conservée", 90, video.getInteger(MediaFormat.KEY_HEIGHT))
            assertEquals(48000, audio.getInteger(MediaFormat.KEY_SAMPLE_RATE))
            for (track in formats.indices) {
                extractor.selectTrack(track)
                extractor.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                var samples = 0
                val buffer = ByteBuffer.allocate(1024 * 1024)
                while (extractor.readSampleData(buffer, 0) >= 0) {
                    samples++
                    if (!extractor.advance()) break
                    buffer.clear()
                }
                assertTrue("Une piste annoncée doit contenir des échantillons", samples > 10)
                extractor.unselectTrack(track)
            }
        } finally {
            extractor.release()
        }
    }

    @Test
    fun h264AacRecordingIsSavedAsReadablePublicMp4() {
        val (name, result) = export(source("novatube-h264-aac.ts"))
        assertNull(result.error)
        assertEquals(true, result.value)
        assertCompatibleVideo(name)
    }

    @Test
    fun hevcRecordingIsConvertedToH264WithAudio() {
        val (name, result) = export(source("novatube-hevc-aac.ts"))
        assertNull(result.error)
        assertEquals(true, result.value)
        assertCompatibleVideo(name)
    }

    @Test
    fun playlistTextIsNeverPublishedAsAnMp4() {
        val source = File(context.cacheDir, "novatube-invalid-${System.nanoTime()}.ts")
        source.writeText("#EXTM3U\n#EXT-X-VERSION:3\n")
        files.add(source)
        val (name, result) = export(source)
        assertNotNull(result.error)
        assertNotEquals(true, result.value)
        assertTrue("Aucun faux MP4 ne doit apparaître dans la galerie", exportedRows(name).isEmpty())
    }

    @After
    fun removeOnlySyntheticTestMedia() {
        for (name in publicNames) {
            for (uri in exportedRows(name)) context.contentResolver.delete(uri, null, null)
        }
        files.forEach { it.delete() }
    }
}
