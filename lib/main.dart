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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/handler.dart';
import 'package:wakeywakey/models/alarms/manual_alarm.dart';
import 'package:wakeywakey/models/alarms/scheduled_alarm.dart';
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/models/scheduling/checkpoint.dart';
import 'package:wakeywakey/screens/alarms/screen_alarms.dart';
import 'package:wakeywakey/screens/scan_code/screen_scancode.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';
import 'package:wakeywakey/screens/settings/screen_settings.dart';
import 'package:wakeywakey/screens/sleep_habits/screen_sleephabits.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';
import 'package:wakeywakey/utils/notifications.dart';
import 'package:wakeywakey/utils/permissions.dart';
import 'package:wakeywakey/utils/utils.dart';

// Feature backlog: see docs/TODO.md T-50 through T-59 (triaged from this file's former ad-hoc
// TODO list - docs/TODO.md T-31 records what happened to each original item).

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Guarantee that no debug log messages are printed in release mode
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  final appState = AppState();
  await appState.initialized;

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WakeyWakey',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      // docs/TODO.md T-51: AppState.themeMode is the one computed value that
      // combines darkMode and followSystemTheme - kept there so this line
      // can't independently drift from that combination.
      themeMode: Provider.of<AppState>(context).themeMode,
      home: appState.permissionsGranted
          ? const MyHomePage(title: 'WakeyWakey')
          : const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  SplashScreenState createState() => SplashScreenState();
}

class SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AppState _appState;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _appState = Provider.of<AppState>(context, listen: false);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    _requestPermissions().then((bool granted) {
      _appState.permissionsGranted = granted;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    // Navigation away from the splash screen happens implicitly: setting
    // permissionsGranted below notifies MyApp, which then swaps its `home`
    // to MyHomePage. An explicit Navigator push here would race with that
    // and create MyHomePage twice.
    final permissionsManager = PermissionsManager();
    await permissionsManager.requestPermissions(context);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _controller,
              child: Image.asset(
                'assets/icons/icon_no_shadow.png',
                width: 300,
                height: 300,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Checking permissions...',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  late final AppState _appState;
  StreamSubscription<AlarmSet>? _subscription;
  AlarmSet _previousRingingAlarms = AlarmSet.empty();
  late Notifications notifications;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Load app state
    _appState = Provider.of<AppState>(context, listen: false);

    // Subscribe to alarm stream. Instance-scoped (not static): a previous
    // version used a static subscription guarded by `??=`, which meant that
    // if MyHomePage was ever remounted with a different AppState (confirmed
    // happening across integration_test's testWidgets, which share one app
    // process - and a real hot-restart during development would do the same
    // thing), the *first* Handler/AppState pairing silently kept handling
    // every alarm forever, ignoring the new one entirely.
    Handler handler = Handler(context);
    _subscription = Alarm.ringing.listen((ringingAlarms) {
      // Alarm.ringing emits the full set of currently-ringing alarms on every
      // change, not one event per newly-ringing alarm - so diff against the
      // previous set to call handleAlarm exactly once per alarm.
      for (final alarm in ringingAlarms.alarms) {
        if (!_previousRingingAlarms.contains(alarm)) {
          handler.handleAlarm(alarm);
        }
      }
      _previousRingingAlarms = ringingAlarms;
    });

    notifications = Notifications();

    // Set the local timezone
    tzdata.initializeTimeZones();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // docs/TODO.md T-79: awaited, and BEFORE the checkpoint below. init()
      // runs Alarm.init(), AwesomeNotifications().initialize() and
      // setListeners(); the checkpoint immediately calls Alarm.getAlarms() /
      // Alarm.set() (FR-18) and schedules FR-16's notification. Fired without
      // awaiting, those landed inside the init window, where the catch blocks
      // silently degrade: the T-74e platform reconciliation turns itself off
      // and per-alarm Alarm.set errors are swallowed - so the sync could be a
      // no-op on exactly FR-17's post-reboot recovery path. A notification
      // created before setListeners() would likewise never wake Checkpoint 2.
      try {
        await notifications.init();
      } catch (e) {
        debugPrint("=====initState: Notifications().init() failed: ${e.runtimeType}");
      }

      // docs/TODO.md T-89: arm the event logger before the first checkpoint
      // runs - otherwise exactly the cold start drops out of the log, i.e.
      // the state FR-17's recovery path is meant to repair. Also registers
      // the alarm types, so the logger can carry them as a stable numeric
      // code instead of a name (under R8 obfuscation a name would be
      // garbage anyway).
      try {
        Diag.registerType(ScheduledAlarm, 1);
        Diag.registerType(ManualAlarm, 2);
        await Diag.init(enabled: _appState.diagnosticsEnabled);
        Diag.setIncludeClockTimes(_appState.diagnosticsIncludeClockTimes);
        Diag.boot(
          coldStart: _appState.lastReplanDate == null,
          notificationsInitAwaited: true,
          scheduledAlarmCount: _appState.scheduledAlarms.length,
          manualAlarmCount: _appState.manualAlarms.length,
          pendingValueCount: _appState.pendingDayValues.length,
          daysSinceLastReplan: _appState.lastReplanDate == null
              ? -1
              : dayDistance(DateTime.now(), _appState.lastReplanDate!),
        );
      } catch (e) {
        debugPrint("=====initState: Diag.init failed: ${e.runtimeType}");
      }

      final String localTimeZone = DateTime.now().timeZoneName;
      final tz.Location location = getLocationFromAbbreviation(localTimeZone);
      _appState.currentTimeZone = location.name;
      // docs/TODO.md T-89: the zone name is regionally identifying - a
      // history of these is a travel trace. Only log the fact.
      debugPrint("=====initState: timezone resolved");

      // FR-17 (docs/scheduling-v2-spec.md): a conditional third Checkpoint-1
      // trigger, running "sofort, vor jeder UI-Interaktion" whenever
      // lastReplanDate is stale (catches a reboot, a force-quit, or simply a
      // missed daily ring) - a no-op otherwise. Runs before the calendar
      // preload below since it's the higher-priority recovery path.
      // The checkpoint schedules FR-16's sleep-time notification itself, in
      // every case (docs/TODO.md T-80) - so a cold start gets its Checkpoint-2
      // hook here even when nothing needs replanning.
      await runCheckpointSafely(_appState,
          trigger: CheckpointTrigger.appForeground);

      // TODO user configurable preload range - 0x39A
      // Load calendar data after setting timezone
      await _syncCalendarAndAlarmsOnOpen();
    });
  }

  /// docs/TODO.md T-60: called on every app open (here for a cold start, and
  /// from [didChangeAppLifecycleState] on every resume) - `preloadCalendarData`
  /// alone only ever fetched once per process lifetime, so a calendar edit
  /// made afterwards stayed invisible in the Schedule tab until the app was
  /// killed and relaunched. [resyncCalendarData] clears that stale cache
  /// before re-fetching; the `manualSync` checkpoint that follows is the same
  /// "reconcile now" the alarm list's own sync button uses
  /// (`screen_alarms.dart`) - deliberately bypassing FR-17's once-a-day lock,
  /// so a calendar edit reaches the user's actually-armed alarms on the same
  /// open that made it visible in the Schedule tab, not only once a day.
  Future<void> _syncCalendarAndAlarmsOnOpen() async {
    await resyncCalendarData(_appState, pastWeeks: 2, futureWeeks: 1);
    await runCheckpointSafely(_appState,
        trigger: CheckpointTrigger.manualSync);
  }

  /// FR-17 (docs/TODO.md T-68): the checkpoint must also run on a real
  /// foreground transition, not only when this widget is first mounted.
  /// `initState`'s post-frame call covers a cold start (reboot, force-quit);
  /// this covers resuming a warm process, which is the normal case on Android
  /// and the third gap FR-17 explicitly names ("opening the app in between is
  /// an additional, cheap opportunistic re-read"). Idempotent by
  /// FR-17's own guard: the checkpoint is a no-op when today has already been
  /// replanned - and it is serialized against the ring checkpoint that the
  /// full-screen intent bringing us to the foreground has just started
  /// (docs/TODO.md T-77).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(runCheckpointSafely(_appState,
          trigger: CheckpointTrigger.appForeground));
      unawaited(_syncCalendarAndAlarmsOnOpen());
    }
    // docs/TODO.md T-89: persist the event buffer when the app is left. The
    // checkpoint already does this itself at the end of its own sequence;
    // this call catches everything that's been added since (ringing, the QR
    // gate, calendar access) - otherwise it would be lost on the next
    // process death, and the events around an alarm are exactly the
    // interesting ones.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(Diag.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: true);
    const List<Widget> pages = <Widget>[
      ScreenAlarms(),
      ScreenSchedule(),
      ScreenScancode(),
      ScreenSleephabits(),
      ScreenSettings(),
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        child: pages[appState.currentPageIndex],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: appState.currentPageIndex,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedItemColor: appState.accentColor,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            appState.currentPageIndex = index;
          });
        },
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.alarm),
            label: 'Alarms',
          ),
          BottomNavigationBarItem(
            // docs/TODO.md T-60: the Schedule tab's calendar is being
            // (re-)fetched on every app open now, not just once per process
            // lifetime - a small spinner in place of the static icon is the
            // only visible sign of that I/O, since it can take a moment on a
            // large calendar.
            icon: appState.isReadingCalendarMutex
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: Padding(
                      padding: EdgeInsets.all(2.0),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.calendar_month),
            label: 'Schedule',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.qr_code),
            label: 'Scan Code',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.bed),
            label: 'Sleep Habits',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
