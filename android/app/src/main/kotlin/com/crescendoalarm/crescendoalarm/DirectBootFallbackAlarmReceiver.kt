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
import android.os.Build

/**
 * docs/TODO.md T-158: fires when [DirectBootReceiver] armed a fallback and
 * its time has come.
 *
 * Deliberately does almost nothing itself: a `BroadcastReceiver`'s
 * `onReceive` runs on the main thread for only a few seconds before Android
 * may kill the process, which is nowhere near enough to actually wake
 * someone up (found the hard way - an earlier version played one
 * notification chime and a single short vibration here directly, which is
 * not what an alarm has to do). All it does is hand off to
 * [DirectBootFallbackService], a genuine foreground service, which is what
 * loops the sound and vibration for real.
 */
class DirectBootFallbackAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Consumed once here, not in the service: this is what tells a
        // stray retry - or the next real boot, before the app has had a
        // chance to mirror a fresh value - not to refire a fallback for an
        // alarm already handled one way or another by then.
        DirectBootFallback.setDueAt(context, null)

        val serviceIntent = Intent(context, DirectBootFallbackService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
