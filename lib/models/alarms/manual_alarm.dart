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
    super.tone,
    super.id,
    super.volume = 0.8,
    Map<DayOfWeek, bool>? repeatOnDays,
  }) : repeatOnDays =
            repeatOnDays ?? {for (var day in DayOfWeek.values) day: true};

  factory ManualAlarm.fromJson(String jsonString) {
    final data = jsonDecode(jsonString);

    // Map von String zu DayOfWeek konvertieren
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
      tone: data['tone'],
      volume: (data['volume'] as num).toDouble(),
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
      'tone': tone,
      'volume': volume,
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
          tone == other.tone &&
          volume == other.volume &&
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
