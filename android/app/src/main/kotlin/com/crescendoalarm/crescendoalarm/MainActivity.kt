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

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    // docs/TODO.md T-229: whether this activity (and with it the ring screen)
    // is in front of the user - RingNotificationPolicy quiets the ringing
    // notification only then.
    private var resumed = false

    override fun onResume() {
        super.onResume()
        resumed = true
    }

    override fun onPause() {
        resumed = false
        super.onPause()
    }

    // docs/TODO.md T-158: this activity is not direct-boot-aware, so reaching
    // it means the device has been unlocked at least once since boot and the
    // real ring pipeline (or the user themselves) can take over. Stop the
    // direct-boot fallback unconditionally, regardless of HOW this activity
    // was reached: tapping the fallback's own notification, tapping the real
    // alarm's own full-screen intent, or the user simply opening the app.
    // Only a safety net: on a real device this alone changed nothing, since
    // the real alarm's full-screen intent does not reliably launch this
    // activity - the reliable stop is DirectBootFallbackService's own
    // ACTION_USER_PRESENT receiver.
    // `stopService` on an already-stopped service is a harmless no-op, so
    // this is safe to call every time regardless of whether a fallback was
    // ever actually armed.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        stopService(Intent(this, DirectBootFallbackService::class.java))
        // docs/TODO.md T-217: remove the old, sound-playing siren channel on
        // every app start, not only when a siren fires.
        DirectBootFallback.deleteLegacySirenChannel(applicationContext)
    }

    // `launchMode="singleTop"` means an already-running instance is handed
    // a new intent here instead of going through onCreate again - covers
    // the app already being open in memory when a fallback (or the real
    // alarm) tries to bring it forward again.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        stopService(Intent(this, DirectBootFallbackService::class.java))
    }

    // docs/TODO.md T-158: the Dart-side mirror
    // (lib/utils/direct_boot_mirror.dart) calls this to keep the
    // device-protected-storage copy of the next alarm's due time current, so
    // DirectBootReceiver can arm a fallback siren even while the device
    // stays locked after a reboot - see DirectBootFallback's own doc
    // comment for why this can't just reuse the app's normal alarm storage.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DirectBootFallback.CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "setNextAlarm") {
                    val dueAtMillis = call.argument<Long>("dueAtMillis")
                    // docs/TODO.md T-217: a write from here means unlocked
                    // - any siren armed at the locked boot is retired.
                    DirectBootFallback.setDueAt(applicationContext, dueAtMillis, fromApp = true)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // docs/TODO.md T-198: the sleep-time Do Not Disturb window. Dart
        // only ever pushes the window here; Do Not Disturb itself is
        // switched by SleepTimeDnd when its own alarms fire. Reachable from
        // every place the window is pushed from, because all of them run in
        // this activity's engine - T-198's H2 finding: the only other engine
        // anything in this app creates is awesome_notifications'
        // DartBackgroundExecutor, which is used solely for silent notification
        // ACTIONS (none here) and never calls configureFlutterEngine.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SleepTimeDnd.CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setWindow" -> result.success(
                        SleepTimeDnd.sync(
                            applicationContext,
                            call.argument<Boolean>("enabled") ?: false,
                            call.argument<Number>("startMillis")?.toLong(),
                            call.argument<Number>("endMillis")?.toLong(),
                        )
                    )
                    "currentInterruptionFilter" ->
                        result.success(SleepTimeDnd.currentFilter(applicationContext))
                    "isAccessGranted" ->
                        result.success(SleepTimeDnd.isAccessGranted(applicationContext))
                    "clearLegacy" ->
                        result.success(SleepTimeDnd.clearLegacy(applicationContext))
                    else -> result.notImplemented()
                }
            }

        // docs/TODO.md T-229: the ring screens (ScreenAlarmActive, QrScanner)
        // call this when they appear and on every resume, to take the
        // plugin's ringing notification out of the heads-up over them.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RingNotification.CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "quiet") {
                    val alarmId = call.argument<Number>("alarmId")?.toInt()
                    if (alarmId == null) {
                        result.success("NO_ID")
                    } else {
                        result.success(RingNotification.quiet(applicationContext, alarmId, resumed))
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
