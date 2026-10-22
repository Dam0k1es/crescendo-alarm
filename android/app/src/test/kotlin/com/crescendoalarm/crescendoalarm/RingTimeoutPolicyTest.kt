package com.crescendoalarm.crescendoalarm

import com.crescendoalarm.crescendoalarm.RingTimeoutPolicy.Decision
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * docs/TODO.md T-237 (maintainer decision 2026-10-23, "nach 60 Min beenden +
 * Meldung"): a ring nobody stops ends itself 60 minutes after its due time and
 * a silent notice says so. The plugin's loop never ends on its own (a device
 * rang for six hours). The decisions are pure and live here.
 */
class RingTimeoutPolicyTest {
    private val minute = 60 * 1000L
    private val due = 1_790_000_000_000L
    private val id = 4711

    @Test
    fun `the timeout is 60 minutes after the due time`() {
        assertEquals(60L, RingTimeoutPolicy.TIMEOUT_MINUTES)
        assertEquals(due + 60 * minute, RingTimeoutPolicy.timeoutAtMillis(due))
    }

    @Test
    fun `a ring that is still ringing exactly at the timeout is stopped and reported`() {
        assertEquals(
            Decision.StopAndNotify(due),
            RingTimeoutPolicy.decide(
                armedDueAtMillis = due,
                nowMillis = due + 60 * minute,
                alarmIsRinging = true,
                savedDueAtMillis = due,
            ),
        )
    }

    @Test
    fun `a ring found long after the timeout is stopped and reported too`() {
        assertEquals(
            Decision.StopAndNotify(due),
            RingTimeoutPolicy.decide(due, due + 6 * 60 * minute, true, due),
        )
    }

    @Test
    fun `one millisecond early the ring is not stopped - it keeps its timeout`() {
        assertEquals(
            Decision.Rearm(due + 60 * minute),
            RingTimeoutPolicy.decide(due, due + 60 * minute - 1, true, due),
        )
    }

    @Test
    fun `an alarm that is not ringing is left alone - stopped, deleted or never rang`() {
        assertEquals(
            Decision.Nothing,
            RingTimeoutPolicy.decide(due, due + 61 * minute, false, due),
        )
        assertEquals(
            Decision.Nothing,
            RingTimeoutPolicy.decide(due, due + 61 * minute, false, null),
        )
    }

    @Test
    fun `a ring found early while still ringing is re-armed for its own timeout`() {
        // The timer fired before due + 60 minutes (a clock change): the ring
        // must not lose its timeout.
        assertEquals(
            Decision.Rearm(due + 60 * minute),
            RingTimeoutPolicy.decide(due, due + 30 * minute, true, due),
        )
    }

    @Test
    fun `a ring whose saved due time moved later was snoozed - it gets the timeout of the new due time`() {
        // Native snooze (the plugin's SnoozeCoordinator) keeps the id with a
        // new due time: the old timeout must neither cut it short nor leave
        // it without one.
        assertEquals(
            Decision.Rearm(due + 5 * minute + 60 * minute),
            RingTimeoutPolicy.decide(due, due + 61 * minute, true, due + 5 * minute),
        )
    }

    @Test
    fun `a saved due time earlier than the armed one is a stale timeout - nothing happens`() {
        assertEquals(
            Decision.Nothing,
            RingTimeoutPolicy.decide(due, due + 61 * minute, true, due - 5 * minute),
        )
    }

    @Test
    fun `an alarm the plugin no longer stores is left alone`() {
        assertEquals(
            Decision.Nothing,
            RingTimeoutPolicy.decide(due, due + 61 * minute, true, null),
        )
    }

    @Test
    fun `a timeout is armed only while it still lies in the future`() {
        assertTrue(RingTimeoutPolicy.shouldArm(due, due))
        assertTrue(RingTimeoutPolicy.shouldArm(due, due + 60 * minute - 1))
        assertFalse(RingTimeoutPolicy.shouldArm(due, due + 60 * minute))
        assertFalse(RingTimeoutPolicy.shouldArm(due, due + 5 * 60 * minute))
    }

    @Test
    fun `after a reboot only entries whose timeout is still ahead are re-armed`() {
        val now = due + 30 * minute
        val entries = mapOf(
            1 to due, // timeout in 30 minutes: re-arm
            2 to due - 30 * minute, // timeout exactly now: gone
            3 to due - 90 * minute, // long past: gone
            4 to due + 20 * minute, // due in the future: re-arm
        )
        assertEquals(
            mapOf(1 to due, 4 to due + 20 * minute),
            RingTimeoutPolicy.entriesToRearmAfterBoot(entries, now),
        )
    }

    @Test
    fun `an entry already past its timeout at boot needs no timeout - the alarm plugin discards it as stale`() {
        assertEquals(
            emptyMap<Int, Long>(),
            RingTimeoutPolicy.entriesToRearmAfterBoot(mapOf(id to due), due + 61 * minute),
        )
    }
}
