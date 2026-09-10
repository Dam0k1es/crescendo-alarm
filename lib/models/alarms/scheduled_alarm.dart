import 'dart:convert';

import 'package:wakeywakey/models/alarms/myalarm.dart';
import 'package:wakeywakey/utils/utils.dart';

class ScheduledAlarm extends MyAlarm {
  /// Kein `title`-Parameter (docs/TODO.md T-86): der Konstruktor hat ihn
  /// immer sofort mit `formatDateTime(time)` überschrieben, ein übergebener
  /// Wert war also wirkungslos - inklusive dem aus [ScheduledAlarm.fromJson],
  /// der beim Laden schlicht verworfen wurde. Der Titel ist bewusst aus der
  /// Zeit abgeleitet und keine eigene Eigenschaft.
  ScheduledAlarm({
    required DateTime super.time,
    super.enabled,
    super.gentlewake,
    super.gentleWakeDuration,
    super.tone,
    // docs/TODO.md T-84: war nicht durchgereicht, also klang JEDER von FR-18
    // gesetzte Alarm mit MyAlarms Default 0.6 und ignorierte
    // appState.selectedVolume - obwohl es dafür eine UI gibt.
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
      // Fehlt bei Alarmen, die vor T-96 gespeichert wurden - dann greift der
      // Default aus MyAlarm (eine Minute, das alte festverdrahtete Verhalten).
      gentleWakeDuration: data['gentleWakeSeconds'] == null
          ? null
          : Duration(seconds: data['gentleWakeSeconds'] as int),
      tone: data['tone'],
      // Fehlt bei Alarmen, die vor T-84 gespeichert wurden - dann greift
      // MyAlarms Default.
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
