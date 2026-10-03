package com.manzilionellm.native_video_player.logic

/**
 * Quand changer de moteur vidéo, et vers lequel.
 *
 * On ne change PAS pour un trou de réseau, un direct en retard, ni une
 * erreur audio. On change seulement si le décodeur vidéo a échoué
 * ([PictureSignal.DECODE]) ou si l'image est noire / figée alors que
 * la lecture est prête ([PictureSignal.BLACK_OR_FROZEN]).
 *
 * Échelle, toujours vers l'avant (on ne revient pas au matériel tout
 * seul : c'est lui qui vient d'échouer) :
 *   matériel → logiciel → FFmpeg, si la bibliothèque vidéo est là.
 * Quand il n'y a plus de marche, [Decision.giveUp] : l'écran montre
 * l'erreur, il ne relance pas le même décodeur en boucle.
 *
 * Les numéros sont ceux de Media3 1.5 `PlaybackException` :
 *   1002 direct en retard, 1003 délai dépassé,
 *   2000–2099 réseau / fichier,
 *   4001–4005 décodeur,
 *   5001–5099 piste audio (AudioTrack).
 */
enum class PictureSignal {
    DECODE,
    BLACK_OR_FROZEN,
    NETWORK,
    AUDIO,
    OTHER,
}

object DecoderFallback {
    data class Decision(
        val engine: VideoEngine,
        val reopen: Boolean,
        val giveUp: Boolean,
    )

    fun classify(errorCode: Int, rendererName: String?): PictureSignal {
        val name = rendererName.orEmpty()
        val video = name.contains("Video", ignoreCase = true)
        val audio = name.contains("Audio", ignoreCase = true)
        if (errorCode in 5001..5099) return PictureSignal.AUDIO
        if (errorCode in 4001..4005) {
            if (audio && !video) return PictureSignal.AUDIO
            return PictureSignal.DECODE
        }
        if (errorCode in 2000..2099 || errorCode == 1002 || errorCode == 1003) {
            return PictureSignal.NETWORK
        }
        return PictureSignal.OTHER
    }

    /**
     * [tried] = moteurs déjà écartés pour CETTE chaîne. [current] est
     * aussi écarté : on ne le réessaie pas dans la foulée.
     */
    fun next(
        current: VideoEngine,
        signal: PictureSignal,
        ffmpegVideoReady: Boolean,
        tried: Set<VideoEngine>,
    ): Decision {
        if (signal != PictureSignal.DECODE && signal != PictureSignal.BLACK_OR_FROZEN) {
            return Decision(current, reopen = false, giveUp = false)
        }
        val ladder = ArrayList<VideoEngine>(3)
        ladder.add(VideoEngine.HARDWARE)
        ladder.add(VideoEngine.SOFTWARE)
        if (ffmpegVideoReady) ladder.add(VideoEngine.FFMPEG)
        val start = ladder.indexOf(current).coerceAtLeast(0)
        val blocked = tried + current
        for (i in (start + 1) until ladder.size) {
            val candidate = ladder[i]
            if (candidate !in blocked) {
                return Decision(candidate, reopen = true, giveUp = false)
            }
        }
        return Decision(current, reopen = false, giveUp = true)
    }
}

/**
 * Image noire ou figée. On ne conclut PAS pendant le chargement :
 * un flux lent n'est pas un décodeur cassé.
 *
 *  - noire : le décodeur est créé, la lecture est prête, aucune trame
 *    après [timeoutMs] ;
 *  - figée : des trames sont déjà passées, la lecture tourne, plus
 *    aucune trame depuis [timeoutMs].
 */
object PictureHealth {
    fun black(
        decoderReady: Boolean,
        framesRendered: Int,
        playbackReady: Boolean,
        buffering: Boolean,
        elapsedMs: Long,
        timeoutMs: Long = 8_000L,
    ): Boolean {
        if (!decoderReady || !playbackReady || buffering) return false
        if (framesRendered > 0) return false
        return elapsedMs >= timeoutMs
    }

    fun frozen(
        framesRendered: Int,
        playing: Boolean,
        buffering: Boolean,
        msSinceLastFrame: Long,
        timeoutMs: Long = 8_000L,
    ): Boolean {
        if (framesRendered <= 0 || !playing || buffering) return false
        return msSinceLastFrame >= timeoutMs
    }
}
