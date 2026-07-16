package com.manzilionellm.native_video_player

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Fabrique appelée par Flutter à chaque fois qu'une PlatformView
 * `native_video_player/view` est créée côté Dart. Crée une [NativeVideoView]
 * et lui passe le messenger + l'id (pour ouvrir le MethodChannel dédié).
 */
class NativeVideoViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        // `preview=true` (posé côté Dart via creationParams) = APERÇU en
        // vignette : tampons ExoPlayer réduits (~8 Mo au lieu de 18-32 Mo).
        // Un aperçu n'a pas besoin de la résilience du plein écran, et sur
        // une box à faible RAM le gros tampon poussait l'app vers l'OOM.
        val preview = (args as? Map<*, *>)?.get("preview") == true
        return NativeVideoView(context, messenger, viewId, preview)
    }
}
