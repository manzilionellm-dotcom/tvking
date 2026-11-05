package com.manzilionellm.native_video_player.ai

import android.content.Context
import org.json.JSONObject
import java.security.MessageDigest

/** Poids entraînés figés ; jamais de téléchargement pendant une lecture. */
internal class ArtCnnAssets private constructor(
    val text: Map<String, String>,
    val referenceInput: ByteArray,
    val referenceOutput: ByteArray,
) {
    companion object {
        const val MODEL = "ArtCNN_C4F16"
        const val MODEL_SHA = "7a6436299b8c757dbb7084ac39a25c310db1941133e73d1ee3e74c8b3bddc1ca"
        const val PIPELINE_SHA = "e93b490f33c147abcb6b3e11dd44038dcde80d953b361c48c325a502f74afcef"
        const val REFERENCE_WIDTH = 16
        const val REFERENCE_HEIGHT = 12

        fun load(context: Context): ArtCnnAssets {
            val files = listOf("vertex.glsl", "denoise.glsl") +
                (0..6).map { "conv$it.glsl" } +
                listOf("composite.glsl", "reference-input.rgba", "reference-output.rgba")
            val manifest = context.assets.open("zuno_ai/manifest.json").bufferedReader().use { JSONObject(it.readText()) }
            check(manifest.getString("modelSha256") == MODEL_SHA)
            check(manifest.getString("pipelineSha256") == PIPELINE_SHA)
            val hashes = manifest.getJSONObject("files")
            val fingerprint = StringBuilder()
            val data = files.associateWith { name ->
                val bytes = context.assets.open("zuno_ai/$name").use { it.readBytes() }
                val digest = sha256(bytes)
                check(digest == hashes.getString(name)) { "MODEL_INTEGRITY:$name" }
                fingerprint.append(name).append(':').append(digest).append('\n')
                bytes
            }
            check(sha256(fingerprint.toString().toByteArray(Charsets.UTF_8)) == PIPELINE_SHA)
            return ArtCnnAssets(data.filterKeys { it.endsWith(".glsl") }.mapValues { it.value.toString(Charsets.UTF_8) },
                data.getValue("reference-input.rgba"), data.getValue("reference-output.rgba"))
        }

        private fun sha256(data: ByteArray): String = MessageDigest.getInstance("SHA-256")
            .digest(data).joinToString("") { "%02x".format(it.toInt() and 255) }
    }
}
