import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/handler.dart';
import 'package:wakeywakey/utils/utils.dart';

class ScreenAlarmActive extends StatefulWidget {
  final int alarmId;

  const ScreenAlarmActive({super.key, required this.alarmId});

  @override
  State<ScreenAlarmActive> createState() => _ScreenAlarmActiveState();
}

class _ScreenAlarmActiveState extends State<ScreenAlarmActive>
    with SingleTickerProviderStateMixin {
  late final AppState _appState;
  late final AnimationController _controller;
  late final Animation<double> _animation;
  late final Timer _timer;
  late TimeOfDay _currentTime;
  late DateTime _currentDateTime;

  @override
  void initState() {
    debugPrint("=====initState: Creating new ScreenAlarmActiveState");
    super.initState();
    _appState = Provider.of<AppState>(context, listen: false);
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
                      if (stopped) {
                        Handler.onAlarmHandled(_appState, widget.alarmId);
                      }
                    } catch (e) {
                      debugPrint(
                          "=====ScreenAlarmActiveState: Failed to stop alarm: $e");
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
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
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
