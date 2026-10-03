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

    /**
     * Dernière vitesse et hauteur remises à Sonic. 1 et 1 au départ :
     * tant que le direct reste figé, Sonic ne se met pas en route.
     * Lecture seule, pour la fiche.
     */
    @Volatile
    private var appliedSpeed: Float = 1f

    @Volatile
    private var appliedPitch: Float = 1f
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

    override fun applyPlaybackParameters(playbackParameters: PlaybackParameters): PlaybackParameters {
        appliedSpeed = playbackParameters.speed
        appliedPitch = playbackParameters.pitch
        sonic.setSpeed(playbackParameters.speed)
        sonic.setPitch(playbackParameters.pitch)
        return playbackParameters
    }

    /** Sonic est-il dans la chaîne active ? Null si onConfigure n'a pas encore répondu. */
    fun sonicActive(): Boolean? = try {
        sonic.isActive
    } catch (_: RuntimeException) {
        null
    }

    fun sonicSpeed(): Float = appliedSpeed

    fun sonicPitch(): Float = appliedPitch

    override fun applySkipSilenceEnabled(skipSilenceEnabled: Boolean): Boolean {
        silence.setEnabled(skipSilenceEnabled)
        return skipSilenceEnabled
    }

    override fun getMediaDuration(playoutDuration: Long): Long {
        return if (sonic.isActive) sonic.getMediaDuration(playoutDuration) else playoutDuration
    }

    override fun getSkippedOutputFrameCount(): Long = silence.getSkippedFrames()
}
