import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/alarms/ringing_alarm_settings.dart';

// docs/TODO.md T-217: source-reading contract between the Dart side and the
// native direct-boot fallback, in the shape of
// sleep_time_dnd_platform_contract_test.dart. The native decision itself is
// JVM-tested (android/app/src/test/.../DirectBootFallbackPolicyTest.kt);
// what no JVM test can see is whether the receiver actually goes through
// that policy, whether the two sides agree on the 60-minute window, and how
// the notification channels are configured (NotificationChannel is an
// android.jar stub on the JVM).

const _kotlinDir =
    'android/app/src/main/kotlin/com/crescendoalarm/crescendoalarm';

String _read(String path) => File(path).readAsStringSync();

void main() {
  final policy = _read('$_kotlinDir/DirectBootFallbackPolicy.kt');
  final receiver = _read('$_kotlinDir/DirectBootReceiver.kt');
  final service = _read('$_kotlinDir/DirectBootFallbackService.kt');
  final missed = _read('$_kotlinDir/DirectBootMissedNotification.kt');
  final alarmReceiver = _read('$_kotlinDir/DirectBootFallbackAlarmReceiver.kt');
  final fallback = _read('$_kotlinDir/DirectBootFallback.kt');
  final mainActivity = _read('$_kotlinDir/MainActivity.kt');

  test('the native overdue window is the same 60 minutes Dart passes to the '
      'alarm plugin as androidStaleAfter', () {
    expect(overdueRingWindow, const Duration(minutes: 60),
        reason: 'maintainer decision 2026-10-06: "Nur bis 60 Min überfällig"');
    expect(policy,
        contains('const val MAX_OVERDUE_MINUTES = ${overdueRingWindow.inMinutes}L'));
  });

  test('DirectBootReceiver decides through the policy, not by hand', () {
    expect(receiver, contains('DirectBootFallbackPolicy.decide('));
    expect(receiver, isNot(contains('if (dueAtMillis > now) dueAtMillis else now')),
        reason: 'the old unconditional "overdue fires now" rule rang the '
            'siren for a due time of any age (T-217)');
    expect(receiver, contains('DirectBootMissedNotification.post('),
        reason: 'beyond the window the user must still learn about the miss');
  });

  test('the fallback siren notification channel is silent and new', () {
    // An existing channel's sound can no longer be changed by the app, so
    // silencing it needs a new id; the old channel is deleted.
    final id = RegExp(r'private const val CHANNEL_ID = "(\w+)"')
        .firstMatch(service)
        ?.group(1);
    expect(id, isNotNull);
    expect(id, isNot('direct_boot_fallback'));
    expect(service, contains('setSound(null, null)'));
    expect(fallback,
        contains('const val LEGACY_SIREN_CHANNEL_ID = "direct_boot_fallback"'));
    expect(fallback, contains('deleteNotificationChannel(LEGACY_SIREN_CHANNEL_ID)'));
    // Not only when a siren fires: on every receiver run and app start.
    for (final caller in [receiver, mainActivity, service]) {
      expect(caller, contains('DirectBootFallback.deleteLegacySirenChannel('));
    }
  });

  test('B1: the receiver tells the policy whether the user is unlocked, and '
      'a changed mirror cancels an already-armed siren', () {
    expect(receiver, contains('DirectBootFallback.isUserUnlocked(context)'));
    expect(fallback, contains('DirectBootFallbackPolicy.cancelsArmedSiren('));
    expect(fallback, contains('FLAG_NO_CREATE'));
  });

  test('the missed-alarm notification is silent and opens the app', () {
    expect(missed, contains('setSound(null, null)'));
    expect(missed, contains('NotificationManager.IMPORTANCE_LOW'));
    expect(missed, contains('MainActivity::class.java'));
    expect(missed, isNot(contains('setFullScreenIntent')));
  });

  test('the firing siren consumes only its own due time, never a newer '
      'mirrored alarm', () {
    expect(fallback, contains('putExtra(EXTRA_DUE_AT_MILLIS, dueAtMillis)'),
        reason: 'the armed PendingIntent must say which due time it is for');
    expect(receiver, contains('armed.dueAtMillis'));
    expect(alarmReceiver, contains('DirectBootFallback.consume('));
    expect(alarmReceiver, isNot(contains('setDueAt(context, null)')),
        reason: 'an unconditional clear erases an alarm the app mirrored '
            'meanwhile (T-217)');
  });

  test('the app channel always cancels an armed siren, and the receiver '
      'arms it through the shared PendingIntent helper', () {
    expect(mainActivity,
        contains('DirectBootFallback.setDueAt(applicationContext, dueAtMillis, fromApp = true)'));
    expect(receiver, contains('DirectBootFallback.sirenIntent('));
    expect(receiver, isNot(contains('PendingIntent.getBroadcast(')),
        reason: 'one definition of the siren PendingIntent, so the cancel '
            'path always matches what was armed');
  });
}
