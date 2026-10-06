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

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.text.format.DateUtils
import android.util.Log

/**
 * docs/TODO.md T-217: the silent notice [DirectBootReceiver] posts instead
 * of the fallback siren when the mirrored alarm is more than
 * [DirectBootFallbackPolicy.MAX_OVERDUE_MINUTES] overdue - so the user
 * still learns that an alarm did not ring, without being blasted by a siren
 * long after it would have helped.
 *
 * Direct-Boot-safe like the siren: only system services and the due time
 * already in hand, nothing from credential-encrypted storage. Silent on
 * purpose (IMPORTANCE_LOW, no sound, no vibration, no full-screen intent);
 * tapping it opens the app. Never throws - a missing POST_NOTIFICATIONS
 * grant only means the notice is not shown.
 */
object DirectBootMissedNotification {
    private const val TAG = "DirectBootMissed"
    private const val CHANNEL_ID = "direct_boot_missed_alarm"
    private const val NOTIFICATION_ID = 0x217

    fun post(context: Context, dueAtMillis: Long) {
        try {
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val dueText = DateUtils.formatDateTime(
                context,
                dueAtMillis,
                DateUtils.FORMAT_SHOW_WEEKDAY or DateUtils.FORMAT_SHOW_DATE or
                    DateUtils.FORMAT_SHOW_TIME or DateUtils.FORMAT_ABBREV_ALL
            )
            val title = "Alarm missed"
            val text = "Your alarm for $dueText could not ring - the phone was " +
                "restarted or the app was stopped. Open the app to check your alarms."

            val openApp = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val contentIntent = PendingIntent.getActivity(
                context, 0x217, openApp,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Missed alarms (phone restarted or app stopped)",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    setSound(null, null)
                    enableVibration(false)
                }
                manager.createNotificationChannel(channel)
                Notification.Builder(context, CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setStyle(Notification.BigTextStyle().bigText(text))
                    .setContentIntent(contentIntent)
                    .setAutoCancel(true)
                    .build()
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
                    .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setStyle(Notification.BigTextStyle().bigText(text))
                    .setPriority(Notification.PRIORITY_LOW)
                    .setContentIntent(contentIntent)
                    .setAutoCancel(true)
                    .build()
            }
            manager.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to post the missed-alarm notification.", e)
        }
    }
}
