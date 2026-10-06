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
 * docs/TODO.md T-229: whether [RingNotification.quiet] may move the `alarm`
 * plugin's ringing notification onto the quiet channel. Pure (no Android
 * API), so it is JVM-tested (`RingNotificationPolicyTest`), like
 * `SleepTimeDndPolicy` and `DirectBootFallbackPolicy`.
 *
 * Maintainer (2026-10-06): "Die Benachrichtigung ist nicht stumm. Ich will
 * nicht, dass sie beim Wecker Bildschirm in den Alarm reinragt." - "In der
 * Benachrichtigungsleiste. Der Wecker-Ton soll natürlich weiter laufen."
 *
 * Why there is anything to quiet: the plugin (alarm 5.12.0,
 * `NotificationService.kt`) posts the ring notification on its own
 * IMPORTANCE_HIGH channel with a full-screen intent. On an unlocked phone in
 * use, SystemUI does not launch a full-screen intent but shows a heads-up
 * instead (AOSP `FullScreenIntentDecisionProvider`, `NO_FSI_EXPECTED_TO_HUN`),
 * and a heads-up whose notification carries a full-screen intent is sticky
 * (`HeadsUpManagerImpl.HeadsUpEntry.isSticky` -> `hasFullScreenIntent`): it
 * never times out and covers the top of the ring screen for as long as the
 * alarm rings. Channel sound is null and channel vibration is off - the
 * "not silent" part is that heads-up, nothing audible.
 *
 * The rules, each guarding the one thing that must not be weakened:
 * - [Decision.SKIP_LOCKED]: a locked device is the full-screen-intent path
 *   (guaranteed wake-up); there is no heads-up to remove there, and the
 *   notification stays exactly as the plugin posted it.
 * - [Decision.SKIP_NOT_IN_FOREGROUND]: with the app in the background the
 *   heads-up is how the user gets to the ring screen at all. It is quieted
 *   only once the ring screen is actually in front (the Dart side asks
 *   again on every resume).
 * - [Decision.SKIP_NO_NOTIFICATION] / [Decision.SKIP_NOT_PLUGIN]: only the
 *   plugin's own notification is ever re-posted - never one invented here,
 *   never another notification that happens to share the id.
 * - [Decision.SKIP_NOT_FOREGROUND_SERVICE]: only while the plugin's
 *   foreground service still owns it. Re-posting after Stop removed it would
 *   leave an orphan ongoing notification behind; [isOrphan] is the check
 *   after posting that closes the remaining race (AOSP `ActiveServices`
 *   applies `FLAG_FOREGROUND_SERVICE` to the re-post only if a foreground
 *   service with that id is still running).
 */
object RingNotificationPolicy {
    /** The `alarm` plugin's channel (`NotificationService.CHANNEL_ID`); test/ring_notification_contract_test.dart keeps it in sync. */
    const val PLUGIN_CHANNEL_ID = "alarm_plugin_channel"

    /** IMPORTANCE_LOW: in the notification shade, no heads-up, no sound, no vibration. */
    const val QUIET_CHANNEL_ID = "alarm_ringing_quiet"

    enum class Decision {
        QUIET,
        SKIP_LOCKED,
        SKIP_NOT_IN_FOREGROUND,
        SKIP_NO_NOTIFICATION,
        SKIP_ALREADY_QUIET,
        SKIP_NOT_PLUGIN,
        SKIP_NOT_FOREGROUND_SERVICE,
    }

    /** `Notification.FLAG_FOREGROUND_SERVICE` (0x40), kept here so the policy stays free of Android classes. */
    const val FLAG_FOREGROUND_SERVICE = 0x00000040

    /**
     * @param activityResumed MainActivity (and with it the ring screen) is in the foreground.
     * @param keyguardLocked the device is locked (`KeyguardManager.isKeyguardLocked`).
     * @param activeChannelId channel of the app's active notification with the alarm's id, or null if there is none.
     * @param activeFlags that notification's `Notification.flags` (ignored when there is none).
     */
    fun decide(activityResumed: Boolean, keyguardLocked: Boolean, activeChannelId: String?, activeFlags: Int): Decision = when {
        keyguardLocked -> Decision.SKIP_LOCKED
        !activityResumed -> Decision.SKIP_NOT_IN_FOREGROUND
        activeChannelId == null -> Decision.SKIP_NO_NOTIFICATION
        activeChannelId == QUIET_CHANNEL_ID -> Decision.SKIP_ALREADY_QUIET
        activeChannelId != PLUGIN_CHANNEL_ID -> Decision.SKIP_NOT_PLUGIN
        activeFlags and FLAG_FOREGROUND_SERVICE == 0 -> Decision.SKIP_NOT_FOREGROUND_SERVICE
        else -> Decision.QUIET
    }

    /**
     * After the re-post: the notification now active under the alarm's id
     * (null if none) is an orphan - no foreground service claimed it, i.e.
     * Stop won the race - and must be cancelled.
     */
    fun isOrphan(posted: Boolean, postedFlags: Int): Boolean =
        posted && postedFlags and FLAG_FOREGROUND_SERVICE == 0
}
