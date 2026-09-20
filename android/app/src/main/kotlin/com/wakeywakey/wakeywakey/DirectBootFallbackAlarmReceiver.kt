// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of WakeyWakey.
//
// WakeyWakey is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// WakeyWakey is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with WakeyWakey. If not, see <https://www.gnu.org/licenses/>.


package com.wakeywakey.wakeywakey

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * docs/TODO.md T-158: the Direct-Boot-safe fallback siren itself.
 *
 * Deliberately built only from Direct-Boot-safe primitives - the system's
 * own default alarm ringtone (`RingtoneManager`, not a bundled or
 * user-chosen tone, which would need the app's own, still-locked storage),
 * a plain `NotificationManager` channel, and the `Vibrator` system service.
 * None of this touches the app's credential-encrypted `SharedPreferences`
 * or starts the Flutter engine - it cannot honour the user's actual tone,
 * volume, or gentle-wake settings, only make sure something loud happens at
 * roughly the right time.
 *
 * Tapping the notification opens `MainActivity` as normal; once the user
 * has unlocked the device to get there, the app's own FR-17 recovery runs
 * as usual and takes over for real.
 */
class DirectBootFallbackAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "DirectBootFallback"
        private const val CHANNEL_ID = "direct_boot_fallback"
        private const val NOTIFICATION_ID = 0x158
    }

    override fun onReceive(context: Context, intent: Intent) {
        // Consumed once: this is a single fallback nudge, not a repeating
        // siren the platform re-arms on its own. Clearing the mirrored due
        // time here means a stray retry - or the next real boot, before the
        // app has had a chance to mirror a fresh value - does not refire it
        // for an alarm already handled one way or another by then.
        DirectBootFallback.setDueAt(context, null)

        try {
            vibrate(context)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to vibrate for the direct-boot fallback.", e)
        }
        try {
            showNotification(context)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show the direct-boot fallback notification.", e)
        }
    }

    private fun vibrate(context: Context) {
        val pattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager =
                context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, -1)
        }
    }

    private fun showNotification(context: Context) {
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val alarmSound = RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)

        val openApp = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            context, 0, openApp,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = "Alarm couldn't ring on time"
        val text = "Device was still locked after a restart - unlock to continue."

        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Fallback alarm (device locked after restart)",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                setSound(alarmSound, audioAttributes)
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)

            Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(title)
                .setContentText(text)
                .setCategory(Notification.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setFullScreenIntent(contentIntent, true)
                .setContentIntent(contentIntent)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(title)
                .setContentText(text)
                .setPriority(Notification.PRIORITY_HIGH)
                .setSound(alarmSound, AudioManager.STREAM_ALARM)
                .setAutoCancel(true)
                .setFullScreenIntent(contentIntent, true)
                .setContentIntent(contentIntent)
                .build()
        }

        notificationManager.notify(NOTIFICATION_ID, notification)
    }
}
