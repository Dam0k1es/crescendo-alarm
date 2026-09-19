// Copyright (C) 2026 Dam0k1es
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

import 'dart:convert';

import 'package:wakeywakey/models/alarms/myalarm.dart';
import 'package:wakeywakey/utils/utils.dart';

class ScheduledAlarm extends MyAlarm {
  /// No `title` parameter (docs/TODO.md T-86): the constructor always
  /// immediately overwrote it with `formatDateTime(time)`, so a passed-in
  /// value had no effect - including the one from [ScheduledAlarm.fromJson],
  /// which was simply discarded on load. The title is deliberately derived
  /// from the time, not its own property.
  ScheduledAlarm({
    required DateTime super.time,
    super.enabled,
    super.gentlewake,
    super.gentleWakeDuration,
    super.tone,
    // docs/TODO.md T-84: this wasn't passed through, so EVERY alarm set by
    // FR-18 rang with MyAlarm's default of 0.6 and ignored
    // appState.selectedVolume - even though there's a UI for it.
    super.volume,
    // docs/TODO.md T-50: same lesson, for vibration - there was no setting
    // at all before this, so every alarm always vibrated.
    super.vibrate,
    super.id,
  }) : super(title: formatDateTime(time));

  factory ScheduledAlarm.fromJson(String jsonString) {
    final data = jsonDecode(jsonString);
    final timeString = data['time'];
    DateTime time = DateTime.parse(timeString);

    return ScheduledAlarm(
      time: time,
      enabled: data['enabled'],
      gentlewake: data['gentlewake'],
      // Missing for alarms stored before T-96 - then MyAlarm's default
      // applies (one minute, the old hardcoded behaviour).
      gentleWakeDuration: data['gentleWakeSeconds'] == null
          ? null
          : Duration(seconds: data['gentleWakeSeconds'] as int),
      tone: data['tone'],
      // Missing for alarms stored before T-84 - then MyAlarm's default
      // applies.
      volume: (data['volume'] as num?)?.toDouble(),
      // Missing for alarms stored before T-50 - then MyAlarm's default
      // (true) applies, matching what every alarm did before this setting
      // existed.
      vibrate: data['vibrate'] as bool?,
      id: data['id'],
    );
  }

  @override
  String toJson() {
    return jsonEncode({
      'time': time.toIso8601String(),
      'title': title,
      'enabled': enabled,
      'gentlewake': gentlewake,
      'gentleWakeSeconds': gentleWakeDuration.inSeconds,
      'tone': tone,
      'volume': volume,
      'vibrate': vibrate,
      'id': id,
    });
  }

  @override
  int get hashCode {
    return jsonEncode(this).hashCode;
  }

  @override
  bool operator ==(Object other) {
    if (other is ScheduledAlarm) {
      return time == other.time &&
          title == other.title &&
          enabled == other.enabled &&
          gentlewake == other.gentlewake &&
          gentleWakeDuration == other.gentleWakeDuration &&
          tone == other.tone &&
          volume == other.volume &&
          vibrate == other.vibrate &&
          id == other.id;
    } else {
      return false;
    }
  }
}
