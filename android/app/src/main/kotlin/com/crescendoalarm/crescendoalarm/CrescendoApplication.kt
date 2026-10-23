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

import android.app.Application

/**
 * The process-wide hook for [RingScreenLauncher]: the `alarm` plugin's
 * foreground service runs in this process even when no Flutter engine and no
 * activity exist (a ring after a swipe from Recents, or after the process was
 * killed), and the observer must be there before the first ring.
 */
class CrescendoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        RingScreenLauncher.install(this)
    }
}
