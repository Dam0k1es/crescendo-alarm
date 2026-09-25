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

import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/widgets.dart';
import 'package:crescendo_alarm/models/alarms/handler.dart';

/// Owns the app's one `Alarm.ringing` subscription and turns each newly
/// ringing alarm into a [Handler.handleAlarm] call - docs/TODO.md T-39.
///
/// This used to be an inline subscription inside `_MyHomePageState`
/// (`main.dart`), which meant the "guaranteed wake-up" gate only worked for
/// as long as that one screen widget happened to be mounted - nothing else
/// enforced the scan requirement, and it was not wired at all while
/// `SplashScreen` was showing, before the first permission grant.
///
/// The fix here is not "make it a bare process-wide static": a static
/// subscription guarded by `??=` is exactly the bug `_MyHomePageState`'s own
/// history already found once - it kept the FIRST `Handler`/`AppState`
/// pairing alive forever, silently ignoring every `AppState` created
/// afterwards (which happens routinely across `flutter test`'s separate
/// `pumpWidget` calls sharing one process). Instead, ownership moves UP, not
/// out to a global: `_MyAppState` (the app's actual root, in `main.dart`)
/// constructs one `AlarmRingGate` in its own `initState` and stops it in its
/// own `dispose` - so the gate is scoped to one real app run (or one test's
/// pumped widget tree) exactly as before, just no longer tied to whichever
/// screen widget the user happens to be on. Switching `MaterialApp`'s
/// `home:` between `SplashScreen` and `MyHomePage` does not recreate
/// `_MyAppState`, so the gate now covers the splash screen too.
class AlarmRingGate {
  AlarmRingGate(
    this._navigatorKey, {
    Stream<AlarmSet>? ringingStream,
    Handler Function(BuildContext)? buildHandler,
  })  : _ringingStream = ringingStream ?? Alarm.ringing,
        _buildHandler = buildHandler ?? Handler.new;

  /// The root Navigator's key, not any particular screen's own context:
  /// `Handler` needs a `BuildContext` inside `MaterialApp`'s `Overlay` (to
  /// show the full-screen ring/QR overlay) that outlives individual screens
  /// - the root Navigator is created once for the whole app run and is not
  /// recreated by switching which page it shows.
  final GlobalKey<NavigatorState> _navigatorKey;
  final Stream<AlarmSet> _ringingStream;
  final Handler Function(BuildContext) _buildHandler;

  StreamSubscription<AlarmSet>? _subscription;
  AlarmSet _previousRingingAlarms = AlarmSet.empty();
  Handler? _handler;

  void start() {
    _subscription ??= _ringingStream.listen((ringingAlarms) {
      // Alarm.ringing emits the full set of currently-ringing alarms on
      // every change, not one event per newly-ringing alarm - so diff
      // against the previous set to call handleAlarm exactly once per alarm.
      for (final alarm in ringingAlarms.alarms) {
        if (_previousRingingAlarms.contains(alarm)) continue;

        final context = _navigatorKey.currentContext;
        if (context == null || !context.mounted) {
          // The first frame has not built yet. In practice this cannot
          // happen for a real ring - the plugin cannot deliver one before
          // the engine has run at least once - but skip defensively rather
          // than use a stale/absent context, the same posture as the rest
          // of this app's platform-boundary code.
          debugPrint(
              '=====AlarmRingGate: alarm ${alarm.id} rang with no live Navigator context - skipped');
          continue;
        }
        (_handler ??= _buildHandler(context)).handleAlarm(alarm);
      }
      _previousRingingAlarms = ringingAlarms;
    });
  }

  void stop() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
