package com.manzilionellm.native_video_player

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import com.manzilionellm.native_video_player.logic.AudioFixes
import com.manzilionellm.native_video_player.logic.AudioSpectrum
import java.nio.ByteBuffer

/**
 * Sonde PCM : elle MESURE le son, elle ne le modifie pas.
 *
 * Coupée par défaut ([AudioFixes.probe] faux, et [enabled] faux).
 * [onConfigure] renvoie alors NOT_SET : Media3 ne l'insère pas dans
 * la chaîne, exactement comme [ClearVoiceProcessor] quand « voix claire »
 * est coupée. Le chemin audio par défaut ne change pas.
 *
 * Allumée : on copie les échantillons tels quels vers la sortie, et on
 * en garde une statistique (énergie au-dessus de 4 kHz, saturation).
 * Aucun gain, aucun filtre sur le son qui sort.
 */
@UnstableApi
class AudioProbeProcessor(
    val stage: String,
    private val onJudgement: (String, AudioSpectrum.Judgement) -> Unit,
) : BaseAudioProcessor() {

    @Volatile
    var enabled: Boolean = false

    private var acc: AudioSpectrum.Accum = AudioSpectrum.start(48_000)
    private var perChannel: List<AudioSpectrum.Accum> = emptyList()
    private var lastKey: String? = null

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (!enabled || inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            return AudioProcessor.AudioFormat.NOT_SET
        }
        if (inputAudioFormat.sampleRate < 1 || inputAudioFormat.channelCount < 1) {
            return AudioProcessor.AudioFormat.NOT_SET
        }
        acc = AudioSpectrum.start(inputAudioFormat.sampleRate)
        perChannel = List(inputAudioFormat.channelCount.coerceIn(1, 8)) {
            AudioSpectrum.start(inputAudioFormat.sampleRate)
        }
        lastKey = null
        // Même format en sortie : Media3 ne rééchantillonne pas à cause de nous.
        return inputAudioFormat
    }

    override fun onFlush() {
        val rate = if (acc.sampleRate > 0) acc.sampleRate else 48_000
        val nch = perChannel.size.coerceAtLeast(1)
        acc = AudioSpectrum.start(rate)
        perChannel = List(nch) { AudioSpectrum.start(rate) }
        lastKey = null
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining <= 0) return
        val output = replaceOutputBuffer(remaining)
        val active = enabled && inputAudioFormat.encoding == C.ENCODING_PCM_16BIT
        if (!active) {
            output.put(inputBuffer)
            output.flip()
            return
        }
        val dup = inputBuffer.duplicate()
        dup.order(inputBuffer.order())
        val n = dup.remaining() / 2
        if (n > 0) {
            val pcm = ShortArray(n)
            var i = 0
            while (i < n && dup.remaining() >= 2) {
                pcm[i] = dup.short
                i++
            }
            val channels = inputAudioFormat.channelCount.coerceAtLeast(1)
            acc = AudioSpectrum.push(acc, pcm, channels)
            if (perChannel.size == channels) {
                perChannel = perChannel.mapIndexed { index, channelAcc ->
                    AudioSpectrum.pushChannel(channelAcc, pcm, channels, index)
                }
            }
            val ratios = perChannel.map { AudioSpectrum.judge(it).highRatio }
            val judged = AudioSpectrum.judge(acc).copy(channelHighRatios = ratios)
            publish(judged)
        }
        // Le tampon d'entrée repart inchangé. On ne touche pas un seul échantillon.
        output.put(inputBuffer)
        output.flip()
    }

    /**
     * Quand la bande ou le pourcentage arrondi change. 2,0 % puis 0,8 %
     * sont la même classe « basse » : on veut quand même le nouveau chiffre.
     * On ignore la fenêtre trop courte.
     */
    private fun publish(judged: AudioSpectrum.Judgement) {
        when (judged.band) {
            AudioSpectrum.Band.SHORT, AudioSpectrum.Band.SILENCE -> return
            else -> Unit
        }
        val key = judged.band.name + " " + judged.percent()
        if (key == lastKey) return
        lastKey = key
        onJudgement(stage, judged)
    }
}
