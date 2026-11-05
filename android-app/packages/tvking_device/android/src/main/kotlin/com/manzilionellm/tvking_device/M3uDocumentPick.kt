package com.manzilionellm.tvking_device

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Sélecteur de document pour un fichier M3U déjà sur la box.
 * Le fichier est copié dans le cache de l'app, borné à 60 Mo
 * (le même plafond que l'import réseau). On ne lit ni la MAC
 * ni un compte.
 */
object M3uDocumentPick {
    const val REQUEST = 41041
    private const val MAX_BYTES = 60L * 1024L * 1024L

    private var pending: MethodChannel.Result? = null

    fun start(activity: Activity?, result: MethodChannel.Result) {
        if (activity == null) {
            result.success(mapOf("status" to "unavailable"))
            return
        }
        if (pending != null) {
            result.success(mapOf("status" to "unavailable"))
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "audio/x-mpegurl",
                    "application/vnd.apple.mpegurl",
                    "application/x-mpegurl",
                    "text/plain",
                ),
            )
        }
        try {
            activity.startActivityForResult(intent, REQUEST)
            pending = result
        } catch (_: Exception) {
            pending = null
            result.success(mapOf("status" to "unavailable"))
        }
    }

    fun onActivityResult(
        context: Context?,
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != REQUEST) return false
        val callback = pending
        pending = null
        if (callback == null) return true
        if (resultCode != Activity.RESULT_OK || data?.data == null || context == null) {
            callback.success(mapOf("status" to "cancelled"))
            return true
        }
        callback.success(copy(context, data.data!!))
        return true
    }

    private fun copy(context: Context, uri: Uri): Map<String, String> {
        return try {
            val dir = File(context.cacheDir, "m3u")
            if (!dir.exists()) dir.mkdirs()
            val out = File(dir, "liste-${System.currentTimeMillis()}.m3u")
            context.contentResolver.openInputStream(uri).use { input ->
                if (input == null) return mapOf("status" to "empty")
                FileOutputStream(out).use { output ->
                    val buffer = ByteArray(16 * 1024)
                    var total = 0L
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        total += n
                        if (total > MAX_BYTES) {
                            out.delete()
                            return mapOf("status" to "too_big")
                        }
                        if (n > 0) output.write(buffer, 0, n)
                    }
                }
            }
            if (!out.exists() || out.length() <= 0L) {
                out.delete()
                mapOf("status" to "empty")
            } else {
                mapOf("status" to "ok", "path" to out.absolutePath)
            }
        } catch (_: Exception) {
            mapOf("status" to "unavailable")
        }
    }
}
