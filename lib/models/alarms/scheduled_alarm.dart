import 'dart:convert';

import 'package:wakeywakey/models/alarms/myalarm.dart';
import 'package:wakeywakey/utils/utils.dart';

class ScheduledAlarm extends MyAlarm {
  ScheduledAlarm({
    required DateTime super.time,
    String? title,
    super.enabled,
    super.gentlewake,
    super.tone,
    super.id,
  }) : super(title: formatDateTime(time));

  factory ScheduledAlarm.fromJson(String jsonString) {
    final data = jsonDecode(jsonString);
    final timeString = data['time'];
    DateTime time = DateTime.parse(timeString);

    return ScheduledAlarm(
      time: time,
      title: data['title'],
      enabled: data['enabled'],
      gentlewake: data['gentlewake'],
      tone: data['tone'],
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
      'tone': tone,
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
          tone == other.tone &&
          id == other.id;
    } else {
      return false;
    }
  }
}
