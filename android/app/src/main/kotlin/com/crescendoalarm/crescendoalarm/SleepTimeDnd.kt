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
import android.util.Log

/**
 * docs/TODO.md T-198: the native half of the sleep-time Do Not Disturb
 * trigger - the only code in the app that switches Do Not Disturb.
 *
 * Dart pushes the window [start, end) via [sync] (channel [CHANNEL],
 * registered in `MainActivity`). This arms two exact AlarmManager alarms -
 * one at the start, one at the end - whose [SleepTimeDndReceiver] calls
 * back into [onAlarm] with no Flutter engine involved, so both fire at
 * their instant even when the app process is dead overnight. That is the
 * point of doing it natively (T-198's H3: the `alarm` plugin's own ring
 * reaches Dart only through `AlarmPlugin.alarmTriggerApi?.alarmRang`, which
 * is null whenever no engine is attached, and the plugin never starts one).
 * The end alarm uses the same `setExactAndAllowWhileIdle(RTC_WAKEUP, ...)`
 * call the `alarm` plugin arms the ring itself with, at the same
 * whole-minute instant - so it goes off with "the very first ring" (R4),
 * and a snooze re-ring or an unrelated alarm cannot end sleep time. Two
 * exact alarms at one instant do not delay each other: an app targeting S+
 * that holds USE_EXACT_ALARM keeps FLAG_ALLOW_WHILE_IDLE, whose quota is 72
 * per hour (AOSP android15-release AlarmManagerService.java
 * DEFAULT_ALLOW_WHILE_IDLE_QUOTA).
 *
 * State lives in device-protected storage, like [DirectBootFallback]: a
 * reboot wipes AlarmManager, and [onBoot] (called from the already
 * direct-boot-aware, already reviewed [DirectBootReceiver], so no new
 * exported component) must re-arm the window - or end it - before the first
 * unlock too.
 *
 * Every decision comes from [SleepTimeDndPolicy]; this object only executes.
 */
object SleepTimeDnd {
    const val CHANNEL = "com.crescendoalarm.crescendoalarm/sleep_time_dnd"

    const val ACTION_START = "com.crescendoalarm.crescendoalarm.action.SLEEP_TIME_START"
    const val ACTION_END = "com.crescendoalarm.crescendoalarm.action.SLEEP_TIME_END"

    private const val TAG = "SleepTimeDnd"

    // Deliberately new names: the removed T-184 feature kept its state in
    // the Flutter SharedPreferences file under different keys (T-197).
    private const val PREFS_NAME = "sleep_time_dnd"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_START = "start_millis"
    private const val KEY_END = "end_millis"
    private const val KEY_ACTIVE_BY_US = "active_by_us"
    private const val KEY_PENDING_START = "pending_start_millis"
    // "last_end_millis" held T-198's last-ring record for the A1 rule, removed
    // in T-203. Never reuse the key: a v1.4.0 install still has it stored.
    private const val KEY_LAST_END_REMOVED = "last_end_millis"
    private const val KEY_REPORT_START_FIRED = "report_start_fired"
    private const val KEY_REPORT_END_FIRED = "report_end_fired"
    private const val KEY_REPORT_APPLY_FAILED = "report_apply_failed"

    private const val REQUEST_START = 7_198_001
    private const val REQUEST_END = 7_198_002

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.createDeviceProtectedStorageContext()
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun SharedPreferences.longOrNull(key: String): Long? =
        if (contains(key)) getLong(key, 0L) else null

    /**
     * Dart's push. Returns the report Dart's `SleepTimeDndReport` parses -
     * the decision plus what happened natively since the previous push
     * (booleans only), then resets those flags.
     *
     * Runs on the main thread with the app process alive, so its writes use
     * `apply()` (in memory at once, on disk shortly after) - a replan pushes
     * once per armed or cancelled alarm, and synchronous `commit()`s there
     * would stall the UI. The receiver and boot paths, whose process may die
     * right after `onReceive`, keep `commit()`.
     */
    @Synchronized
    fun sync(context: Context, enabled: Boolean, startMillis: Long?, endMillis: Long?): Map<String, Any> {
        val stored = prefs(context)
        val wasEnabled = stored.getBoolean(KEY_ENABLED, false)
        stored.edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putOrRemove(KEY_START, startMillis)
            .putOrRemove(KEY_END, endMillis)
            .apply()

        val decision = run(context, SleepTimeDndPolicy.Trigger.SYNC, wasEnabled, durable = false)

        val report = hashMapOf<String, Any>(
            "decision" to decision.code,
            "startFired" to stored.getBoolean(KEY_REPORT_START_FIRED, false),
            "endFired" to stored.getBoolean(KEY_REPORT_END_FIRED, false),
            "applyFailed" to stored.getBoolean(KEY_REPORT_APPLY_FAILED, false),
            "accessMissing" to (enabled && !isAccessGranted(context)),
        )
        stored.edit()
            .remove(KEY_REPORT_START_FIRED)
            .remove(KEY_REPORT_END_FIRED)
            .remove(KEY_REPORT_APPLY_FAILED)
            .apply()
        return report
    }

    /**
     * One-shot, called by Dart when it finds the removed v1.3.0 feature's
     * preference keys (docs/TODO.md T-197/T-198): ends that feature's
     * leftover Do Not Disturb on API 35+ - see
     * [SleepTimeDndPolicy.legacyCleanupFilter] for why only there. Returns
     * whether a call was made and accepted.
     */
    @Synchronized
    fun clearLegacy(context: Context): Boolean {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return false
        val filter = SleepTimeDndPolicy.legacyCleanupFilter(
            Build.VERSION.SDK_INT, prefs(context).getBoolean(KEY_ACTIVE_BY_US, false)
        ) ?: return false
        return setFilter(context, nm, filter)
    }

    /** [SleepTimeDndReceiver]: the window's start or end alarm fired. */
    @Synchronized
    fun onAlarm(context: Context, trigger: SleepTimeDndPolicy.Trigger) {
        val stored = prefs(context)
        val flag = if (trigger == SleepTimeDndPolicy.Trigger.START_ALARM) {
            KEY_REPORT_START_FIRED
        } else {
            KEY_REPORT_END_FIRED
        }
        stored.edit().putBoolean(flag, true).commit()
        run(context, trigger, stored.getBoolean(KEY_ENABLED, false))
    }

    /** [DirectBootReceiver], on LOCKED_BOOT_COMPLETED: AlarmManager is empty. */
    @Synchronized
    fun onBoot(context: Context) {
        try {
            run(context, SleepTimeDndPolicy.Trigger.BOOT, prefs(context).getBoolean(KEY_ENABLED, false))
        } catch (e: Exception) {
            // Must never take the direct-boot alarm fallback down with it.
            Log.e(TAG, "Re-arming the sleep-time window after boot failed", e)
        }
    }

    private fun run(
        context: Context,
        trigger: SleepTimeDndPolicy.Trigger,
        wasEnabled: Boolean,
        durable: Boolean = true,
    ): SleepTimeDndPolicy.Decision {
        val stored = prefs(context)
        val decision = SleepTimeDndPolicy.decide(
            SleepTimeDndPolicy.Input(
                now = System.currentTimeMillis(),
                trigger = trigger,
                enabled = stored.getBoolean(KEY_ENABLED, false),
                wasEnabled = wasEnabled,
                startMillis = stored.longOrNull(KEY_START),
                endMillis = stored.longOrNull(KEY_END),
                activeByUs = stored.getBoolean(KEY_ACTIVE_BY_US, false),
                pendingStartAt = stored.longOrNull(KEY_PENDING_START),
            )
        )
        Log.i(TAG, "trigger=$trigger decision=${decision.code} action=${decision.action}")

        val activeByUs = stored.getBoolean(KEY_ACTIVE_BY_US, false)
        val nowActive = when (decision.action) {
            SleepTimeDndPolicy.Action.ACTIVATE -> activate(context, activeByUs)
            SleepTimeDndPolicy.Action.DEACTIVATE ->
                deactivate(context, activeByUs, decision.forceDeactivate)
            SleepTimeDndPolicy.Action.NONE -> activeByUs
        }

        armOrCancel(context, ACTION_START, REQUEST_START, decision.startAlarmAt)
        armOrCancel(context, ACTION_END, REQUEST_END, decision.endAlarmAt)

        val editor = stored.edit()
            .putBoolean(KEY_ACTIVE_BY_US, nowActive)
            .putOrRemove(KEY_PENDING_START, decision.startAlarmAt)
        if (!decision.keepWindow) editor.remove(KEY_START).remove(KEY_END)
        // T-203: drop v1.4.0's leftover last-ring record; nothing reads it.
        editor.remove(KEY_LAST_END_REMOVED)
        if (durable) editor.commit() else editor.apply()
        return decision
    }

    /** Returns whether this app now holds Do Not Disturb on. */
    private fun activate(context: Context, activeByUs: Boolean): Boolean {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return activeByUs
        val filter = SleepTimeDndPolicy.activationFilter(
            Build.VERSION.SDK_INT, nm.currentInterruptionFilter, activeByUs
        ) ?: return activeByUs
        return if (setFilter(context, nm, filter)) true else activeByUs
    }

    /** Returns whether this app still holds Do Not Disturb on. */
    private fun deactivate(context: Context, activeByUs: Boolean, forced: Boolean): Boolean {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return activeByUs
        val filter = SleepTimeDndPolicy.deactivationFilter(
            Build.VERSION.SDK_INT, nm.currentInterruptionFilter, activeByUs, forced
        ) ?: return false
        // A refused call (access revoked) keeps the claim, so the next push
        // or boot retries instead of forgetting it switched Do Not Disturb on.
        return if (setFilter(context, nm, filter)) false else activeByUs
    }

    private fun setFilter(context: Context, nm: NotificationManager, filter: Int): Boolean {
        if (!nm.isNotificationPolicyAccessGranted) {
            markApplyFailed(context)
            return false
        }
        return try {
            nm.setInterruptionFilter(filter)
            true
        } catch (e: RuntimeException) {
            // SecurityException without access, IllegalArgumentException for
            // an invalid filter (AOSP NotificationManagerService
            // .setInterruptionFilter) - never let either crash the receiver.
            Log.e(TAG, "setInterruptionFilter($filter) refused", e)
            markApplyFailed(context)
            false
        }
    }

    private fun markApplyFailed(context: Context) {
        // commit(): may run in a receiver whose process ends right after.
        prefs(context).edit().putBoolean(KEY_REPORT_APPLY_FAILED, true).commit()
    }

    private fun armOrCancel(context: Context, action: String, requestCode: Int, atMillis: Long?) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(context, SleepTimeDndReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        if (atMillis == null) {
            alarmManager.cancel(pendingIntent)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                // Same fallback as the `alarm` plugin's AlarmScheduler: late
                // beats never.
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pendingIntent)
            } else {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pendingIntent)
            }
        } catch (e: RuntimeException) {
            Log.e(TAG, "Arming $action failed", e)
        }
    }

    /**
     * Read-only queries for Dart (channel methods `currentInterruptionFilter`
     * and `isAccessGranted`). The filter is the effective one across every
     * active rule (see [SleepTimeDndPolicy.deactivationFilter]) - for
     * observing, never for restoring.
     */
    fun currentFilter(context: Context): Int =
        context.getSystemService(NotificationManager::class.java)?.currentInterruptionFilter
            ?: NotificationManager.INTERRUPTION_FILTER_UNKNOWN

    fun isAccessGranted(context: Context): Boolean =
        context.getSystemService(NotificationManager::class.java)?.isNotificationPolicyAccessGranted
            ?: false

    private fun SharedPreferences.Editor.putOrRemove(key: String, value: Long?): SharedPreferences.Editor =
        if (value == null) remove(key) else putLong(key, value)
}
