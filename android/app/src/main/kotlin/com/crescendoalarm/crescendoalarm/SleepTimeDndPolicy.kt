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
 * docs/TODO.md T-198: every decision the sleep-time Do Not Disturb trigger
 * makes, as pure functions - no Android types, so
 * `android/app/src/test/.../SleepTimeDndPolicyTest.kt` runs them on the JVM.
 * [SleepTimeDnd] only executes what this returns.
 *
 * Sleep time is the half-open window [start, end): start = next alarm minus
 * Sleep Goal, end = that alarm's ring (both computed on the Dart side, see
 * `lib/utils/sleep_time_dnd.dart`). The rules that make T-197's two device
 * symptoms impossible live here:
 *
 * - Nothing is ever activated outside [start, end) - not on a push from
 *   Dart, not from a start alarm that fires late or for a window that has
 *   since moved. Pushing a window whose start lies days ahead only arms an
 *   alarm (symptom 1: "DND on immediately after switching the toggle on").
 * - The end deactivates unconditionally when its alarm fires, and any later
 *   push or boot that finds the window over deactivates too (symptom 2:
 *   "DND not off after the alarm rang").
 */
object SleepTimeDndPolicy {
    /**
     * docs/TODO.md T-110, adopted from the bedtime reminder (R2): a start
     * already in the past is caught up two minutes from now, not
     * immediately - the same lead the reminder uses for a missed bedtime.
     */
    const val CATCH_UP_MILLIS: Long = 2 * 60 * 1000L

    /**
     * From API 35 (VANILLA_ICE_CREAM) on, for an app targeting it,
     * `setInterruptionFilter` no longer touches the global Do Not Disturb
     * state: it activates/deactivates an implicit `AutomaticZenRule` owned
     * by this app (AOSP android15-release, NotificationManager.java
     * setInterruptionFilter's javadoc; NotificationManagerService
     * .setInterruptionFilter -> ZenModeHelper
     * .applyGlobalZenModeAsImplicitZenRule). Below it, the call changes the
     * user's own global Do Not Disturb.
     */
    const val IMPLICIT_RULE_SDK = 35

    /** `NotificationManager.INTERRUPTION_FILTER_ALL` - Do Not Disturb off. */
    const val FILTER_ALL = 1

    /**
     * `NotificationManager.INTERRUPTION_FILTER_ALARMS` - only alarms (and
     * media) get through. Never `INTERRUPTION_FILTER_NONE`: that would
     * silence this app's own alarm too.
     */
    const val FILTER_ALARMS = 4

    /** Decision codes, shared with `SleepTimeDndDecision` in Dart. */
    object Code {
        const val DISABLED = 1
        const val NO_WINDOW = 2
        const val SCHEDULED = 3
        const val CATCH_UP = 4
        const val ALREADY_ACTIVE = 5
        const val ENDED = 6
        const val TOO_LATE = 7
        /** The start alarm fired inside the window. Native-only. */
        const val ACTIVATED = 8
        /** An alarm fired for a window that has since moved. Native-only. */
        const val STALE_ALARM = 9
    }

    enum class Trigger {
        /** Dart pushed the current window (or "disabled"). */
        SYNC,
        /** The window's start alarm fired. */
        START_ALARM,
        /** The window's end alarm fired - the first ring of the target alarm. */
        END_ALARM,
        /** The device booted (LOCKED_BOOT_COMPLETED); AlarmManager was wiped. */
        BOOT,
    }

    enum class Action { NONE, ACTIVATE, DEACTIVATE }

    data class Input(
        val now: Long,
        val trigger: Trigger,
        val enabled: Boolean,
        /** Whether the feature was on before this push (SYNC only). */
        val wasEnabled: Boolean,
        val startMillis: Long?,
        val endMillis: Long?,
        /** This app switched Do Not Disturb on and has not switched it off. */
        val activeByUs: Boolean,
        /** When the start alarm is currently armed for, if at all. */
        val pendingStartAt: Long?,
    )

    data class Decision(
        val code: Int,
        val action: Action,
        /**
         * Deactivate even without a record of having activated. Only acted
         * on where that cannot touch the user's own Do Not Disturb - see
         * [deactivationFilter].
         */
        val forceDeactivate: Boolean,
        /** Arm the start alarm for this instant, or cancel it (null). */
        val startAlarmAt: Long?,
        /** Arm the end alarm for this instant, or cancel it (null). */
        val endAlarmAt: Long?,
        /** Keep the stored window; false clears it. */
        val keepWindow: Boolean,
    )

    fun decide(i: Input): Decision {
        val start = i.startMillis
        val end = i.endMillis

        if (!i.enabled) {
            // Switching the feature off (R6) leaves Do Not Disturb even when
            // the record of having switched it on was lost (reinstall, data
            // cleared - docs/TODO.md T-190's device report).
            val turnedOff = i.trigger == Trigger.SYNC && i.wasEnabled
            return Decision(
                code = Code.DISABLED,
                action = if (i.activeByUs || turnedOff) Action.DEACTIVATE else Action.NONE,
                forceDeactivate = turnedOff,
                startAlarmAt = null,
                endAlarmAt = null,
                keepWindow = false,
            )
        }

        if (start == null || end == null || start >= end) {
            return Decision(
                code = Code.NO_WINDOW,
                action = if (i.activeByUs) Action.DEACTIVATE else Action.NONE,
                forceDeactivate = false,
                startAlarmAt = null,
                endAlarmAt = null,
                keepWindow = false,
            )
        }

        if (i.now >= end) {
            // The window is over - its end alarm just fired (R4: the first
            // ring), or a push/boot finds it over after the fact.
            val forced = i.trigger == Trigger.END_ALARM
            return Decision(
                code = Code.ENDED,
                action = if (i.activeByUs || forced) Action.DEACTIVATE else Action.NONE,
                forceDeactivate = forced,
                startAlarmAt = null,
                endAlarmAt = null,
                keepWindow = false,
            )
        }

        if (i.now < start) {
            // Before sleep time. Whatever triggered this, nothing is
            // activated now - a start alarm firing here belongs to a window
            // that has since moved later. If Do Not Disturb is still on from
            // before (the target alarm moved later mid-window), sleep time is
            // no longer now, so it goes off until the new start.
            val alarmFired = i.trigger == Trigger.START_ALARM || i.trigger == Trigger.END_ALARM
            return Decision(
                code = if (alarmFired) Code.STALE_ALARM else Code.SCHEDULED,
                action = if (i.activeByUs) Action.DEACTIVATE else Action.NONE,
                forceDeactivate = false,
                startAlarmAt = start,
                endAlarmAt = end,
                keepWindow = true,
            )
        }

        // Inside sleep time: start <= now < end.
        return when (i.trigger) {
            Trigger.START_ALARM -> Decision(
                code = Code.ACTIVATED,
                action = Action.ACTIVATE,
                forceDeactivate = false,
                startAlarmAt = null,
                endAlarmAt = end,
                keepWindow = true,
            )
            Trigger.BOOT ->
                if (i.activeByUs) {
                    // Re-apply: whether a reboot preserves the rule's active
                    // state is platform detail this does not rely on.
                    Decision(Code.ALREADY_ACTIVE, Action.ACTIVATE, false, null, end, true)
                } else {
                    catchUp(i, end)
                }
            Trigger.SYNC ->
                if (i.activeByUs) {
                    Decision(Code.ALREADY_ACTIVE, Action.NONE, false, null, end, true)
                } else {
                    catchUp(i, end)
                }
            Trigger.END_ALARM -> {
                // An end alarm before the end belongs to an older, earlier
                // window. Keep the current one as a push would.
                val asSync = if (i.activeByUs) {
                    Decision(Code.ALREADY_ACTIVE, Action.NONE, false, null, end, true)
                } else {
                    catchUp(i, end)
                }
                asSync.copy(code = Code.STALE_ALARM)
            }
        }
    }

    /**
     * Inside sleep time, not yet active: T-110's "now + 2 minutes". A
     * catch-up already armed within that span is kept, so repeated pushes
     * (one replan arms and cancels several alarms, and each pushes) cannot
     * keep postponing it.
     */
    private fun catchUp(i: Input, end: Long): Decision {
        val pending = i.pendingStartAt
        val at = if (pending != null && pending > i.now && pending <= i.now + CATCH_UP_MILLIS) {
            pending
        } else {
            i.now + CATCH_UP_MILLIS
        }
        return if (at >= end) {
            // The alarm rings within the catch-up delay - not worth
            // silencing the phone for the few seconds left.
            Decision(Code.TOO_LATE, Action.NONE, false, null, end, true)
        } else {
            Decision(Code.CATCH_UP, Action.NONE, false, at, end, true)
        }
    }

    /**
     * The filter to set for [Action.ACTIVATE], or null for no call.
     *
     * - API 35+: always [FILTER_ALARMS]. It only activates this app's own
     *   implicit rule; the user's own Do Not Disturb (or any other mode) is
     *   untouched and simply combines with it.
     * - Below: only when Do Not Disturb is currently off. If the user's own
     *   Do Not Disturb is already on, this leaves it alone and does not claim
     *   it - so the end will not switch the user's own setting off either.
     *   Once claimed, a later re-apply does not override a change the user
     *   made meanwhile.
     */
    fun activationFilter(sdkInt: Int, currentFilter: Int, activeByUs: Boolean): Int? =
        when {
            sdkInt >= IMPLICIT_RULE_SDK -> FILTER_ALARMS
            activeByUs -> null
            currentFilter == FILTER_ALL -> FILTER_ALARMS
            else -> null
        }

    /**
     * The filter to set for [Action.DEACTIVATE], or null for no call.
     *
     * - API 35+: [FILTER_ALL] whenever this app activated, or the decision
     *   forces it - [FILTER_ALL] only deactivates this app's own implicit
     *   rule (ZenModeHelper: "Deactivate implicit rule if it exists and is
     *   active; otherwise ignore"), so it can never switch off the user's own
     *   Do Not Disturb. Deliberately NOT "restore the previous filter":
     *   `getCurrentInterruptionFilter` reports the effective filter across
     *   every active rule, and handing a remembered non-ALL value back would
     *   ACTIVATE this app's rule instead of ending it.
     * - Below: only if this app switched it on and it is still exactly what
     *   this app set; if the user changed it meanwhile, it is theirs now.
     */
    fun deactivationFilter(
        sdkInt: Int,
        currentFilter: Int,
        activeByUs: Boolean,
        forced: Boolean,
    ): Int? =
        when {
            sdkInt >= IMPLICIT_RULE_SDK -> if (activeByUs || forced) FILTER_ALL else null
            activeByUs && currentFilter == FILTER_ALARMS -> FILTER_ALL
            else -> null
        }
}
