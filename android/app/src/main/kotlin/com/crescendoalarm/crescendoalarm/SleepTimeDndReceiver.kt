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

/**
 * docs/TODO.md T-198: receives the sleep-time window's start and end alarms
 * armed by [SleepTimeDnd] and hands them straight back to it - no Flutter
 * engine, so the start and the end both happen at their instant even with
 * the app process dead.
 *
 * `android:exported="false"` in the manifest: only this app's own
 * PendingIntents (fired by AlarmManager on its behalf) can reach it, so no
 * other app can switch the phone into or out of Do Not Disturb through it.
 * Reads nothing from the Intent but its action; the window itself comes
 * from [SleepTimeDnd]'s own storage. Direct-boot-aware, so an end that falls
 * before the first unlock after a reboot is still delivered.
 */
class SleepTimeDndReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            SleepTimeDnd.ACTION_START ->
                SleepTimeDnd.onAlarm(context, SleepTimeDndPolicy.Trigger.START_ALARM)
            SleepTimeDnd.ACTION_END ->
                SleepTimeDnd.onAlarm(context, SleepTimeDndPolicy.Trigger.END_ALARM)
        }
    }
}
