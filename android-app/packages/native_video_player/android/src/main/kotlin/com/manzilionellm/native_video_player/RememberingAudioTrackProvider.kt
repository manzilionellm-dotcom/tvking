package com.manzilionellm.native_video_player

import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import androidx.media3.common.AudioAttributes
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink

/**
 * Le fournisseur d'AudioTrack PAR DÉFAUT de Media3 1.5.1, plus une
 * référence gardée pour lire des compteurs.
 *
 * On ne personnalise pas le Builder : [DefaultAudioSink.AudioTrackProvider.DEFAULT]
 * construit la piste exactement comme avant (taille de tampon, mode flux,
 * pas de offload forcé). On retient l'objet seulement pour appeler des
 * lectures : getUnderrunCount, getLatency, getSampleRate. Aucun setter.
 */
@UnstableApi
class RememberingAudioTrackProvider : DefaultAudioSink.AudioTrackProvider {

    private val delegate: DefaultAudioSink.AudioTrackProvider =
        DefaultAudioSink.AudioTrackProvider.DEFAULT

    @Volatile
    private var current: AudioTrack? = null

    override fun getAudioTrack(
        audioTrackConfig: AudioSink.AudioTrackConfig,
        audioAttributes: AudioAttributes,
        audioSessionId: Int,
    ): AudioTrack {
        val track = delegate.getAudioTrack(audioTrackConfig, audioAttributes, audioSessionId)
        current = track
        return track
    }

    /** Piste encore initialisée, ou null. Une piste déjà rendue ne compte pas. */
    fun current(): AudioTrack? {
        val track = current ?: return null
        return try {
            if (track.state == AudioTrack.STATE_INITIALIZED) track else null
        } catch (_: IllegalStateException) {
            null
        }
    }
}

/**
 * Lectures Android, séparées du texte (le texte est dans AudioFormatMeter,
 * testé sans appareil). Tout est dans un try : un getter qui refuse
 * répond null, jamais une fiche inventée.
 */
object AudioTrackReadout {

    data class Raw(
        val underruns: Int? = null,
        val latencyMs: Int? = null,
        val bufferMs: Int? = null,
        val sampleRate: Int = 0,
        val deviceHz: Int? = null,
        val deviceFrames: Int? = null,
        val encoding: String? = null,
        val playbackSpeed: Float? = null,
    )

    fun read(track: AudioTrack?, manager: AudioManager?): Raw {
        val deviceHz = propertyInt(manager, AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)
        val deviceFrames = propertyInt(manager, AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)
        if (track == null) {
            return Raw(deviceHz = deviceHz, deviceFrames = deviceFrames)
        }
        return Raw(
            underruns = underruns(track),
            latencyMs = latencyMs(track),
            bufferMs = bufferMs(track),
            sampleRate = safe { track.sampleRate } ?: 0,
            deviceHz = deviceHz,
            deviceFrames = deviceFrames,
            encoding = encoding(track),
            playbackSpeed = playbackSpeed(track),
        )
    }

    private fun propertyInt(manager: AudioManager?, key: String): Int? {
        if (manager == null) return null
        val raw = try {
            manager.getProperty(key)
        } catch (_: RuntimeException) {
            null
        } ?: return null
        val n = raw.toIntOrNull() ?: return null
        return if (n > 0) n else null
    }

    /** API 24. Avant, seul le rappel Media3 existe. */
    private fun underruns(track: AudioTrack): Int? {
        if (Build.VERSION.SDK_INT < 24) return null
        return safe { track.underrunCount }
    }

    /**
     * Méthode cachée, la même que lit Media3 pour sa position.
     * Elle renvoie des millisecondes, tampon compris, et sur plusieurs
     * appareils elle compte ce tampon deux fois. On ne la divise pas :
     * la fiche montre le brut ET la taille du tampon.
     */
    private fun latencyMs(track: AudioTrack): Int? {
        return try {
            val method = AudioTrack::class.java.getMethod("getLatency")
            val value = method.invoke(track) as? Int ?: return null
            if (value < 0) null else value
        } catch (_: Throwable) {
            null
        }
    }

    private fun bufferMs(track: AudioTrack): Int? {
        if (Build.VERSION.SDK_INT < 23) return null
        val frames = safe { track.bufferSizeInFrames } ?: return null
        val rate = safe { track.sampleRate } ?: return null
        if (frames <= 0 || rate <= 0) return null
        return frames * 1000 / rate
    }

    private fun playbackSpeed(track: AudioTrack): Float? {
        if (Build.VERSION.SDK_INT < 23) return null
        return safe { track.playbackParams.speed }
    }

    private fun encoding(track: AudioTrack): String? {
        if (Build.VERSION.SDK_INT < 23) return null
        val format = safe { track.format } ?: return null
        return encodingName(format.encoding)
    }

    /**
     * Mêmes mots que la fiche « Sortie », pour qu'on compare sans
     * traduire deux vocabulaires. Les constantes Android et celles de
     * Media3 ont les mêmes numéros pour le PCM et le Dolby.
     */
    private fun encodingName(encoding: Int): String = when (encoding) {
        AudioFormat.ENCODING_PCM_16BIT -> "PCM 16 bits"
        AudioFormat.ENCODING_PCM_FLOAT -> "PCM flottant"
        // Android nomme ce codage PACKED (valeur 21). Media3 l'appelle ENCODING_PCM_24BIT.
        AudioFormat.ENCODING_PCM_24BIT_PACKED -> "PCM 24 bits"
        AudioFormat.ENCODING_PCM_32BIT -> "PCM 32 bits"
        AudioFormat.ENCODING_AC3 -> "AC-3"
        AudioFormat.ENCODING_E_AC3 -> "E-AC-3"
        AudioFormat.ENCODING_DTS -> "DTS"
        else -> "codage $encoding"
    }

    private inline fun <T> safe(block: () -> T): T? =
        try {
            block()
        } catch (_: RuntimeException) {
            null
        }
}
