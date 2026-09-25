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

import android.app.NotificationManager
import android.content.Context

/**
 * docs/TODO.md T-184: a thin wrapper over `android.app.NotificationManager`'s
 * own Do Not Disturb control - `getCurrentInterruptionFilter`/
 * `setInterruptionFilter` - pure AOSP framework API, no Google Play Services
 * or any other proprietary surface involved. Deliberately custom, native code
 * rather than a third-party plugin dependency: the only pub.dev package found
 * for this (`do_not_disturb`) is unmaintained (last published ~21 months
 * before this was written) and MPL-2.0-licensed - GPLv3-compatible, but a
 * different licence category than every other dependency this project
 * carries, for four one-line framework calls this project can just make
 * directly, the same way `DirectBootFallback` already does for a different
 * native-only need.
 *
 * The *permission* to call `setInterruptionFilter` at all
 * (`ACCESS_NOTIFICATION_POLICY`, a "special" permission granted only via its
 * own Settings screen, not a runtime dialog) is requested from Dart via the
 * already-present `permission_handler` dependency
 * (`Permission.accessNotificationPolicy`) - this channel does not duplicate
 * that, only the actual state read/write once access is granted.
 */
object DoNotDisturbChannel {
    const val CHANNEL = "com.crescendoalarm.crescendoalarm/dnd"

    fun getCurrentInterruptionFilter(context: Context): Int {
        val manager =
            context.applicationContext.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
        return manager.currentInterruptionFilter
    }

    fun setInterruptionFilter(context: Context, filter: Int) {
        val manager =
            context.applicationContext.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
        manager.setInterruptionFilter(filter)
    }
}
