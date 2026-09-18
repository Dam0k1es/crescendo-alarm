import 'package:alarm/alarm.dart';

/// The [AlarmSettings] a ringing alarm is armed with - shared by
/// `AppState._setAlarm` (a `ScheduledAlarm`/`ManualAlarm` actually going off)
/// and `AppState.setSnoozeAlarm` (FR-20's postponed re-ring), so the two
/// cannot silently drift apart on something as consequential as whether the
/// alarm can be silenced by swiping its notification away.
///
/// Bug report (docs/TODO.md T-147): `androidStopAlarmOnDismiss` used to keep
/// its plugin default of `true`, so a stray notification swipe stopped the
/// alarm entirely at the native level, with no Dart code involved - the
/// root cause of the ring screen getting stuck open with nothing left
/// ringing behind it. Fixed the underlying cause rather than only reacting
/// to it (`RingingWatch` still exists as a safety net for the paths that
/// remain, e.g. the QR gate's emergency stop button silencing an alarm a
/// different screen is showing): only the app's own explicit Stop button or
/// QR scan may now deactivate a ringing alarm. A swipe puts the notification
/// straight back for as long as the alarm is still ringing, per that field's
/// own doc comment - there is deliberately no `stopButton` on the
/// notification either, since the maintainer's call was that the
/// notification itself has no role in stopping the alarm at all.
///
/// A pure function (no `Alarm.set()` call), so this guarantee has a test
/// that doesn't need the real plugin's platform channel.
AlarmSettings buildRingingAlarmSettings({
  required int id,
  required DateTime dateTime,
  required String? tone,
  required bool gentlewake,
  required double volume,
  required Duration gentleWakeDuration,
  required String title,
  required String body,
}) {
  return AlarmSettings(
    id: id,
    dateTime: dateTime,
    assetAudioPath: tone,
    // docs/TODO.md T-96: the ramp duration used to come from here as a
    // hardcoded Duration(seconds: 60). Now the alarm carries it itself, so
    // planAlarmSync can recognize a change as a deviation and replace the
    // alarm (the lesson from T-84).
    volumeSettings: gentlewake
        ? VolumeSettings.fade(volume: volume, fadeDuration: gentleWakeDuration)
        : VolumeSettings.fixed(volume: volume),
    notificationSettings: NotificationSettings(
      title: title,
      body: body,
      androidStopAlarmOnDismiss: false,
    ),
    loopAudio: true,
    vibrate: true,
    warningNotificationOnKill: true,
    androidFullScreenIntent: true,
  );
}
