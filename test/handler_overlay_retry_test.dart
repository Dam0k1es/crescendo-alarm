import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/handler.dart';

// docs/TODO.md T-38 (maintainer request): a single failed attempt to show
// the ringing overlay used to fall straight through to the 3-second
// Alarm.stopAll() fallback. `context.mounted` (the most common reason that
// attempt fails) can flip back to true moments later, so it's worth
// retrying a few times first - this pins down that the retry count/timing
// is what the maintainer asked for (5 attempts, ~15 seconds total), not
// just that "some" retrying happens.

AlarmSettings _fakeAlarmSettings({int id = 1}) => AlarmSettings(
      id: id,
      dateTime: DateTime.now().add(const Duration(seconds: 1)),
      volumeSettings: VolumeSettings.fixed(volume: 0.5),
      notificationSettings: const NotificationSettings(
        title: 'Test alarm',
        body: 'ringing',
      ),
    );

/// Builds a `Handler` from a still-mounted context (the constructor itself
/// needs `Provider.of` to work), then unmounts that context by replacing the
/// whole widget tree - so every subsequent attempt to show the overlay
/// through it fails exactly like a real "context is no longer mounted"
/// case, without needing to fake `showFullScreenOverlay` itself.
Future<Handler> _handlerWithContextUnmountedAfterConstruction(
  WidgetTester tester,
  AppState appState, {
  required Future<void> Function(Duration) sleep,
}) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  final handler = Handler(
    capturedContext,
    runCheckpoint: (_) async => null,
    sleep: sleep,
  );
  await tester.pumpWidget(const SizedBox());
  expect(capturedContext.mounted, isFalse,
      reason: 'the test setup itself must produce an unmounted context, or '
          'this test proves nothing');
  return handler;
}

void main() {
  testWidgets(
      'retries showing the overlay 5 times, 3 seconds apart, before giving up',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    final sleeps = <Duration>[];
    final handler = await _handlerWithContextUnmountedAfterConstruction(
      tester,
      appState,
      sleep: (duration) async {
        sleeps.add(duration);
      },
    );

    await handler.handleAlarm(_fakeAlarmSettings());

    expect(Handler.maxOverlayAttempts, 5,
        reason: 'the maintainer asked for 5 attempts specifically');
    expect(Handler.overlayRetryDelay, const Duration(seconds: 3),
        reason: '5 attempts, 3 seconds apart, is ~15 seconds total');
    // 4 sleeps between the 5 retry attempts, plus one more before the final
    // Alarm.stopAll() fallback - every one of them overlayRetryDelay long.
    expect(sleeps, List.filled(5, Handler.overlayRetryDelay));
  });

  testWidgets('stops retrying as soon as the overlay is shown successfully',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    late BuildContext context;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: MaterialApp(
          home: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    var sleepCalls = 0;
    final handler = Handler(
      context,
      runCheckpoint: (_) async => null,
      sleep: (duration) async {
        sleepCalls++;
      },
    );

    await handler.handleAlarm(_fakeAlarmSettings());
    await tester.pump();

    expect(sleepCalls, 0,
        reason: 'the very first attempt succeeds (context is mounted), so '
            'there is nothing to retry and nothing to sleep for');
  });
}
