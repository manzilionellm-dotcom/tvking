// =========================================================
//  GalleryExporter.kt — Export d'enregistrements vers la Galerie
// =========================================================
//  Sur Android moderne (10+), les apps n'ont plus accès au stockage
//  externe librement (`scoped storage`). Pour qu'un fichier apparaisse
//  dans la GALERIE PHOTO native du téléphone, il faut passer par
//  MediaStore.Video.Media qui gère automatiquement :
//    - L'indexation du fichier dans la base de données médias
//    - L'apparition dans Galerie, Files, Photos
//    - La survie après désinstallation de l'app
//
//  Méthode exposée :
//    - exportVideo(srcPath, displayName) : bool
//      Convertit l'enregistrement en VRAI MP4 H.264/AAC puis le
//      range dans Movies/ via MediaStore. Retourne true si OK.
//
//  H.264 + AAC compatibles : remux sans ré-encodage ni perte de qualité.
//  Autres codecs : conversion native, si les codecs du téléphone le permettent.
//  Un TS renommé MP4, une piste sonore perdue ou une copie partielle sont
//  des ÉCHECS. Le fichier original reste toujours conservé dans l'application.
//
//  Tout tourne sur un thread d'ARRIÈRE-PLAN (le transcodage peut durer
//  plusieurs secondes) ; le résultat est renvoyé à Flutter sur le thread
//  principal. On ne touche PAS au pipeline d'enregistrement / de lecture.
// =========================================================

package com.sevenmotion.novatube

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.util.Log
import android.view.Surface
import androidx.media3.exoplayer.MediaExtractorCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.DataInputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.Executors

class GalleryExporter(
    messenger: BinaryMessenger,
    private val context: Context,
    private val activity: Activity? = null,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "GalleryExporter"
        private const val CHANNEL = "com.manzilionellm.tvking/gallery"
        // Taille plancher du tampon de copie d'échantillon (remux). Une
        // I-frame 4K peut dépasser 1 MiB ; on prend large pour ne pas
        // lever "buffer too small" sur readSampleData.
        private const val MIN_BUFFER_BYTES = 4 * 1024 * 1024

        // Délai d'attente unitaire des opérations MediaCodec (µs).
        private const val CODEC_TIMEOUT_US = 10_000L
        private const val STORAGE_REQUEST_CODE = 55021
    }

    private val channel: MethodChannel =
        MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler(this@GalleryExporter)
        }

    // Le transcodage est lourd → thread dédié. Les callbacks Flutter
    // doivent revenir sur le thread principal (mainHandler).
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var exporting = false
    private var pendingPermission: Pair<Map<String, Any?>, MethodChannel.Result>? = null

    private class ExportFailure(val code: String, message: String) : IOException(message)

    private data class SourceTracks(
        val videoTrack: Int,
        val videoFormat: MediaFormat,
        val audioTrack: Int,
        val audioFormat: MediaFormat?,
    ) {
        val hasAudio: Boolean get() = audioFormat != null
    }

    /** Résultat interne d'un export, traduit ensuite en result.success/error. */
    private class ExportOutcome private constructor(
        val ok: Boolean,
        val code: String?,
        val message: String?,
    ) {
        companion object {
            fun success() = ExportOutcome(true, null, null)
            fun error(code: String, message: String?) = ExportOutcome(false, code, message)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "exportVideo" -> {
                if (exporting) {
                    result.error("EXPORT_IN_PROGRESS", "Un export est déjà en cours", null)
                    return
                }
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                exporting = true
                if (GalleryExportPolicy.legacyPermissionRequired(Build.VERSION.SDK_INT) &&
                    activity?.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                    pendingPermission = args to result
                    try {
                        if (activity == null) throw SecurityException("Activity requise pour l'autorisation Android")
                        activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), STORAGE_REQUEST_CODE)
                    } catch (e: Exception) {
                        pendingPermission = null
                        finish(result, ExportOutcome.error("PERMISSION_DENIED", e.message))
                    }
                } else {
                    startExport(args, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != STORAGE_REQUEST_CODE) return false
        val pending = pendingPermission ?: return true
        pendingPermission = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            startExport(pending.first, pending.second)
        } else {
            finish(pending.second, ExportOutcome.error("PERMISSION_DENIED", "Accès au dossier Movies refusé"))
        }
        return true
    }

    private fun startExport(args: Map<String, Any?>, result: MethodChannel.Result) {
        ioExecutor.execute {
            val outcome = try {
                exportVideoBlocking(args)
            } catch (e: ExportFailure) {
                ExportOutcome.error(e.code, e.message)
            } catch (e: Exception) {
                Log.e(TAG, "exportVideo failed: ${e.javaClass.simpleName}")
                ExportOutcome.error("EXPORT_FAILED", e.message)
            }
            mainHandler.post { finish(result, outcome) }
        }
    }

    private fun finish(result: MethodChannel.Result, outcome: ExportOutcome) {
        exporting = false
        if (outcome.ok) result.success(true)
        else result.error(outcome.code ?: "EXPORT_FAILED", outcome.message, null)
    }

    // ============================================================
    //  EXPORT (thread d'arrière-plan)
    // ============================================================

    private fun exportVideoBlocking(args: Map<String, Any?>): ExportOutcome {
        val srcPath = args["srcPath"] as? String
        val displayName = args["displayName"] as? String

        if (srcPath.isNullOrBlank() || displayName.isNullOrBlank()) {
            return ExportOutcome.error("INVALID_ARGS", "srcPath et displayName requis")
        }

        val srcFile = File(srcPath)
        if (!srcFile.isFile) {
            Log.w(TAG, "Source introuvable: $srcPath")
            return ExportOutcome.error("SRC_MISSING", "Fichier introuvable: $srcPath")
        }
        if (srcFile.length() == 0L) {
            Log.w(TAG, "Source vide (0 octets): $srcPath")
            return ExportOutcome.error(
                "SRC_EMPTY",
                "Fichier .ts vide — libmpv n'a peut-être pas eu le temps de flush",
            )
        }

        val source = inspectRecordedSource(srcFile)
        val dataFile = remuxToMp4(srcFile, source) ?: transcodeToMp4(srcFile, source)
            ?: return ExportOutcome.error("CONVERSION_FAILED", "Aucun MP4 H.264/AAC complet n'a été produit")
        return try {
            validatePortableMp4(dataFile, source)
            insertIntoGallery(dataFile, displayName)
            ExportOutcome.success()
        } catch (e: ExportFailure) {
            ExportOutcome.error(e.code, e.message)
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException: $e")
            ExportOutcome.error(
                "PERMISSION_DENIED",
                "Permission MediaStore refusée — vérifie les autorisations de l'app",
            )
        } catch (e: Exception) {
            Log.e(TAG, "insertIntoGallery failed: $e")
            ExportOutcome.error("EXPORT_FAILED", e.message ?: e.javaClass.simpleName)
        } finally {
            dataFile.delete()
        }
    }

    /** Le TS source passe par le même extracteur HEVC que le lecteur Media3. */
    private fun inspectRecordedSource(file: File): SourceTracks {
        val extractor = MediaExtractorCompat(context)
        try {
            extractor.setDataSource(file.absolutePath)
            return inspectTracks(file, extractor.trackCount, extractor::getTrackFormat)
        } catch (e: ExportFailure) {
            throw e
        } catch (e: Exception) {
            throw ExportFailure("UNSUPPORTED_CODEC", "Format source non pris en charge")
        } finally {
            extractor.release()
        }
    }

    /** La sortie reste relue par Android lui-même, avant toute publication. */
    private fun inspectSource(file: File): SourceTracks {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(file.absolutePath)
            return inspectTracks(file, extractor.trackCount, extractor::getTrackFormat)
        } catch (e: ExportFailure) {
            throw e
        } catch (e: Exception) {
            throw ExportFailure("UNSUPPORTED_CODEC", "Format source non pris en charge")
        } finally {
            extractor.release()
        }
    }

    private fun inspectTracks(file: File, trackCount: Int, formatAt: (Int) -> MediaFormat): SourceTracks {
        var video = -1
        var audio = -1
        for (index in 0 until trackCount) {
            val mime = formatAt(index).getString(MediaFormat.KEY_MIME).orEmpty()
            if (video < 0 && mime.startsWith("video/")) video = index
            if (audio < 0 && mime.startsWith("audio/")) audio = index
        }
        if (video < 0) throw ExportFailure("UNSUPPORTED_CODEC", "Aucune piste vidéo décodable identifiée")
        if (audio < 0) {
            val prefix = ByteArray(minOf(file.length(), 2L * 1024 * 1024).toInt())
            val read = FileInputStream(file).use { input ->
                var position = 0
                while (position < prefix.size) {
                    val count = input.read(prefix, position, prefix.size - position)
                    if (count < 0) break
                    position += count
                }
                position
            }
            val bytes = prefix.copyOf(read)
            if (!GalleryExportPolicy.isMp4Header(bytes) && GalleryExportPolicy.transportStreamOffset(bytes) != null &&
                GalleryExportPolicy.declaredTsAudio(bytes) != false) {
                throw ExportFailure("UNSUPPORTED_CODEC", "L'audio TS ne peut pas être préservé par cet appareil")
            }
        }
        return SourceTracks(video, formatAt(video), audio,
            if (audio >= 0) formatAt(audio) else null)
    }

    /** Vérifie le conteneur et les pistes réellement écrites avant toute insertion publique. */
    private fun validatePortableMp4(file: File, source: SourceTracks) {
        val header = ByteArray(12)
        DataInputStream(FileInputStream(file)).use { it.readFully(header) }
        if (!GalleryExportPolicy.isMp4Header(header)) {
            throw ExportFailure("CONVERSION_FAILED", "Conteneur MP4 invalide")
        }
        val output = inspectSource(file)
        if (!GalleryExportPolicy.canRemux(output.videoFormat.getString(MediaFormat.KEY_MIME),
                output.audioFormat?.getString(MediaFormat.KEY_MIME), source.hasAudio) ||
            output.hasAudio != source.hasAudio) {
            throw ExportFailure("CONVERSION_FAILED", "Piste H.264/AAC absente ou audio perdu")
        }
        for (key in listOf(MediaFormat.KEY_WIDTH, MediaFormat.KEY_HEIGHT)) {
            if (!output.videoFormat.containsKey(key) || !source.videoFormat.containsKey(key) ||
                output.videoFormat.getInteger(key) != source.videoFormat.getInteger(key)) {
                throw ExportFailure("CONVERSION_FAILED", "Dimensions de la source non conservées")
            }
        }
        for (track in listOf(output.videoTrack, output.audioTrack).filter { it >= 0 }) {
            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(file.absolutePath)
                extractor.selectTrack(track)
                if (extractor.sampleTrackIndex < 0 || extractor.sampleTime < 0) {
                    throw ExportFailure("CONVERSION_FAILED", "Une piste MP4 est vide")
                }
            } finally {
                extractor.release()
            }
        }
    }

    /** Insère [dataFile] dans la galerie (Movies/) via MediaStore. */
    private fun insertIntoGallery(dataFile: File, displayName: String) {
        val finalDisplayName = GalleryExportPolicy.displayName(displayName)
        var legacyFile: File? = null
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, finalDisplayName)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/NOVATUBE")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            } else {
                @Suppress("DEPRECATION")
                val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "NOVATUBE")
                if (!directory.isDirectory && !directory.mkdirs()) throw IOException("Dossier Movies indisponible")
                // Nom unique : un deuxième export n'écrase jamais une vidéo existante.
                legacyFile = File.createTempFile(finalDisplayName.removeSuffix(".mp4") + "_", ".mp4", directory)
                @Suppress("DEPRECATION")
                put(MediaStore.Video.Media.DATA, legacyFile!!.absolutePath)
            }
        }

        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }

        Log.i(TAG, "Inserting MediaStore entry: $finalDisplayName (${dataFile.length()} bytes)")
        val resolver = context.contentResolver
        var uri: android.net.Uri? = null
        try {
            uri = resolver.insert(collection, values) ?: throw IOException("Insertion MediaStore refusée")
            val copied = resolver.openOutputStream(uri, "w")?.use { out ->
                FileInputStream(dataFile).use { input -> input.copyTo(out, 64 * 1024) }.also { out.flush() }
            } ?: throw IOException("Écriture MediaStore indisponible")
            if (copied != dataFile.length() || copied == 0L) throw IOException("Copie MediaStore incomplète")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val finalize = ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }
                if (resolver.update(uri, finalize, null, null) != 1) throw IOException("Finalisation MediaStore refusée")
            }
            Log.i(TAG, "Export NOVATUBE terminé")
        } catch (error: Exception) {
            if (uri != null) try { resolver.delete(uri, null, null) } catch (_: Exception) {}
            legacyFile?.delete()
            throw error
        }
    }

    // ============================================================
    //  NIVEAU 1 : REMUX (copie de pistes, sans ré-encodage)
    // ============================================================

    private fun remuxToMp4(srcFile: File, source: SourceTracks): File? {
        if (!GalleryExportPolicy.canRemux(source.videoFormat.getString(MediaFormat.KEY_MIME),
                source.audioFormat?.getString(MediaFormat.KEY_MIME), source.hasAudio)) return null
        val extractor = MediaExtractorCompat(context)
        var muxer: MediaMuxer? = null
        val outFile = File.createTempFile("novatube_remux_", ".mp4", context.cacheDir)
        var complete = false
        try {
            extractor.setDataSource(srcFile.absolutePath)
            muxer = MediaMuxer(outFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            setOrientation(muxer, source.videoFormat)
            val indexMap = HashMap<Int, Int>()
            var maxInputSize = MIN_BUFFER_BYTES
            // Une piste vidéo + la première piste audio : compatible dès API24.
            // Ne jamais accepter une piste refusée en la supprimant silencieusement.
            for (i in listOf(source.videoTrack, source.audioTrack).filter { it >= 0 }) {
                val format = extractor.getTrackFormat(i)
                indexMap[i] = muxer.addTrack(format)
                if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    maxInputSize = maxOf(maxInputSize, format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                }
            }
            if (maxInputSize > GalleryExportPolicy.MAX_SAMPLE_BYTES) return null
            for (srcIndex in indexMap.keys) extractor.selectTrack(srcIndex)
            muxer.start()
            var buffer = ByteBuffer.allocate(maxInputSize)
            val bufferInfo = MediaCodec.BufferInfo()
            val lastPts = HashMap<Int, Long>()
            val sampleCounts = HashMap<Int, Int>()
            while (true) {
                // Media3 annonce la taille avant la lecture : ne pas dépendre
                // d'une exception propre à l'extracteur Android pour agrandir.
                val expectedSize = extractor.sampleSize
                if (expectedSize < 0L) break
                if (expectedSize > GalleryExportPolicy.MAX_SAMPLE_BYTES.toLong()) return null
                if (expectedSize > buffer.capacity().toLong()) {
                    buffer = ByteBuffer.allocate(expectedSize.toInt())
                }
                buffer.clear()
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize.toLong() != expectedSize) return null
                val dstTrack = indexMap[extractor.sampleTrackIndex]
                if (dstTrack != null && sampleSize > 0) {
                    val pts = extractor.sampleTime
                    if (pts < 0) return null
                    val prev = lastPts[dstTrack]
                    // Les B-frames sont prises en charge à partir d'API25.
                    // Modifier leurs timestamps détruirait la cadence : sur API24,
                    // demander une conversion au lieu d'inventer des PTS.
                    if (Build.VERSION.SDK_INT < 25 && prev != null && pts < prev) return null
                    lastPts[dstTrack] = pts
                    bufferInfo.offset = 0
                    bufferInfo.size = sampleSize
                    bufferInfo.presentationTimeUs = pts
                    bufferInfo.flags = sampleFlagsToBufferFlags(extractor.sampleFlags)
                    muxer.writeSampleData(dstTrack, buffer, bufferInfo)
                    sampleCounts[dstTrack] = (sampleCounts[dstTrack] ?: 0) + 1
                }
                extractor.advance()
            }
            muxer.stop()
            if (indexMap.values.any { (sampleCounts[it] ?: 0) == 0 }) return null
            complete = true
            return outFile
        } catch (e: Exception) {
            Log.w(TAG, "remux échoué (${e.javaClass.simpleName}: ${e.message})")
            try {
                outFile.delete()
            } catch (_: Exception) {
            }
            return null
        } finally {
            try {
                extractor.release()
            } catch (_: Exception) {
            }
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
            if (!complete) outFile.delete()
        }
    }

    private fun setOrientation(muxer: MediaMuxer, format: MediaFormat) {
        val rotation = if (format.containsKey(MediaFormat.KEY_ROTATION)) format.getInteger(MediaFormat.KEY_ROTATION) else 0
        if (rotation in setOf(0, 90, 180, 270)) muxer.setOrientationHint(rotation)
    }

    // ============================================================
    //  NIVEAU 2 : TRANSCODE (ré-encodage H.264/AAC via MediaCodec)
    // ============================================================

    /** Petit échantillon encodé mis en attente tant que le muxer n'est pas
     *  démarré (on attend d'avoir le format des DEUX encodeurs). */
    private class PendingSample(val data: ByteArray, val info: MediaCodec.BufferInfo)

    /** Conversion native complète : l'audio présent dans la source est obligatoire. */
    private fun transcodeToMp4(srcFile: File, source: SourceTracks): File? {
        val vFormat = source.videoFormat
        if (!vFormat.containsKey(MediaFormat.KEY_WIDTH) || !vFormat.containsKey(MediaFormat.KEY_HEIGHT)) {
            throw ExportFailure("UNSUPPORTED_CODEC", "Dimensions vidéo inconnues")
        }
        val width = vFormat.getInteger(MediaFormat.KEY_WIDTH)
        val height = vFormat.getInteger(MediaFormat.KEY_HEIGHT)
        val frameRate = sourceFrameRate(srcFile, source)
        if (vFormat.containsKey(MediaFormat.KEY_COLOR_TRANSFER) &&
            vFormat.getInteger(MediaFormat.KEY_COLOR_TRANSFER) in setOf(MediaFormat.COLOR_TRANSFER_ST2084, MediaFormat.COLOR_TRANSFER_HLG)) {
            // Sans moteur de tone-mapping, une conversion HDR→SDR ferait perdre
            // les couleurs. Refuser plutôt que livrer un MP4 délavé.
            throw ExportFailure("UNSUPPORTED_CODEC", "Conversion HDR vers H.264 SDR indisponible")
        }
        val outFile = File.createTempFile("novatube_xcode_", ".mp4", context.cacheDir)
        var complete = false

        var vExtractor: MediaExtractorCompat? = null
        var aExtractor: MediaExtractorCompat? = null
        var vDecoder: MediaCodec? = null
        var vEncoder: MediaCodec? = null
        var aDecoder: MediaCodec? = null
        var inputSurface: Surface? = null
        var muxer: MediaMuxer? = null

        try {
            // --- Encodeur vidéo H.264 avec Surface d'entrée ---------------
            val outVideoFormat = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC, width, height,
            ).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
                )
                setFloat(MediaFormat.KEY_FRAME_RATE, frameRate.toFloat())
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
                if (Build.VERSION.SDK_INT >= 29) setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
                for (key in listOf(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.KEY_COLOR_RANGE, MediaFormat.KEY_COLOR_TRANSFER)) {
                    if (vFormat.containsKey(key)) setInteger(key, vFormat.getInteger(key))
                }
            }
            val sourceBitrate = if (vFormat.containsKey(MediaFormat.KEY_BIT_RATE)) vFormat.getInteger(MediaFormat.KEY_BIT_RATE) else 0
            vEncoder = configuredEncoder(outVideoFormat,
                GalleryExportPolicy.videoBitrate(width, height, frameRate, sourceBitrate))
            inputSurface = vEncoder.createInputSurface()
            vEncoder.start()

            // --- Décodeur vidéo → rend sur la Surface de l'encodeur -------
            // (peut lever si l'appareil n'a pas de décodeur pour ce codec).
            vExtractor = MediaExtractorCompat(context).apply {
                setDataSource(srcFile.absolutePath)
                selectTrack(source.videoTrack)
            }
            val decodeFormat = vExtractor.getTrackFormat(source.videoTrack).apply {
                // L'orientation est portée par le MP4, pas appliquée deux fois.
                setInteger(MediaFormat.KEY_ROTATION, 0)
                // Android Q permet d'interdire les images supprimées quand
                // l'encodeur est plus lent ; la constante publique arrive en S.
                if (Build.VERSION.SDK_INT >= 29) setInteger("allow-frame-drop", 0)
            }
            val videoDecoderName = MediaCodecList(MediaCodecList.REGULAR_CODECS).findDecoderForFormat(decodeFormat)
                ?: throw ExportFailure("UNSUPPORTED_CODEC", "Décodeur vidéo indisponible")
            vDecoder = MediaCodec.createByCodecName(videoDecoderName)
            vDecoder.configure(decodeFormat, inputSurface, null, 0)
            vDecoder.start()

            // L'encodeur AAC sera créé à réception du format PCM réel du
            // décodeur (fréquence/canaux parfois différents du format compressé).
            if (source.hasAudio) {
                aExtractor = MediaExtractorCompat(context).apply {
                    setDataSource(srcFile.absolutePath)
                    selectTrack(source.audioTrack)
                }
                val audioDecodeFormat = aExtractor.getTrackFormat(source.audioTrack).apply {
                    setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                }
                val audioDecoderName = MediaCodecList(MediaCodecList.REGULAR_CODECS).findDecoderForFormat(audioDecodeFormat)
                    ?: throw ExportFailure("UNSUPPORTED_CODEC", "Décodeur audio indisponible")
                aDecoder = MediaCodec.createByCodecName(audioDecoderName)
                aDecoder.configure(audioDecodeFormat, null, null, 0)
                aDecoder.start()
            }

            muxer = MediaMuxer(outFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            setOrientation(muxer, source.videoFormat)

            val ok = runTranscodeLoop(
                vExtractor!!, vDecoder!!, vEncoder!!,
                aExtractor, aDecoder,
                muxer,
            )
            if (!ok) {
                try { outFile.delete() } catch (_: Exception) {}
                return null
            }
            complete = true
            return outFile
        } catch (e: ExportFailure) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "transcode échoué (${e.javaClass.simpleName}: ${e.message})")
            try { outFile.delete() } catch (_: Exception) {}
            return null
        } finally {
            try { vDecoder?.stop() } catch (_: Exception) {}
            try { vDecoder?.release() } catch (_: Exception) {}
            try { vEncoder?.stop() } catch (_: Exception) {}
            try { vEncoder?.release() } catch (_: Exception) {}
            try { aDecoder?.stop() } catch (_: Exception) {}
            try { aDecoder?.release() } catch (_: Exception) {}
            try { inputSurface?.release() } catch (_: Exception) {}
            try { vExtractor?.release() } catch (_: Exception) {}
            try { aExtractor?.release() } catch (_: Exception) {}
            try { muxer?.release() } catch (_: Exception) {}
            if (!complete) outFile.delete()
        }
    }

    /** Choisit un encodeur qui accepte réellement la taille/cadence et borne son débit. */
    private fun configuredEncoder(format: MediaFormat, targetBitrate: Int): MediaCodec {
        val mime = format.getString(MediaFormat.KEY_MIME)!!
        for (info in MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos) {
            if (!info.isEncoder || !info.supportedTypes.any { it.equals(mime, ignoreCase = true) }) continue
            var codec: MediaCodec? = null
            try {
                val capabilities = info.getCapabilitiesForType(mime)
                val range = if (mime.startsWith("video/")) capabilities.videoCapabilities.bitrateRange
                            else capabilities.audioCapabilities.bitrateRange
                format.setInteger(MediaFormat.KEY_BIT_RATE, targetBitrate.coerceIn(range.lower, range.upper))
                val mode = listOf(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR,
                    MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR).firstOrNull {
                    capabilities.encoderCapabilities.isBitrateModeSupported(it)
                } ?: continue
                // Réécrire le mode pour chaque candidat : un VBR essayé sur
                // le précédent ne doit pas empêcher un encodeur CBR compatible.
                format.setInteger(MediaFormat.KEY_BITRATE_MODE, mode)
                if (!capabilities.isFormatSupported(format)) continue
                codec = MediaCodec.createByCodecName(info.name)
                codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                return codec
            } catch (_: Exception) {
                try { codec?.release() } catch (_: Exception) {}
            }
        }
        throw ExportFailure("UNSUPPORTED_CODEC", "Aucun encodeur compatible avec la qualité source")
    }

    private fun sourceFrameRate(file: File, source: SourceTracks): Double {
        if (source.videoFormat.containsKey(MediaFormat.KEY_FRAME_RATE)) {
            val rate = runCatching { source.videoFormat.getFloat(MediaFormat.KEY_FRAME_RATE).toDouble() }
                .getOrElse { runCatching { source.videoFormat.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble() }.getOrDefault(0.0) }
            if (rate.isFinite() && rate > 0) return rate
        }
        val extractor = MediaExtractorCompat(context)
        try {
            extractor.setDataSource(file.absolutePath)
            extractor.selectTrack(source.videoTrack)
            val timestamps = ArrayList<Long>()
            while (timestamps.size < 120 && extractor.sampleTime >= 0) {
                timestamps.add(extractor.sampleTime)
                if (!extractor.advance()) break
            }
            val differences = timestamps.sorted().zipWithNext { a, b -> b - a }.filter { it > 0 }.sorted()
            if (differences.isNotEmpty()) return 1_000_000.0 / differences[differences.size / 2]
        } finally { extractor.release() }
        // Une source d'une seule image n'a pas de cadence mesurable. Les PTS
        // restent copiés tels quels : aucune image supplémentaire n'est créée.
        return 30.0
    }

    /**
     * Boucle de transcodage coordonnée (vidéo Surface + audio buffers).
     * Démarre le muxer seulement quand les DEUX encodeurs ont publié leur
     * format ; les échantillons produits avant sont mis en attente.
     * Retourne true seulement si toutes les pistes attendues sont non vides
     * et si le conteneur a été finalisé après leur fin de flux.
     */
    private fun runTranscodeLoop(
        vExtractor: MediaExtractorCompat,
        vDecoder: MediaCodec,
        vEncoder: MediaCodec,
        aExtractor: MediaExtractorCompat?,
        aDecoder: MediaCodec?,
        muxer: MediaMuxer,
    ): Boolean {
        val doAudio = aExtractor != null && aDecoder != null
        var aEncoder: MediaCodec? = null
        var lastProgressMs = SystemClock.elapsedRealtime()
        var audioSampleRate = 0
        var audioChannels = 0

        var videoExtractorDone = false
        var videoDecoderDone = false
        var videoEncoderDone = false
        var audioExtractorDone = false
        var audioDecoderDone = false
        var audioEncoderDone = !doAudio

        var videoFormatReady = false
        var audioFormatReady = !doAudio
        var muxing = false
        var videoMuxTrack = -1
        var audioMuxTrack = -1

        val pendingVideo = ArrayList<PendingSample>()
        val pendingAudio = ArrayList<PendingSample>()
        var pendingBytes = 0L
        var videoSamples = 0
        var audioSamples = 0

        // Index d'un buffer de sortie du décodeur audio gardé en attente
        // tant que l'encodeur audio n'a pas de slot d'entrée libre.
        var pendingAudioDecoderOut = -1
        var pendingAudioConsumed = 0
        val audioDecInfo = MediaCodec.BufferInfo()

        val vInfo = MediaCodec.BufferInfo()
        val vEncInfo = MediaCodec.BufferInfo()
        val aEncInfo = MediaCodec.BufferInfo()

        fun maybeStartMuxer() {
            if (!muxing && videoFormatReady && audioFormatReady) {
                muxer.start()
                muxing = true
                // Vide les échantillons mis en attente avant le démarrage.
                for (p in pendingVideo) muxer.writeSampleData(videoMuxTrack, ByteBuffer.wrap(p.data), p.info)
                for (p in pendingAudio) muxer.writeSampleData(audioMuxTrack, ByteBuffer.wrap(p.data), p.info)
                pendingVideo.clear()
                pendingAudio.clear()
                pendingBytes = 0L
            }
        }

        fun writeOrBuffer(track: Int, list: ArrayList<PendingSample>, buf: ByteBuffer, info: MediaCodec.BufferInfo) {
            if (muxing) {
                muxer.writeSampleData(track, buf, info)
            } else {
                pendingBytes += info.size
                if (pendingBytes > GalleryExportPolicy.MAX_PENDING_BYTES) {
                    throw ExportFailure("CONVERSION_FAILED", "Une piste ne démarre pas ; export interrompu")
                }
                val copy = ByteArray(info.size)
                buf.position(info.offset)
                buf.get(copy, 0, info.size)
                val ic = MediaCodec.BufferInfo()
                ic.set(0, info.size, info.presentationTimeUs, info.flags)
                list.add(PendingSample(copy, ic))
            }
        }

        fun prepareAudioEncoder() {
            val pcmFormat = aDecoder!!.outputFormat
            val sampleRate = pcmFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channels = pcmFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val encoding = if (pcmFormat.containsKey(MediaFormat.KEY_PCM_ENCODING))
                pcmFormat.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
            if (encoding != AudioFormat.ENCODING_PCM_16BIT || sampleRate <= 0 || channels <= 0) {
                throw ExportFailure("UNSUPPORTED_CODEC", "Format PCM non pris en charge")
            }
            if (aEncoder != null) {
                if (sampleRate != audioSampleRate || channels != audioChannels) {
                    throw ExportFailure("UNSUPPORTED_CODEC", "Le format audio change pendant l'enregistrement")
                }
                return
            }
            audioSampleRate = sampleRate
            audioChannels = channels
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channels).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 64 * 1024)
            }
            aEncoder = configuredEncoder(format, GalleryExportPolicy.audioBitrate(channels))
            aEncoder!!.start()
        }

        try {
            while (!videoEncoderDone || !audioEncoderDone) {
                if (GalleryExportPolicy.stalled(SystemClock.elapsedRealtime(), lastProgressMs)) {
                    Log.w(TAG, "transcode: aucune progression depuis une minute")
                    return false
                }

                // ---- 1. Alimente le décodeur vidéo -------------------------
                if (!videoExtractorDone) {
                    val inIdx = vDecoder.dequeueInputBuffer(CODEC_TIMEOUT_US)
                    if (inIdx >= 0) {
                        lastProgressMs = SystemClock.elapsedRealtime()
                        val buf = vDecoder.getInputBuffer(inIdx)!!
                        val size = vExtractor.readSampleData(buf, 0)
                        if (size < 0) {
                            vDecoder.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            videoExtractorDone = true
                        } else {
                            vDecoder.queueInputBuffer(inIdx, 0, size, vExtractor.sampleTime, 0)
                            vExtractor.advance()
                        }
                    }
                }

                // ---- 2. Draine le décodeur vidéo → Surface de l'encodeur ----
                if (!videoDecoderDone) {
                    val outIdx = vDecoder.dequeueOutputBuffer(vInfo, CODEC_TIMEOUT_US)
                    if (outIdx >= 0) {
                        lastProgressMs = SystemClock.elapsedRealtime()
                        val eos = (vInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        // render=true → la frame décodée part sur la Surface de
                        // l'encodeur, qui la ré-encode en H.264.
                        vDecoder.releaseOutputBuffer(outIdx, vInfo.size > 0)
                        if (eos) {
                            videoDecoderDone = true
                            vEncoder.signalEndOfInputStream()
                        }
                    }
                }

                // ---- 3. Draine l'encodeur vidéo → muxer --------------------
                if (!videoEncoderDone) {
                    val outIdx = vEncoder.dequeueOutputBuffer(vEncInfo, CODEC_TIMEOUT_US)
                    if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        lastProgressMs = SystemClock.elapsedRealtime()
                        videoMuxTrack = muxer.addTrack(vEncoder.outputFormat)
                        videoFormatReady = true
                        maybeStartMuxer()
                    } else if (outIdx >= 0) {
                        lastProgressMs = SystemClock.elapsedRealtime()
                        val encBuf = vEncoder.getOutputBuffer(outIdx)!!
                        if ((vEncInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                            vEncInfo.size = 0
                        }
                        if (vEncInfo.size > 0 && videoMuxTrack >= 0) {
                            writeOrBuffer(videoMuxTrack, pendingVideo, encBuf, vEncInfo)
                            videoSamples++
                        }
                        val eos = (vEncInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        vEncoder.releaseOutputBuffer(outIdx, false)
                        if (eos) videoEncoderDone = true
                    }
                }

                // ---- 4. Audio : extracteur → décodeur ----------------------
                if (doAudio && !audioExtractorDone) {
                    val inIdx = aDecoder!!.dequeueInputBuffer(CODEC_TIMEOUT_US)
                    if (inIdx >= 0) {
                        lastProgressMs = SystemClock.elapsedRealtime()
                        val buf = aDecoder.getInputBuffer(inIdx)!!
                        val size = aExtractor!!.readSampleData(buf, 0)
                        if (size < 0) {
                            aDecoder.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            audioExtractorDone = true
                        } else {
                            aDecoder.queueInputBuffer(inIdx, 0, size, aExtractor.sampleTime, 0)
                            aExtractor.advance()
                        }
                    }
                }

                // ---- 5. Audio : décodeur (PCM) → encodeur AAC --------------
                if (doAudio && !audioDecoderDone) {
                    if (pendingAudioDecoderOut < 0) {
                        val o = aDecoder!!.dequeueOutputBuffer(audioDecInfo, CODEC_TIMEOUT_US)
                        if (o >= 0) {
                            lastProgressMs = SystemClock.elapsedRealtime()
                            pendingAudioDecoderOut = o
                            pendingAudioConsumed = 0
                            if (aEncoder == null) prepareAudioEncoder()
                        } else if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                            lastProgressMs = SystemClock.elapsedRealtime()
                            prepareAudioEncoder()
                        }
                    }
                    if (pendingAudioDecoderOut >= 0) {
                        val encoder = aEncoder!!
                        val inIdx = encoder.dequeueInputBuffer(CODEC_TIMEOUT_US)
                        if (inIdx >= 0) {
                            lastProgressMs = SystemClock.elapsedRealtime()
                            val eos = (audioDecInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                            val encIn = encoder.getInputBuffer(inIdx)!!
                            encIn.clear()
                            val count = GalleryExportPolicy.pcmChunkBytes(
                                audioDecInfo.size - pendingAudioConsumed, encIn.remaining(), audioChannels)
                            if (count > 0) {
                                val pcm = aDecoder!!.getOutputBuffer(pendingAudioDecoderOut)!!
                                pcm.position(audioDecInfo.offset + pendingAudioConsumed)
                                pcm.limit(audioDecInfo.offset + pendingAudioConsumed + count)
                                encIn.put(pcm)
                            }
                            val lastChunk = pendingAudioConsumed + count == audioDecInfo.size
                            encoder.queueInputBuffer(
                                inIdx, 0, count,
                                GalleryExportPolicy.pcmTimestampUs(audioDecInfo.presentationTimeUs, pendingAudioConsumed,
                                    audioSampleRate, audioChannels),
                                if (eos && lastChunk) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0,
                            )
                            pendingAudioConsumed += count
                            if (lastChunk) {
                                aDecoder!!.releaseOutputBuffer(pendingAudioDecoderOut, false)
                                pendingAudioDecoderOut = -1
                                if (eos) audioDecoderDone = true
                            }
                        }
                    }
                }

                // ---- 6. Audio : encodeur AAC → muxer -----------------------
                if (doAudio && !audioEncoderDone && aEncoder != null) {
                    val encoder = aEncoder!!
                    val outIdx = encoder.dequeueOutputBuffer(aEncInfo, CODEC_TIMEOUT_US)
                    if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        lastProgressMs = SystemClock.elapsedRealtime()
                        audioMuxTrack = muxer.addTrack(encoder.outputFormat)
                        audioFormatReady = true
                        maybeStartMuxer()
                    } else if (outIdx >= 0) {
                        lastProgressMs = SystemClock.elapsedRealtime()
                        val encBuf = encoder.getOutputBuffer(outIdx)!!
                        if ((aEncInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                            aEncInfo.size = 0
                        }
                        if (aEncInfo.size > 0 && audioMuxTrack >= 0) {
                            writeOrBuffer(audioMuxTrack, pendingAudio, encBuf, aEncInfo)
                            audioSamples++
                        }
                        val eos = (aEncInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        encoder.releaseOutputBuffer(outIdx, false)
                        if (eos) audioEncoderDone = true
                    }
                }
            }

            // Sécurité : si le muxer n'a jamais démarré (formats jamais reçus),
            // l'export n'a rien produit d'exploitable.
            if (!muxing) {
                Log.w(TAG, "transcode: muxer jamais démarré")
                return false
            }
            try {
                muxer.stop()
            } catch (e: Exception) {
                Log.w(TAG, "transcode: muxer.stop() a levé: ${e.message}")
                return false
            }
            return videoSamples > 0 && (!doAudio || audioSamples > 0)
        } finally {
            try { aEncoder?.stop() } catch (_: Exception) {}
            try { aEncoder?.release() } catch (_: Exception) {}
        }
    }

    /** Traduit les flags d'échantillon de MediaExtractor en flags MediaCodec
     *  attendus par MediaMuxer.writeSampleData (seul le keyframe nous importe). */
    private fun sampleFlagsToBufferFlags(sampleFlags: Int): Int {
        var flags = 0
        if (sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
            flags = flags or MediaCodec.BUFFER_FLAG_KEY_FRAME
        }
        return flags
    }
}
