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

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.UserManager
import android.util.Log

/**
 * docs/TODO.md T-158: storage and channel constants shared between the
 * Dart-side mirror (`lib/utils/direct_boot_mirror.dart`) and the native
 * Direct-Boot fallback (`DirectBootReceiver`/`DirectBootFallbackAlarmReceiver`).
 *
 * Deliberately its own device-protected-storage-backed `SharedPreferences`
 * file, not the app's normal one: everything here has to be readable while
 * the device is still locked after a reboot, before the user's
 * credential-encrypted storage - which holds the app's and the `alarm`
 * plugin's real alarm/settings data - is even decryptable.
 */
object DirectBootFallback {
    const val CHANNEL = "com.crescendoalarm.crescendoalarm/direct_boot"
    private const val PREFS_NAME = "direct_boot_fallback"
    private const val KEY_DUE_AT_MILLIS = "due_at_millis"

    /** The due time a fallback siren PendingIntent was armed for (T-217). */
    const val EXTRA_DUE_AT_MILLIS = "com.crescendoalarm.crescendoalarm.direct_boot_fallback.DUE_AT"

    private fun prefs(context: Context): SharedPreferences {
        val deviceContext = context.applicationContext.createDeviceProtectedStorageContext()
        return deviceContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    /** Records the next moment the fallback siren should be armed for, or clears it. */
    @Synchronized
    fun setDueAt(context: Context, dueAtMillis: Long?, fromApp: Boolean = false) {
        // docs/TODO.md T-217: a siren armed for the previous due time must
        // not survive the alarm it was for being deleted, disabled or moved,
        // and any write from the app (device unlocked) retires it.
        if (DirectBootFallbackPolicy.cancelsArmedSiren(getDueAt(context), dueAtMillis, fromApp)) {
            cancelArmedSiren(context)
        }
        val editor = prefs(context).edit()
        if (dueAtMillis == null) {
            editor.remove(KEY_DUE_AT_MILLIS)
        } else {
            editor.putLong(KEY_DUE_AT_MILLIS, dueAtMillis)
        }
        editor.apply()
    }

    /**
     * docs/TODO.md T-217: consumes the due time a siren or missed notice was
     * for - see [DirectBootFallbackPolicy.mirrorAfterConsuming]. Synchronized
     * with [setDueAt], the Dart side's write path in the same process.
     */
    @Synchronized
    fun consume(context: Context, firedForDueAt: Long?) {
        val stored = getDueAt(context)
        if (DirectBootFallbackPolicy.mirrorAfterConsuming(stored, firedForDueAt) != stored) {
            setDueAt(context, null)
        }
    }

    /** The stored due time, or null when nothing is currently armed. */
    fun getDueAt(context: Context): Long? {
        val stored = prefs(context)
        return if (stored.contains(KEY_DUE_AT_MILLIS)) stored.getLong(KEY_DUE_AT_MILLIS, -1L) else null
    }

    /** The PendingIntent DirectBootReceiver arms the siren with (request code 0). */
    // [dueAtMillis] travels as [EXTRA_DUE_AT_MILLIS] when arming; extras do
    // not take part in PendingIntent matching, so the cancel path finds it.
    fun sirenIntent(context: Context, flags: Int, dueAtMillis: Long? = null): PendingIntent? {
        val intent = Intent(context, DirectBootFallbackAlarmReceiver::class.java)
        if (dueAtMillis != null) intent.putExtra(EXTRA_DUE_AT_MILLIS, dueAtMillis)
        return PendingIntent.getBroadcast(context, 0, intent, flags or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun cancelArmedSiren(context: Context) {
        try {
            val pending = sirenIntent(context, PendingIntent.FLAG_NO_CREATE) ?: return
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(pending)
            pending.cancel()
        } catch (e: Exception) {
            Log.w("DirectBootFallback", "Failed to cancel the armed fallback siren.", e)
        }
    }

    /** Whether credential-encrypted storage is unlocked (see DirectBootFallbackPolicy.decide). */
    fun isUserUnlocked(context: Context): Boolean =
        (context.getSystemService(Context.USER_SERVICE) as UserManager).isUserUnlocked

    /**
     * docs/TODO.md T-217: the siren's first notification channel played the
     * default notification sound; its replacement is silent. Deleted here -
     * called from DirectBootReceiver and MainActivity.onCreate, not only when
     * a siren fires - so the stale entry leaves the app's notification
     * settings on the next app start. A no-op once gone.
     */
    const val LEGACY_SIREN_CHANNEL_ID = "direct_boot_fallback"

    fun deleteLegacySirenChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .deleteNotificationChannel(LEGACY_SIREN_CHANNEL_ID)
        } catch (e: Exception) {
            Log.w("DirectBootFallback", "Failed to delete the legacy siren channel.", e)
        }
    }
}
