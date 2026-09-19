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

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:wakeywakey/models/alarms/myalarm.dart';
import 'package:wakeywakey/utils/utils.dart';

class ManualAlarm extends MyAlarm {
  Map<DayOfWeek, bool> repeatOnDays;

  ManualAlarm({
    required TimeOfDay super.time,
    super.title,
    super.enabled,
    super.gentlewake,
    super.gentleWakeDuration,
    super.tone,
    super.id,
    super.volume = 0.8,
    // docs/TODO.md T-50: same inheritance rule as tone/volume/gentlewake -
    // a manual alarm carries its own vibrate value, defaulted from
    // AppState.vibrationEnabled at creation time by the caller, not read
    // live from AppState on every ring.
    super.vibrate,
    Map<DayOfWeek, bool>? repeatOnDays,
  }) : repeatOnDays =
            repeatOnDays ?? {for (var day in DayOfWeek.values) day: true};

  factory ManualAlarm.fromJson(String jsonString) {
    final data = jsonDecode(jsonString);

    // Convert the String keys back to DayOfWeek values.
    final repeatOnDays = (data['repeatOnDays'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(
        DayOfWeek.values.firstWhere((day) => day.toString() == key),
        value as bool,
      ),
    );

    return ManualAlarm(
      time: timeOfDayFromString(data['time']),
      title: data['title'],
      enabled: data['enabled'],
      gentlewake: data['gentlewake'],
      gentleWakeDuration: data['gentleWakeSeconds'] == null
          ? null
          : Duration(seconds: data['gentleWakeSeconds'] as int),
      tone: data['tone'],
      volume: (data['volume'] as num).toDouble(),
      // Missing for alarms stored before T-50 - then MyAlarm's default
      // (true) applies, matching what every alarm did before this setting
      // existed.
      vibrate: data['vibrate'] as bool?,
      repeatOnDays: repeatOnDays,
      id: data['id'],
    );
  }

  @override
  String toJson() {
    return jsonEncode({
      'time': formatTimeOfDay(time),
      'title': title,
      'enabled': enabled,
      'gentlewake': gentlewake,
      'gentleWakeSeconds': gentleWakeDuration.inSeconds,
      'tone': tone,
      'volume': volume,
      'vibrate': vibrate,
      'repeatOnDays':
          repeatOnDays.map((day, value) => MapEntry(day.toString(), value)),
      'id': id,
    });
  }

  @override
  int get hashCode {
    return jsonEncode(this).hashCode;
  }

  @override
  bool operator ==(Object other) {
    if (other is ManualAlarm) {
      return time == other.time &&
          title == other.title &&
          enabled == other.enabled &&
          gentlewake == other.gentlewake &&
          gentleWakeDuration == other.gentleWakeDuration &&
          tone == other.tone &&
          volume == other.volume &&
          vibrate == other.vibrate &&
          id == other.id &&
          compareRepeatDays(repeatOnDays, other.repeatOnDays);
    } else {
      return false;
    }
  }

  bool compareRepeatDays(Map<DayOfWeek, bool> a, Map<DayOfWeek, bool> b) {
    if (a.length != b.length) return false;
    for (final day in DayOfWeek.values) {
      if (a[day] != b[day]) return false;
    }
    return true;
  }
}

enum DayOfWeek {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday,
}
