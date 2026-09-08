import 'package:wakeywakey/utils/utils.dart';

abstract class MyAlarm {
  dynamic time;
  String title;
  bool enabled;
  bool gentlewake;
  String tone;
  double volume;
  int id; // Neue ID-Eigenschaft hinzugefügt

  MyAlarm({
    required this.time,
    String? title,
    bool? enabled,
    bool? gentlewake,
    String? tone,
    double? volume,
    int? id,
  })  : title = title ?? 'Alarm',
        enabled = enabled ?? true,
        gentlewake = gentlewake ?? false,
        tone = tone ?? 'Default',
        volume = volume ?? 0.6,
        id = id ?? getRandom();

  String toJson();

  factory MyAlarm.fromJson(String jsonString) {
    throw UnimplementedError();
  }
}
