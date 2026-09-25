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

// docs/TODO.md T-184: the native side lives in
// android/app/src/main/kotlin/com/crescendoalarm/crescendoalarm/
// DoNotDisturbChannel.kt - a thin wrapper over `android.app.NotificationManager`
// itself, not a third-party plugin (see that file's own doc comment for why).
//
// Android's own interruption-filter values (`NotificationManager` constants,
// confirmed against the official platform docs) - `unknown` is what a query
// returns before the OS has ever been asked, `all` is "Do Not Disturb off".
const int interruptionFilterUnknown = 0;
const int interruptionFilterAll = 1;
const int interruptionFilterPriority = 2;
const int interruptionFilterNone = 3;

/// The mode this feature actually uses: only alarms may interrupt. Never
/// [interruptionFilterNone] - that would silence the alarm clock's own alarm
/// too, defeating the entire point of an app whose job is to wake the user
/// up.
const int interruptionFilterAlarms = 4;

const MethodChannel _dndChannel =
    MethodChannel('com.crescendoalarm.crescendoalarm/dnd');

/// The device's current Do Not Disturb interruption filter, or `null` if it
/// could not be read (no native implementation on this platform - the Linux
/// dev loop, `flutter test` - or the call otherwise failed).
///
/// Injectable, the same shape as `mirrorDirectBootFallback`: production code
/// calls this directly, a test overrides the variable.
Future<int?> Function() getCurrentInterruptionFilter =
    _getCurrentInterruptionFilter;

Future<int?> _getCurrentInterruptionFilter() async {
  try {
    return await _dndChannel.invokeMethod<int>('getCurrentInterruptionFilter');
  } catch (e) {
    return null;
  }
}

/// Sets the device's Do Not Disturb interruption filter to [filter]. Returns
/// whether the call actually reached the platform - `false` covers both "no
/// native implementation" (non-Android) and a genuine platform failure (most
/// likely: `ACCESS_NOTIFICATION_POLICY` was never granted, since Android
/// silently no-ops `setInterruptionFilter` without it rather than throwing).
Future<bool> Function(int filter) setInterruptionFilter =
    _setInterruptionFilter;

Future<bool> _setInterruptionFilter(int filter) async {
  try {
    await _dndChannel.invokeMethod<void>('setInterruptionFilter', {
      'filter': filter,
    });
    return true;
  } catch (e) {
    return false;
  }
}
