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
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.net.Uri
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
 * own Stop action), `ACTION_USER_PRESENT` fires (the device was unlocked -
 * see [userPresentReceiver]'s own doc comment for why this, not
 * `MainActivity`'s lifecycle, is the reliable stop signal), or
 * [MAX_RING_MILLIS] elapses.
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
    private var toneGenerator: ToneGenerator? = null
    private var toneLoopRunnable: Runnable? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private val stopRunnable = Runnable { stopSelf() }
    private var userPresentReceiverRegistered = false

    // docs/TODO.md T-158: a real-device test found that stopping this from
    // MainActivity's onCreate/onNewIntent (relying on the real alarm's own
    // full-screen intent, or the user tapping this fallback's notification,
    // to actually launch/resume the activity) did not reliably happen -
    // both kept ringing together regardless. ACTION_USER_PRESENT is the
    // system's own, unconditional signal that the keyguard was just
    // dismissed - it fires whether or not any activity ever launches - so
    // this is the actually-reliable way to know the fallback's one job
    // (getting someone to unlock the device) is done. Can only be received
    // by a dynamically registered receiver (implicit broadcasts like this
    // one aren't delivered to manifest-declared receivers since Android
    // 3.1), which is exactly what a running foreground service can do.
    private val userPresentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            Log.i(TAG, "Device unlocked (ACTION_USER_PRESENT); stopping the direct-boot fallback.")
            stopSelf()
        }
    }

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

        registerUserPresentReceiver()
        acquireWakeLock()
        startLoopingSound()
        startVibration()
        handler.postDelayed(stopRunnable, MAX_RING_MILLIS)

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(stopRunnable)
        unregisterUserPresentReceiver()

        mediaPlayer?.let {
            try {
                it.stop()
            } catch (e: Exception) {
                Log.w(TAG, "MediaPlayer.stop() failed while tearing down.", e)
            }
            it.release()
        }
        mediaPlayer = null
        stopToneGeneratorLoop()

        stopVibration()

        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null

        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(NOTIFICATION_ID)

        super.onDestroy()
    }

    private fun registerUserPresentReceiver() {
        try {
            registerReceiver(userPresentReceiver, IntentFilter(Intent.ACTION_USER_PRESENT))
            userPresentReceiverRegistered = true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register the ACTION_USER_PRESENT receiver.", e)
        }
    }

    private fun unregisterUserPresentReceiver() {
        if (!userPresentReceiverRegistered) return
        try {
            unregisterReceiver(userPresentReceiver)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to unregister the ACTION_USER_PRESENT receiver.", e)
        }
        userPresentReceiverRegistered = false
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

    /**
     * Tries the device's actual chosen alarm sound first, then its generic
     * default, and only falls back to a synthesized tone if both fail.
     *
     * Found necessary by real-device testing: vibration worked continuously
     * but no sound played at all pre-unlock. The likely cause is that
     * `RingtoneManager`'s URI can point at a *custom* alarm sound the user
     * picked in system settings, which - unlike a built-in system sound -
     * may live on storage that isn't mounted/decryptable yet at this point
     * in the boot sequence, so `MediaPlayer.setDataSource`/`prepare` fails
     * silently into the catch block below. [ToneGenerator] needs no file or
     * URI at all - it synthesizes its tone in code - so it cannot hit that
     * failure mode and is the one primitive here actually guaranteed to be
     * Direct-Boot-safe.
     */
    private fun startLoopingSound() {
        if (tryPlayUri(RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_ALARM))) {
            return
        }
        if (tryPlayUri(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))) {
            return
        }
        Log.w(TAG, "No ringtone URI could be played; falling back to a synthesized tone.")
        startToneGeneratorLoop()
    }

    private fun tryPlayUri(uri: Uri?): Boolean {
        if (uri == null) return false
        return try {
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@DirectBootFallbackService, uri)
                isLooping = true
                prepare()
                start()
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to play $uri for the direct-boot fallback.", e)
            mediaPlayer?.release()
            mediaPlayer = null
            false
        }
    }

    private fun startToneGeneratorLoop() {
        val generator = try {
            ToneGenerator(AudioManager.STREAM_ALARM, ToneGenerator.MAX_VOLUME)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create a ToneGenerator for the direct-boot fallback.", e)
            return
        }
        toneGenerator = generator

        val runnable = object : Runnable {
            override fun run() {
                generator.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 1_000)
                handler.postDelayed(this, 1_500)
            }
        }
        toneLoopRunnable = runnable
        handler.post(runnable)
    }

    private fun stopToneGeneratorLoop() {
        toneLoopRunnable?.let { handler.removeCallbacks(it) }
        toneLoopRunnable = null
        toneGenerator?.release()
        toneGenerator = null
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
