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
//      Copie le fichier .ts depuis le stockage privé app vers
//      Movies/7MOTION/<displayName>.mp4 dans MediaStore.
//      Retourne true si la copie a réussi.
//
//  Stratégie : on RENOMME .ts en .mp4 sans transcoder. La plupart
//  des players (galerie native Android, VLC, MX Player, etc.)
//  acceptent un MPEG-TS dans un container .mp4 — c'est un mismatch
//  MIME bénin. Évite la complexité d'embarquer ffmpeg (50 MB).
// =========================================================

package com.manzilionellm.tvking

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class GalleryExporter(
    messenger: BinaryMessenger,
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "GalleryExporter"
        private const val CHANNEL = "com.manzilionellm.tvking/gallery"
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

            Log.i(TAG, "Inserting MediaStore entry: $finalDisplayName ($srcSize bytes)")
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

            // Copie .ts → MediaStore (re-écrit l'extension en .mp4
            // dans le DISPLAY_NAME, mais les bytes sont du MPEG-TS
            // brut — la plupart des players décodent quand même).
            context.contentResolver.openOutputStream(uri)?.use { out ->
                FileInputStream(srcFile).use { input ->
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
        }
    }
}
