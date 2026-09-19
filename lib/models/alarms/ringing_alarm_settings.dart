// Copyright (C) 2026 Dam0k1es
//
// This file is part of WakeyWakey.
//
// WakeyWakey is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// WakeyWakey is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with WakeyWakey. If not, see <https://www.gnu.org/licenses/>.

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
  // docs/TODO.md T-50: used to be hardcoded `true` here - there was no
  // vibration setting anywhere in the app, so every alarm always vibrated
  // regardless of anything the user could do.
  required bool vibrate,
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
      // docs/TODO.md T-54: without this, Android falls back to the launcher
      // icon (or a generic system icon) instead of a purpose-made small
      // monochrome icon - see android/app/src/main/res/drawable-*dpi/
      // ic_notification.png (a plain white silhouette on a transparent
      // background, required by Android for the status-bar icon; a full-colour
      // icon would just render as an undifferentiated white blob, since the
      // OS builds this icon from the alpha channel only).
      icon: 'ic_notification',
    ),
    loopAudio: true,
    vibrate: vibrate,
    warningNotificationOnKill: true,
    androidFullScreenIntent: true,
  );
}
