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

import 'package:flutter/services.dart';

// docs/TODO.md T-240: whether the alarm screen can open by itself depends on
// two special accesses only the user can grant, read and opened through the
// native side (`AlarmScreenAccess.kt`):
// - full-screen intents (Android 14+): the locked-phone path. Denied, the
//   alarm shows as a plain notification even on the lock screen.
// - "Display over other apps": what lets the app start its screen on an
//   unlocked phone in use, where Android shows only a heads-up.
// Replaceable functions, the same seam shape as `mirrorDirectBootFallback`:
// where there is no native side (the Linux dev loop, `flutter test`) every
// call falls back to "unavailable" / `false` instead of throwing.

const MethodChannel _channel =
    MethodChannel('com.crescendoalarm.crescendoalarm/alarm_screen_access');

class AlarmScreenAccess {
  const AlarmScreenAccess({
    required this.fullScreenIntent,
    required this.overlay,
    this.available = true,
  });

  /// `null`: nothing to grant (Android below 14) - or unknown when
  /// [available] is false.
  final bool? fullScreenIntent;
  final bool overlay;

  /// Whether the native side answered at all.
  final bool available;

  static const unavailable = AlarmScreenAccess(
      fullScreenIntent: null, overlay: false, available: false);
}

Future<AlarmScreenAccess> Function() readAlarmScreenAccess = _read;
Future<bool> Function() openFullScreenIntentSettings =
    () => _open('openFullScreenIntentSettings');
Future<bool> Function() openOverlaySettings = () => _open('openOverlaySettings');

Future<AlarmScreenAccess> _read() async {
  try {
    final reply = await _channel.invokeMapMethod<String, Object?>('status');
    if (reply == null) return AlarmScreenAccess.unavailable;
    final overlay = reply['overlay'];
    final fullScreenIntent = reply['fullScreenIntent'];
    if (overlay is! bool || (fullScreenIntent != null && fullScreenIntent is! bool)) {
      return AlarmScreenAccess.unavailable;
    }
    return AlarmScreenAccess(
      fullScreenIntent: fullScreenIntent as bool?,
      overlay: overlay,
    );
  } catch (_) {
    return AlarmScreenAccess.unavailable;
  }
}

Future<bool> _open(String method) async {
  try {
    return await _channel.invokeMethod<bool>(method) ?? false;
  } catch (_) {
    return false;
  }
}

/// The phone's state at the last ring, as `RingScreenLauncher` saw it
/// (docs/TODO.md T-240) - recorded by `Handler.handleAlarm` in the diagnostics
/// log. [decisionCode] is `RingScreenLaunchPolicy.Decision.code` (or 6 for a
/// refused start).
class RingScreenState {
  const RingScreenState({
    required this.ringId,
    required this.decisionCode,
    required this.keyguardLocked,
    required this.screenOn,
    required this.appInFront,
    required this.overlayGranted,
    required this.fullScreenIntent,
  });

  /// Counts the rings the native launcher has seen in this process; a state
  /// whose [ringId] is not newer than the last recorded one belongs to an
  /// earlier ring.
  final int ringId;
  final int decisionCode;
  final bool keyguardLocked;
  final bool screenOn;
  final bool appInFront;
  final bool overlayGranted;

  /// `null`: nothing to grant (Android below 14).
  final bool? fullScreenIntent;
}

/// The native launcher's state of a ring newer than [after] - it waits a
/// moment for the ring and for a start it issued to show (or fail to) - or
/// null when it has seen none (or there is no native side).
Future<RingScreenState?> Function(int after) readLastRingScreenState =
    _readRingState;

Future<RingScreenState?> _readRingState(int after) async {
  try {
    final reply = await _channel
        .invokeMapMethod<String, Object?>('ringState', {'after': after});
    if (reply == null) return null;
    final ring = reply['ring'];
    final decision = reply['decision'];
    final locked = reply['keyguardLocked'];
    final screenOn = reply['screenOn'];
    final front = reply['appInFront'];
    final overlay = reply['overlay'];
    final fsi = reply['fullScreenIntent'];
    if (ring is! int ||
        decision is! int ||
        locked is! bool ||
        screenOn is! bool ||
        front is! bool ||
        overlay is! bool ||
        (fsi != null && fsi is! bool)) {
      return null;
    }
    return RingScreenState(
      ringId: ring,
      decisionCode: decision,
      keyguardLocked: locked,
      screenOn: screenOn,
      appInFront: front,
      overlayGranted: overlay,
      fullScreenIntent: fsi as bool?,
    );
  } catch (_) {
    return null;
  }
}
