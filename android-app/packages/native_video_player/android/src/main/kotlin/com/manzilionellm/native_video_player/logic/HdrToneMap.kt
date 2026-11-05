package com.manzilionellm.native_video_player.logic

/**
 * HDR sur un écran qui ne sait pas l'afficher (émulateur, beaucoup de
 * Fire Stick branchés en SDR) : le décodeur matériel sort des trames
 * noires et le son continue. À partir d'Android 12 (API 31) on peut
 * demander au codec de convertir vers le SDR
 * (KEY_COLOR_TRANSFER_REQUEST). Sur un vrai écran HDR on ne demande
 * rien : l'image garde ses métadonnées.
 */
object HdrToneMap {
    const val MIN_SDK = 31

    fun requestSdr(displaySupportsHdr: Boolean, sdkInt: Int, transferIsHdr: Boolean): Boolean =
        transferIsHdr && !displaySupportsHdr && sdkInt >= MIN_SDK
}
