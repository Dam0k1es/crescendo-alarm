import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/screens/alarms/screen_alarms.dart';
import 'package:wakeywakey/screens/scan_code/qr_scanner.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';
import 'package:wakeywakey/utils/permissions.dart';

// Maintainer request (2026-09-20): permissions should be requested only when
// actually needed, not all upfront on the splash screen -
// PermissionsManager.requestPermissions() used to request camera and
// calendar access unconditionally at first launch, regardless of whether
// the user ever scans a code or opens the Schedule tab.
//
// - Camera: only when the QR scanner actually opens - QrScanner is shared
//   by both the initial code-import flow (PageImportQr) and the
//   alarm-deactivation flow (Handler.handleAlarm), so one seam covers both.
// - Calendar: only when the Schedule tab is opened, or the "Sync Alarms"
//   button is pressed.
// - Notification/exact-alarm permissions are deliberately left requested
//   upfront (main.dart T-79's ordering still applies) - alarms/background
//   sound need them immediately, not lazily.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    requestCameraPermission = requestCameraPermissionDefault;
    requestCalendarPermission = requestCalendarPermissionDefault;
  });

  testWidgets('opening the QR scanner requests camera permission',
      (tester) async {
    var requested = false;
    requestCameraPermission = () async {
      requested = true;
    };

    final appState = AppState();
    await appState.initialized;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: QrScanner()),
      ),
    );

    expect(requested, isTrue);
  });

  testWidgets('opening the Schedule tab requests calendar permission',
      (tester) async {
    var requested = false;
    requestCalendarPermission = () async {
      requested = true;
    };

    final appState = AppState();
    await appState.initialized;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: ScreenSchedule()),
      ),
    );

    expect(requested, isTrue);
  });

  testWidgets('pressing "Sync Alarms" requests calendar permission',
      (tester) async {
    var requested = false;
    requestCalendarPermission = () async {
      requested = true;
    };

    final appState = AppState();
    await appState.initialized;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: ScreenAlarms()),
      ),
    );
    await tester.pump();
    // Reset: the Schedule tab isn't involved here, but AppState is shared
    // process-wide across statics in this test file's own imports - nothing
    // else should have set this yet, this just documents the assumption.
    expect(requested, isFalse,
        reason: 'the alarms screen itself must not request calendar access '
            'just by being shown');

    await tester.tap(find.byTooltip('Sync Alarms'));
    await tester.pump();

    expect(requested, isTrue);
  });
}
