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

// docs/TODO.md T-198: source-reading guards for the parts of the Do Not
// Disturb trigger that live across the Dart/Kotlin boundary, where
// `flutter test` cannot reach. Two kinds:
//
// 1. The contract itself - channel name, method names, decision codes and
//    the manifest entries have to match on both sides, or every call fails
//    silently at runtime (MissingPluginException, swallowed).
// 2. The structure that makes T-197's two device symptoms impossible,
//    rather than merely untested: Do Not Disturb is switched ONLY by native
//    code reacting to its own AlarmManager alarms at the window's start and
//    end, never by Dart and never from an awesome_notifications callback.
//    T-198's H1 finding (read from the AndroidAwnCore 0.12.1 bytecode) is
//    that `onNotificationCreatedMethod` fires when a notification is
//    SCHEDULED, not when it is due - the removed T-184 code hung its
//    activation there, which is exactly "DND on immediately after switching
//    the toggle on" and "DND back on right after the ring".

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/utils/sleep_time_dnd.dart';

const _kotlinDir =
    'android/app/src/main/kotlin/com/crescendoalarm/crescendoalarm';

String _read(String path) => File(path).readAsStringSync();

String _upperSnake(String camel) => camel
    .replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m.group(0)}')
    .toUpperCase();

/// Everything between `fun name(` and the next top-level-in-class `fun `/end.
String _functionBody(String source, String name) {
  final start = source.indexOf(RegExp('(Future<void>|void) $name\\('));
  expect(start, isNot(-1), reason: 'could not find $name - renamed?');
  final next = source.indexOf(RegExp(r'\n  (Future|void|bool|int|static|set |MyAlarm|DateTime|List|Map|///)'), start + 1);
  return source.substring(start, next == -1 ? source.length : next);
}

void main() {
  final manifest = _read('android/app/src/main/AndroidManifest.xml');
  final policy = _read('$_kotlinDir/SleepTimeDndPolicy.kt');
  final dnd = _read('$_kotlinDir/SleepTimeDnd.kt');
  final mainActivity = _read('$_kotlinDir/MainActivity.kt');

  group('manifest', () {
    test('declares ACCESS_NOTIFICATION_POLICY and no longer strips it', () {
      expect(
          manifest,
          contains('<uses-permission android:name='
              '"android.permission.ACCESS_NOTIFICATION_POLICY" />'));
      expect(
          RegExp(r'ACCESS_NOTIFICATION_POLICY"\s+tools:node="remove"')
              .hasMatch(manifest),
          isFalse);
    });

    test('the window receiver is not exported and is direct-boot-aware', () {
      final receiver = RegExp(
              r'<receiver\s+android:name="\.SleepTimeDndReceiver"[^>]*/?>')
          .firstMatch(manifest);
      expect(receiver, isNotNull, reason: 'SleepTimeDndReceiver not declared');
      final tag = receiver!.group(0)!;
      expect(tag, contains('android:exported="false"'),
          reason: 'only AlarmManager (via this app\'s own PendingIntent) '
              'may trigger it - an exported receiver would let any app '
              'switch the phone into Do Not Disturb');
      expect(tag, contains('android:directBootAware="true"'),
          reason: 'the end of a window that falls before the first unlock '
              'after a reboot must still be delivered');
    });

    test('no new exported component: boot re-arming reuses the already-'
        'accepted DirectBootReceiver (docs/TODO.md T-160)', () {
      final boot = _read('$_kotlinDir/DirectBootReceiver.kt');
      expect(boot, contains('SleepTimeDnd.onBoot(context)'));
      expect(manifest, isNot(contains('android.intent.action.BOOT_COMPLETED')),
          reason: 'the app itself registers no BOOT_COMPLETED receiver');
    });
  });

  group('channel contract', () {
    test('channel name matches on both sides and MainActivity registers it',
        () {
      expect(dnd, contains('const val CHANNEL = "$sleepTimeDndChannelName"'));
      expect(mainActivity, contains('SleepTimeDnd.CHANNEL'));
    });

    test('the native side exposes exactly the three methods Dart calls - '
        'none of which switches Do Not Disturb directly', () {
      final methods = RegExp(r'"(\w+)" ->')
          .allMatches(mainActivity)
          .map((m) => m.group(1)!)
          .where((m) => m != 'setNextAlarm')
          .toSet();
      expect(methods, {'setWindow', 'currentInterruptionFilter', 'isAccessGranted'});
    });

    test('every decision code Dart understands has the same value in Kotlin',
        () {
      for (final decision in SleepTimeDndDecision.values) {
        if (decision == SleepTimeDndDecision.channelFailed) continue;
        final name = _upperSnake(decision.name);
        expect(policy, contains('const val $name = ${decision.code}'),
            reason: '$name must be ${decision.code} in SleepTimeDndPolicy.kt');
      }
    });
  });

  group('structure that rules out T-197\'s symptoms', () {
    test('no Dart code switches the interruption filter itself', () {
      final offenders = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        if (RegExp(r'setInterruptionFilter|interruptionFilterAlarms|'
                r"invokeMethod<\w*>\('(activate|deactivate)")
            .hasMatch(source)) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('no awesome_notifications callback reaches the Do Not Disturb code '
        '(H1: "created" fires at scheduling time)', () {
      final notifications = _read('lib/utils/notifications.dart');
      expect(notifications, isNot(contains('sleep_time_dnd')));
      expect(notifications, isNot(contains('SleepTime')));
      expect(notifications, isNot(contains('refreshSleepTimeDnd')));
    });

    test('the bedtime reminder itself is untouched by the trigger (R2/R3 '
        'hook into it, they do not alter it)', () {
      final reminder = _read('lib/utils/sleep_reminder.dart');
      expect(reminder, isNot(contains('sleep_time_dnd')));
      expect(reminder, isNot(contains('DoNotDisturb')));
    });

    test('native activation only ever happens from the policy\'s decision, '
        'which is driven by the window, not by a Dart call', () {
      // The only call site of setInterruptionFilter in the whole app.
      final kotlinFiles = Directory(_kotlinDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.kt'));
      final callers = kotlinFiles
          .where((f) => f.readAsStringSync().contains('setInterruptionFilter('))
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(callers, ['SleepTimeDnd.kt']);
    });
  });

  group('AppState keeps the window current on every real arm/cancel', () {
    // Not drivable in flutter test: both reach the real `alarm` plugin (see
    // test/app_state_direct_boot_fallback_test.dart for the same limit). A
    // manual alarm created, edited, deleted or toggled changes "the next
    // alarm" without running a checkpoint, so without these two calls the
    // window would stay stale until the next day's first app open.
    final appState = _read('lib/app_state.dart');

    test('_setAlarm re-arms the window', () {
      expect(_functionBody(appState, '_setAlarm'),
          contains('refreshSleepTimeDnd()'));
    });

    test('_stopAlarm re-arms the window', () {
      expect(_functionBody(appState, '_stopAlarm'),
          contains('refreshSleepTimeDnd()'));
    });
  });
}
