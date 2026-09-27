// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of Crescendo Alarm.
//
// Crescendo Alarm is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Crescendo Alarm is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Crescendo Alarm. If not, see <https://www.gnu.org/licenses/>.

package com.crescendoalarm.crescendoalarm

import com.crescendoalarm.crescendoalarm.SleepTimeDndPolicy.Action
import com.crescendoalarm.crescendoalarm.SleepTimeDndPolicy.Code
import com.crescendoalarm.crescendoalarm.SleepTimeDndPolicy.Input
import com.crescendoalarm.crescendoalarm.SleepTimeDndPolicy.Trigger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * docs/TODO.md T-198: the native decisions of the sleep-time Do Not Disturb
 * trigger. These are still unit tests - the lesson of T-197 is that unit
 * tests alone are not enough, which is why
 * integration_test/sleep_time_dnd_test.dart observes the real
 * NotificationManager on an emulator - but they pin down the part that runs
 * with no Flutter engine at all, which the Dart suite cannot reach.
 */
class SleepTimeDndPolicyTest {
    private val hour = 60 * 60 * 1000L
    private val minute = 60 * 1000L

    // Window: 22:00 -> 06:00, as epoch-like millis relative to an origin.
    private val start = 1_000_000_000_000L
    private val end = start + 8 * hour

    private fun input(
        now: Long,
        trigger: Trigger = Trigger.SYNC,
        enabled: Boolean = true,
        wasEnabled: Boolean = true,
        startMillis: Long? = start,
        endMillis: Long? = end,
        activeByUs: Boolean = false,
        pendingStartAt: Long? = null,
    ) = Input(now, trigger, enabled, wasEnabled, startMillis, endMillis, activeByUs, pendingStartAt)

    // ---------------------------------------------------------- symptom 1

    @Test
    fun `symptom 1 - switching on while the next alarm is days away activates nothing`() {
        val threeDaysBefore = start - 3 * 24 * hour
        val d = SleepTimeDndPolicy.decide(input(now = threeDaysBefore, wasEnabled = false))

        assertEquals(Code.SCHEDULED, d.code)
        assertEquals(Action.NONE, d.action)
        assertEquals(start, d.startAlarmAt)
        assertEquals(end, d.endAlarmAt)
    }

    @Test
    fun `a start alarm firing before the window (it has since moved later) activates nothing`() {
        val d = SleepTimeDndPolicy.decide(input(now = start - hour, trigger = Trigger.START_ALARM))

        assertEquals(Code.STALE_ALARM, d.code)
        assertEquals(Action.NONE, d.action)
        assertEquals(start, d.startAlarmAt)
    }

    @Test
    fun `a boot before the window only re-arms it`() {
        val d = SleepTimeDndPolicy.decide(input(now = start - hour, trigger = Trigger.BOOT))

        assertEquals(Action.NONE, d.action)
        assertEquals(start, d.startAlarmAt)
        assertEquals(end, d.endAlarmAt)
    }

    // ------------------------------------------------------------ start

    @Test
    fun `the start alarm inside the window activates and arms the end`() {
        val d = SleepTimeDndPolicy.decide(input(now = start, trigger = Trigger.START_ALARM))

        assertEquals(Code.ACTIVATED, d.code)
        assertEquals(Action.ACTIVATE, d.action)
        assertNull(d.startAlarmAt)
        assertEquals(end, d.endAlarmAt)
    }

    @Test
    fun `past start - a push inside the window catches up two minutes from now (T-110), not immediately`() {
        val now = start + 3 * hour
        val d = SleepTimeDndPolicy.decide(input(now = now))

        assertEquals(Code.CATCH_UP, d.code)
        assertEquals(Action.NONE, d.action)
        assertEquals(now + SleepTimeDndPolicy.CATCH_UP_MILLIS, d.startAlarmAt)
        assertEquals(end, d.endAlarmAt)
    }

    @Test
    fun `repeated pushes keep an already armed catch-up instead of postponing it`() {
        val first = start + 3 * hour
        val pending = first + SleepTimeDndPolicy.CATCH_UP_MILLIS
        val d = SleepTimeDndPolicy.decide(input(now = first + 30_000L, pendingStartAt = pending))

        assertEquals(pending, d.startAlarmAt)
    }

    @Test
    fun `inside the window with less than the catch-up left - nothing is activated`() {
        val d = SleepTimeDndPolicy.decide(input(now = end - minute))

        assertEquals(Code.TOO_LATE, d.code)
        assertEquals(Action.NONE, d.action)
        assertNull(d.startAlarmAt)
    }

    @Test
    fun `already active inside the window - a push changes nothing but keeps the end armed`() {
        val d = SleepTimeDndPolicy.decide(input(now = start + hour, activeByUs = true))

        assertEquals(Code.ALREADY_ACTIVE, d.code)
        assertEquals(Action.NONE, d.action)
        assertEquals(end, d.endAlarmAt)
    }

    @Test
    fun `a boot inside the window while active re-applies, since a reboot may have reset it`() {
        val d = SleepTimeDndPolicy.decide(
            input(now = start + hour, trigger = Trigger.BOOT, activeByUs = true)
        )

        assertEquals(Action.ACTIVATE, d.action)
        assertEquals(end, d.endAlarmAt)
    }

    // -------------------------------------------------------------- end

    @Test
    fun `symptom 2 - the end alarm (the first ring) deactivates, forced, and clears the window`() {
        val d = SleepTimeDndPolicy.decide(
            input(now = end, trigger = Trigger.END_ALARM, activeByUs = true)
        )

        assertEquals(Code.ENDED, d.code)
        assertEquals(Action.DEACTIVATE, d.action)
        assertTrue(d.forceDeactivate)
        assertNull(d.startAlarmAt)
        assertNull(d.endAlarmAt)
        assertFalse(d.keepWindow)
    }

    @Test
    fun `symptom 2 - the end alarm deactivates even if the record of activating was lost`() {
        val d = SleepTimeDndPolicy.decide(
            input(now = end, trigger = Trigger.END_ALARM, activeByUs = false)
        )

        assertEquals(Action.DEACTIVATE, d.action)
        assertTrue(d.forceDeactivate)
    }

    @Test
    fun `symptom 2 - after the ring the next push moves the window on and leaves Do Not Disturb`() {
        // The end alarm was missed (force-stopped overnight, say); Dart's
        // push after the ring carries the NEXT night's window.
        val nextStart = start + 24 * hour
        val d = SleepTimeDndPolicy.decide(
            input(
                now = end + 5 * minute,
                startMillis = nextStart,
                endMillis = nextStart + 8 * hour,
                activeByUs = true,
            )
        )

        assertEquals(Code.SCHEDULED, d.code)
        assertEquals(Action.DEACTIVATE, d.action)
        assertEquals(nextStart, d.startAlarmAt)
    }

    @Test
    fun `a push or boot that finds the window over deactivates if ours`() {
        for (trigger in listOf(Trigger.SYNC, Trigger.BOOT)) {
            val d = SleepTimeDndPolicy.decide(
                input(now = end + hour, trigger = trigger, activeByUs = true)
            )
            assertEquals(Code.ENDED, d.code)
            assertEquals(Action.DEACTIVATE, d.action)
        }
    }

    @Test
    fun `R4 - a snooze re-ring or an unrelated alarm cannot end sleep time - only the end alarm at the window end does`() {
        // Anything that is not the end alarm, inside the window, while
        // active: no deactivation. (A snooze re-ring, an excluded manual
        // alarm, Dart pushing mid-night - all arrive as a SYNC, if at all.)
        val d = SleepTimeDndPolicy.decide(input(now = start + 5 * hour, activeByUs = true))
        assertEquals(Action.NONE, d.action)

        // A stale end alarm from an earlier, shorter window: no deactivation.
        val stale = SleepTimeDndPolicy.decide(
            input(now = start + 5 * hour, trigger = Trigger.END_ALARM, activeByUs = true)
        )
        assertEquals(Code.STALE_ALARM, stale.code)
        assertEquals(Action.NONE, stale.action)
        assertEquals(end, stale.endAlarmAt)
    }

    // ----------------------------------------------------- switching off

    @Test
    fun `R6 - switching the feature off leaves Do Not Disturb and cancels both alarms`() {
        val d = SleepTimeDndPolicy.decide(
            input(now = start + hour, enabled = false, wasEnabled = true, activeByUs = true)
        )

        assertEquals(Code.DISABLED, d.code)
        assertEquals(Action.DEACTIVATE, d.action)
        assertNull(d.startAlarmAt)
        assertNull(d.endAlarmAt)
        assertFalse(d.keepWindow)
    }

    @Test
    fun `R6 - switching off forces the deactivation even without a record of activating`() {
        val d = SleepTimeDndPolicy.decide(
            input(now = start + hour, enabled = false, wasEnabled = true, activeByUs = false)
        )

        assertEquals(Action.DEACTIVATE, d.action)
        assertTrue(d.forceDeactivate)
    }

    @Test
    fun `staying off touches nothing`() {
        val d = SleepTimeDndPolicy.decide(
            input(now = start + hour, enabled = false, wasEnabled = false, activeByUs = false)
        )

        assertEquals(Action.NONE, d.action)
    }

    @Test
    fun `no window (no alarm ahead) cancels the alarms and leaves Do Not Disturb if ours`() {
        val d = SleepTimeDndPolicy.decide(
            input(now = start, startMillis = null, endMillis = null, activeByUs = true)
        )

        assertEquals(Code.NO_WINDOW, d.code)
        assertEquals(Action.DEACTIVATE, d.action)
        assertNull(d.startAlarmAt)
        assertNull(d.endAlarmAt)
    }

    // -------------------------------------------- the filter per platform

    @Test
    fun `API 35+ - activation always sets ALARMS on this app's own implicit rule`() {
        for (current in listOf(1, 2, 3, 4)) {
            assertEquals(
                SleepTimeDndPolicy.FILTER_ALARMS,
                SleepTimeDndPolicy.activationFilter(35, current, activeByUs = false)
            )
        }
    }

    @Test
    fun `API 35+ - deactivation sets ALL (ends only this app's rule), never a remembered filter`() {
        assertEquals(
            SleepTimeDndPolicy.FILTER_ALL,
            SleepTimeDndPolicy.deactivationFilter(36, currentFilter = 2, activeByUs = true, forced = false)
        )
        assertEquals(
            SleepTimeDndPolicy.FILTER_ALL,
            SleepTimeDndPolicy.deactivationFilter(35, currentFilter = 1, activeByUs = false, forced = true)
        )
        assertNull(
            SleepTimeDndPolicy.deactivationFilter(35, currentFilter = 4, activeByUs = false, forced = false)
        )
    }

    @Test
    fun `below API 35 - the user's own Do Not Disturb is neither claimed nor switched off`() {
        // Already on (the user's own, priority only): not claimed.
        assertNull(SleepTimeDndPolicy.activationFilter(34, currentFilter = 2, activeByUs = false))
        // Off: switched on.
        assertEquals(
            SleepTimeDndPolicy.FILTER_ALARMS,
            SleepTimeDndPolicy.activationFilter(34, currentFilter = 1, activeByUs = false)
        )
        // Ours and unchanged: switched off.
        assertEquals(
            SleepTimeDndPolicy.FILTER_ALL,
            SleepTimeDndPolicy.deactivationFilter(34, currentFilter = 4, activeByUs = true, forced = false)
        )
        // Changed by the user meanwhile: theirs now, even when forced.
        assertNull(
            SleepTimeDndPolicy.deactivationFilter(34, currentFilter = 2, activeByUs = true, forced = true)
        )
        // Never ours: not switched off, even when forced.
        assertNull(
            SleepTimeDndPolicy.deactivationFilter(34, currentFilter = 4, activeByUs = false, forced = true)
        )
    }

    @Test
    fun `the filter constants match the Android framework's values`() {
        // android.app.NotificationManager.INTERRUPTION_FILTER_ALL / _ALARMS -
        // compile-time constants, inlined, so readable on the plain JVM.
        assertEquals(android.app.NotificationManager.INTERRUPTION_FILTER_ALL, SleepTimeDndPolicy.FILTER_ALL)
        assertEquals(android.app.NotificationManager.INTERRUPTION_FILTER_ALARMS, SleepTimeDndPolicy.FILTER_ALARMS)
        assertEquals(android.os.Build.VERSION_CODES.VANILLA_ICE_CREAM, SleepTimeDndPolicy.IMPLICIT_RULE_SDK)
    }
}
