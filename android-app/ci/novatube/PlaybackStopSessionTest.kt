package com.sevenmotion.novatube

import org.junit.Assert.*
import org.junit.Test

class PlaybackStopSessionTest {
    @Test fun notificationConsumesOnlyItsCurrentCastOnce() {
        val state = PlaybackStopSession()
        assertTrue(state.startCast("cast-a"))
        assertFalse(state.stopFromNotification(null))
        assertFalse(state.stopFromNotification("other"))
        assertEquals("cast-a", state.activeCastId)
        assertTrue(state.stopFromNotification("cast-a"))
        assertNull(state.activeCastId)
        assertFalse(state.stopFromNotification("cast-a"))
    }

    @Test fun lateNotificationAndLateInternalStopCannotStopNewCast() {
        val state = PlaybackStopSession()
        assertTrue(state.startCast("cast-a"))
        assertTrue(state.stopFromApp("cast-a"))
        assertTrue(state.startCast("cast-b"))
        assertFalse(state.stopFromNotification("cast-a"))
        assertFalse(state.stopFromApp("cast-a"))
        assertFalse(state.stopFromApp(null))
        assertEquals("cast-b", state.activeCastId)
    }

    @Test fun permissionRepostCannotResurrectUserStoppedSession() {
        val state = PlaybackStopSession()
        assertTrue(state.startCast("cast-a"))
        assertTrue(state.stopFromNotification("cast-a"))
        state.release(null) // onDestroy ne perd pas l'arrêt déjà demandé.
        assertFalse(state.startCast("cast-a"))
        assertTrue(state.startCast("cast-b"))
        assertFalse(state.startCast("cast-a"))
        assertEquals("cast-b", state.activeCastId)
    }

    @Test fun internalStopDoesNotActAsAUserNotification() {
        val state = PlaybackStopSession()
        assertTrue(state.startCast("cast-a"))
        assertTrue(state.stopFromApp("cast-a"))
        assertFalse(state.stopFromNotification("cast-a"))
        assertTrue(state.startCast("cast-b"))
    }

    @Test fun audioKeepsItsUnscopedStopAndRejectsOldCastStop() {
        val state = PlaybackStopSession()
        assertTrue(state.startCast("cast-a"))
        state.startAudio()
        assertFalse(state.stopFromNotification("cast-a"))
        assertFalse(state.stopFromApp("cast-a"))
        assertTrue(state.stopFromApp(null))
    }

    @Test fun oldServiceDestructionDoesNotReleaseNewOwner() {
        val state = PlaybackStopSession()
        assertTrue(state.startCast("cast-a"))
        assertTrue(state.startCast("cast-b"))
        state.release("cast-a")
        assertEquals("cast-b", state.activeCastId)
        state.release("cast-b")
        assertNull(state.activeCastId)
        assertFalse(state.startCast(" "))
    }
}
