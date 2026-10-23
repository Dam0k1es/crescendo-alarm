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

import com.crescendoalarm.crescendoalarm.RingScreenLaunchPolicy.Decision
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The ring screen opening by itself on an unlocked phone (the maintainer's
 * report: "an alarm rings, no screen opens, only a notification"). Android
 * shows a full-screen-intent notification as a heads-up on a phone in use
 * (AOSP NO_FSI_EXPECTED_TO_HUN), so the app starts its own activity then -
 * which a background process may only do with "Display over other apps".
 * Every other state is left to the full-screen intent (locked or screen
 * off) or needs nothing (the app is already in front).
 */
class RingScreenLaunchPolicyTest {
    private fun decide(
        overlayGranted: Boolean = true,
        keyguardLocked: Boolean = false,
        interactive: Boolean = true,
        activityResumed: Boolean = false,
    ) = RingScreenLaunchPolicy.decide(overlayGranted, keyguardLocked, interactive, activityResumed)

    @Test
    fun `an unlocked phone in use with the app in the background gets the ring screen started`() {
        assertEquals(Decision.LAUNCH, decide())
    }

    @Test
    fun `without the overlay permission nothing is started - a background start would be blocked`() {
        assertEquals(Decision.SKIP_NO_PERMISSION, decide(overlayGranted = false))
    }

    @Test
    fun `a locked phone is the full-screen-intent path and is not touched`() {
        assertEquals(Decision.SKIP_LOCKED, decide(keyguardLocked = true))
    }

    @Test
    fun `a screen that is off is the full-screen-intent path too`() {
        assertEquals(Decision.SKIP_SCREEN_OFF, decide(interactive = false))
    }

    @Test
    fun `an app already in front needs no start`() {
        assertEquals(Decision.SKIP_ALREADY_IN_FRONT, decide(activityResumed = true))
    }

    @Test
    fun `the cheaper rules come first - a locked phone is reported as locked even without the permission`() {
        assertEquals(Decision.SKIP_LOCKED, decide(overlayGranted = false, keyguardLocked = true))
        assertEquals(Decision.SKIP_SCREEN_OFF, decide(overlayGranted = false, interactive = false))
    }

    @Test
    fun `the decision codes are the ones the diagnostics log decodes`() {
        // Dart's RingLaunchDecision (lib/utils/diag/diag_log.dart) carries the same numbers;
        // 6 is the launcher's own "start failed", 0 "no ring seen yet".
        assertEquals(1, Decision.LAUNCH.code)
        assertEquals(2, Decision.SKIP_LOCKED.code)
        assertEquals(3, Decision.SKIP_SCREEN_OFF.code)
        assertEquals(4, Decision.SKIP_ALREADY_IN_FRONT.code)
        assertEquals(5, Decision.SKIP_NO_PERMISSION.code)
        assertEquals(6, RingScreenLaunchPolicy.CODE_LAUNCH_FAILED)
        assertEquals(0, RingScreenLaunchPolicy.CODE_UNKNOWN)
    }
}
