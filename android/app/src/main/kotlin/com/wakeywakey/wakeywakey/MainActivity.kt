package com.wakeywakey.wakeywakey

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
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
