// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of WakeyWakey.
//
// WakeyWakey is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// WakeyWakey is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with WakeyWakey. If not, see <https://www.gnu.org/licenses/>.

import 'package:wakeywakey/utils/utils.dart';

abstract class MyAlarm {
  dynamic time;
  String title;
  bool enabled;
  bool gentlewake;

  /// How long the gentle-wake ramp takes to reach [volume] - i.e. how long
  /// the alarm stays quiet (docs/TODO.md T-96).
  ///
  /// Deliberately a property of the ALARM, not just an AppState default:
  /// `planAlarmSync` decides whether an already-armed alarm must be replaced
  /// based on the alarm's own properties. If the value lived only in
  /// AppState, a change there could never be recognized as a deviation - the
  /// setting would have a UI but would never affect existing alarms. That's
  /// exactly what T-84 was, for tone and volume.
  Duration gentleWakeDuration;

  String tone;
  double volume;

  /// docs/TODO.md T-50: whether this alarm vibrates when it rings. A
  /// property of the ALARM, not just an `AppState` default, for the same
  /// reason [gentleWakeDuration] is (see its own doc comment): `planAlarmSync`
  /// decides whether an already-armed alarm must be replaced based on the
  /// alarm's own properties, and a value that only lived in `AppState` could
  /// never be recognized as a deviation there.
  bool vibrate;

  int id; // Added id property

  MyAlarm({
    required this.time,
    String? title,
    bool? enabled,
    bool? gentlewake,
    Duration? gentleWakeDuration,
    String? tone,
    double? volume,
    bool? vibrate,
    int? id,
  })  : title = title ?? 'Alarm',
        enabled = enabled ?? true,
        gentlewake = gentlewake ?? false,
        // The previously hardcoded value from app_state.dart - so existing
        // installations keep sounding unchanged.
        gentleWakeDuration = gentleWakeDuration ?? const Duration(minutes: 1),
        tone = tone ?? 'Default',
        volume = volume ?? 0.6,
        // The previously hardcoded value passed to the `alarm` plugin - so
        // existing installations keep vibrating unchanged.
        vibrate = vibrate ?? true,
        id = id ?? getRandom();

  String toJson();

  factory MyAlarm.fromJson(String jsonString) {
    throw UnimplementedError();
  }
}
