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
//      Copie l'enregistrement depuis le stockage privé app vers
//      Movies/ dans MediaStore. Retourne true si la copie a réussi.
//
//  --- POURQUOI ON REMUXE (correctif "format non supporté") ----------
//  Les enregistrements IPTV sont des MPEG-TS (.ts) bruts. L'ancienne
//  stratégie se contentait de RENOMMER le .ts en .mp4 : les players
//  permissifs (VLC, MX) s'en accommodaient, mais la GALERIE native du
//  téléphone scanne le CONTENU réel du fichier — un .mp4 sans boîte
//  `moov` valide est rejeté → "format non pris en charge".
//
//  On REMUXE donc le flux dans un VRAI conteneur MP4 via les API
//  natives Android `MediaExtractor` (lit le TS) + `MediaMuxer` (écrit
//  le MP4) en COPIANT les pistes telles quelles :
//    - AUCUN ré-encodage, AUCUNE perte de qualité, AUCUN ffmpeg embarqué
//    - on ne touche PAS au pipeline d'enregistrement / de lecture vidéo
//    - le .mp4 produit est un vrai MP4 → accepté par la galerie de la
//      grande majorité des téléphones (codecs IPTV usuels H.264/HEVC +
//      AAC, supportés par MediaMuxer).
//
//  Repli : si un codec n'est pas muxable en MP4 (ex. audio AC3/MP2 sur
//  certains appareils), on retombe sur l'ancienne copie brute renommée
//  .mp4 — au pire l'export n'est pas pire qu'avant pour ces cas rares.
// =========================================================

package com.manzilionellm.tvking

import android.content.ContentValues
import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer

class GalleryExporter(
    messenger: BinaryMessenger,
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "GalleryExporter"
        private const val CHANNEL = "com.manzilionellm.tvking/gallery"
        // Taille plancher du tampon de copie d'échantillon. Une I-frame
        // 4K peut dépasser 1 MiB ; on prend large pour ne pas lever
        // "buffer too small" sur readSampleData. Honoré aussi via
        // KEY_MAX_INPUT_SIZE quand la piste le déclare.
        private const val MIN_BUFFER_BYTES = 4 * 1024 * 1024
    }

    private val channel: MethodChannel =
        MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler(this@GalleryExporter)
        }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "exportVideo" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                    exportVideo(args, result)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "method ${call.method} threw: $e")
            result.error("GALLERY_ERROR", e.message, null)
        }
    }

    private fun exportVideo(args: Map<String, Any?>, result: MethodChannel.Result) {
        val srcPath = args["srcPath"] as? String
        val displayName = args["displayName"] as? String

        if (srcPath.isNullOrBlank() || displayName.isNullOrBlank()) {
            result.error("INVALID_ARGS", "srcPath et displayName requis", null)
            return
        }

        val srcFile = File(srcPath)
        if (!srcFile.exists()) {
            Log.w(TAG, "Source introuvable: $srcPath")
            // result.error pour que le snackbar côté Dart affiche le motif
            // exact au lieu d'un "indisponible" vague.
            result.error("SRC_MISSING", "Fichier introuvable: $srcPath", null)
            return
        }
        val srcSize = srcFile.length()
        if (srcSize == 0L) {
            Log.w(TAG, "Source vide (0 octets): $srcPath")
            result.error(
                "SRC_EMPTY",
                "Fichier .ts vide — libmpv n'a peut-être pas eu le temps de flush",
                null,
            )
            return
        }

        // --- Étape 1 : remux TS → vrai MP4 (copie de pistes, sans ré-encoder).
        // Si ça échoue (codec non muxable, fichier exotique), `remuxed` est
        // null et on retombe sur la copie brute du .ts (ancien comportement).
        val remuxed: File? = remuxToMp4(srcFile)
        val dataFile: File = remuxed ?: srcFile
        if (remuxed == null) {
            Log.w(TAG, "Remux indisponible → copie brute (fallback) de $srcPath")
        } else {
            Log.i(TAG, "Remux OK: ${remuxed.length()} octets MP4 valides")
        }

        try {
            // Prépare l'entrée MediaStore. RELATIVE_PATH = Movies seulement
            // (pas de sous-dossier "7MOTION"). Plusieurs constructeurs Android
            // refusent la création de sous-dossier via MediaStore — c'est
            // implémentation-dépendant. À la place, on préfixe le nom du
            // fichier par "7MOTION_" pour qu'il soit reconnaissable dans
            // la liste de la galerie.
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
                    // IS_PENDING = 1 : le fichier est "en cours d'écriture",
                    // pas visible des autres apps. On le passe à 0 après
                    // que la copie soit complète — comportement atomique.
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
                ?: run {
                    Log.e(TAG, "MediaStore.insert returned null")
                    result.error(
                        "INSERT_NULL",
                        "MediaStore a refusé l'insertion (collection=$collection)",
                        null,
                    )
                    return
                }

            // Copie des octets (MP4 remuxé si dispo, sinon .ts brut) vers
            // l'entrée MediaStore.
            context.contentResolver.openOutputStream(uri)?.use { out ->
                FileInputStream(dataFile).use { input ->
                    val buffer = ByteArray(64 * 1024) // 64 KiB chunks
                    var bytes = input.read(buffer)
                    while (bytes >= 0) {
                        out.write(buffer, 0, bytes)
                        bytes = input.read(buffer)
                    }
                    out.flush()
                }
            } ?: throw java.io.IOException("openOutputStream returned null")

            // Marque le fichier comme "complet" pour Android 10+.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val finalize = ContentValues().apply {
                    put(MediaStore.Video.Media.IS_PENDING, 0)
                }
                context.contentResolver.update(uri, finalize, null, null)
            }

            Log.i(TAG, "Exported $srcPath → $uri")
            result.success(true)
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException: $e")
            result.error(
                "PERMISSION_DENIED",
                "Permission MediaStore refusée — vérifie les autorisations de l'app",
                null,
            )
        } catch (e: Exception) {
            Log.e(TAG, "exportVideo failed: $e")
            result.error("EXPORT_FAILED", e.message ?: e.javaClass.simpleName, null)
        } finally {
            // Nettoyage du MP4 temporaire (cache) une fois copié dans MediaStore.
            if (remuxed != null) {
                try {
                    remuxed.delete()
                } catch (e: Exception) {
                    Log.w(TAG, "Suppression temp remux échouée: ${e.message}")
                }
            }
        }
    }

    /**
     * Remux un fichier (MPEG-TS typiquement) vers un VRAI conteneur MP4
     * en COPIANT les pistes encodées telles quelles — pas de décodage,
     * pas de ré-encodage, pas de perte. Utilise uniquement les API
     * natives Android (MediaExtractor + MediaMuxer), aucune dépendance.
     *
     * Retourne le fichier .mp4 temporaire (dans le cache) en cas de
     * succès, ou `null` si le remux est impossible (codec non muxable
     * en MP4, fichier illisible…) — l'appelant retombe alors sur la
     * copie brute.
     */
    private fun remuxToMp4(srcFile: File): File? {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        val outFile = File(context.cacheDir, "export_${System.currentTimeMillis()}.mp4")
        try {
            extractor.setDataSource(srcFile.absolutePath)
            val trackCount = extractor.trackCount
            if (trackCount == 0) return null

            muxer = MediaMuxer(
                outFile.absolutePath,
                MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4,
            )

            // Associe chaque piste lisible (vidéo/audio) à une piste du muxer.
            val indexMap = HashMap<Int, Int>()
            var maxInputSize = MIN_BUFFER_BYTES
            var hasVideo = false
            for (i in 0 until trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) continue
                try {
                    val muxIndex = muxer.addTrack(format)
                    indexMap[i] = muxIndex
                    if (mime.startsWith("video/")) hasVideo = true
                    if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                        val s = format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                        if (s > maxInputSize) maxInputSize = s
                    }
                } catch (e: Exception) {
                    // Codec non supporté par MediaMuxer (ex. AC3 sur certains
                    // appareils) → on ignore cette piste plutôt que d'échouer.
                    Log.w(TAG, "addTrack a refusé la piste '$mime': ${e.message}")
                }
            }

            // Sans piste vidéo muxable, le remux n'a pas d'intérêt → fallback.
            if (!hasVideo || indexMap.isEmpty()) {
                Log.w(TAG, "Aucune piste vidéo muxable → fallback copie brute")
                return null
            }

            for (srcIndex in indexMap.keys) extractor.selectTrack(srcIndex)

            muxer.start()
            var buffer = ByteBuffer.allocate(maxInputSize)
            val bufferInfo = MediaCodec.BufferInfo()
            // Dernier PTS écrit par piste — garantit un horodatage
            // strictement non-décroissant (exigence MediaMuxer). Les flux
            // IPTV (MPEG-TS) ont fréquemment des discontinuités de PTS
            // (coupures pub, resets de flux) : sans ce garde-fou, le 1er
            // recul de PTS faisait lever writeSampleData → tout le remux
            // échouait et on retombait sur le .ts cassé.
            val lastPts = HashMap<Int, Long>()
            while (true) {
                // Lecture de l'échantillon. Si le tampon est trop petit pour
                // cette frame (grosse I-frame 4K), readSampleData lève
                // IllegalArgumentException → on double le tampon et on relit
                // le MÊME échantillon (advance() n'a pas encore été appelé).
                var sampleSize: Int
                while (true) {
                    try {
                        sampleSize = extractor.readSampleData(buffer, 0)
                        break
                    } catch (e: IllegalArgumentException) {
                        val newCap = buffer.capacity() * 2
                        Log.w(TAG, "Tampon trop petit (${buffer.capacity()}) → $newCap")
                        buffer = ByteBuffer.allocate(newCap)
                    }
                }
                if (sampleSize < 0) break
                val dstTrack = indexMap[extractor.sampleTrackIndex]
                if (dstTrack != null) {
                    var pts = extractor.sampleTime
                    if (pts < 0) pts = 0
                    // Force la monotonie : si le PTS recule ou stagne, on le
                    // repousse d'1 µs au-dessus du précédent sur cette piste.
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
            return outFile
        } catch (e: Exception) {
            // Remux impossible : on nettoie le temp et on signale le fallback.
            Log.w(TAG, "Remux échoué (${e.javaClass.simpleName}: ${e.message}) → fallback")
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
