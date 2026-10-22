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

// docs/TODO.md T-237 (maintainer decision 2026-10-23): a ring nobody stops
// ends itself 60 minutes after its due time, with a silent notice. The
// timeout runs natively (`RingTimeout*.kt`) - it has to work with no Flutter
// engine, after the app was swiped away - so Dart only tells it which alarm
// id is armed for which instant, at every real arm and cancel, the way the
// direct-boot mirror and the sleep-time window are pushed.
//
// Every function is a replaceable variable (the same seam shape as
// `mirrorDirectBootFallback`) and swallows every error, including the
// `MissingPluginException`/`StateError` of platforms without the native half
// (the Linux dev loop, `flutter test`): a failed timeout push must never
// break arming an alarm, which is the much higher-stakes action.

const MethodChannel _channel =
    MethodChannel('com.crescendoalarm.crescendoalarm/ring_timeout');

/// Arms the timeout of alarm [id], which is armed to ring at [dueAt].
Future<void> Function(int id, DateTime dueAt) armRingTimeout = _arm;

/// Cancels the timeout of alarm [id] (it was stopped or removed).
Future<void> Function(int id) cancelRingTimeout = _cancel;

/// Cancels every timeout (`Alarm.stopAll`).
Future<void> Function() cancelAllRingTimeouts = _cancelAll;

/// Arms a timeout for every alarm the plugin itself has stored. The plugin
/// re-arms its alarms after a force-stop, an app update or a boot without
/// going through Dart, so those would otherwise have no timeout.
Future<void> Function() syncRingTimeouts = _sync;

/// The ids of the rings that ended by their timeout since the last call
/// (consumed). Dart marks them as rung, see
/// `AppState.reconcileManualAlarmsWithPlatform`.
Future<List<int>> Function() takeTimedOutRingIds = _takeTimedOut;

Future<void> _arm(int id, DateTime dueAt) async {
  try {
    await _channel.invokeMethod<void>('arm', {
      'id': id,
      'dueAtMillis': dueAt.toUtc().millisecondsSinceEpoch,
    });
  } catch (_) {}
}

Future<void> _cancel(int id) async {
  try {
    await _channel.invokeMethod<void>('cancel', {'id': id});
  } catch (_) {}
}

Future<void> _cancelAll() async {
  try {
    await _channel.invokeMethod<void>('cancelAll');
  } catch (_) {}
}

Future<void> _sync() async {
  try {
    await _channel.invokeMethod<void>('sync');
  } catch (_) {}
}

Future<List<int>> _takeTimedOut() async {
  try {
    final ids = await _channel.invokeListMethod<int>('takeTimedOut');
    return ids ?? const [];
  } catch (_) {
    return const [];
  }
}
