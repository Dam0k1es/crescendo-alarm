package com.crescendoalarm.crescendoalarm

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    // docs/TODO.md T-158: the app running at all - reached here - means the
    // device has been unlocked and the real ring pipeline (or the user
    // themselves) can take over from here. Stop the direct-boot fallback
    // unconditionally, regardless of HOW this activity was reached: tapping
    // the fallback's own notification, tapping the real alarm's own
    // full-screen intent, or the user simply opening the app - a real
    // device test found the fallback siren kept running after the real
    // alarm's ring screen had already taken over, because nothing had ever
    // told it to stop unless its own notification specifically was tapped.
    // `stopService` on an already-stopped service is a harmless no-op, so
    // this is safe to call every time regardless of whether a fallback was
    // ever actually armed.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        stopService(Intent(this, DirectBootFallbackService::class.java))
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
                    DirectBootFallback.setDueAt(applicationContext, dueAtMillis)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
