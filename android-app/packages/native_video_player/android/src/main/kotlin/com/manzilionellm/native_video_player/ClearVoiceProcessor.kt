package com.manzilionellm.native_video_player

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import com.manzilionellm.native_video_player.logic.ClearVoiceGain
import java.nio.ByteBuffer

/**
 * Compresseur PCM 16 bits, coupé par défaut.
 *
 * Tant que [enabled] est faux au moment où Media3 configure la chaîne,
 * [onConfigure] renvoie NOT_SET : le processeur est inactif, aucun
 * copie de tampon, le son est celui d'avant. Le passthrough (AC-3, E-AC-3,
 * DTS) ne passe JAMAIS par ici : Media3 ne met les processeurs que sur
 * le PCM.
 *
 * Allumé : on réduit les pics (voix qui crie d'une chaîne à l'autre,
 * mode nuit). On ne remonte pas le niveau moyen.
 */
@UnstableApi
class ClearVoiceProcessor : BaseAudioProcessor() {
    @Volatile
    var enabled: Boolean = false

    private var gain: Float = 1f

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (!enabled) return AudioProcessor.AudioFormat.NOT_SET
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            // Un format qu'on ne sait pas compresser : on ne le casse pas.
            return AudioProcessor.AudioFormat.NOT_SET
        }
        return inputAudioFormat
    }

    override fun onFlush() {
        gain = 1f
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining <= 0) return
        val output = replaceOutputBuffer(remaining)
        if (!enabled || inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            output.put(inputBuffer)
            output.flip()
            gain = 1f
            return
        }
        var peak = 0
        val scan = inputBuffer.duplicate()
        scan.order(inputBuffer.order())
        while (scan.remaining() >= 2) {
            val sample = scan.short.toInt()
            val abs = if (sample < 0) -sample else sample
            if (abs > peak) peak = abs
        }
        val peakUnit = peak / 32768f
        gain = ClearVoiceGain.smooth(gain, ClearVoiceGain.target(peakUnit))
        val applied = gain
        while (inputBuffer.remaining() >= 2) {
            val sample = inputBuffer.short.toInt()
            val scaled = (sample * applied).toInt().coerceIn(-32768, 32767)
            output.putShort(scaled.toShort())
        }
        if (inputBuffer.hasRemaining()) output.put(inputBuffer)
        output.flip()
    }
}
