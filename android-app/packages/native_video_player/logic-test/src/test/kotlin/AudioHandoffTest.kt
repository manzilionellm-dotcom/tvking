import com.manzilionellm.native_video_player.logic.AacRoute
import com.manzilionellm.native_video_player.logic.AudioGate
import com.manzilionellm.native_video_player.logic.AudioHandoff
import com.manzilionellm.native_video_player.logic.PlayerCensus
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 50 zaps entre formats différents, puis 10 sorties / retours.
 * À chaque pas : un seul décodeur, un seul AudioTrack, volume jamais
 * à 0,2, et un repli qui ne se propage pas à une autre chaîne.
 *
 * Le test REJOUE l'ordre réel de Media3 1.5.1 : stop() ne rend pas
 * l'AudioTrack tout de suite. On n'ouvre qu'après le rendu, comme
 * [AudioGate] le fait dans le lecteur. Le test ÉCHOUE s'il reste
 * plus d'un vivant.
 */
class AudioHandoffTest {

    private val formats = listOf(
        "test://aac-lc-48k-stereo",
        "test://mp2-44k1-stereo",
        "test://aac-5-1",
        "test://he-aac-24k",
    )

    @BeforeTest
    fun fresh() {
        PlayerCensus.reset()
        AacRoute.forgetAll()
        AacRoute.sessionWide = false
    }

    @AfterTest
    fun clean() {
        PlayerCensus.reset()
        AacRoute.forgetAll()
        AacRoute.sessionWide = false
    }

    @Test
    fun cinquanteZapsEtDixRetoursLaissentUnSeulDeChaque() {
        PlayerCensus.playerCreated()
        var maxTracks = 0
        var maxDecoders = 0
        val gate = AudioGate { false }
        var volume = AudioHandoff.VOLUME_FULL

        fun note() {
            val t = PlayerCensus.tracksAlive()
            val d = PlayerCensus.decodersAlive()
            if (t > maxTracks) maxTracks = t
            if (d > maxDecoders) maxDecoders = d
            assertTrue(t <= 1, "AudioTrack vivants : $t")
            assertTrue(d <= 1, "décodeurs vivants : $d")
            assertTrue(volume != AudioHandoff.VOLUME_DUCK_FORBIDDEN)
        }

        // Rend l'ancienne piste PUIS seulement on autorise l'ouverture.
        // C'est le délai de Media3, rejoué sans Android.
        fun openOne(url: String) {
            PlayerCensus.onZap(AacRoute.key(url))
            var tick = gate.onStopped(PlayerCensus.tracksAlive())
            if (!tick.prepare) {
                if (PlayerCensus.tracksAlive() > 0) PlayerCensus.audioTrackClosed()
                if (PlayerCensus.decodersAlive() > 0) PlayerCensus.audioDecoderClosed()
                note()
                tick = gate.onTracksAlive(PlayerCensus.tracksAlive())
                assertTrue(tick.prepare, tick.line)
            }
            PlayerCensus.audioDecoderOpened()
            PlayerCensus.audioTrackOpened()
            // Baisse demandée : le volume reste 1.
            volume = AudioHandoff.outputVolume(handoffMute = false, duckRequested = true)
            assertEquals(AudioHandoff.VOLUME_FULL, volume)
            note()
        }

        repeat(50) { n ->
            val url = formats[n % formats.size]
            // n = 22 → formats[2]. Une panne ICI ne doit pas toucher formats[0].
            if (n == 22) {
                val zap = PlayerCensus.snapshot(AacRoute.key(url), null).zap + 1
                AacRoute.markFailed(url, AacRoute.Reason.TIMEOUT, zap)
            }
            openOne(url)
        }
        // Retour sur la première : toujours FFmpeg (le repli est sur une autre).
        val back = formats[0]
        openOne(back)
        assertNull(AacRoute.boxFor(back))
        assertNotNull(AacRoute.boxFor(formats[2]))
        assertEquals(1, AacRoute.count())

        repeat(10) { i ->
            // Sortie : stop, piste et décodeur rendus, rien ne joue.
            if (PlayerCensus.tracksAlive() > 0) PlayerCensus.audioTrackClosed()
            if (PlayerCensus.decodersAlive() > 0) PlayerCensus.audioDecoderClosed()
            assertEquals(0, PlayerCensus.tracksAlive(), "suspend $i")
            assertEquals(0, PlayerCensus.decodersAlive(), "suspend $i")
            val plan = if (i % 2 == 0) {
                AudioHandoff.resume(vod = false, lastKnownPos = 12_000L)
            } else {
                AudioHandoff.resume(vod = true, lastKnownPos = 45_000L)
            }
            if (i % 2 == 0) assertNull(plan.startPositionMs) else assertEquals(45_000L, plan.startPositionMs)
            // Retour : une seule piste, un seul décodeur. Pas de second lecteur.
            var tick = gate.onStopped(PlayerCensus.tracksAlive())
            assertTrue(tick.prepare, tick.line)
            PlayerCensus.audioDecoderOpened()
            PlayerCensus.audioTrackOpened()
            volume = AudioHandoff.outputVolume(handoffMute = false, duckRequested = true)
            note()
        }

        val end = PlayerCensus.snapshot(AacRoute.key(back), AacRoute.boxFor(back))
        println("HANDOFF " + PlayerCensus.describe(end) + " volume=$volume maxPistes=$maxTracks maxDecodeurs=$maxDecoders")
        assertEquals(1, end.playersAlive)
        assertEquals(1, end.audioDecodersAlive)
        assertEquals(1, end.audioTracksAlive)
        assertEquals(1, maxTracks)
        assertEquals(1, maxDecoders)
        assertEquals(AudioHandoff.VOLUME_FULL, volume)
        assertFalse(PlayerCensus.overlapping(end))
        assertNull(end.boxFailure)
    }

    @Test
    fun lePassageImmediatLaisseDeuxPistesCestLeReglageDeRepli() {
        PlayerCensus.playerCreated()
        PlayerCensus.audioDecoderOpened()
        PlayerCensus.audioTrackOpened()
        val gate = AudioGate { true }
        val tick = gate.onStopped(PlayerCensus.tracksAlive())
        assertTrue(tick.prepare)
        assertTrue(tick.line!!.contains("repli"))
        // L'ancien comportement ouvre avant le rendu : deux pistes.
        PlayerCensus.audioTrackOpened()
        PlayerCensus.audioDecoderOpened()
        assertEquals(2, PlayerCensus.tracksAlive())
        assertEquals(2, PlayerCensus.decodersAlive())
        assertTrue(PlayerCensus.overlapping(PlayerCensus.snapshot(1, null)))
    }

    @Test
    fun leFiletDes8sNeVoitPasLeFfmpegDeLaChaineDavant() {
        // Retour d'arrière-plan : le drapeau est remis à faux dans le silence.
        assertFalse(
            AudioHandoff.watchdogShouldFallback(
                ffmpegActiveThisSession = false,
                readyThisSession = false,
                forceBox = false,
                platformGaveUp = false,
                playbackReady = false,
            ),
        )
        // Vraie panne : FFmpeg de CETTE ouverture, jamais prêt.
        assertTrue(
            AudioHandoff.watchdogShouldFallback(
                ffmpegActiveThisSession = true,
                readyThisSession = false,
                forceBox = false,
                platformGaveUp = false,
                playbackReady = false,
            ),
        )
        // A déjà été prêt : un re-tamponnage ne bascule pas.
        assertFalse(
            AudioHandoff.watchdogShouldFallback(
                ffmpegActiveThisSession = true,
                readyThisSession = true,
                forceBox = false,
                platformGaveUp = false,
                playbackReady = false,
            ),
        )
    }

    @Test
    fun leVolumeDePassageEstZeroPuisUnJamaisZeroDeux() {
        assertEquals(AudioHandoff.VOLUME_SILENT, AudioHandoff.outputVolume(handoffMute = true, duckRequested = true))
        assertEquals(AudioHandoff.VOLUME_FULL, AudioHandoff.outputVolume(handoffMute = false, duckRequested = true))
        assertEquals(AudioHandoff.VOLUME_FULL, AudioHandoff.outputVolume(handoffMute = false, duckRequested = false))
    }
}

