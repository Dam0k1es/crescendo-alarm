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
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

/**
 * The two special accesses that decide whether the alarm screen can open by
 * itself (Settings > Alarm Screen, channel [CHANNEL]):
 * - full-screen intents (Android 14+: `NotificationManager.canUseFullScreenIntent`;
 *   below 14 the manifest permission is all there is, reported as null) - the
 *   locked-phone path; a denied one shows a plain heads-up even when locked;
 * - "Display over other apps" - what lets [RingScreenLauncher] start the
 *   screen on an unlocked phone in use.
 * Opening the system screens is the only way to change either.
 */
object AlarmScreenAccess {
    const val CHANNEL = "com.crescendoalarm.crescendoalarm/alarm_screen_access"

    fun overlayGranted(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    /** Null below Android 14, where there is nothing to grant or revoke. */
    fun fullScreenIntentGranted(context: Context): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return null
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return manager.canUseFullScreenIntent()
    }

    fun status(context: Context): Map<String, Any?> = mapOf(
        "fullScreenIntent" to fullScreenIntentGranted(context),
        "overlay" to overlayGranted(context),
    )

    fun openFullScreenIntentSettings(context: Context): Boolean =
        open(context, "android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT")

    fun openOverlaySettings(context: Context): Boolean =
        open(context, Settings.ACTION_MANAGE_OVERLAY_PERMISSION)

    private fun open(context: Context, action: String): Boolean = try {
        context.startActivity(
            Intent(action, Uri.parse("package:${context.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (e: Exception) {
        false
    }
}
