import 'package:alarm/alarm.dart' show VolumeFadeStep;
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/models/alarms/ringing_alarm_settings.dart';

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

  test('gentle wake produces a staircase fade, otherwise a fixed volume',
      () {
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

    // docs/TODO.md T-175: no longer VolumeSettings.fade (a plain
    // fadeDuration, which the plugin's own native source confirms is a
    // strictly linear ramp) - fadeSteps carries the actual curve instead.
    expect(fading.volumeSettings.fadeDuration, isNull);
    expect(fading.volumeSettings.fadeSteps, isNotEmpty);
    expect(fixed.volumeSettings.fadeSteps, isEmpty);
  });

  group('T-175: the gentle-wake ramp is exponential, not linear', () {
    // Maintainer feedback from real-device use: the ramp "felt" too fast,
    // reaching full volume too quickly to feel gentle. The fix isn't
    // testable by ear from here - these instead pin down the actual
    // mathematical shape the plugin is handed, which is the only thing
    // this layer controls.
    List<VolumeFadeStep> stepsFor(Duration duration, double volume) =>
        buildRingingAlarmSettings(
          id: 1,
          dateTime: DateTime(2026, 3, 10, 7, 30),
          tone: null,
          gentlewake: true,
          volume: volume,
          gentleWakeDuration: duration,
          title: 'Alarm',
          body: 'Your alarm is ringing',
          vibrate: true,
        ).volumeSettings.fadeSteps;

    test('starts at (near-)silent and ends exactly at the target volume',
        () {
      final steps = stepsFor(const Duration(minutes: 5), 0.8);

      expect(steps.first.time, Duration.zero);
      expect(steps.first.volume, 0.0);
      expect(steps.last.time, const Duration(minutes: 5));
      expect(steps.last.volume, closeTo(0.8, 0.0001));
    });

    test('is monotonically increasing - never dips back down', () {
      final steps = stepsFor(const Duration(minutes: 5), 0.8);

      for (var i = 1; i < steps.length; i++) {
        expect(steps[i].volume, greaterThanOrEqualTo(steps[i - 1].volume));
        expect(steps[i].time, greaterThan(steps[i - 1].time));
      }
    });

    test(
        'the midpoint sits below the halfway volume - the defining '
        'difference from a linear ramp', () {
      final steps = stepsFor(const Duration(minutes: 10), 1.0);
      final midpoint =
          steps.firstWhere((s) => s.time == const Duration(minutes: 5));

      // A linear ramp would put the 5-minute mark at exactly half volume.
      // Staying meaningfully quieter than that at the midpoint, then
      // catching up by the end, is exactly the "quiet for longer" shape
      // the maintainer asked for.
      expect(midpoint.volume, lessThan(0.5));
    });

    test('scales with the target volume, same time points either way', () {
      final full = stepsFor(const Duration(minutes: 5), 1.0);
      final half = stepsFor(const Duration(minutes: 5), 0.5);

      expect(half.length, full.length);
      for (var i = 0; i < full.length; i++) {
        expect(half[i].time, full[i].time);
        expect(half[i].volume, closeTo(full[i].volume / 2, 0.0001));
      }
    });
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
