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
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * docs/TODO.md T-158: the actual Direct-Boot-safe fallback siren.
 *
 * A `BroadcastReceiver.onReceive` (the first version of this fallback,
 * before real-device testing showed the gap) runs on the main thread for
 * only a few seconds before Android may reclaim it - long enough for a
 * single notification chime and a short vibration, nowhere near enough to
 * actually wake anyone. A genuine foreground service is what real alarm
 * apps use for exactly this reason, and it is what loops the sound and
 * vibration here for real, until [ACTION_STOP] is sent (the notification's
 * own Stop action) or [MAX_RING_MILLIS] elapses.
 *
 * Deliberately built only from Direct-Boot-safe primitives - the system's
 * own default alarm ringtone (`RingtoneManager`, not a bundled or
 * user-chosen tone, which would need the app's own, still-locked storage),
 * plain `NotificationManager`/`Vibrator`/`PowerManager` system services.
 * None of this touches the app's credential-encrypted `SharedPreferences`
 * or starts the Flutter engine - it cannot honour the user's actual tone,
 * volume, or gentle-wake settings, only make sure something loud and
 * continuous happens until the device is unlocked.
 */
class DirectBootFallbackService : Service() {
    companion object {
        private const val TAG = "DirectBootFallback"
        private const val CHANNEL_ID = "direct_boot_fallback"
        private const val NOTIFICATION_ID = 0x158
        const val ACTION_STOP = "com.wakeywakey.wakeywakey.direct_boot_fallback.STOP"

        // A real alarm rings until dismissed, but nothing here can tell
        // whether anyone is even present to dismiss it - an uncapped
        // foreground service plus wake lock running forever on a bug would
        // be its own hazard. Ten minutes is generous enough to actually
        // wake someone while staying bounded.
        private const val MAX_RING_MILLIS = 10 * 60 * 1000L
    }

    private var mediaPlayer: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private val stopRunnable = Runnable { stopSelf() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        acquireWakeLock()
        startLoopingSound()
        startVibration()
        handler.postDelayed(stopRunnable, MAX_RING_MILLIS)

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(stopRunnable)

        mediaPlayer?.let {
            try {
                it.stop()
            } catch (e: Exception) {
                Log.w(TAG, "MediaPlayer.stop() failed while tearing down.", e)
            }
            it.release()
        }
        mediaPlayer = null

        stopVibration()

        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null

        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(NOTIFICATION_ID)

        super.onDestroy()
    }

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "wakeywakey:direct_boot_fallback"
            ).apply {
                setReferenceCounted(false)
                acquire(MAX_RING_MILLIS + 5_000)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire the direct-boot fallback wake lock.", e)
        }
    }

    private fun startLoopingSound() {
        val alarmSound =
            RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        try {
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@DirectBootFallbackService, alarmSound)
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to play the direct-boot fallback sound.", e)
        }
    }

    private fun startVibration() {
        // Repeat index 0 (not -1): loops the whole pattern indefinitely,
        // rather than firing it once, until cancelled in onDestroy.
        val pattern = longArrayOf(0, 1000, 500)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager =
                    getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                manager.defaultVibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to vibrate for the direct-boot fallback.", e)
        }
    }

    private fun stopVibration() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                    .defaultVibrator.cancel()
            } else {
                @Suppress("DEPRECATION")
                (getSystemService(Context.VIBRATOR_SERVICE) as Vibrator).cancel()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel vibration.", e)
        }
    }

    private fun buildNotification(): Notification {
        val openApp = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            this, 0, openApp,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = PendingIntent.getService(
            this, 0,
            Intent(this, DirectBootFallbackService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = "Alarm couldn't ring on time"
        val text = "Device was still locked after a restart - unlock to continue."

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // The channel itself stays silent (no sound attached) - the
            // service loops the alarm sound via MediaPlayer instead, so the
            // system doesn't also play its own one-shot channel sound on
            // top of it.
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Fallback alarm (device locked after restart)",
                NotificationManager.IMPORTANCE_HIGH
            )
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)

            Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(title)
                .setContentText(text)
                .setCategory(Notification.CATEGORY_ALARM)
                .setOngoing(true)
                .setFullScreenIntent(contentIntent, true)
                .setContentIntent(contentIntent)
                .addAction(Notification.Action.Builder(null, "Stop", stopIntent).build())
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(title)
                .setContentText(text)
                .setPriority(Notification.PRIORITY_HIGH)
                .setOngoing(true)
                .setFullScreenIntent(contentIntent, true)
                .setContentIntent(contentIntent)
                .addAction(0, "Stop", stopIntent)
                .build()
        }
    }
}
