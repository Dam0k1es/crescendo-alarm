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

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log

/**
 * docs/TODO.md T-229: takes the `alarm` plugin's ringing notification out of
 * the heads-up while the ring screen is in front of the user - see
 * [RingNotificationPolicy] for the cause and the rules.
 *
 * How: the plugin's notification (posted by its foreground service with
 * `startForeground(alarmId, ...)`, null tag) is re-posted under the same id
 * from the same package. AOSP `ActiveServices
 * .applyForegroundServiceNotificationLocked` matches it to the running
 * foreground service by id and keeps it that service's notification (flag
 * `FLAG_FOREGROUND_SERVICE` re-applied), so the service, its audio and
 * vibration, and `stopForeground(STOP_FOREGROUND_REMOVE)` at the end are
 * unaffected. The copy comes from `Notification.Builder.recoverBuilder`, so
 * title, content intent and the plugin's delete intent (which re-posts the
 * notification after a swipe, T-147) are the plugin's own. Changed: the
 * channel (IMPORTANCE_LOW - SystemUI's `PeekNotImportantSuppressor` then
 * declines a heads-up, and `HeadsUpCoordinator.onEntryUpdated` removes the
 * one already showing), `setOnlyAlertOnce(true)`, and the full-screen
 * intent dropped - inert on a LOW channel anyway (`NO_FSI_NOT_IMPORTANT_ENOUGH`)
 * and its job is already done: the ring screen is showing.
 *
 * Not covered: the plugin keeps its own copy and re-posts it after a swipe
 * from the shade (`restoreNotification`) or when another alarm's start
 * command arrives mid-ring (`fulfillForegroundObligation`); that brings the
 * heads-up back until the app is next resumed.
 */
object RingNotification {
    const val CHANNEL = "com.crescendoalarm.crescendoalarm/ring_notification"
    private const val TAG = "RingNotification"

    /** Returns the decision's name, for the Dart side's log only. */
    fun quiet(context: Context, alarmId: Int, activityResumed: Boolean): String {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val active = activeAlarmNotification(manager, alarmId)
        val channelId = active?.let(::channelOf)
        val flags = active?.flags ?: 0
        val decision = RingNotificationPolicy.decide(activityResumed, keyguard.isKeyguardLocked, channelId, flags)
        if (decision != RingNotificationPolicy.Decision.QUIET || active == null) {
            return decision.name
        }
        try {
            ensureQuietChannel(manager)
            val builder = Notification.Builder.recoverBuilder(context, active)
                .setOnlyAlertOnce(true)
                .setFullScreenIntent(null, false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                builder.setChannelId(RingNotificationPolicy.QUIET_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                builder.setPriority(Notification.PRIORITY_LOW)
            }
            manager.notify(alarmId, builder.build())
            // Stop may have removed the service's notification between the
            // check above and notify(): then nothing owns the re-post.
            val posted = activeAlarmNotification(manager, alarmId)
            if (RingNotificationPolicy.isOrphan(posted != null, posted?.flags ?: 0)) {
                manager.cancel(alarmId)
                return "ORPHAN_CANCELLED"
            }
        } catch (e: Exception) {
            // Best effort: a failure leaves the plugin's notification as it was.
            Log.w(TAG, "Quieting the ring notification failed: ${e.javaClass.simpleName}")
            return "FAILED"
        }
        return decision.name
    }

    private fun activeAlarmNotification(manager: NotificationManager, alarmId: Int): Notification? =
        manager.activeNotifications.firstOrNull { it.id == alarmId && it.tag == null }?.notification

    private fun channelOf(notification: Notification): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) notification.channelId
        else RingNotificationPolicy.PLUGIN_CHANNEL_ID

    private fun ensureQuietChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            RingNotificationPolicy.QUIET_CHANNEL_ID,
            "Ringing alarm (alarm screen open)",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }
}
