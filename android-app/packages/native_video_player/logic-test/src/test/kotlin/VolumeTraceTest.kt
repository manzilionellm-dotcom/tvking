package com.manzilionellm.native_video_player.logic

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class VolumeTraceTest {

    @Test
    fun dixSecondesSansBaisseAZeroDeux() {
        val volume = AudioHandoff.outputVolume(handoffMute = false, duckRequested = true)
        assertEquals(AudioHandoff.VOLUME_FULL, volume)
        val lines = (1..VolumeTrace.SECONDS).map { sec ->
            VolumeTrace.line(
                VolumeTrace.Sample(
                    second = sec,
                    playerVolume = volume,
                    trackVolume = null,
                    streamVolume = 15,
                    streamMax = 15,
                    focusHeld = true,
                    media3Focus = false,
                    pausedByFocus = false,
                    owner = AudioRouteState.attribute(announced = 1, uidMatches = null, ourTracks = 1),
                    path = AudioRouteState.Facts(mode = AudioRouteState.MODE_NORMAL),
                ),
            )
        }
        assertEquals(10, lines.size)
        assertTrue(lines.first().startsWith("Seconde 1 :"))
        assertTrue(lines.last().startsWith("Seconde 10 :"))
        for (line in lines) {
            assertTrue(line.contains("volume lecteur 1,0"), line)
            assertTrue(line.contains("volume AudioTrack non lisible"), line)
            assertTrue(line.contains("volume musique de la box 15/15"), line)
            assertTrue(line.contains("focus tenu par Zuno"), line)
            assertTrue(line.contains("lectures de cette app 1"), line)
            assertTrue(line.contains("autres apps 0"), line)
            assertFalse(line.contains("lectures Zuno 0"), line)
            assertFalse(line.contains("0,2"), line)
        }
    }

    @Test
    fun leSilenceDePassageNestPasLaBaisse() {
        val muted = AudioHandoff.outputVolume(handoffMute = true, duckRequested = true)
        assertEquals(AudioHandoff.VOLUME_SILENT, muted)
        val line = VolumeTrace.line(
            VolumeTrace.Sample(
                second = 1,
                playerVolume = muted,
                trackVolume = null,
                streamVolume = 15,
                streamMax = 15,
                focusHeld = true,
                media3Focus = false,
                pausedByFocus = false,
                owner = AudioRouteState.attribute(announced = 0, uidMatches = null, ourTracks = 0),
            ),
        )
        assertTrue(line.contains("volume lecteur 0,0"))
        assertFalse(line.contains("0,2"))
    }
}
