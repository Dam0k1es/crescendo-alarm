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

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/utils/alarm_screen_access.dart' as access;

// docs/TODO.md T-240: the two special accesses behind "the alarm screen opens
// by itself" (full-screen intents, "Display over other apps") are read from
// the native side. Dart must read the map as it is sent and fall back to
// "unavailable" - never throw - where there is no native side (the Linux dev
// loop, `flutter test`).

const _channel = MethodChannel('com.crescendoalarm.crescendoalarm/alarm_screen_access');

void _mock(Future<Object?> Function(MethodCall call)? handler) {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => _mock(null));

  test('Android 14+: both accesses are read as sent', () async {
    _mock((call) async => {'fullScreenIntent': false, 'overlay': true});

    final status = await access.readAlarmScreenAccess();

    expect(status.available, isTrue);
    expect(status.fullScreenIntent, isFalse);
    expect(status.overlay, isTrue);
  });

  test('below Android 14 the full-screen intent is "nothing to grant" (null)',
      () async {
    _mock((call) async => {'fullScreenIntent': null, 'overlay': false});

    final status = await access.readAlarmScreenAccess();

    expect(status.available, isTrue);
    expect(status.fullScreenIntent, isNull);
    expect(status.overlay, isFalse);
  });

  test('without a native side the status is "unavailable", not an exception',
      () async {
    _mock(null);

    final status = await access.readAlarmScreenAccess();

    expect(status.available, isFalse);
  });

  test('a malformed reply is unavailable too', () async {
    _mock((call) async => 'nonsense');

    expect((await access.readAlarmScreenAccess()).available, isFalse);
  });

  test('opening the two system screens calls the matching native method',
      () async {
    final calls = <String>[];
    _mock((call) async {
      calls.add(call.method);
      return true;
    });

    expect(await access.openFullScreenIntentSettings(), isTrue);
    expect(await access.openOverlaySettings(), isTrue);

    expect(calls, ['openFullScreenIntentSettings', 'openOverlaySettings']);
  });

  test('opening a system screen without a native side reports false', () async {
    _mock(null);

    expect(await access.openFullScreenIntentSettings(), isFalse);
    expect(await access.openOverlaySettings(), isFalse);
  });
}
