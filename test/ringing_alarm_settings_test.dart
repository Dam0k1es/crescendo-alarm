import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/models/alarms/ringing_alarm_settings.dart';

// Bug report: swiping the alarm notification away stopped the alarm at the
// native level (`NotificationSettings.androidStopAlarmOnDismiss` defaults to
// `true`), which is what T-147's ring-screen-stuck-open bug came from in the
// first place, and re-fixing that with the screens' own `RingingWatch` still
// left a race with the in-app Stop button (both paths can pop the same route
// once the alarm leaves `Alarm.ringing`). The maintainer's call after seeing
// both bugs on a real device: swiping the notification must not be able to
// deactivate the alarm at all - only the explicit in-app Stop button (or QR
// scan) may. `androidStopAlarmOnDismiss: false` is the one-line fix; a
// stray swipe then puts the notification straight back for as long as the
// alarm keeps ringing, per that field's own doc comment.
//
// This builder is extracted purely so that guarantee has a test that does
// not need the real `alarm` plugin's platform channel - constructing an
// `AlarmSettings` is plain data, but `Alarm.set()` itself is not.

void main() {
  test('a ringing alarm never lets a notification swipe stop it', () {
    final settings = buildRingingAlarmSettings(
      id: 1,
      dateTime: DateTime(2026, 3, 10, 7, 30),
      tone: 'assets/sounds/lollipop.mp3',
      gentlewake: false,
      volume: 0.8,
      gentleWakeDuration: const Duration(minutes: 1),
      title: 'Alarm',
      body: 'Your alarm is ringing',
      vibrate: true,
    );

    expect(settings.notificationSettings.androidStopAlarmOnDismiss, isFalse);
  });

  test('gentle wake produces a fade, otherwise a fixed volume', () {
    final fading = buildRingingAlarmSettings(
      id: 1,
      dateTime: DateTime(2026, 3, 10, 7, 30),
      tone: null,
      gentlewake: true,
      volume: 0.5,
      gentleWakeDuration: const Duration(minutes: 3),
      title: 'Alarm',
      body: 'Your alarm is ringing',
      vibrate: true,
    );
    final fixed = buildRingingAlarmSettings(
      id: 1,
      dateTime: DateTime(2026, 3, 10, 7, 30),
      tone: null,
      gentlewake: false,
      volume: 0.5,
      gentleWakeDuration: const Duration(minutes: 3),
      title: 'Alarm',
      body: 'Your alarm is ringing',
      vibrate: true,
    );

    expect(fading.volumeSettings.fadeDuration, const Duration(minutes: 3));
    expect(fixed.volumeSettings.fadeDuration, isNull);
  });

  test('carries the id, time, tone, title and body through unchanged', () {
    final settings = buildRingingAlarmSettings(
      id: 42,
      dateTime: DateTime(2026, 3, 10, 7, 30),
      tone: 'assets/sounds/wake_up.mp3',
      gentlewake: false,
      volume: 0.8,
      gentleWakeDuration: const Duration(minutes: 1),
      title: 'Wake up',
      body: 'Time to go',
      vibrate: true,
    );

    expect(settings.id, 42);
    expect(settings.dateTime, DateTime(2026, 3, 10, 7, 30));
    expect(settings.assetAudioPath, 'assets/sounds/wake_up.mp3');
    expect(settings.notificationSettings.title, 'Wake up');
    expect(settings.notificationSettings.body, 'Time to go');
  });

  test('shows the app notification icon instead of the OS default', () {
    // docs/TODO.md T-54: `icon` used to be left unset, so Android fell back
    // to the launcher icon (or a generic system icon on some versions)
    // instead of a purpose-made small monochrome icon.
    final settings = buildRingingAlarmSettings(
      id: 1,
      dateTime: DateTime(2026, 3, 10, 7, 30),
      tone: null,
      gentlewake: false,
      volume: 0.5,
      gentleWakeDuration: const Duration(minutes: 1),
      title: 'Alarm',
      body: 'Your alarm is ringing',
      vibrate: true,
    );

    expect(settings.notificationSettings.icon, 'ic_notification');
  });

  test('carries the vibrate setting through unchanged', () {
    final vibrating = buildRingingAlarmSettings(
      id: 1,
      dateTime: DateTime(2026, 3, 10, 7, 30),
      tone: null,
      gentlewake: false,
      volume: 0.5,
      gentleWakeDuration: const Duration(minutes: 1),
      title: 'Alarm',
      body: 'Your alarm is ringing',
      vibrate: true,
    );
    final silent = buildRingingAlarmSettings(
      id: 1,
      dateTime: DateTime(2026, 3, 10, 7, 30),
      tone: null,
      gentlewake: false,
      volume: 0.5,
      gentleWakeDuration: const Duration(minutes: 1),
      title: 'Alarm',
      body: 'Your alarm is ringing',
      vibrate: false,
    );

    expect(vibrating.vibrate, isTrue);
    expect(silent.vibrate, isFalse);
  });
}
