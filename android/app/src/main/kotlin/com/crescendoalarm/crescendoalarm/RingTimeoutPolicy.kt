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

/**
 * docs/TODO.md T-237 (maintainer decision 2026-10-23): a ring nobody stops
 * ends itself [TIMEOUT_MINUTES] minutes after its due time - the `alarm`
 * plugin's own loop never ends. Pure (no Android API), JVM-tested
 * (`RingTimeoutPolicyTest`), like [DirectBootFallbackPolicy].
 *
 * The window equals `overdueRingWindow` in
 * `lib/models/alarms/ringing_alarm_settings.dart` (kept equal by
 * test/ring_timeout_contract_test.dart).
 *
 * The timeout is keyed to the due time it was armed for. The plugin keeps
 * an id across a native snooze (`SnoozeCoordinator` saves the same id with
 * a new due time) and across the repeat of a daily alarm, so a timeout for
 * an OLD due time must neither cut the new ring short nor leave it without
 * one: [Decision.Rearm].
 */
object RingTimeoutPolicy {
    const val TIMEOUT_MINUTES = 60L
    private const val MINUTE_MILLIS = 60_000L

    sealed class Decision {
        object Nothing : Decision()

        /** End the ring and report it; [dueAtMillis] is the due time it rang for. */
        data class StopAndNotify(val dueAtMillis: Long) : Decision()

        /** Not yet: the ring that is going now times out at [atMillis]. */
        data class Rearm(val atMillis: Long) : Decision()
    }

    fun timeoutAtMillis(dueAtMillis: Long): Long = dueAtMillis + TIMEOUT_MINUTES * MINUTE_MILLIS

    /** A timeout is worth arming only while it still lies in the future. */
    fun shouldArm(dueAtMillis: Long, nowMillis: Long): Boolean =
        timeoutAtMillis(dueAtMillis) > nowMillis

    /**
     * The timer armed for [armedDueAtMillis] fired. [savedDueAtMillis] is the
     * due time the plugin has stored for that id now (null: it stores
     * none), [alarmIsRinging] whether the plugin's service rings that id.
     */
    fun decide(
        armedDueAtMillis: Long,
        nowMillis: Long,
        alarmIsRinging: Boolean,
        savedDueAtMillis: Long?,
    ): Decision {
        if (!alarmIsRinging || savedDueAtMillis == null) return Decision.Nothing
        if (savedDueAtMillis < armedDueAtMillis) return Decision.Nothing
        if (savedDueAtMillis > armedDueAtMillis) {
            return Decision.Rearm(timeoutAtMillis(savedDueAtMillis))
        }
        val at = timeoutAtMillis(armedDueAtMillis)
        return if (nowMillis >= at) Decision.StopAndNotify(armedDueAtMillis) else Decision.Rearm(at)
    }

    /** After a reboot AlarmManager is empty: which mirrored entries get a timer again. */
    fun entriesToRearmAfterBoot(entries: Map<Int, Long>, nowMillis: Long): Map<Int, Long> =
        entries.filterValues { shouldArm(it, nowMillis) }
}
