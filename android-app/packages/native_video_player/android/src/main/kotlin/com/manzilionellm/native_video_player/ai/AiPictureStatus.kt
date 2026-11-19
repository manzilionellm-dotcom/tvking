package com.manzilionellm.native_video_player.ai

import com.manzilionellm.native_video_player.logic.AiBypassReason
import com.manzilionellm.native_video_player.logic.AiFrameDecision

/** Métadonnées du traitement observé, jamais une note de qualité inventée. */
@ConsistentCopyVisibility
data class AiPictureStatus internal constructor(
    val sessionId: Int,
    val active: Boolean,
    val reason: AiBypassReason?,
    val sourceWidth: Int,
    val sourceHeight: Int,
    val outputWidth: Int,
    val outputHeight: Int,
    private val decision: AiFrameDecision,
    private val capabilities: AiCapabilities?,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "sessionId" to sessionId, "active" to active, "reason" to reason?.name,
        "sourceWidth" to sourceWidth, "sourceHeight" to sourceHeight,
        "outputWidth" to outputWidth, "outputHeight" to outputHeight,
        "scale" to if (active) 2 else 1,
        "model" to ArtCnnAssets.MODEL,
        "modelSha256" to ArtCnnAssets.MODEL_SHA,
        "pipelineSha256" to ArtCnnAssets.PIPELINE_SHA,
        "score" to decision.score, "p95Ms" to decision.p95Ms,
        "gpuRenderer" to capabilities?.renderer, "gpuVersion" to capabilities?.version,
        // Android n'expose pas une capacité VRAM portable sur les GPU partagés.
        "dedicatedVramBytes" to null,
        "availableSystemBytes" to capabilities?.availableSystemBytes,
        "npuFeatureAdvertised" to capabilities?.npuFeatureAdvertised,
        "npuBackendUsed" to false, "backend" to if (active) "gles_artcnn" else "native",
    )
}

internal data class AiCapabilities(
    val renderer: String,
    val version: String,
    val driverId: String,
    val maxTextureSize: Int,
    val es3: Boolean,
    val availableSystemBytes: Long?,
    val npuFeatureAdvertised: Boolean,
    val refusal: AiBypassReason?,
)
