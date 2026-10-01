package com.manzilionellm.native_video_player

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import com.manzilionellm.native_video_player.logic.AudioSpectrum
import com.manzilionellm.native_video_player.logic.ProbeAttach
import java.nio.ByteBuffer

/**
 * Sonde PCM : elle MESURE le son, elle ne le modifie pas.
 *
 * Coupée par défaut ([enabled] faux).
 * [onConfigure] renvoie alors NOT_SET : Media3 ne l'insère pas dans
 * la chaîne, exactement comme [ClearVoiceProcessor] quand « voix claire »
 * est coupée. Le chemin audio par défaut ne change pas.
 *
 * Allumer [enabled] APRÈS un onConfigure ne suffit pas : Media3 ne
 * rappelle onConfigure qu'à la prochaine configuration du sink. Le
 * lecteur rouvre la chaîne quand on allume le réglage.
 *
 * [onFlush] ne remet pas le compteur à zéro. Media3 flush quand
 * l'horloge du direct saute : l'ancien compteur n'atteignait jamais
 * la fenêtre, et la fiche restait sans mesure. Le PCM copié, lui,
 * ne change pas.
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

    /** Dernier onConfigure a accepté le PCM. Faux = NOT_SET, sonde hors chaîne. */
    @Volatile
    var lastAccepted: Boolean = false

    /** Pourquoi le dernier onConfigure a refusé. Null si accepté ou jamais appelé. */
    @Volatile
    var lastReject: String? = null

    /** Trames vues depuis le dernier onConfigure. Un flush ne les efface pas. */
    @Volatile
    var usefulFrames: Int = 0

    private var acc: AudioSpectrum.Accum = AudioSpectrum.start(48_000)
    private var perChannel: List<AudioSpectrum.Accum> = emptyList()
    private var lastKey: String? = null

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val decision = ProbeAttach.onConfigure(
            enabled = enabled,
            pcm16 = inputAudioFormat.encoding == C.ENCODING_PCM_16BIT,
            sampleRate = inputAudioFormat.sampleRate,
            channels = inputAudioFormat.channelCount,
        )
        lastAccepted = decision.accept
        lastReject = decision.reason
        usefulFrames = 0
        if (!decision.accept) {
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
        // Volontairement vide. Media3 appelle flush à chaque saut
        // d'horloge du direct (plus de 200 ms). Remettre [acc] à zéro
        // ici coupait la fenêtre avant 8 192 trames : la fiche restait
        // sans chiffre alors que la sonde était branchée.
        // onConfigure a déjà ouvert une fenêtre neuve si le format change.
        // Les échantillons écrits dans la sortie ne dépendent pas de ce compteur.
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
            usefulFrames = acc.frames
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
