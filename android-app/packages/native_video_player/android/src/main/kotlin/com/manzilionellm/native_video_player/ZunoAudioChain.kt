package com.manzilionellm.native_video_player

import androidx.media3.common.PlaybackParameters
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.AudioProcessorChain
import androidx.media3.common.audio.SonicAudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.SilenceSkippingAudioProcessor

/**
 * Même chaîne que [androidx.media3.exoplayer.audio.DefaultAudioSink.DefaultAudioProcessorChain],
 * plus trois sondes. Chaque sonde renvoie NOT_SET tant qu'elle est coupée :
 * Media3 ne la met pas dans les processeurs actifs. Voix claire coupée,
 * silences non sautés, vitesse 1 : aucun processeur actif, le PCM va
 * droit à l'AudioTrack, comme avant.
 *
 * Ordre : sonde décodeur, voix claire, sonde voix, silence, sonde silence,
 * Sonic, sonde AudioTrack. ToInt16, le mapping et le trim restent DEVANT,
 * ajoutés par le sink. Ils ne sont pas des passe-bas.
 */
@UnstableApi
class ZunoAudioChain(
    probeDecoder: AudioProbeProcessor,
    clearVoice: ClearVoiceProcessor,
    probeVoice: AudioProbeProcessor,
    probeSilence: AudioProbeProcessor,
    probeSink: AudioProbeProcessor,
) : AudioProcessorChain {

    private val silence = SilenceSkippingAudioProcessor()
    private val sonic = SonicAudioProcessor()
    private val processors = arrayOf<AudioProcessor>(
        probeDecoder,
        clearVoice,
        probeVoice,
        silence,
        probeSilence,
        sonic,
        probeSink,
    )

    override fun getAudioProcessors(): Array<AudioProcessor> = processors

    /**
     * Fréquence de SORTIE demandée à Sonic (essai « Sortie : 48 kHz »,
     * 04/10/2026). [SonicAudioProcessor.SAMPLE_RATE_NO_CHANGE] = la
     * fréquence du flux, comme avant (défaut). Pris en compte à la prochaine
     * configuration du sink : l'appelant rouvre la chaîne si elle joue.
     * Pourquoi : la fiche montre un flux AAC 44,1 kHz sorti en 44,1 kHz ;
     * sur certaines box, c'est la conversion 44,1 → 48 kHz de la puce qui
     * abîme le son. Ici l'app rééchantillonne elle-même avant la sortie.
     */
    fun setOutputSampleRateHz(hz: Int) {
        sonic.setOutputSampleRateHz(hz)
    }

    override fun applyPlaybackParameters(playbackParameters: PlaybackParameters): PlaybackParameters {
        sonic.setSpeed(playbackParameters.speed)
        sonic.setPitch(playbackParameters.pitch)
        return playbackParameters
    }

    override fun applySkipSilenceEnabled(skipSilenceEnabled: Boolean): Boolean {
        silence.setEnabled(skipSilenceEnabled)
        return skipSilenceEnabled
    }

    override fun getMediaDuration(playoutDuration: Long): Long {
        return if (sonic.isActive) sonic.getMediaDuration(playoutDuration) else playoutDuration
    }

    override fun getSkippedOutputFrameCount(): Long = silence.getSkippedFrames()
}
