package com.manzilionellm.native_video_player.logic

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * L'interrupteur est coupé : le type envoyé reste celui d'avant
 * (film, ou parole si la voix claire est allumée). L'essai ne
 * change que le mot dit à Android, pas un calcul sur les échantillons.
 */
class AudioContentChoiceTest {

    @Test
    fun coupeParDefautEtValeurIllisible() {
        assertEquals(AudioContentChoice.OFF, AudioContentChoice.fromWire(null))
        assertEquals(AudioContentChoice.OFF, AudioContentChoice.fromWire(""))
        assertEquals(AudioContentChoice.OFF, AudioContentChoice.fromWire("off"))
        assertEquals(AudioContentChoice.OFF, AudioContentChoice.fromWire("MOVIE"))
        assertEquals(AudioContentChoice.OFF, AudioContentChoice.fromWire("film"))
        assertEquals(AudioContentChoice.MOVIE, AudioContentChoice.fromWire("movie"))
        assertEquals(AudioContentChoice.MUSIC, AudioContentChoice.fromWire("music"))
        assertEquals(AudioContentChoice.SPEECH, AudioContentChoice.fromWire("speech"))
    }

    @Test
    fun leDefautResteFilmOuParoleSiVoixClaire() {
        assertEquals(
            AudioContentChoice.MOVIE,
            AudioContentChoice.declared(AudioContentChoice.OFF, clearVoice = false),
        )
        assertEquals(
            AudioContentChoice.SPEECH,
            AudioContentChoice.declared(AudioContentChoice.OFF, clearVoice = true),
        )
    }

    @Test
    fun lessaiGagneSurLaVoixClaire() {
        assertEquals(
            AudioContentChoice.MUSIC,
            AudioContentChoice.declared(AudioContentChoice.MUSIC, clearVoice = true),
        )
        assertEquals(
            AudioContentChoice.MOVIE,
            AudioContentChoice.declared(AudioContentChoice.MOVIE, clearVoice = true),
        )
        assertEquals(
            AudioContentChoice.SPEECH,
            AudioContentChoice.declared(AudioContentChoice.SPEECH, clearVoice = false),
        )
    }

    @Test
    fun leBoutonTourneCoupeFilmMusiqueParole() {
        var choice = AudioContentChoice.OFF
        choice = AudioContentChoice.next(choice)
        assertEquals(AudioContentChoice.MOVIE, choice)
        assertEquals("Type : film", AudioContentChoice.buttonLabel(choice))
        choice = AudioContentChoice.next(choice)
        assertEquals(AudioContentChoice.MUSIC, choice)
        assertEquals("Type : musique", AudioContentChoice.buttonLabel(choice))
        choice = AudioContentChoice.next(choice)
        assertEquals(AudioContentChoice.SPEECH, choice)
        assertEquals("Type : parole", AudioContentChoice.buttonLabel(choice))
        choice = AudioContentChoice.next(choice)
        assertEquals(AudioContentChoice.OFF, choice)
        assertEquals("Type : coupé", AudioContentChoice.buttonLabel(choice))
        assertEquals("off", AudioContentChoice.toWire(choice))
    }

    @Test
    fun laLigneDitCoupeOuEssaiSansAdresse() {
        val off = AudioContentChoice.diagLine(AudioContentChoice.OFF, clearVoice = false)
        assertTrue(off.contains("Type déclaré : film"))
        assertTrue(off.contains("interrupteur coupé"))
        assertTrue(off.contains("délestage coupé"))
        assertTrue(off.contains("tunnel coupé"))
        assertFalse(off.contains("http"))

        val essai = AudioContentChoice.diagLine(AudioContentChoice.MUSIC, clearVoice = true)
        assertTrue(essai.contains("Type déclaré : musique"))
        assertTrue(essai.contains("essai"))
        assertFalse(essai.contains("parole"))
    }
}
