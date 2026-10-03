package com.manzilionellm.native_video_player.logic

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * L'essai d'attributs est coupé par défaut. Coupé, les chiffres sont
 * ceux d'aujourd'hui. Les quatre essais ne changent QUE le contenu.
 */
class AudioProfileTest {

    @Test
    fun coupeParDefautEtUnTexteInconnuResteCoupe() {
        assertEquals(AudioProfile.OFF, AudioProfile.current)
        assertEquals(AudioProfile.KEY, "zuno.audio.profile")
        assertEquals(AudioProfile.OFF, AudioProfile.parse(null))
        assertEquals(AudioProfile.OFF, AudioProfile.parse(""))
        assertEquals(AudioProfile.OFF, AudioProfile.parse("film "))
        assertEquals(AudioProfile.OFF, AudioProfile.parse("http://exemple.test"))
    }

    @Test
    fun coupeSansVoixClaireEstLeFilmDaujourdhui() {
        val c = AudioProfile.resolve(AudioProfile.OFF, clearVoice = false)
        assertFalse(c.trial)
        assertEquals(AudioProfile.CONTENT_MOVIE, c.contentType)
        assertEquals(AudioProfile.USAGE_MEDIA, c.usage)
        assertEquals(0, c.flags)
        assertEquals(AudioProfile.CAPTURE_ALL, c.allowedCapturePolicy)
        assertEquals(AudioProfile.SPATIAL_AUTO, c.spatializationBehavior)
        assertEquals(AudioProfile.PERFORMANCE_NONE, c.performanceMode)
        assertFalse(c.offload)
        assertFalse(c.tunneling)
        assertFalse(c.overridesClearVoice)
    }

    @Test
    fun coupeAvecVoixClairePasseEnParoleCommeAujourdHui() {
        val c = AudioProfile.resolve(AudioProfile.OFF, clearVoice = true)
        assertFalse(c.trial)
        assertEquals(AudioProfile.CONTENT_SPEECH, c.contentType)
        assertFalse(c.overridesClearVoice)
        assertTrue(AudioProfile.line(c).contains("voix claire"), AudioProfile.line(c))
    }

    @Test
    fun filmForceLeFilmMemeSiLaVoixClaireEstAllumee() {
        val c = AudioProfile.resolve(AudioProfile.FILM, clearVoice = true)
        assertTrue(c.trial)
        assertEquals(AudioProfile.CONTENT_MOVIE, c.contentType)
        assertTrue(c.overridesClearVoice)
        val line = AudioProfile.line(c)
        assertTrue(line.contains("essai film"), line)
        assertTrue(line.contains("remplace le contenu parole"), line)
    }

    @Test
    fun musiqueParoleEtDefautMedia3NeChangentQueLeContenu() {
        val base = AudioProfile.resolve(AudioProfile.OFF, clearVoice = false)
        val music = AudioProfile.resolve(AudioProfile.MUSIC, clearVoice = false)
        val speech = AudioProfile.resolve(AudioProfile.SPEECH, clearVoice = false)
        val media3 = AudioProfile.resolve(AudioProfile.MEDIA3, clearVoice = true)
        assertEquals(AudioProfile.CONTENT_MUSIC, music.contentType)
        assertEquals(AudioProfile.CONTENT_SPEECH, speech.contentType)
        assertEquals(AudioProfile.CONTENT_UNKNOWN, media3.contentType)
        for (c in listOf(music, speech, media3)) {
            assertTrue(c.trial)
            assertEquals(base.usage, c.usage)
            assertEquals(base.flags, c.flags)
            assertEquals(base.allowedCapturePolicy, c.allowedCapturePolicy)
            assertEquals(base.spatializationBehavior, c.spatializationBehavior)
            assertEquals(base.performanceMode, c.performanceMode)
            assertEquals(base.offload, c.offload)
            assertEquals(base.tunneling, c.tunneling)
        }
        // Voix claire allumée + défaut Media3 : le contenu reste inconnu.
        assertTrue(media3.overridesClearVoice)
    }

    @Test
    fun leDefautMedia3EtVlc30LaissentLeContenuInconnu() {
        val stock = AudioProfile.media3Default()
        assertEquals(AudioProfile.CONTENT_UNKNOWN, stock.contentType)
        assertEquals(AudioProfile.USAGE_MEDIA, stock.usage)
        assertEquals(0, stock.flags)
        assertFalse(stock.offload)
        assertFalse(stock.tunneling)
        // VLC 3.0 STREAM_MUSIC, traduit par Android 14/15.
        assertEquals(stock.contentType, AudioProfile.vlc30LegacyContentType())
        val zuno = AudioProfile.resolve(AudioProfile.OFF, clearVoice = false)
        assertEquals(AudioProfile.CONTENT_MOVIE, zuno.contentType)
        assertTrue(zuno.contentType != stock.contentType)
        val line = AudioProfile.line(zuno)
        assertTrue(line.contains("seul le contenu diffère"), line)
        assertTrue(line.contains("VLC 3.0"), line)
        assertFalse(line.contains("http"), line)
        assertFalse(line.contains("password"), line)
    }

    @Test
    fun leDefautMedia3NaPasDecartDeContenu() {
        val line = AudioProfile.line(AudioProfile.media3Default())
        assertTrue(line.contains("aucun écart de contenu"), line)
        assertTrue(line.contains("essai défaut Media3"), line)
        assertTrue(line.contains("tunneling coupé"), line)
        assertTrue(line.contains("offload coupé"), line)
        assertTrue(line.contains("ne change pas le tampon"), line)
    }

    @Test
    fun leBoutonTourneEtNeRouvrePasSiRienNeChange() {
        assertEquals(AudioProfile.FILM, AudioProfile.next(AudioProfile.OFF))
        assertEquals(AudioProfile.MUSIC, AudioProfile.next(AudioProfile.FILM))
        assertEquals(AudioProfile.SPEECH, AudioProfile.next(AudioProfile.MUSIC))
        assertEquals(AudioProfile.MEDIA3, AudioProfile.next(AudioProfile.SPEECH))
        assertEquals(AudioProfile.OFF, AudioProfile.next(AudioProfile.MEDIA3))
        assertEquals(AudioProfile.FILM, AudioProfile.next("n'importe quoi"))
        assertFalse(AudioProfile.shouldReopen(AudioProfile.OFF, AudioProfile.OFF, playing = true))
        assertFalse(AudioProfile.shouldReopen(AudioProfile.MUSIC, AudioProfile.MUSIC, playing = true))
        assertFalse(AudioProfile.shouldReopen(AudioProfile.OFF, AudioProfile.FILM, playing = false))
        assertTrue(AudioProfile.shouldReopen(AudioProfile.OFF, AudioProfile.MUSIC, playing = true))
        assertTrue(AudioProfile.shouldReopen(null, AudioProfile.MEDIA3, playing = true))
    }

    @Test
    fun laFichePorteLaLigneSansEnFaireUneCauseSure() {
        val line = AudioProfile.line(AudioProfile.resolve(AudioProfile.MUSIC, clearVoice = false))
        val report = AudioDiagnosis.report(
            AudioSnapshot(
                mime = "audio/mp4a-latm",
                codecs = "mp4a.40.2",
                decoder = "c2.android.aac.decoder",
                outSampleRate = 48_000,
                outChannels = 2,
                outEncoding = "PCM 16 bits",
                attributeLine = line,
            ),
        )
        assertTrue(report.contains("essai musique"), report)
        assertTrue(report.contains("Attributs :"), report)
        assertTrue(AudioDiagnosis.sureCauses(AudioSnapshot(attributeLine = line)).isEmpty())
    }
}
