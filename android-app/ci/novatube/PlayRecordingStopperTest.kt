package com.sevenmotion.novatube

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class PlayRecordingStopperTest {
    @Test fun foregroundEndsBeforeAProducerCanBlock() {
        val calls = mutableListOf<String>()
        val producerEntered = CountDownLatch(1)
        val releaseProducer = CountDownLatch(1)
        val stopper = PlayRecordingStopper(
            { calls.add("stopForeground/stopSelf") },
            { calls.add("locks") },
            { producerEntered.countDown(); releaseProducer.await(2, TimeUnit.SECONDS) },
            { calls.add(it) },
            { throw AssertionError(it) },
        )
        val thread = Thread { stopper.stop("foregroundTimeout") }.apply { start() }
        try {
            assertTrue(producerEntered.await(1, TimeUnit.SECONDS))
            assertEquals(listOf("stopForeground/stopSelf", "locks"), calls.toList())
        } finally {
            releaseProducer.countDown()
            thread.join(2000)
        }
        assertFalse(thread.isAlive)
        assertEquals("foregroundTimeout", calls.last())
    }

    @Test fun timeoutThenDestroyDoesNotCloseOrNotifyTwice() {
        val calls = mutableListOf<String>()
        val stopper = PlayRecordingStopper(
            { calls.add("foreground") }, { calls.add("locks") },
            { calls.add("producer") }, { calls.add(it) }, { throw AssertionError(it) },
        )
        assertTrue(stopper.stop("foregroundTimeout"))
        assertFalse(stopper.stop("serviceDestroyed"))
        assertEquals(listOf("foreground", "locks", "producer", "foregroundTimeout"), calls)
    }

    @Test fun cleanupFailureDoesNotSkipOtherResourcesOrDartNotification() {
        val calls = mutableListOf<String>()
        val failures = mutableListOf<Throwable>()
        val stopper = PlayRecordingStopper(
            { calls.add("foreground"); throw IllegalStateException("foreground") },
            { calls.add("locks"); throw IllegalStateException("locks") },
            { calls.add("producer"); throw IllegalStateException("producer") },
            { calls.add(it) }, { failures.add(it) },
        )
        stopper.stop("notificationStop")
        assertEquals(listOf("foreground", "locks", "producer", "notificationStop"), calls)
        assertEquals(3, failures.size)
        assertTrue(stopper.isStopped)
    }

    @Test fun concurrentStopRequestsOwnTheProducerExactlyOnce() {
        val closes = AtomicInteger()
        val notifications = AtomicInteger()
        val stopper = PlayRecordingStopper({}, {}, { closes.incrementAndGet() },
            { notifications.incrementAndGet() }, { throw AssertionError(it) })
        val ready = CountDownLatch(1)
        val threads = List(8) { Thread { ready.await(); stopper.stop("foregroundTimeout") } }
        threads.forEach { it.start() }
        ready.countDown()
        threads.forEach { it.join(2000); assertFalse(it.isAlive) }
        assertEquals(1, closes.get())
        assertEquals(1, notifications.get())
    }
}
