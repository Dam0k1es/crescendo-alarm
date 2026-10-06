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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/handler.dart';
import 'package:crescendo_alarm/models/alarms/ringing_watch.dart';
import 'package:crescendo_alarm/screens/alarms/snooze_button.dart';
import 'package:crescendo_alarm/utils/ring_notification.dart';
import 'package:crescendo_alarm/utils/utils.dart';

/// The default ring screen for alarm [alarmId], shown by
/// `Handler.handleAlarm` when no deactivation code is required (otherwise
/// `QrScanner` is shown instead).
///
/// Back navigation is blocked (`PopScope(canPop: false)`), so the screen
/// closes only through Stop, a successful Snooze (FR-20), or [RingingWatch]
/// noticing that the alarm stopped ringing somewhere else. Stop and an
/// external stop share one `Handler.onAlarmHandled` call; a snooze is a
/// postponement and runs none.
class ScreenAlarmActive extends StatefulWidget {
  final int alarmId;

  const ScreenAlarmActive({super.key, required this.alarmId});

  /// Test-only seam: when set, [RingingWatch] observes this stream instead
  /// of the real `Alarm.ringing` - which has no platform channel in
  /// `flutter test` and never carries a test's fake alarm id.
  @visibleForTesting
  static Stream<AlarmSet>? debugRingingStreamOverride;

  /// Test-only seam: the real `Handler.onAlarmHandled` has no way of its own
  /// to observe how many times it was called - needed to pin down the
  /// double-dismiss bug `_callOnAlarmHandledOnce` guards against.
  @visibleForTesting
  static void Function(AppState appState, int alarmId)?
      debugOnAlarmHandledOverride;

  @override
  State<ScreenAlarmActive> createState() => _ScreenAlarmActiveState();
}

class _ScreenAlarmActiveState extends State<ScreenAlarmActive>
    with SingleTickerProviderStateMixin {
  late final AppState _appState;
  late final AnimationController _controller;
  late final Animation<double> _animation;
  late final Timer _timer;
  late final RingingWatch _ringingWatch;

  /// docs/TODO.md T-229: keeps the plugin's notification out of the
  /// heads-up over this screen.
  late final RingNotificationQuieter _notificationQuieter;
  late TimeOfDay _currentTime;
  late DateTime _currentDateTime;

  /// Guards `Handler.onAlarmHandled` against being called more than once for
  /// this ring. A successful Stop's own `Alarm.stop()` also removes the alarm
  /// from `Alarm.ringing`, so [RingingWatch] reacts to the same change the
  /// Stop button is already handling - without this guard the dismissal
  /// would run twice, e.g. re-arming a repeating manual alarm twice
  /// (docs/TODO.md T-147).
  bool _onAlarmHandledCalled = false;

  /// Set synchronously the instant Snooze is pressed, before anything
  /// asynchronous happens - see `SnoozeButton.onBeforeSnooze`'s doc comment
  /// for why "before", not "after a successful postponement": a successful
  /// snooze calls `Alarm.stop()` on the *old* alarm as its last internal
  /// step, which [RingingWatch] also observes, and in practice its listener
  /// fires before the snooze's own completion handler gets a chance to say
  /// "this one was a postponement, not a real stop".
  bool _snoozing = false;

  /// See [_onAlarmHandledCalled].
  void _callOnAlarmHandledOnce() {
    if (_onAlarmHandledCalled) return;
    _onAlarmHandledCalled = true;
    (ScreenAlarmActive.debugOnAlarmHandledOverride ?? Handler.onAlarmHandled)(
        _appState, widget.alarmId);
  }

  /// Idempotent by construction (`ModalRoute.isCurrent`), so every caller -
  /// Stop, Snooze, and [RingingWatch] - can call it unconditionally without
  /// its own guard. Stop and Snooze both change `Alarm.ringing` themselves,
  /// so [RingingWatch] reacts to the same change: an unguarded second
  /// `Navigator.pop` hit the navigator mid-transaction (a "!_debugLocked"
  /// assertion, docs/TODO.md T-147) or would pop the route underneath.
  void _pop() {
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.pop(context);
    }
  }

  @override
  void initState() {
    debugPrint("=====initState: Creating new ScreenAlarmActiveState");
    super.initState();
    _appState = Provider.of<AppState>(context, listen: false);

    // Bug: an alarm stopped by swiping its notification away (no app UI
    // open) left this screen stuck showing on reopen, with nothing actually
    // ringing and no way out (PopScope below). `Alarm.ringing` is the only
    // place Dart learns about a stop that happened entirely at the native
    // level - see RingingWatch's doc comment for why its first event is
    // deliberately ignored. `androidStopAlarmOnDismiss: false`
    // (ringing_alarm_settings.dart) means a notification swipe can no longer
    // trigger this particular path in practice, but RingingWatch stays as
    // the safety net for the paths that remain - e.g. the QR gate's
    // emergency-stop-all button silencing an alarm this screen is showing.
    _ringingWatch = RingingWatch(
      alarmId: widget.alarmId,
      ringingStream: ScreenAlarmActive.debugRingingStreamOverride,
      onGone: () {
        if (!mounted) return;
        if (!_snoozing) _callOnAlarmHandledOnce();
        _pop();
      },
    );
    _notificationQuieter = RingNotificationQuieter(widget.alarmId);
    _currentTime = TimeOfDay.now();
    _currentDateTime = DateTime.now();
    // The alarm plugin may fire a few seconds before the minute it was set
    // for. Only the date line reads this value (the HH:MM clock below uses
    // `TimeOfDay.now()` as is), so the rounding matters for a midnight alarm.
    if (_currentDateTime.second >= 55) {
      _currentDateTime = _currentDateTime.add(const Duration(minutes: 1));
    }
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: -0.1, end: 0.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.bounceInOut),
    );

    _timer = Timer.periodic(const Duration(seconds: 10), (Timer timer) {
      setState(() {
        _currentTime = TimeOfDay.now();
        _currentDateTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer.cancel();
    _ringingWatch.cancel();
    _notificationQuieter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          // The SnoozeButton (FR-20) makes this Column taller than short
          // viewports - first seen on `flutter test`'s 800x600 surface, but a
          // small phone screen is no different. LayoutBuilder +
          // ConstrainedBox(minHeight) + IntrinsicHeight keep the Spacer-based
          // centering below whenever the content fits and only scroll once
          // it doesn't; a plain SingleChildScrollView alone can't host a
          // Spacer (flex needs a bounded height, which an unbounded scroll
          // axis doesn't give it).
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                      // FR-20: snooze sits above the stop button and disappears once
                      // the budget is exhausted.
                      SnoozeButton(
                        alarmId: widget.alarmId,
                        onBeforeSnooze: () => _snoozing = true,
                        onSnoozeAttemptFailed: () => _snoozing = false,
                        onSnoozed: _pop,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              formatDateTime(_currentDateTime),
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey.shade400,
                              ),
                            ),
                            Text(
                              formatTimeOfDay(_currentTime),
                              style: TextStyle(
                                fontSize: 100,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey.shade400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Center(
                        child: SizedBox(
                          width: 200,
                          height: 200,
                          child: RotationTransition(
                            turns: _animation,
                            child: Icon(
                              Icons.alarm,
                              size: 200,
                              color: Colors.blueGrey.shade300,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _appState.accentColor,
                            minimumSize: const Size(double.infinity, 60),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          onPressed: () async {
                            bool stopped = false;
                            try {
                              stopped = await Alarm.stop(widget.alarmId);
                            } catch (e) {
                              debugPrint(
                                  "=====ScreenAlarmActiveState: Failed to stop alarm: ${e.runtimeType}");
                            }
                            if (!stopped) {
                              // Don't silently leave: the alarm is still ringing.
                              // canPop is false, so staying here (rather than
                              // popping anyway) is the only option that doesn't
                              // strand the user behind a closed screen with a live
                              // alarm.
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Failed to stop the alarm - please try again.'),
                                  ),
                                );
                              }
                              return;
                            }
                            _callOnAlarmHandledOnce();
                            _pop();
                          },
                          child: const Text(
                            'Stop',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
