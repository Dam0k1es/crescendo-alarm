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

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.gdelataillade.alarm.alarm.AlarmService
import com.gdelataillade.alarm.services.AlarmStorage

/**
 * docs/TODO.md T-237: the timer armed by [RingTimeout] fired. Not exported,
 * no intent filter - only [RingTimeout]'s explicit PendingIntent reaches it.
 *
 * Decides through [RingTimeoutPolicy] from what the plugin itself says (its
 * stored due time for the id, whether its service rings it) and ends only
 * THAT ring through the plugin's own stop path (audio, vibration, audio
 * focus, the foreground notification and its storage are all released by
 * it). No Flutter engine is needed. Before the first unlock the plugin's
 * credential-encrypted storage cannot be read - nothing can ring then
 * (the plugin's service is not direct-boot-aware), so nothing is done.
 */
class RingTimeoutReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "RingTimeoutReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != RingTimeout.ACTION) return
        val id = intent.getIntExtra(RingTimeout.EXTRA_ID, 0)
        val armedDue = intent.getLongExtra(RingTimeout.EXTRA_DUE, -1L)
        if (id == 0 || armedDue < 0) return
        val app = context.applicationContext
        try {
            if (!RingTimeout.isUserUnlocked(app)) {
                RingTimeout.consume(app, id, timedOut = false)
                return
            }
            val saved = AlarmStorage(app).getSavedAlarms().firstOrNull { it.id == id }
                ?.dateTime?.time
            val ringing = id in AlarmService.ringingAlarmIds
            when (val decision =
                RingTimeoutPolicy.decide(armedDue, System.currentTimeMillis(), ringing, saved)) {
                is RingTimeoutPolicy.Decision.StopAndNotify -> {
                    Log.i(TAG, "Ring $id was not stopped within the timeout; ending it.")
                    AlarmService.instance?.handleStopAlarmCommand(id)
                    DirectBootMissedNotification.postUnstopped(app, decision.dueAtMillis)
                    RingTimeout.consume(app, id, timedOut = true)
                }
                is RingTimeoutPolicy.Decision.Rearm ->
                    RingTimeout.rearm(app, id, maxOf(armedDue, saved ?: armedDue), decision.atMillis)
                RingTimeoutPolicy.Decision.Nothing -> RingTimeout.consume(app, id, timedOut = false)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Ring timeout handling failed", e)
        }
        // The alarm that follows (a daily repeat the plugin re-armed itself)
        // has no timeout yet.
        RingTimeout.syncFromPlugin(app)
    }
}
