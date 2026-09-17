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
          id == other.id;
    } else {
      return false;
    }
  }
}
