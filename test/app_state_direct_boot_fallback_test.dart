import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/utils/direct_boot_mirror.dart' as direct_boot_mirror;

// docs/TODO.md T-158: neither this app nor the `alarm` plugin is
// direct-boot-aware, so a reboot followed by the device staying locked
// withholds BOOT_COMPLETED (and with it, the plugin's own re-arm) entirely
// until the first unlock - the alarm does not ring at all until then. The
// mitigation mirrors the single next-due instant into Android's
// device-protected storage, so a native, direct-boot-aware receiver can arm
// a fallback siren even while the device stays locked.
//
// `AppState.refreshDirectBootFallback` is the pure, testable half of that:
// it computes the same instant `nextWakeUpTime` already computes for the
// bedtime reminder (T-66) and hands it to the injectable
// `direct_boot_mirror.mirrorDirectBootFallback` seam. The actual native
// arming, and the wiring that calls this after every real `_setAlarm`/
// `_stopAlarm`, cannot be exercised in `flutter test` - like the rest of the
// `alarm` plugin boundary - and needs real-device verification instead.

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  DateTime? mirrored;
  int callCount = 0;

  setUp(() {
    mirrored = null;
    callCount = 0;
    direct_boot_mirror.mirrorDirectBootFallback = (dueAt) async {
      mirrored = dueAt;
      callCount++;
    };
  });

  tearDown(() {
    // Restore the real implementation so no other test file's run is
    // affected by this override - the same discipline as every other
    // injectable seam in this suite.
    direct_boot_mirror.mirrorDirectBootFallback =
        (dueAt) async {}; // overwritten again by the next test's setUp
  });

  test('mirrors the earliest upcoming manual alarm', () async {
    final appState = await _freshAppState();
    final now = DateTime(2026, 3, 10, 6, 0);
    // `AppState()`'s own init already calls refreshDirectBootFallback once
    // (with nothing armed yet) - reset so this test only asserts on the
    // explicit call below.
    callCount = 0;

    appState.manualAlarms.add(ManualAlarm(
      time: const TimeOfDay(hour: 7, minute: 0),
      enabled: true,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      id: 1,
    ));

    appState.refreshDirectBootFallback(now: () => now);

    expect(callCount, 1);
    expect(mirrored, DateTime(2026, 3, 10, 7, 0));
  });

  test('a disabled manual alarm is not mirrored', () async {
    final appState = await _freshAppState();
    final now = DateTime(2026, 3, 10, 6, 0);

    appState.manualAlarms.add(ManualAlarm(
      time: const TimeOfDay(hour: 7, minute: 0),
      enabled: false,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      id: 1,
    ));

    appState.refreshDirectBootFallback(now: () => now);

    expect(mirrored, isNull,
        reason: 'nothing is actually armed for a disabled alarm, so there '
            'is nothing for the fallback to arm either');
  });

  test('mirrors null once every alarm is gone', () async {
    final appState = await _freshAppState();
    final now = DateTime(2026, 3, 10, 6, 0);

    appState.manualAlarms.add(ManualAlarm(
      time: const TimeOfDay(hour: 7, minute: 0),
      enabled: true,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      id: 1,
    ));
    appState.refreshDirectBootFallback(now: () => now);
    expect(mirrored, isNotNull);

    appState.manualAlarms.clear();
    appState.refreshDirectBootFallback(now: () => now);

    expect(mirrored, isNull,
        reason: 'clearing the stored due time is what tells the native '
            'receiver there is nothing left to arm a fallback for');
  });
}
