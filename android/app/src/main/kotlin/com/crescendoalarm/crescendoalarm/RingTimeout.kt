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
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.UserManager
import android.util.Log
import com.gdelataillade.alarm.services.AlarmStorage

/**
 * docs/TODO.md T-237: the native half of "a ring nobody stops ends itself
 * after 60 minutes". Dart pushes which alarm id is armed for which due time
 * ([arm], [cancel], [cancelAll], channel [CHANNEL] in `MainActivity`); this
 * arms one exact AlarmManager alarm per id at due + 60 minutes, whose
 * [RingTimeoutReceiver] needs no Flutter engine - it works with the app
 * process dead, which is the whole point (a Recents swipe leaves the ring
 * going since T-230).
 *
 * The entries are mirrored into device-protected storage (like
 * [DirectBootFallback]): a reboot wipes AlarmManager, and
 * [rearmAfterBoot] (from the already direct-boot-aware [DirectBootReceiver])
 * re-arms the ones still ahead. A mirrored entry is dropped when it fires
 * or when its timeout has passed.
 *
 * The plugin re-arms its own alarms after a force-stop, an update or a boot
 * without telling Dart, and after a native-only timeout the next alarm of a
 * daily repeat is armed by the plugin too: [syncFromPlugin] reads the
 * plugin's stored alarms and arms a timeout for each, at cold start and
 * after every timeout. Reading them needs credential-encrypted storage, so
 * it only runs once the user has unlocked and swallows every failure.
 */
object RingTimeout {
    const val CHANNEL = "com.crescendoalarm.crescendoalarm/ring_timeout"
    const val ACTION = "com.crescendoalarm.crescendoalarm.action.RING_TIMEOUT"
    const val EXTRA_ID = "alarmId"
    const val EXTRA_DUE = "dueAtMillis"

    private const val TAG = "RingTimeout"
    private const val PREFS_NAME = "ring_timeout"
    private const val ENTRY_PREFIX = "due_"
    private const val TIMED_OUT_PREFIX = "timedout_"
    private const val TIMED_OUT_KEEP_MILLIS = 48L * 60 * 60 * 1000

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.createDeviceProtectedStorageContext()
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun isUserUnlocked(context: Context): Boolean =
        context.getSystemService(UserManager::class.java)?.isUserUnlocked ?: false

    @Synchronized
    fun arm(context: Context, id: Int, dueAtMillis: Long) {
        val now = System.currentTimeMillis()
        if (!RingTimeoutPolicy.shouldArm(dueAtMillis, now)) {
            cancel(context, id)
            return
        }
        prefs(context).edit().putLong("$ENTRY_PREFIX$id", dueAtMillis).apply()
        schedule(context, id, dueAtMillis, RingTimeoutPolicy.timeoutAtMillis(dueAtMillis))
    }

    @Synchronized
    fun cancel(context: Context, id: Int) {
        prefs(context).edit().remove("$ENTRY_PREFIX$id").apply()
        pendingIntent(context, id, 0L, PendingIntent.FLAG_NO_CREATE)?.let {
            alarmManager(context).cancel(it)
            it.cancel()
        }
    }

    @Synchronized
    fun cancelAll(context: Context) {
        for (id in entries(context).keys) cancel(context, id)
    }

    /** Re-arms the same timer later (the receiver fired too early or the ring was snoozed). */
    @Synchronized
    fun rearm(context: Context, id: Int, dueAtMillis: Long, atMillis: Long) {
        prefs(context).edit().putLong("$ENTRY_PREFIX$id", dueAtMillis).commit()
        schedule(context, id, dueAtMillis, atMillis)
    }

    /** The timer for [id] fired and acted: its mirrored entry is done. */
    @Synchronized
    fun consume(context: Context, id: Int, timedOut: Boolean) {
        val edit = prefs(context).edit().remove("$ENTRY_PREFIX$id")
        if (timedOut) edit.putLong("$TIMED_OUT_PREFIX$id", System.currentTimeMillis())
        edit.commit()
    }

    /** The ids that ended by their timeout since the last call (consumed). */
    @Synchronized
    fun takeTimedOut(context: Context): List<Int> {
        val stored = prefs(context)
        val now = System.currentTimeMillis()
        val ids = mutableListOf<Int>()
        val edit = stored.edit()
        for ((key, value) in stored.all) {
            if (!key.startsWith(TIMED_OUT_PREFIX)) continue
            val at = value as? Long ?: continue
            val id = key.removePrefix(TIMED_OUT_PREFIX).toIntOrNull()
            if (id != null && now - at <= TIMED_OUT_KEEP_MILLIS) ids.add(id)
            edit.remove(key)
        }
        edit.apply()
        return ids
    }

    /** [DirectBootReceiver], on LOCKED_BOOT_COMPLETED: AlarmManager is empty. */
    @Synchronized
    fun rearmAfterBoot(context: Context) {
        try {
            val now = System.currentTimeMillis()
            val all = entries(context)
            val keep = RingTimeoutPolicy.entriesToRearmAfterBoot(all, now)
            for ((id, due) in keep) {
                schedule(context, id, due, RingTimeoutPolicy.timeoutAtMillis(due))
            }
            val edit = prefs(context).edit()
            for (id in all.keys - keep.keys) edit.remove("$ENTRY_PREFIX$id")
            edit.apply()
        } catch (e: Exception) {
            // Must never take the direct-boot alarm fallback down with it.
            Log.e(TAG, "Re-arming the ring timeouts after boot failed", e)
        }
    }

    /**
     * Arms a timeout for every alarm the plugin has stored. Needs
     * credential-encrypted storage (the plugin's DataStore): before the first
     * unlock nothing is read, and nothing can ring then either.
     */
    @Synchronized
    fun syncFromPlugin(context: Context) {
        if (!isUserUnlocked(context)) return
        try {
            val now = System.currentTimeMillis()
            for (alarm in AlarmStorage(context.applicationContext).getSavedAlarms()) {
                val due = alarm.dateTime.time
                if (RingTimeoutPolicy.shouldArm(due, now) &&
                    prefs(context).getLong("$ENTRY_PREFIX${alarm.id}", -1L) != due
                ) {
                    arm(context, alarm.id, due)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Syncing the ring timeouts from the alarm plugin failed", e)
        }
    }

    private fun entries(context: Context): Map<Int, Long> {
        val out = hashMapOf<Int, Long>()
        for ((key, value) in prefs(context).all) {
            if (!key.startsWith(ENTRY_PREFIX)) continue
            val id = key.removePrefix(ENTRY_PREFIX).toIntOrNull() ?: continue
            if (value is Long) out[id] = value
        }
        return out
    }

    private fun alarmManager(context: Context) =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    /**
     * Explicit intent to the non-exported receiver, immutable, request code =
     * alarm id (the component is part of a PendingIntent's identity, so the
     * plugin's own request codes cannot collide). The due time travels as an
     * extra; FLAG_UPDATE_CURRENT refreshes it.
     */
    private fun pendingIntent(context: Context, id: Int, dueAtMillis: Long, flags: Int): PendingIntent? {
        val intent = Intent(context, RingTimeoutReceiver::class.java).apply {
            action = ACTION
            putExtra(EXTRA_ID, id)
            putExtra(EXTRA_DUE, dueAtMillis)
        }
        return PendingIntent.getBroadcast(context, id, intent, flags or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun schedule(context: Context, id: Int, dueAtMillis: Long, atMillis: Long) {
        try {
            val pending =
                pendingIntent(context, id, dueAtMillis, PendingIntent.FLAG_UPDATE_CURRENT) ?: return
            val manager = alarmManager(context)
            // The exact-alarm permission can be revoked on API 31-32 only: an
            // inexact timeout is still far better than none (same pattern as
            // SleepTimeDnd).
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()) {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
            } else {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Arming the ring timeout failed", e)
        }
    }
}
