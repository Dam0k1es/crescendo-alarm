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
