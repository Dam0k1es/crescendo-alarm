import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/handler.dart';
import 'package:wakeywakey/models/alarms/ringing_watch.dart';
import 'package:wakeywakey/screens/alarms/snooze_button.dart';
import 'package:wakeywakey/utils/utils.dart';

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
  late TimeOfDay _currentTime;
  late DateTime _currentDateTime;

  /// Guards `Handler.onAlarmHandled` against being called more than once for
  /// this ring - see `_callOnAlarmHandledOnce`.
  bool _onAlarmHandledCalled = false;

  /// Set synchronously the instant Snooze is pressed, before anything
  /// asynchronous happens - see `SnoozeButton.onBeforeSnooze`'s doc comment
  /// for why "before", not "after a successful postponement": a successful
  /// snooze calls `Alarm.stop()` on the *old* alarm as its last internal
  /// step, which [RingingWatch] also observes, and in practice its listener
  /// fires before the snooze's own completion handler gets a chance to say
  /// "this one was a postponement, not a real stop". Bug report: pressing
  /// Stop threw a Navigator "!_debugLocked" assertion, from the same
  /// `Alarm.stop()`-updates-`Alarm.ringing` mechanism racing the Stop
  /// button's own dismissal - not from snoozing, but the underlying hazard
  /// (two independent reactions to one platform change) is identical, so
  /// both needed the same treatment.
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
  /// its own guard.
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
    _currentTime = TimeOfDay.now();
    _currentDateTime = DateTime.now();
    // The alarm library may trigger the event before the minutes have changed.
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
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
                            content:
                                Text('Failed to stop the alarm - please try again.'),
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
    );
  }
}
