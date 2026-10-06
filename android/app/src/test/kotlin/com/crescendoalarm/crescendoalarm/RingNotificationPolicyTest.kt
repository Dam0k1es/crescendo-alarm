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

import com.crescendoalarm.crescendoalarm.RingNotificationPolicy.Decision
import com.crescendoalarm.crescendoalarm.RingNotificationPolicy.PLUGIN_CHANNEL_ID
import com.crescendoalarm.crescendoalarm.RingNotificationPolicy.QUIET_CHANNEL_ID
import android.app.Notification
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * docs/TODO.md T-229: whether the ring screen may move the `alarm` plugin's
 * ringing notification onto the quiet channel. Maintainer (2026-10-06):
 * "Ich will nicht, dass sie beim Wecker Bildschirm in den Alarm reinragt" -
 * only while the ring screen is actually in front of the user; the alarm
 * tone is untouched either way.
 */
class RingNotificationPolicyTest {
    // The plugin's ring notification as the foreground service posts it.
    private val FGS = RingNotificationPolicy.FLAG_FOREGROUND_SERVICE or 0x2 /* FLAG_ONGOING_EVENT */

    @Test
    fun `ring screen in front of an unlocked phone - quiet the heads-up`() {
        assertEquals(
            Decision.QUIET,
            RingNotificationPolicy.decide(activityResumed = true, keyguardLocked = false, activeChannelId = PLUGIN_CHANNEL_ID, activeFlags = FGS),
        )
    }

    @Test
    fun `app in the background - the heads-up is how the user finds the alarm, leave it`() {
        assertEquals(
            Decision.SKIP_NOT_IN_FOREGROUND,
            RingNotificationPolicy.decide(activityResumed = false, keyguardLocked = false, activeChannelId = PLUGIN_CHANNEL_ID, activeFlags = FGS),
        )
    }

    @Test
    fun `locked device - the full-screen intent path, never touched`() {
        assertEquals(
            Decision.SKIP_LOCKED,
            RingNotificationPolicy.decide(activityResumed = true, keyguardLocked = true, activeChannelId = PLUGIN_CHANNEL_ID, activeFlags = FGS),
        )
        assertEquals(
            Decision.SKIP_LOCKED,
            RingNotificationPolicy.decide(activityResumed = false, keyguardLocked = true, activeChannelId = PLUGIN_CHANNEL_ID, activeFlags = FGS),
        )
    }

    @Test
    fun `no notification with that id - nothing to re-post (never invent one)`() {
        assertEquals(
            Decision.SKIP_NO_NOTIFICATION,
            RingNotificationPolicy.decide(activityResumed = true, keyguardLocked = false, activeChannelId = null, activeFlags = FGS),
        )
    }

    @Test
    fun `already quiet - no second post`() {
        assertEquals(
            Decision.SKIP_ALREADY_QUIET,
            RingNotificationPolicy.decide(activityResumed = true, keyguardLocked = false, activeChannelId = QUIET_CHANNEL_ID, activeFlags = FGS),
        )
    }

    @Test
    fun `a notification of ours on another channel with the same id is not the alarm's`() {
        assertEquals(
            Decision.SKIP_NOT_PLUGIN,
            RingNotificationPolicy.decide(activityResumed = true, keyguardLocked = false, activeChannelId = "sleep_reminder", activeFlags = FGS),
        )
    }

    @Test
    fun `the quiet channel is its own channel`() {
        assertNotEquals(PLUGIN_CHANNEL_ID, QUIET_CHANNEL_ID)
    }

    @Test
    fun `the plugin's notification no longer owned by its foreground service (Stop raced) - never re-post`() {
        assertEquals(
            Decision.SKIP_NOT_FOREGROUND_SERVICE,
            RingNotificationPolicy.decide(activityResumed = true, keyguardLocked = false, activeChannelId = PLUGIN_CHANNEL_ID, activeFlags = 0x2),
        )
    }

    @Test
    fun `a re-post no foreground service claimed is an orphan, one it claimed is not`() {
        assertTrue(RingNotificationPolicy.isOrphan(posted = true, postedFlags = 0x2))
        assertFalse(RingNotificationPolicy.isOrphan(posted = true, postedFlags = FGS))
        assertFalse(RingNotificationPolicy.isOrphan(posted = false, postedFlags = 0))
    }

    @Test
    fun `the flag constant is Android's`() {
        assertEquals(Notification.FLAG_FOREGROUND_SERVICE, RingNotificationPolicy.FLAG_FOREGROUND_SERVICE)
    }
}
