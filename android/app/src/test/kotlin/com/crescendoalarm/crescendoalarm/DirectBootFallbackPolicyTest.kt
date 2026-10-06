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

import com.crescendoalarm.crescendoalarm.DirectBootFallbackPolicy.Decision
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * docs/TODO.md T-217: what DirectBootReceiver does with the mirrored due
 * time. Maintainer decision (2026-10-06): the fallback siren may ring for an
 * overdue alarm only up to 60 minutes overdue; beyond that no siren, but a
 * silent "alarm missed" notification, so the user still learns about it.
 */
class DirectBootFallbackPolicyTest {
    private val minute = 60 * 1000L
    private val hour = 60 * minute

    // Some Saturday 07:00, as epoch millis.
    private val due = 1_790_000_000_000L

    @Test
    fun `nothing mirrored - nothing to do`() {
        assertEquals(Decision.Nothing, DirectBootFallbackPolicy.decide(null, due, userUnlocked = false))
    }

    @Test
    fun `a future due time arms the siren for that due time, as before`() {
        assertEquals(
            Decision.ArmSiren(atMillis = due, dueAtMillis = due),
            DirectBootFallbackPolicy.decide(due, due - 8 * hour, userUnlocked = false),
        )
    }

    @Test
    fun `a due time exactly now rings now`() {
        assertEquals(
            Decision.ArmSiren(atMillis = due, dueAtMillis = due),
            DirectBootFallbackPolicy.decide(due, due, userUnlocked = false),
        )
    }

    @Test
    fun `T-158's purpose stays - a few minutes overdue after a locked reboot rings now`() {
        val now = due + 5 * minute
        assertEquals(
            Decision.ArmSiren(atMillis = now, dueAtMillis = due),
            DirectBootFallbackPolicy.decide(due, now, userUnlocked = false),
        )
    }

    @Test
    fun `exactly 60 minutes overdue still rings - up to 60 min is inclusive`() {
        val now = due + 60 * minute
        assertEquals(
            Decision.ArmSiren(atMillis = now, dueAtMillis = due),
            DirectBootFallbackPolicy.decide(due, now, userUnlocked = false),
        )
    }

    @Test
    fun `one millisecond past 60 minutes overdue does not ring but reports the miss`() {
        assertEquals(
            Decision.NotifyMissed(dueAtMillis = due),
            DirectBootFallbackPolicy.decide(due, due + 60 * minute + 1, userUnlocked = false),
        )
    }

    @Test
    fun `a weekend powered off does not ring a siren at boot`() {
        assertEquals(
            Decision.NotifyMissed(dueAtMillis = due),
            DirectBootFallbackPolicy.decide(due, due + 50 * hour, userUnlocked = false),
        )
    }

    @Test
    fun `the 60 minutes match the alarm plugin's androidStaleAfter set from Dart`() {
        // lib/models/alarms/ringing_alarm_settings.dart passes the same
        // window as androidStaleAfter; test/direct_boot_fallback_contract_test
        // .dart checks the two sources agree. The plugin's own BootReceiver
        // discards when `now - due > staleAfter`, i.e. inclusive like here.
        assertEquals(60L, DirectBootFallbackPolicy.MAX_OVERDUE_MINUTES)
        assertEquals(60 * minute, DirectBootFallbackPolicy.MAX_OVERDUE_MILLIS)
    }

    /**
     * The real-device report of 2026-10-04/05, step by step:
     * `verify-long-idle-alarm-survival.sh arm` armed a manual alarm about 24
     * hours ahead (the mirror then holds Saturday's due time), rebooted, and
     * force-stopped the app. On Android 15+ the force-stop cancels every
     * PendingIntent - the fallback's and the plugin's alarm alike - and
     * nothing refreshes the mirror while the app is stopped. When the user
     * launched the app on Sunday evening, ActivityManagerService
     * (`maybeSendBootCompletedLocked`, flag `stayStopped`) sent this
     * encryption-aware app LOCKED_BOOT_COMPLETED again, and the receiver
     * found Saturday's due time, 36 hours old.
     */
    @Test
    fun `the Sunday sequence - reboot before the due time arms it, the launch a day and a half later does not ring`() {
        val armedFriday = due - 24 * hour + 2 * minute
        val rebootFriday = armedFriday + 3 * minute
        assertEquals(
            Decision.ArmSiren(atMillis = due, dueAtMillis = due),
            DirectBootFallbackPolicy.decide(due, rebootFriday, userUnlocked = false),
        )

        val sundayEveningLaunch = due + 36 * hour
        assertEquals(
            Decision.NotifyMissed(dueAtMillis = due),
            DirectBootFallbackPolicy.decide(due, sundayEveningLaunch, userUnlocked = true),
        )
    }

    // ------------------------------------------- consuming the mirror (T-217)

    @Test
    fun `consuming the fired due time clears the mirror`() {
        assertEquals(null, DirectBootFallbackPolicy.mirrorAfterConsuming(due, due))
    }

    @Test
    fun `a newer alarm mirrored meanwhile survives the old siren firing`() {
        val next = due + 24 * hour
        assertEquals(next, DirectBootFallbackPolicy.mirrorAfterConsuming(next, due))
    }

    @Test
    fun `nothing stored stays nothing`() {
        assertEquals(null, DirectBootFallbackPolicy.mirrorAfterConsuming(null, due))
    }

    @Test
    fun `a siren armed by an older build carries no due time - cleared as before`() {
        assertEquals(null, DirectBootFallbackPolicy.mirrorAfterConsuming(due, null))
    }

    // ------------------------------------- receiver run while unlocked (B1)
    //
    // On a launch after a force-stop (Android 15+) the receiver runs because
    // the user just opened the app: the device is unlocked, the `alarm`
    // plugin gets BOOT_COMPLETED right after and re-arms the real alarm
    // itself. A siren then would ring on top of it (overdue) or stay armed
    // for a mirrored time nothing cancels any more (future).

    @Test
    fun `unlocked - a future alarm arms no siren, the real alarm is armed by the plugin`() {
        assertEquals(
            Decision.Nothing,
            DirectBootFallbackPolicy.decide(due, due - 8 * hour, userUnlocked = true),
        )
    }

    @Test
    fun `unlocked - an alarm up to 60 minutes overdue rings no siren on top of the real one`() {
        assertEquals(
            Decision.Nothing,
            DirectBootFallbackPolicy.decide(due, due + 30 * minute, userUnlocked = true),
        )
        assertEquals(
            Decision.Nothing,
            DirectBootFallbackPolicy.decide(due, due + 60 * minute, userUnlocked = true),
        )
    }

    @Test
    fun `unlocked - more than 60 minutes overdue still reports the miss`() {
        assertEquals(
            Decision.NotifyMissed(dueAtMillis = due),
            DirectBootFallbackPolicy.decide(due, due + 61 * minute, userUnlocked = true),
        )
    }

    @Test
    fun `unlocked - nothing mirrored is still nothing`() {
        assertEquals(Decision.Nothing, DirectBootFallbackPolicy.decide(null, due, userUnlocked = true))
    }

    // ---------------------------- cancelling an armed siren on change (B1b)

    @Test
    fun `a changed or cleared mirror cancels the armed siren, an unchanged one does not`() {
        assertEquals(true, DirectBootFallbackPolicy.cancelsArmedSiren(due, due + hour, fromApp = false))
        assertEquals(true, DirectBootFallbackPolicy.cancelsArmedSiren(due, null, fromApp = false))
        assertEquals(false, DirectBootFallbackPolicy.cancelsArmedSiren(due, due, fromApp = false))
        assertEquals(false, DirectBootFallbackPolicy.cancelsArmedSiren(null, null, fromApp = false))
        assertEquals(true, DirectBootFallbackPolicy.cancelsArmedSiren(null, due, fromApp = false))
    }

    @Test
    fun `any write from the app cancels the siren, even with the same due time`() {
        // A write over the Dart channel means the device is unlocked and the
        // plugin's own re-arm has run: a siren armed at the locked boot for
        // that same alarm would otherwise ring together with the real one.
        assertEquals(true, DirectBootFallbackPolicy.cancelsArmedSiren(due, due, fromApp = true))
        assertEquals(true, DirectBootFallbackPolicy.cancelsArmedSiren(null, null, fromApp = true))
    }
}
