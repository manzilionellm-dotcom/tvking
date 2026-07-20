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
//      Convertit l'enregistrement en VRAI MP4 lisible partout puis le
//      range dans Movies/ via MediaStore. Retourne true si OK.
//
//  --- 3 NIVEAUX DE CONVERSION (du plus rapide au plus universel) ------
//  Les enregistrements IPTV sont des MPEG-TS (.ts) bruts. Renommer en
//  .mp4 ne suffit PAS : la galerie native scanne le CONTENU réel.
//
//   1) REMUX (rapide, sans perte) — MediaExtractor + MediaMuxer copient
//      les pistes telles quelles dans un conteneur MP4. Marche quand les
//      codecs sont déjà compatibles MP4 (vidéo H.264/HEVC + audio AAC).
//      Aucun ré-encodage, aucune perte, quasi-instantané.
//
//   2) TRANSCODE (universel) — si le remux ne peut pas embarquer la vidéo
//      (ex. 6ter = MPEG-2) ou perd l'audio (ex. AC3), on RÉ-ENCODE via
//      MediaCodec : vidéo → H.264, audio → AAC. Plus lent (proche du
//      temps réel) mais le MP4 produit est lisible PARTOUT (galerie,
//      WhatsApp, iPhone…). Si le téléphone n'a pas de décodeur audio
//      (AC3 non licencié), on garde la vidéo SANS le son plutôt que
//      d'échouer. Aucun ffmpeg embarqué : 100 % API natives Android.
//
//   3) COPIE BRUTE (dernier repli) — si même le transcodage est
//      impossible (codec vidéo non décodable par l'appareil), on copie
//      le .ts tel quel. Au pire on n'est pas plus mauvais qu'avant.
//
//  Tout tourne sur un thread d'ARRIÈRE-PLAN (le transcodage peut durer
//  plusieurs secondes) ; le résultat est renvoyé à Flutter sur le thread
//  principal. On ne touche PAS au pipeline d'enregistrement / de lecture.
// =========================================================

package com.manzilionellm.tvking

import android.content.ContentValues
import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors

class GalleryExporter(
    messenger: BinaryMessenger,
    private val context: Context,
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
        // Garde-fou : un transcodage ne doit jamais bloquer indéfiniment.
        // Au-delà, on abandonne et on retombe sur le repli.
        private const val TRANSCODE_MAX_MS = 10 * 60 * 1000L
    }

    private val channel: MethodChannel =
        MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler(this@GalleryExporter)
        }

    // Le transcodage est lourd → thread dédié. Les callbacks Flutter
    // doivent revenir sur le thread principal (mainHandler).
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

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
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                // Travail lourd hors du thread principal pour éviter l'ANR.
                ioExecutor.execute {
                    val outcome = try {
                        exportVideoBlocking(args)
                    } catch (e: Exception) {
                        Log.e(TAG, "exportVideo threw: $e")
                        ExportOutcome.error("EXPORT_FAILED", e.message ?: e.javaClass.simpleName)
                    }
                    mainHandler.post {
                        if (outcome.ok) {
                            result.success(true)
                        } else {
                            result.error(outcome.code ?: "EXPORT_FAILED", outcome.message, null)
                        }
                    }
                }
            }
            // Convertit un .ts en VRAI MP4 posé à côté de la source (même
            // dossier, même nom, extension .mp4) et retourne le chemin du
            // MP4 produit. Ne supprime PAS la source — c'est le côté Dart
            // qui bascule la fiche puis efface le .ts. Sert à finaliser
            // chaque enregistrement dans un format que tous les téléphones
            // lisent, sans passer par la Galerie.
            "convertToMp4" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                ioExecutor.execute {
                    var newPath: String? = null
                    var error: Exception? = null
                    try {
                        newPath = convertToMp4Blocking(args)
                    } catch (e: Exception) {
                        Log.e(TAG, "convertToMp4 threw: $e")
                        error = e
                    }
                    mainHandler.post {
                        if (newPath != null) {
                            result.success(newPath)
                        } else {
                            result.error(
                                "CONVERT_FAILED",
                                error?.message ?: "conversion impossible",
                                null,
                            )
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
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
        if (!srcFile.exists()) {
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

        // --- Choix de la stratégie de conversion --------------------------
        // produceMp4 : remux sans perte si possible, sinon transcodage,
        // sinon vidéo remuxée sans audio. Null = rien n'a marché.
        //
        // CORRECTIF (galerie « VLC seulement ») : AVANT, si produceMp4
        // échouait, on copiait le .ts BRUT dans la galerie en le nommant
        // « …mp4 » avec le type MIME video/mp4. La galerie/le lecteur photo du
        // téléphone se fie au conteneur (MP4) → démux MP4 sur des octets
        // MPEG-TS → échec → « seul VLC (qui sniffe le contenu) l'ouvre ».
        // On NE MENT PLUS sur le format : on n'insère un video/mp4 QUE si on a
        // produit un VRAI MP4. Sinon on renvoie une erreur claire (l'appelant
        // affiche un message) — l'enregistrement reste lisible dans l'app.
        val produced = produceMp4(srcFile, context.cacheDir)
        if (produced == null) {
            Log.w(TAG, "Conversion MP4 impossible sur cet appareil (codec non muxable/décodable)")
            return ExportOutcome.error(
                "CONVERT_UNSUPPORTED",
                "Cette chaîne ne peut pas être convertie en MP4 sur ce téléphone " +
                    "(codec vidéo non pris en charge). L'enregistrement reste lisible dans l'app.",
            )
        }
        val dataFile: File = produced
        val tempToCleanup: File? = produced

        return try {
            // On garantit une extension .mp4 sur le nom affiché (le .ts a pu
            // rester dans displayName si l'appelant ne l'a pas remplacé).
            val mp4Name = if (displayName.endsWith(".mp4", ignoreCase = true)) {
                displayName
            } else {
                displayName.substringBeforeLast('.') + ".mp4"
            }
            insertIntoGallery(dataFile, mp4Name)
            ExportOutcome.success()
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
            if (tempToCleanup != null) {
                try {
                    tempToCleanup.delete()
                } catch (e: Exception) {
                    Log.w(TAG, "Suppression temp échouée: ${e.message}")
                }
            }
        }
    }

    /** Insère [dataFile] dans la galerie (Movies/) via MediaStore. */
    private fun insertIntoGallery(dataFile: File, displayName: String) {
        // RELATIVE_PATH = Movies. On préfixe le nom par "7MOTION_" pour
        // qu'il soit reconnaissable dans la liste de la galerie.
        val finalDisplayName = if (displayName.startsWith("7MOTION_")) {
            displayName
        } else {
            "7MOTION_$displayName"
        }
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, finalDisplayName)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES)
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
        }

        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }

        Log.i(TAG, "Inserting MediaStore entry: $finalDisplayName (${dataFile.length()} bytes)")
        val uri = context.contentResolver.insert(collection, values)
            ?: throw java.io.IOException("MediaStore a refusé l'insertion (collection=$collection)")

        context.contentResolver.openOutputStream(uri)?.use { out ->
            FileInputStream(dataFile).use { input ->
                val buffer = ByteArray(64 * 1024)
                var bytes = input.read(buffer)
                while (bytes >= 0) {
                    out.write(buffer, 0, bytes)
                    bytes = input.read(buffer)
                }
                out.flush()
            }
        } ?: throw java.io.IOException("openOutputStream returned null")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val finalize = ContentValues().apply {
                put(MediaStore.Video.Media.IS_PENDING, 0)
            }
            context.contentResolver.update(uri, finalize, null, null)
        }
        Log.i(TAG, "Exported → $uri")
    }

    // ============================================================
    //  CONVERSION EN PLACE (.ts → .mp4 à côté de la source)
    // ============================================================

    /**
     * Convertit le fichier pointé par `srcPath` en MP4 posé dans le MÊME
     * dossier (rename atomique possible : même filesystem). Retourne le
     * chemin absolu du MP4 produit. Lève une exception avec un message
     * exploitable si la conversion n'est pas possible — dans ce cas la
     * source n'est pas touchée et le .ts reste utilisable tel quel.
     */
    private fun convertToMp4Blocking(args: Map<String, Any?>): String {
        val srcPath = args["srcPath"] as? String
        if (srcPath.isNullOrBlank()) {
            throw IllegalArgumentException("srcPath requis")
        }
        val srcFile = File(srcPath)
        if (!srcFile.exists()) {
            throw java.io.FileNotFoundException("Fichier introuvable: $srcPath")
        }
        if (srcFile.length() == 0L) {
            throw java.io.IOException("Fichier source vide (0 octet)")
        }
        val dir = srcFile.parentFile
            ?: throw java.io.IOException("Dossier parent introuvable: $srcPath")

        // Le temporaire est produit dans le dossier de destination : le
        // renameTo final reste sur le même filesystem (le cacheDir, lui,
        // vit sur une autre partition que le storage externe de l'app).
        val produced = produceMp4(srcFile, dir)
            ?: throw java.io.IOException(
                "Aucune piste convertible en MP4 sur cet appareil",
            )

        val base = srcFile.name.substringBeforeLast('.')
        var outFile = File(dir, "$base.mp4")
        // Noms horodatés à la minute → collision improbable, mais on
        // n'écrase jamais un fichier existant.
        var n = 2
        while (outFile.exists()) {
            outFile = File(dir, "$base ($n).mp4")
            n++
        }
        if (!produced.renameTo(outFile)) {
            // Même dossier → ne devrait jamais arriver ; repli par copie.
            produced.copyTo(outFile, overwrite = true)
            produced.delete()
        }
        Log.i(TAG, "convertToMp4: ${srcFile.name} → ${outFile.name} (${outFile.length()} octets)")
        return outFile.absolutePath
    }

    // ============================================================
    //  SÉLECTION DE STRATÉGIE (remux → transcode → remux partiel)
    // ============================================================

    /**
     * Produit un MP4 temporaire dans [workDir] à partir de [srcFile] :
     *   1) remux sans perte si vidéo ET audio sont muxables,
     *   2) sinon transcodage universel H.264 + AAC,
     *   3) sinon la vidéo remuxée seule (sans son).
     * Retourne le fichier temporaire produit (à renommer ou supprimer par
     * l'appelant), ou `null` si rien n'a marché.
     */
    private fun produceMp4(srcFile: File, workDir: File): File? {
        val remux = remuxToMp4(srcFile, workDir)
        if (remux != null && (remux.audioMuxed || !remux.sourceHadAudio)) {
            // Remux complet (vidéo + audio si présent) → parfait, sans perte.
            Log.i(TAG, "Remux complet: ${remux.file.length()} octets")
            return remux.file
        }
        // Soit pas de vidéo muxable, soit audio perdu → on transcode.
        Log.i(TAG, "Remux insuffisant (remux=${remux != null}) → transcodage")
        val transcoded = transcodeToMp4(srcFile, workDir)
        if (transcoded != null) {
            // Le remux partiel (vidéo seule) ne sert plus.
            remux?.file?.delete()
            Log.i(TAG, "Transcodage OK: ${transcoded.length()} octets")
            return transcoded
        }
        if (remux != null) {
            // Transcodage impossible mais on a au moins la vidéo
            // remuxée (sans son) → mieux que le .ts brut.
            Log.w(TAG, "Transcodage indisponible → vidéo remuxée (sans audio)")
            return remux.file
        }
        return null
    }

    // ============================================================
    //  NIVEAU 1 : REMUX (copie de pistes, sans ré-encodage)
    // ============================================================

    /** Résultat du remux : le fichier MP4, + si l'audio a pu être embarqué
     *  et si la source CONTENAIT de l'audio (pour décider d'un transcodage). */
    private class RemuxOutcome(
        val file: File,
        val audioMuxed: Boolean,
        val sourceHadAudio: Boolean,
    )

    private fun remuxToMp4(srcFile: File, workDir: File): RemuxOutcome? {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        // Suffixe .tmp : jamais confondu avec un vrai .mp4 finalisé si un
        // crash laisse traîner le temporaire (MediaMuxer ignore l'extension).
        val outFile = File(workDir, "remux_${System.currentTimeMillis()}.mp4.tmp")
        try {
            extractor.setDataSource(srcFile.absolutePath)
            val trackCount = extractor.trackCount
            if (trackCount == 0) return null

            muxer = MediaMuxer(outFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val indexMap = HashMap<Int, Int>()
            var maxInputSize = MIN_BUFFER_BYTES
            var hasVideo = false
            var sourceHadAudio = false
            var audioMuxed = false
            for (i in 0 until trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                val isVideo = mime.startsWith("video/")
                val isAudio = mime.startsWith("audio/")
                if (!isVideo && !isAudio) continue
                if (isAudio) sourceHadAudio = true
                try {
                    val muxIndex = muxer.addTrack(format)
                    indexMap[i] = muxIndex
                    if (isVideo) hasVideo = true
                    if (isAudio) audioMuxed = true
                    if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                        val s = format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                        if (s > maxInputSize) maxInputSize = s
                    }
                } catch (e: Exception) {
                    // Codec non muxable en MP4 (MPEG-2 vidéo, AC3 audio…).
                    Log.w(TAG, "remux: addTrack a refusé '$mime': ${e.message}")
                }
            }

            // Sans vidéo muxable, le remux n'a pas d'intérêt → on laissera
            // le transcodage prendre le relais.
            if (!hasVideo || indexMap.isEmpty()) {
                Log.w(TAG, "remux: aucune piste vidéo muxable")
                return null
            }

            for (srcIndex in indexMap.keys) extractor.selectTrack(srcIndex)

            muxer.start()
            var buffer = ByteBuffer.allocate(maxInputSize)
            val bufferInfo = MediaCodec.BufferInfo()
            val lastPts = HashMap<Int, Long>()
            while (true) {
                var sampleSize: Int
                while (true) {
                    try {
                        sampleSize = extractor.readSampleData(buffer, 0)
                        break
                    } catch (e: IllegalArgumentException) {
                        val newCap = buffer.capacity() * 2
                        Log.w(TAG, "remux: tampon trop petit (${buffer.capacity()}) → $newCap")
                        buffer = ByteBuffer.allocate(newCap)
                    }
                }
                if (sampleSize < 0) break
                val dstTrack = indexMap[extractor.sampleTrackIndex]
                if (dstTrack != null) {
                    var pts = extractor.sampleTime
                    if (pts < 0) pts = 0
                    val prev = lastPts[dstTrack]
                    if (prev != null && pts <= prev) pts = prev + 1
                    lastPts[dstTrack] = pts
                    bufferInfo.offset = 0
                    bufferInfo.size = sampleSize
                    bufferInfo.presentationTimeUs = pts
                    bufferInfo.flags = sampleFlagsToBufferFlags(extractor.sampleFlags)
                    muxer.writeSampleData(dstTrack, buffer, bufferInfo)
                }
                extractor.advance()
            }
            muxer.stop()
            return RemuxOutcome(outFile, audioMuxed, sourceHadAudio)
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
        }
    }

    // ============================================================
    //  NIVEAU 2 : TRANSCODE (ré-encodage universel via MediaCodec)
    // ============================================================

    /** Petit échantillon encodé mis en attente tant que le muxer n'est pas
     *  démarré (on attend d'avoir le format des DEUX encodeurs). */
    private class PendingSample(val data: ByteArray, val info: MediaCodec.BufferInfo)

    /**
     * Ré-encode la source en MP4 H.264 + AAC. La vidéo est décodée puis
     * ré-encodée via une Surface (chemin GPU, pas de copie de pixels en
     * RAM). L'audio est décodé en PCM puis ré-encodé en AAC ; s'il n'y a
     * pas de décodeur audio (AC3 non licencié), on produit une vidéo SANS
     * son plutôt que d'échouer. Retourne le MP4 ou `null` si même la vidéo
     * n'est pas décodable par l'appareil.
     */
    private fun transcodeToMp4(srcFile: File, workDir: File): File? {
        val outFile = File(workDir, "xcode_${System.currentTimeMillis()}.mp4.tmp")

        // --- Repérage des pistes ----------------------------------------
        var videoTrack = -1
        var audioTrack = -1
        var videoFormat: MediaFormat? = null
        var audioFormat: MediaFormat? = null
        val probe = MediaExtractor()
        try {
            probe.setDataSource(srcFile.absolutePath)
            for (i in 0 until probe.trackCount) {
                val f = probe.getTrackFormat(i)
                val m = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (videoTrack < 0 && m.startsWith("video/")) {
                    videoTrack = i; videoFormat = f
                } else if (audioTrack < 0 && m.startsWith("audio/")) {
                    audioTrack = i; audioFormat = f
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "transcode: setDataSource échoué: ${e.message}")
            return null
        } finally {
            try {
                probe.release()
            } catch (_: Exception) {
            }
        }
        val vFormat = videoFormat
        if (videoTrack < 0 || vFormat == null) {
            Log.w(TAG, "transcode: pas de piste vidéo")
            return null
        }
        if (!vFormat.containsKey(MediaFormat.KEY_WIDTH) || !vFormat.containsKey(MediaFormat.KEY_HEIGHT)) {
            Log.w(TAG, "transcode: dimensions vidéo inconnues")
            return null
        }
        val width = vFormat.getInteger(MediaFormat.KEY_WIDTH)
        val height = vFormat.getInteger(MediaFormat.KEY_HEIGHT)
        val vMime = vFormat.getString(MediaFormat.KEY_MIME) ?: return null
        val frameRate = if (vFormat.containsKey(MediaFormat.KEY_FRAME_RATE)) {
            vFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
        } else {
            25
        }

        var vExtractor: MediaExtractor? = null
        var aExtractor: MediaExtractor? = null
        var vDecoder: MediaCodec? = null
        var vEncoder: MediaCodec? = null
        var aDecoder: MediaCodec? = null
        var aEncoder: MediaCodec? = null
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
                setInteger(MediaFormat.KEY_BIT_RATE, estimateVideoBitrate(width, height))
                setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            }
            vEncoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            vEncoder.configure(outVideoFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            inputSurface = vEncoder.createInputSurface()
            vEncoder.start()

            // --- Décodeur vidéo → rend sur la Surface de l'encodeur -------
            // (peut lever si l'appareil n'a pas de décodeur pour ce codec).
            vExtractor = MediaExtractor().apply {
                setDataSource(srcFile.absolutePath)
                selectTrack(videoTrack)
            }
            vDecoder = MediaCodec.createDecoderByType(vMime)
            vDecoder.configure(vFormat, inputSurface, null, 0)
            vDecoder.start()

            // --- Audio (best-effort) -------------------------------------
            var doAudio = false
            val aFormat = audioFormat
            if (audioTrack >= 0 && aFormat != null) {
                try {
                    val aMime = aFormat.getString(MediaFormat.KEY_MIME)!!
                    val sampleRate = aFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    val channels = aFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    val outAudioFormat = MediaFormat.createAudioFormat(
                        MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channels,
                    ).apply {
                        setInteger(
                            MediaFormat.KEY_AAC_PROFILE,
                            MediaCodecInfo.CodecProfileLevel.AACObjectLC,
                        )
                        setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
                        setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 64 * 1024)
                    }
                    aEncoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
                    aEncoder.configure(outAudioFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                    aEncoder.start()

                    aExtractor = MediaExtractor().apply {
                        setDataSource(srcFile.absolutePath)
                        selectTrack(audioTrack)
                    }
                    aDecoder = MediaCodec.createDecoderByType(aMime)
                    aDecoder.configure(aFormat, null, null, 0)
                    aDecoder.start()
                    doAudio = true
                } catch (e: Exception) {
                    // Pas de décodeur audio (AC3…) → vidéo seule, sans son.
                    Log.w(TAG, "transcode: audio non transcodable (${e.message}) → vidéo sans son")
                    try { aDecoder?.release() } catch (_: Exception) {}
                    try { aEncoder?.release() } catch (_: Exception) {}
                    try { aExtractor?.release() } catch (_: Exception) {}
                    aDecoder = null; aEncoder = null; aExtractor = null
                    doAudio = false
                }
            }

            muxer = MediaMuxer(outFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val ok = runTranscodeLoop(
                vExtractor!!, vDecoder!!, vEncoder!!,
                if (doAudio) aExtractor else null,
                if (doAudio) aDecoder else null,
                if (doAudio) aEncoder else null,
                muxer,
            )
            if (!ok) {
                try { outFile.delete() } catch (_: Exception) {}
                return null
            }
            return outFile
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
            try { aEncoder?.stop() } catch (_: Exception) {}
            try { aEncoder?.release() } catch (_: Exception) {}
            try { inputSurface?.release() } catch (_: Exception) {}
            try { vExtractor?.release() } catch (_: Exception) {}
            try { aExtractor?.release() } catch (_: Exception) {}
            try { muxer?.release() } catch (_: Exception) {}
        }
    }

    /**
     * Boucle de transcodage coordonnée (vidéo Surface + audio buffers).
     * Démarre le muxer seulement quand les DEUX encodeurs ont publié leur
     * format ; les échantillons produits avant sont mis en attente.
     * Retourne true si au moins la vidéo a été écrite jusqu'à la fin.
     */
    private fun runTranscodeLoop(
        vExtractor: MediaExtractor,
        vDecoder: MediaCodec,
        vEncoder: MediaCodec,
        aExtractor: MediaExtractor?,
        aDecoder: MediaCodec?,
        aEncoder: MediaCodec?,
        muxer: MediaMuxer,
    ): Boolean {
        val doAudio = aExtractor != null && aDecoder != null && aEncoder != null
        val startMs = System.currentTimeMillis()

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

        // Index d'un buffer de sortie du décodeur audio gardé en attente
        // tant que l'encodeur audio n'a pas de slot d'entrée libre.
        var pendingAudioDecoderOut = -1
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
            }
        }

        fun writeOrBuffer(track: Int, list: ArrayList<PendingSample>, buf: ByteBuffer, info: MediaCodec.BufferInfo) {
            if (muxing) {
                muxer.writeSampleData(track, buf, info)
            } else {
                val copy = ByteArray(info.size)
                buf.position(info.offset)
                buf.get(copy, 0, info.size)
                val ic = MediaCodec.BufferInfo()
                ic.set(0, info.size, info.presentationTimeUs, info.flags)
                list.add(PendingSample(copy, ic))
            }
        }

        while (!videoEncoderDone || !audioEncoderDone) {
            if (System.currentTimeMillis() - startMs > TRANSCODE_MAX_MS) {
                Log.w(TAG, "transcode: dépassement du budget temps → abandon")
                return false
            }

            // ---- 1. Alimente le décodeur vidéo -------------------------
            if (!videoExtractorDone) {
                val inIdx = vDecoder.dequeueInputBuffer(CODEC_TIMEOUT_US)
                if (inIdx >= 0) {
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
                    videoMuxTrack = muxer.addTrack(vEncoder.outputFormat)
                    videoFormatReady = true
                    maybeStartMuxer()
                } else if (outIdx >= 0) {
                    val encBuf = vEncoder.getOutputBuffer(outIdx)!!
                    if ((vEncInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                        vEncInfo.size = 0
                    }
                    if (vEncInfo.size > 0 && videoMuxTrack >= 0) {
                        writeOrBuffer(videoMuxTrack, pendingVideo, encBuf, vEncInfo)
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
                        pendingAudioDecoderOut = o
                    }
                    // INFO_OUTPUT_FORMAT_CHANGED / TRY_AGAIN : on ignore.
                }
                if (pendingAudioDecoderOut >= 0) {
                    val inIdx = aEncoder!!.dequeueInputBuffer(CODEC_TIMEOUT_US)
                    if (inIdx >= 0) {
                        val eos = (audioDecInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        val pcm = aDecoder!!.getOutputBuffer(pendingAudioDecoderOut)!!
                        val encIn = aEncoder.getInputBuffer(inIdx)!!
                        encIn.clear()
                        if (audioDecInfo.size > 0) {
                            pcm.position(audioDecInfo.offset)
                            pcm.limit(audioDecInfo.offset + audioDecInfo.size)
                            encIn.put(pcm)
                        }
                        aEncoder.queueInputBuffer(
                            inIdx, 0, audioDecInfo.size, audioDecInfo.presentationTimeUs,
                            if (eos) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0,
                        )
                        aDecoder.releaseOutputBuffer(pendingAudioDecoderOut, false)
                        pendingAudioDecoderOut = -1
                        if (eos) audioDecoderDone = true
                    }
                }
            }

            // ---- 6. Audio : encodeur AAC → muxer -----------------------
            if (doAudio && !audioEncoderDone) {
                val outIdx = aEncoder!!.dequeueOutputBuffer(aEncInfo, CODEC_TIMEOUT_US)
                if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    audioMuxTrack = muxer.addTrack(aEncoder.outputFormat)
                    audioFormatReady = true
                    maybeStartMuxer()
                } else if (outIdx >= 0) {
                    val encBuf = aEncoder.getOutputBuffer(outIdx)!!
                    if ((aEncInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                        aEncInfo.size = 0
                    }
                    if (aEncInfo.size > 0 && audioMuxTrack >= 0) {
                        writeOrBuffer(audioMuxTrack, pendingAudio, encBuf, aEncInfo)
                    }
                    val eos = (aEncInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                    aEncoder.releaseOutputBuffer(outIdx, false)
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
        return true
    }

    /** Débit cible H.264 ~ proportionnel à la résolution, borné. */
    private fun estimateVideoBitrate(width: Int, height: Int): Int {
        val pixels = width.toLong() * height.toLong()
        // ~4 bits/pixel : confortable pour de la TNT ré-encodée, borné
        // entre 1,5 Mbps (SD) et 12 Mbps (Full HD+).
        val bps = pixels * 4
        return bps.coerceIn(1_500_000L, 12_000_000L).toInt()
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
