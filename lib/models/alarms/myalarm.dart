import 'package:wakeywakey/utils/utils.dart';

abstract class MyAlarm {
  dynamic time;
  String title;
  bool enabled;
  bool gentlewake;

  /// Wie lange die Gentle-Wake-Rampe braucht, bis sie [volume] erreicht -
  /// also wie lange der Alarm leise bleibt (docs/TODO.md T-96).
  ///
  /// Bewusst eine Eigenschaft des ALARMS und nicht nur eine AppState-Vorgabe:
  /// `planAlarmSync` entscheidet anhand der Alarm-Eigenschaften, ob ein bereits
  /// gesetzter Alarm ersetzt werden muss. Läge der Wert nur im AppState, könnte
  /// eine Änderung dort nie als Abweichung erkannt werden - die Einstellung
  /// hätte eine UI, würde aber auf bestehende Alarme niemals wirken. Genau das
  /// war T-84 bei Ton und Lautstärke.
  Duration gentleWakeDuration;

  String tone;
  double volume;
  int id; // Neue ID-Eigenschaft hinzugefügt

  MyAlarm({
    required this.time,
    String? title,
    bool? enabled,
    bool? gentlewake,
    Duration? gentleWakeDuration,
    String? tone,
    double? volume,
    int? id,
  })  : title = title ?? 'Alarm',
        enabled = enabled ?? true,
        gentlewake = gentlewake ?? false,
        // Der bisher festverdrahtete Wert aus app_state.dart - so klingen
        // bestehende Installationen unverändert weiter.
        gentleWakeDuration = gentleWakeDuration ?? const Duration(minutes: 1),
        tone = tone ?? 'Default',
        volume = volume ?? 0.6,
        id = id ?? getRandom();

  String toJson();

  factory MyAlarm.fromJson(String jsonString) {
    throw UnimplementedError();
  }
}
