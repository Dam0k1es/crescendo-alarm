// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of Crescendo Alarm.
//
// Crescendo Alarm is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Crescendo Alarm is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Crescendo Alarm. If not, see <https://www.gnu.org/licenses/>.

import 'dart:math';

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
///
/// docs/TODO.md T-175 (maintainer feedback, from real-device use): the
/// ramp "felt" too fast, reaching full volume too quickly to feel gentle -
/// confirmed against the plugin's own native source
/// (`AudioService.kt`'s `startFadeIn`, the implementation behind
/// `VolumeSettings.fade`): a constant volume delta every 100ms, i.e. a
/// strictly linear ramp. The plugin exposes no curve-shape parameter on
/// `.fade` itself, but does expose `VolumeSettings.staircaseFade(fadeSteps:
/// ...)` - an explicit list of (time, volume) points the plugin linearly
/// interpolates between at its own 100ms tick, driven by exactly the same
/// native code path either way. [_exponentialFadeSteps] samples an
/// exponential curve at a fixed number of points and hands the plugin the
/// result - quiet for longer, then catching up toward the end, rather than
/// climbing at a constant rate the whole time.
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
    // alarm (the lesson from T-84). T-175: exponential rather than linear -
    // see this function's own doc comment for why.
    volumeSettings: gentlewake
        ? VolumeSettings.staircaseFade(
            volume: volume,
            fadeSteps: _exponentialFadeSteps(gentleWakeDuration, volume),
          )
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

/// A fixed number of (time, volume) points sampling
/// `volume(t) = targetVolume * (e^(k*t/T) - 1) / (e^k - 1)` across
/// `[0, duration]` - `0` at `t=0`, `targetVolume` at `t=duration`, both
/// exactly (the formula's numerator and denominator are equal at `t=T`).
/// `k` (steepness) controls how long it stays quiet before catching up:
/// higher stays quieter for longer with a steeper finish, `0` in the limit
/// degenerates to the plugin's own linear `.fade`. `3.0` was chosen as a
/// noticeably-curved but not extreme middle ground - not measured against
/// a real ear, so revisit this constant on further feedback rather than
/// treating it as settled.
///
/// [stepCount] is fixed regardless of [duration] - the plugin's own
/// `startStaircaseFadeIn` (`AudioService.kt`) linearly interpolates
/// *between* consecutive points at its own 100ms tick, so more points than
/// needed for a visually smooth curve only bloats the platform-channel
/// payload for no perceptible benefit; 40 is comfortably above that need
/// even for a long ramp.
List<VolumeFadeStep> _exponentialFadeSteps(Duration duration, double volume) {
  const stepCount = 40;
  const steepness = 3.0;
  final denominator = exp(steepness) - 1;
  return [
    for (var i = 0; i <= stepCount; i++)
      VolumeFadeStep(
        Duration(
            microseconds:
                (duration.inMicroseconds * i / stepCount).round()),
        volume * (exp(steepness * i / stepCount) - 1) / denominator,
      ),
  ];
}
