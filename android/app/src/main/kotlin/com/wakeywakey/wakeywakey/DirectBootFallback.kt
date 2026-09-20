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

import android.content.Context
import android.content.SharedPreferences

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
    const val CHANNEL = "com.wakeywakey.wakeywakey/direct_boot"
    private const val PREFS_NAME = "direct_boot_fallback"
    private const val KEY_DUE_AT_MILLIS = "due_at_millis"

    private fun prefs(context: Context): SharedPreferences {
        val deviceContext = context.applicationContext.createDeviceProtectedStorageContext()
        return deviceContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    /** Records the next moment the fallback siren should be armed for, or clears it. */
    fun setDueAt(context: Context, dueAtMillis: Long?) {
        val editor = prefs(context).edit()
        if (dueAtMillis == null) {
            editor.remove(KEY_DUE_AT_MILLIS)
        } else {
            editor.putLong(KEY_DUE_AT_MILLIS, dueAtMillis)
        }
        editor.apply()
    }

    /** The stored due time, or null when nothing is currently armed. */
    fun getDueAt(context: Context): Long? {
        val stored = prefs(context)
        return if (stored.contains(KEY_DUE_AT_MILLIS)) stored.getLong(KEY_DUE_AT_MILLIS, -1L) else null
    }
}
