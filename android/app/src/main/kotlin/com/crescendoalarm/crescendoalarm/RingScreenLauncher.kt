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

import android.app.Activity
import android.app.Application
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.lifecycle.Observer
import com.gdelataillade.alarm.services.AlarmRingingLiveData

/**
 * The ring screen opening by itself on an unlocked phone in use. Android
 * only shows the `alarm` plugin's full-screen-intent notification as a
 * heads-up there; the plugin never starts an activity. This starts
 * [MainActivity] when an alarm begins to ring in exactly that state, see
 * [RingScreenLaunchPolicy] for the rules and why the locked and screen-off
 * states are left alone. The Flutter side needs nothing: with an engine
 * alive it has already queued the ring screen (`Handler.handleAlarm`), on a
 * cold start `Alarm.init` finds the ringing alarm - the same as after a tap
 * on the notification.
 *
 * The trigger is the plugin's own in-process `AlarmRingingLiveData`, updated
 * by its service for every ring that has a full-screen intent (which the app
 * always sets, `buildRingingAlarmSettings`). Failures are swallowed: this is
 * an addition to the notification, never a precondition of the ring.
 */
object RingScreenLauncher {
    private const val TAG = "RingScreenLauncher"
    private var resumedActivities = 0
    private var installed = false

    /** What the launcher saw at the last ring (docs/TODO.md T-240), for the diagnostics log. */
    @Volatile
    private var lastState: Map<String, Any?>? = null

    /** Null until a ring has been seen in this process. */
    fun lastRingState(): Map<String, Any?>? = lastState

    fun install(app: Application) {
        if (installed) return
        installed = true
        app.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) { resumedActivities++ }
            override fun onActivityPaused(activity: Activity) { if (resumedActivities > 0) resumedActivities-- }
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
        AlarmRingingLiveData.instance.observeForever(Observer { ringing ->
            if (ringing == true) onRing(app)
        })
    }

    private fun onRing(context: Context) {
        try {
            val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val decision = RingScreenLaunchPolicy.decide(
                overlayGranted = AlarmScreenAccess.overlayGranted(context),
                keyguardLocked = keyguard.isKeyguardLocked,
                interactive = power.isInteractive,
                activityResumed = resumedActivities > 0,
            )
            Log.i(TAG, "ring: decision=$decision")
            val state = hashMapOf<String, Any?>(
                "decision" to decision.code,
                "keyguardLocked" to keyguard.isKeyguardLocked,
                "screenOn" to power.isInteractive,
                "appInFront" to (resumedActivities > 0),
                "overlay" to AlarmScreenAccess.overlayGranted(context),
                "fullScreenIntent" to AlarmScreenAccess.fullScreenIntentGranted(context),
            )
            lastState = state
            if (decision != RingScreenLaunchPolicy.Decision.LAUNCH) return
            try {
                context.startActivity(
                    Intent(context, MainActivity::class.java).addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                    )
                )
            } catch (e: Exception) {
                state["decision"] = RingScreenLaunchPolicy.CODE_LAUNCH_FAILED
                lastState = state
                throw e
            }
        } catch (e: Exception) {
            Log.w(TAG, "Starting the ring screen failed: ${e.javaClass.simpleName}")
        }
    }
}
