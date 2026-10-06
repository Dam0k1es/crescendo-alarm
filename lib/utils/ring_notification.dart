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
import 'package:flutter/widgets.dart';

/// docs/TODO.md T-229 (maintainer, 2026-10-06): "Die Benachrichtigung ist
/// nicht stumm. Ich will nicht, dass sie beim Wecker Bildschirm in den Alarm
/// reinragt." - the `alarm` plugin's ringing notification showed as a
/// sticky heads-up over the ring screen on an unlocked phone. Asking the
/// native side (`RingNotification.kt`) to move it onto a quiet,
/// low-importance channel takes it out of the heads-up and leaves it in the
/// notification shade. The alarm tone and vibration are the plugin's
/// foreground service's, not the notification's, and keep running.
///
/// Native decides whether it actually does anything
/// (`RingNotificationPolicy`): never on a locked device (the full-screen
/// intent path), never while the app is in the background (the heads-up is
/// then how the user reaches the ring screen), only for the plugin's own
/// notification.
const String ringNotificationChannelName =
    'com.crescendoalarm.crescendoalarm/ring_notification';

const MethodChannel _channel = MethodChannel(ringNotificationChannelName);

/// Injectable seam, the same shape as `mirrorDirectBootFallback`.
Future<void> Function(int alarmId) quietRingNotification =
    defaultQuietRingNotification;

/// The real call. Best effort: without a native side (`flutter test`, the
/// Linux dev loop) or on any failure nothing happens - this must never get
/// in the way of a ringing alarm.
Future<void> defaultQuietRingNotification(int alarmId) async {
  try {
    await _channel.invokeMethod<String>('quiet', {'alarmId': alarmId});
  } catch (e) {
    // See direct_boot_mirror.dart: MissingPluginException, or a StateError
    // with no binding at all.
  }
}

/// Used by both ring screens: asks once when the screen appears and again
/// on every return to the foreground (the heads-up is deliberately left in
/// place while the app is in the background). Call [dispose] with the screen.
class RingNotificationQuieter with WidgetsBindingObserver {
  RingNotificationQuieter(this.alarmId) {
    WidgetsBinding.instance.addObserver(this);
    quietRingNotification(alarmId);
  }

  final int alarmId;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) quietRingNotification(alarmId);
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);
}
