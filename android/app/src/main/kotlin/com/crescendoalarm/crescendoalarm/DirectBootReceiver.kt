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
 * docs/TODO.md T-158: `BOOT_COMPLETED` (and with it, the `alarm` plugin's
 * own re-arm of `AlarmManager`) only arrives once the user unlocks the
 * device for the first time after a reboot - for every app, direct-boot-aware
 * or not. `LOCKED_BOOT_COMPLETED` arrives before that, but only to
 * direct-boot-aware components, which this receiver is. It cannot read the app's real alarm
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

        // docs/TODO.md T-198: a reboot wiped the sleep-time Do Not Disturb
        // window's AlarmManager alarms too. Re-armed here - before the
        // fallback's own early return below - rather than from a new
        // BOOT_COMPLETED receiver: that would be a second exported component
        // (see T-160 for the review this one already had), and it would only
        // run after the first unlock, too late for an end that falls before
        // it. Reads nothing from the Intent; swallows its own failures.
        SleepTimeDnd.onBoot(context)

        // docs/TODO.md T-217: not only a real boot. On Android 15+ a
        // force-stopped app gets LOCKED_BOOT_COMPLETED again when the user
        // next launches it (AOSP ActivityManagerService
        // maybeSendBootCompletedLocked, flag stayStopped), and the mirrored
        // due time can then be days old - the real-device report was a
        // siren a day and a half late. The policy rings only up to 60
        // minutes overdue (the `alarm` plugin's androidStaleAfter, set from
        // lib/), reports anything older as missed, and arms no siren at all
        // when the user is already unlocked - then the plugin's own
        // BootReceiver re-arms the real alarm right after this.
        val now = System.currentTimeMillis()
        DirectBootFallback.deleteLegacySirenChannel(context)
        val decision = DirectBootFallbackPolicy.decide(
            DirectBootFallback.getDueAt(context), now, DirectBootFallback.isUserUnlocked(context)
        )
        val armed = when (decision) {
            is DirectBootFallbackPolicy.Decision.Nothing -> {
                Log.d(TAG, "No fallback needed (nothing mirrored, or already unlocked).")
                return
            }
            is DirectBootFallbackPolicy.Decision.NotifyMissed -> {
                Log.i(TAG, "Mirrored alarm is too far overdue to ring; reporting it as missed.")
                DirectBootMissedNotification.post(context, decision.dueAtMillis)
                // Consumed, so the next boot does not report it again -
                // unless the app has meanwhile mirrored a newer alarm.
                DirectBootFallback.consume(context, decision.dueAtMillis)
                return
            }
            is DirectBootFallbackPolicy.Decision.ArmSiren -> decision
        }

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            // Exact-alarm permission was revoked since this was mirrored
            // (only possible on API 31-32: from 33 on, USE_EXACT_ALARM is
            // granted at install and cannot be revoked) -
            // nothing more this receiver can do without credential-encrypted
            // storage to check anything else. The `alarm` plugin's own
            // re-arm still runs normally once BOOT_COMPLETED is finally
            // delivered at unlock.
            Log.w(TAG, "Cannot schedule exact alarms; skipping direct-boot fallback.")
            return
        }

        // T-217: the shared helper, so DirectBootFallback's cancel path
        // always matches what is armed here; the due time travels as an
        // extra and tells the alarm receiver which value it consumes.
        val pendingIntent = DirectBootFallback.sirenIntent(
            context, PendingIntent.FLAG_UPDATE_CURRENT, armed.dueAtMillis
        ) ?: return

        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, armed.atMillis, pendingIntent)
        Log.i(TAG, "Direct-boot fallback armed for ${armed.atMillis}.")
    }
}
