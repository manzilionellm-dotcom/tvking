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
        return NativeVideoView(context, messenger, viewId)
    }
}
