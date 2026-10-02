package com.manzilionellm.native_video_player.logic

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Le compteur « lectures Zuno 0 / lectures de la box 1 (film) » était
 * faux : l'UID n'est pas lisible, et le « 1 (film) » était Zuno. Ici on
 * reproduit exactement ce cas et on vérifie que la nouvelle fiche attribue
 * la lecture à Zuno, et dit comment.
 */
class PlaybackCountTest {

    private val film = PlaybackCount.Playback(PlaybackCount.CONTENT_MOVIE, PlaybackCount.USAGE_MEDIA)
    private val musique = PlaybackCount.Playback(PlaybackCount.CONTENT_MUSIC, PlaybackCount.USAGE_MEDIA)

    @Test
    fun leCasDuTelephoneAndroid16EstAttribueAZuno() {
        // UID non lisible (réflexion refusée), pas de numéro de session, notre piste vivante.
        val c = PlaybackCount.count(
            list = listOf(film),
            ourUid = 1000,
            ourSessionIds = emptySet(),
            ourContentType = PlaybackCount.CONTENT_MOVIE,
            ourUsage = PlaybackCount.USAGE_MEDIA,
            ourTrackAlive = true,
        )
        assertEquals(1, c.total)
        assertEquals(1, c.ours)
        assertEquals(0, c.others)
        assertEquals(PlaybackCount.Method.ATTRIBUTES, c.method)
        val line = PlaybackCount.line(c)
        assertTrue(line.contains("la nôtre seulement"), line)
        assertTrue(line.contains("attribution par les attributs"), line)
        assertFalse(line.contains("lectures Zuno 0"), line)
    }

    @Test
    fun uneAutreAppQuiJoueEstCompteeCommeAutre() {
        val c = PlaybackCount.count(
            list = listOf(film, musique),
            ourUid = null,
            ourSessionIds = emptySet(),
            ourContentType = PlaybackCount.CONTENT_MOVIE,
            ourUsage = PlaybackCount.USAGE_MEDIA,
            ourTrackAlive = true,
        )
        assertEquals(2, c.total)
        assertEquals(1, c.ours)
        assertEquals(1, c.others)
        assertEquals(listOf("musique"), c.othersLabels)
        assertTrue(PlaybackCount.line(c).contains("une autre app joue en même temps"))
    }

    @Test
    fun sansPisteVivanteRienNestANous() {
        val c = PlaybackCount.count(
            list = listOf(film),
            ourUid = null,
            ourSessionIds = emptySet(),
            ourContentType = PlaybackCount.CONTENT_MOVIE,
            ourUsage = PlaybackCount.USAGE_MEDIA,
            ourTrackAlive = false,
        )
        assertEquals(0, c.ours)
        assertEquals(1, c.others)
        assertTrue(PlaybackCount.line(c).contains("aucune n'est la nôtre"))
    }

    @Test
    fun lUidOuLaSessionQuandAndroidLesDonneSontExacts() {
        val mine = film.copy(uid = 10_123, sessionId = 41)
        val other = musique.copy(uid = 10_999, sessionId = 77)
        val byUid = PlaybackCount.count(listOf(mine, other), 10_123, emptySet(), PlaybackCount.CONTENT_MOVIE, PlaybackCount.USAGE_MEDIA, true)
        assertEquals(PlaybackCount.Method.UID, byUid.method)
        assertEquals(1, byUid.ours)
        assertEquals(1, byUid.others)
        val bySession = PlaybackCount.count(listOf(mine, other), null, setOf(41), PlaybackCount.CONTENT_MOVIE, PlaybackCount.USAGE_MEDIA, true)
        assertEquals(PlaybackCount.Method.SESSION, bySession.method)
        assertEquals(1, bySession.ours)
        // Deux lectures à nous = chevauchement, dit tel quel.
        val twice = PlaybackCount.count(listOf(mine, mine.copy(sessionId = 42)), null, setOf(41, 42), PlaybackCount.CONTENT_MOVIE, PlaybackCount.USAGE_MEDIA, true)
        assertEquals(2, twice.ours)
        assertTrue(PlaybackCount.line(twice).contains("chevauchement"))
    }

    @Test
    fun unAppelEnCoursEstNommeParSonUsage() {
        val appel = PlaybackCount.Playback(PlaybackCount.CONTENT_SPEECH, PlaybackCount.USAGE_VOICE_COMMUNICATION)
        val c = PlaybackCount.count(listOf(film, appel), null, emptySet(), PlaybackCount.CONTENT_MOVIE, PlaybackCount.USAGE_MEDIA, true)
        assertEquals(listOf("parole, APPEL"), c.othersLabels)
        assertEquals("lectures 2 (nôtre 1, autres 1)", PlaybackCount.short(c))
        assertEquals("lectures pas encore comptées", PlaybackCount.short(null))
        assertTrue(PlaybackCount.line(PlaybackCount.count(emptyList(), null, emptySet(), 3, 1, false)).contains(": 0"))
    }
}
