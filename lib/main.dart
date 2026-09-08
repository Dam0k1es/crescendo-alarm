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
import 'package:wakeywakey/screens/alarms/screen_alarms.dart';
import 'package:wakeywakey/screens/scan_code/screen_scancode.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';
import 'package:wakeywakey/screens/settings/screen_settings.dart';
import 'package:wakeywakey/screens/sleep_habits/screen_sleephabits.dart';
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
      themeMode: Provider.of<AppState>(context).darkMode
          ? ThemeMode.dark
          : ThemeMode.light,
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

    // Initialize notifications
    Notifications().init();
    notifications = Notifications();

    // Set the local timezone
    tzdata.initializeTimeZones();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final String localTimeZone = DateTime.now().timeZoneName;
      final tz.Location location = getLocationFromAbbreviation(localTimeZone);
      _appState.currentTimeZone = location.name;
      debugPrint(
          "=====initState: Current timezone is ${_appState.currentTimeZone}");

      // TODO user configurable preload range - 0x39A
      // Load calendar data after setting timezone
      await preloadCalendarData(_appState, pastWeeks: 2, futureWeeks: 1);
    });
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
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.alarm),
            label: 'Alarms',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: 'Schedule',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code),
            label: 'Scan Code',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bed),
            label: 'Sleep Habits',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
