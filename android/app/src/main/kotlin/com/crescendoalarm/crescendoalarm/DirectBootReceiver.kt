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
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * docs/TODO.md T-158: while a non-direct-boot-aware app's `BOOT_COMPLETED`
 * (and with it, the `alarm` plugin's own re-arm of `AlarmManager`) is
 * withheld by Android entirely until the device is unlocked for the first
 * time after a reboot, this receiver IS direct-boot-aware and receives
 * `LOCKED_BOOT_COMPLETED` immediately. It cannot read the app's real alarm
 * data - that lives in the normal, credential-encrypted `SharedPreferences`
 * both this app and the `alarm` plugin use, not decryptable yet - only the
 * single due time mirrored ahead of time into device-protected storage by
 * `lib/utils/direct_boot_mirror.dart` (via `DirectBootFallback`).
 *
 * What it arms is deliberately NOT the real ring path: the user's actual
 * tone, volume, and gentle-wake settings, and the QR gate, all need the
 * Flutter engine and the app's real settings, none of which are reachable
 * pre-unlock. It arms a loud, Direct-Boot-safe fallback siren instead - see
 * `DirectBootFallbackAlarmReceiver`. The user still has to unlock the
 * device for the real alarm (and the app's own FR-17 recovery) to take
 * over from there; this receiver only makes sure something audible happens
 * at roughly the right time instead of nothing at all.
 */
class DirectBootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "DirectBootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_LOCKED_BOOT_COMPLETED) return

        val dueAtMillis = DirectBootFallback.getDueAt(context)
        if (dueAtMillis == null) {
            Log.d(TAG, "No mirrored alarm to arm a fallback for.")
            return
        }

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            // Exact-alarm permission was revoked since this was mirrored -
            // nothing more this receiver can do without credential-encrypted
            // storage to check anything else. The `alarm` plugin's own
            // re-arm still runs normally once BOOT_COMPLETED is finally
            // delivered at unlock.
            Log.w(TAG, "Cannot schedule exact alarms; skipping direct-boot fallback.")
            return
        }

        val now = System.currentTimeMillis()
        // Same shape as the `alarm` plugin's own BootReceiver: an alarm
        // still ahead is scheduled for its real time; one already overdue
        // by the time this finally runs fires as soon as possible instead
        // of being silently dropped, since a locked reboot could take a
        // while to even get this receiver called.
        val fireAt = if (dueAtMillis > now) dueAtMillis else now

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, DirectBootFallbackAlarmReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pendingIntent)
        Log.i(TAG, "Direct-boot fallback armed for $fireAt (due was $dueAtMillis).")
    }
}
