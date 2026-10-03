package com.manzilionellm.native_video_player

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.media.audiofx.AudioEffect
import android.os.Build
import android.os.SystemClock
import com.manzilionellm.native_video_player.logic.AudioSystemEffects

/**
 * LECTURE SEULE des effets du système (03/10/2026).
 *
 * On interroge le catalogue ([AudioEffect.queryEffects]) et le
 * spatialiseur. On ne construit JAMAIS d'Equalizer, de BassBoost,
 * de Virtualizer, de LoudnessEnhancer ni de DynamicsProcessing :
 * le constructeur brancherait l'effet sur la session et changerait
 * le son. Le catalogue dit ce qui est INSTALLÉ, pas ce qui est allumé.
 *
 * La fréquence et la taille de tampon viennent de
 * [AudioManager.getProperty] : c'est le chemin rapide de l'appareil,
 * pas forcément la piste média de Zuno. Le micro vient de
 * [AudioManager.isMicrophoneMute].
 */
object SystemEffectsRead {

    /** Le catalogue ne change pas pendant que l'app tourne : on le lit une fois. */
    private var catalog: List<AudioSystemEffects.Engine>? = null
    private var catalogFailed = false

    /** Le spatialiseur et le micro ne bougent pas à chaque fenêtre PCM. */
    private var cached: AudioSystemEffects.Sheet? = null
    private var cachedKey: String = ""
    private var cachedAtMs: Long = 0L

    fun sheet(
        am: AudioManager?,
        sessionId: Int,
        mode: Int,
        plays: List<AudioSystemEffects.Play>,
    ): AudioSystemEffects.Sheet {
        val key = buildString {
            append(sessionId).append('|').append(mode).append('|')
            for (p in plays) {
                append(p.usage).append(':').append(p.contentType).append(':')
                append(p.flags).append(':').append(p.flagsComplete).append(':')
                append(p.deviceType).append(':').append(p.ours).append(';')
            }
        }
        val now = SystemClock.elapsedRealtime()
        val hit = cached
        if (hit != null && key == cachedKey && now - cachedAtMs < 2_000L) return hit
        val engines = catalog()
        val built = AudioSystemEffects.Sheet(
            sessionId = sessionId,
            engines = engines,
            catalogRead = catalog != null,
            catalogFailed = catalogFailed,
            outputSampleRate = propInt(am, AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE),
            framesPerBuffer = propInt(am, AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER),
            micMuted = mic(am),
            spatial = spatial(am),
            plays = plays,
            mode = mode,
        )
        cached = built
        cachedKey = key
        cachedAtMs = now
        return built
    }

    /**
     * Drapeaux de cette lecture. On essaie d'abord getAllFlags (caché) :
     * c'est lui qui porte le bit SCO (chemin d'appel). Android 16 peut
     * le refuser : on retombe alors sur les drapeaux publics, et on le dit.
     */
    fun flagsOf(config: AudioPlaybackConfiguration): Pair<Int, Boolean> {
        val attrs = config.audioAttributes
        return try {
            val method = attrs.javaClass.getMethod("getAllFlags")
            val value = method.invoke(attrs) as? Int
            if (value == null) attrs.flags to false else value to true
        } catch (_: Throwable) {
            attrs.flags to false
        }
    }

    private fun catalog(): List<AudioSystemEffects.Engine> {
        catalog?.let { return it }
        if (catalogFailed) return emptyList()
        return try {
            val raw = AudioEffect.queryEffects()
            val list = raw?.map { describe(it) } ?: emptyList()
            catalog = list
            list
        } catch (_: Throwable) {
            // Un catalogue illisible ne doit pas casser la lecture.
            catalogFailed = true
            emptyList()
        }
    }

    private fun describe(d: AudioEffect.Descriptor): AudioSystemEffects.Engine {
        return AudioSystemEffects.Engine(
            name = d.name ?: "",
            implementor = d.implementor ?: "",
            typeUuid = d.type?.toString()?.lowercase() ?: "",
            connectMode = d.connectMode ?: "",
        )
    }

    private fun propInt(am: AudioManager?, key: String): Int {
        if (am == null) return -1
        val raw = try {
            am.getProperty(key)
        } catch (_: Throwable) {
            null
        } ?: return -1
        return raw.trim().toIntOrNull() ?: -1
    }

    private fun mic(am: AudioManager?): Boolean? {
        if (am == null) return null
        return try {
            am.isMicrophoneMute
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * Le spatialiseur se lit. On ne l'allume pas, on n'écoute pas ses
     * changements. canBeSpatialized répond pour un film stéréo 48 kHz
     * et pour un 5.1 : ce sont des questions, pas une lecture.
     */
    private fun spatial(am: AudioManager?): AudioSystemEffects.Spatial? {
        if (am == null || Build.VERSION.SDK_INT < 32) return null
        return try {
            val sp = am.spatializer
            val movie = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                .build()
            AudioSystemEffects.Spatial(
                level = sp.immersiveAudioLevel,
                available = sp.isAvailable,
                enabled = sp.isEnabled,
                headTracker = try {
                    sp.isHeadTrackerAvailable
                } catch (_: Throwable) {
                    null
                },
                stereoMovie = sp.canBeSpatialized(movie, pcm(AudioFormat.CHANNEL_OUT_STEREO)),
                fiveOneMovie = sp.canBeSpatialized(movie, pcm(AudioFormat.CHANNEL_OUT_5POINT1)),
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun pcm(channelMask: Int): AudioFormat {
        return AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(48_000)
            .setChannelMask(channelMask)
            .build()
    }
}
