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
 * Whether [RingScreenLauncher] starts the ring screen itself when an alarm
 * starts ringing. Pure (no Android API), JVM-tested
 * (`RingScreenLaunchPolicyTest`), like [RingNotificationPolicy].
 *
 * Android launches a notification's full-screen intent only when the screen is
 * off or the device is locked; on a phone in use it shows a heads-up instead
 * (AOSP `NotificationInterruptStateProviderImpl` `NO_FSI_EXPECTED_TO_HUN`),
 * and a background process may not start an activity at all unless it holds
 * one of the documented exemptions - here "Display over other apps"
 * (SYSTEM_ALERT_WINDOW). So the app starts its activity only in the one state
 * that is otherwise left with a heads-up: unlocked, screen on, app not in
 * front, permission granted. The locked and screen-off states stay exactly
 * the full-screen-intent path (guaranteed wake-up), untouched.
 */
object RingScreenLaunchPolicy {
    /** [code] is what the diagnostics log records (Dart's `RingLaunchDecision`). */
    enum class Decision(val code: Int) {
        LAUNCH(1),
        SKIP_LOCKED(2),
        SKIP_SCREEN_OFF(3),
        SKIP_ALREADY_IN_FRONT(4),
        SKIP_NO_PERMISSION(5),
    }

    /** The launcher decided to start the screen and Android refused or threw. */
    const val CODE_LAUNCH_FAILED = 6

    /** The start was issued and the app was still not in front 2 s later (blocked silently). */
    const val CODE_LAUNCH_NOT_SHOWN = 7

    /** No ring has been seen by the launcher yet. */
    const val CODE_UNKNOWN = 0

    fun decide(
        overlayGranted: Boolean,
        keyguardLocked: Boolean,
        interactive: Boolean,
        activityResumed: Boolean,
    ): Decision = when {
        keyguardLocked -> Decision.SKIP_LOCKED
        !interactive -> Decision.SKIP_SCREEN_OFF
        activityResumed -> Decision.SKIP_ALREADY_IN_FRONT
        !overlayGranted -> Decision.SKIP_NO_PERMISSION
        else -> Decision.LAUNCH
    }
}
