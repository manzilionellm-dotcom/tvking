package com.manzilionellm.native_video_player.logic

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Le « 1 (film) » qui naît avec notre AudioTrack n'est plus compté
 * comme une autre app. Le mode communication est nommé.
 */
class AudioRouteStateTest {

    @Test
    fun android16UneLectureUnAudioTrackCestNous() {
        val o = AudioRouteState.attribute(announced = 1, uidMatches = null, ourTracks = 1)
        assertEquals(1, o.ours)
        assertEquals(0, o.others)
        assertFalse(o.uidTrusted)
        val note = AudioRouteState.playbackNote(o, audible = true)
        assertTrue(note.contains("c'est cette app"), note)
        assertTrue(note.contains("Zuno 0, box 1"), note)
        assertFalse(note.contains("lectures Zuno 0"))
        val line = VolumeTrace.line(
            VolumeTrace.Sample(
                second = 3,
                playerVolume = 1f,
                trackVolume = null,
                streamVolume = 13,
                streamMax = 15,
                focusHeld = true,
                media3Focus = false,
                pausedByFocus = false,
                owner = o,
                path = AudioRouteState.Facts(
                    mode = AudioRouteState.MODE_NORMAL,
                    routedType = AudioRouteState.TYPE_BUILTIN_SPEAKER,
                    routedName = "Speaker",
                    plannedTypes = listOf(AudioRouteState.TYPE_BUILTIN_SPEAKER),
                    usage = AudioRouteState.USAGE_MEDIA,
                    contentType = AudioRouteState.CONTENT_MOVIE,
                ),
            ),
        )
        assertTrue(line.contains("lectures de cette app 1, autres apps 0"), line)
        assertTrue(line.contains("mode normal"), line)
        assertFalse(line.contains("chemin d'appel"), line)
        assertTrue(line.contains("haut-parleur interne"), line)
        assertTrue(line.contains("flux musique (contenu film)"), line)
        assertFalse(line.contains("lectures Zuno 0"), line)
    }

    @Test
    fun uneLectureDePlusEstUneAutreApp() {
        val o = AudioRouteState.attribute(announced = 2, uidMatches = null, ourTracks = 1)
        assertEquals(1, o.ours)
        assertEquals(1, o.others)
        val note = AudioRouteState.playbackNote(o, audible = true)
        assertTrue(note.contains("autres apps 1"), note)
        assertTrue(note.contains("Une autre application"), note)
    }

    @Test
    fun compteurClientCruQuandIlNousReconnait() {
        val o = AudioRouteState.attribute(announced = 2, uidMatches = 1, ourTracks = 1)
        assertTrue(o.uidTrusted)
        assertEquals(1, o.ours)
        assertEquals(1, o.others)
    }

    @Test
    fun compteurClientAZeroAlorsQueNotrePisteVitNestPasCru() {
        // Android 16 : getClientUid renvoie -1 ou 0, le compte dit 0
        // match alors que l'AudioTrack est le nôtre.
        val o = AudioRouteState.attribute(announced = 1, uidMatches = 0, ourTracks = 1)
        assertFalse(o.uidTrusted)
        assertEquals(1, o.ours)
        assertEquals(0, o.others)
    }

    @Test
    fun pisteArreteeEtUneAnnonceCestUneAutreApp() {
        val o = AudioRouteState.attribute(announced = 1, uidMatches = 0, ourTracks = 0)
        assertTrue(o.uidTrusted)
        assertEquals(0, o.ours)
        assertEquals(1, o.others)
    }

    @Test
    fun modeCommunicationEstUnCheminDappel() {
        assertTrue(AudioRouteState.callPath(AudioRouteState.MODE_IN_COMMUNICATION))
        assertTrue(AudioRouteState.callPath(AudioRouteState.MODE_IN_CALL))
        assertFalse(AudioRouteState.callPath(AudioRouteState.MODE_NORMAL))
        val line = AudioRouteState.pathLine(
            AudioRouteState.Facts(
                mode = AudioRouteState.MODE_IN_COMMUNICATION,
                speakerphone = true,
                bluetoothSco = true,
                routedType = AudioRouteState.TYPE_BLUETOOTH_SCO,
                usage = AudioRouteState.USAGE_VOICE_COMMUNICATION,
                contentType = AudioRouteState.CONTENT_SPEECH,
            ),
        )
        assertTrue(line.contains("mode communication"), line)
        assertTrue(line.contains("chemin d'appel"), line)
        assertTrue(line.contains("Bluetooth appel allumé"), line)
        assertTrue(line.contains("flux appel"), line)
    }

    @Test
    fun hdmiEtMusiqueNeSontPasUnAppel() {
        assertEquals("HDMI", AudioRouteState.deviceLabel(AudioRouteState.TYPE_HDMI))
        assertEquals(
            "musique (contenu film)",
            AudioRouteState.streamLabel(AudioRouteState.USAGE_MEDIA, AudioRouteState.CONTENT_MOVIE),
        )
        val line = AudioRouteState.pathLine(
            AudioRouteState.Facts(
                mode = AudioRouteState.MODE_NORMAL,
                routedType = AudioRouteState.TYPE_HDMI,
                routedName = "TV\nsalon",
                plannedTypes = listOf(AudioRouteState.TYPE_HDMI),
                usage = AudioRouteState.USAGE_MEDIA,
                contentType = AudioRouteState.CONTENT_MOVIE,
            ),
        )
        assertFalse(line.contains("\n"), line)
        assertTrue(line.contains("HDMI"), line)
        assertFalse(line.contains("chemin d'appel"), line)
    }
}
