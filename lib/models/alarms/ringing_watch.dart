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

import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';

/// Notices [alarmId] disappearing from [Alarm.ringing] - the only place Dart
/// learns that an alarm was stopped entirely outside the screen showing it,
/// e.g. by swiping the alarm notification away rather than the in-app Stop
/// button (`NotificationSettings.androidStopAlarmOnDismiss` defaults to
/// `true` since plugin 5.0.3 and runs the native stop with no Dart code
/// involved at all). Without this, the screen a ringing alarm opened
/// (`ScreenAlarmActive`/`QrScanner`, both `PopScope(canPop: false)`) stayed
/// stuck showing on reopen, with no alarm left to stop and no way out.
///
/// [ringingStream] defaults to the real [Alarm.ringing]; a test passes its
/// own controller instead, since the real stream has no channel to a
/// platform in `flutter test` and never carries a test's fake alarm id.
///
/// [Alarm.ringing] is a `BehaviorSubject`, so the first event a new
/// subscriber gets is its current snapshot, not a change - deliberately
/// ignored here. Reacting to it would auto-close a screen the instant it
/// opens whenever nothing has (yet) told the real subject that this alarm is
/// ringing, which is exactly the state of `flutter test`'s unpopulated
/// static `Alarm.ringing` in every existing test that calls
/// `Handler.handleAlarm` directly rather than going through the plugin.
///
/// [onGone] fires exactly once per present-to-absent **edge**, not once per
/// event where [alarmId] happens to be absent. A later, unrelated alarm
/// ringing and stopping still emits further events on the same shared
/// stream, each of which would otherwise re-confirm "still absent" and call
/// [onGone] again - multiplying however many times whatever it does (e.g. a
/// screen popping itself) runs. Tracking the previous presence explicitly
/// (rather than "ignore the very first event") also subsumes the seed-value
/// case above for free: with nothing observed yet, there is no edge to have
/// crossed.
class RingingWatch {
  RingingWatch({
    required int alarmId,
    required void Function() onGone,
    Stream<AlarmSet>? ringingStream,
  }) {
    bool? wasPresent;
    _subscription = (ringingStream ?? Alarm.ringing).listen((ringing) {
      final isPresent = ringing.containsId(alarmId);
      if (wasPresent == true && !isPresent) onGone();
      wasPresent = isPresent;
    });
  }

  late final StreamSubscription<AlarmSet> _subscription;

  void cancel() => unawaited(_subscription.cancel());
}
