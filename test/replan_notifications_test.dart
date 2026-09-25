import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/scheduling/replan.dart';
import 'package:crescendo_alarm/models/scheduling/replan_notifications.dart';
import 'package:crescendo_alarm/utils/notifications.dart';

// docs/TODO.md T-67/T-74a/T-74b: the three warning flags (FR-6, FR-9, FR-12)
// used to be reported only in the ring path, shared one common try, and
// weren't testable. FR-6 also required "once", but reported again on every
// replan.

class _RecordingNotifications implements Notifications {
  final List<String> bodies = [];
  int failuresRemaining = 0;

  @override
  Future<int> scheduleNotification({
    String? title,
    String? body,
    DateTime? scheduledDate,
    int? id,
  }) async {
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('notification plugin unavailable');
    }
    bodies.add(body ?? '');
    return id ?? 1;
  }

  @override
  Future<void> cancelAllNotifications() async {}

  @override
  Future<void> cancelNotification(int id) async {}

  @override
  Future<void> init() async {}
}

const _allFlags = ReplanResult(
  overrunNotificationNeeded: true,
  safetyValveTriggered: true,
  possiblyMissedAppointment: true,
);

const _onlyValve = ReplanResult(
  overrunNotificationNeeded: false,
  safetyValveTriggered: true,
  possiblyMissedAppointment: false,
);

const _noFlags = ReplanResult(
  overrunNotificationNeeded: false,
  safetyValveTriggered: false,
  possiblyMissedAppointment: false,
);

Future<AppState> _freshAppState() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  return appState;
}

void main() {
  test('all three flags each become their own notification', () async {
    final appState = await _freshAppState();
    final notifications = _RecordingNotifications();

    await reportReplanNotifications(appState, _allFlags,
        notifications: notifications);

    expect(notifications.bodies.length, 3);
    // distinguishable texts (FR-12 must be distinguishable from FR-6/FR-9)
    expect(notifications.bodies.toSet().length, 3);
  });

  test('T-74b: one failed notification does not suppress the others',
      () async {
    final appState = await _freshAppState();
    final notifications = _RecordingNotifications()..failuresRemaining = 1;

    await reportReplanNotifications(appState, _allFlags,
        notifications: notifications);

    // The first one (FR-6) fails, FR-9 and FR-12 still get through.
    expect(notifications.bodies.length, 2);
  });

  test('T-74a: FR-6 reports only once per overrun episode', () async {
    final appState = await _freshAppState();
    final notifications = _RecordingNotifications();
    const onlyOverrun = ReplanResult(
      overrunNotificationNeeded: true,
      safetyValveTriggered: false,
      possiblyMissedAppointment: false,
    );

    await reportReplanNotifications(appState, onlyOverrun,
        notifications: notifications);
    await reportReplanNotifications(appState, onlyOverrun,
        notifications: notifications);
    await reportReplanNotifications(appState, onlyOverrun,
        notifications: notifications);

    expect(notifications.bodies.length, 1);
    expect(appState.overrunNotificationSent, isTrue);
  });

  test('T-74a: reporting is allowed again after the episode ends', () async {
    final appState = await _freshAppState();
    final notifications = _RecordingNotifications();
    const onlyOverrun = ReplanResult(
      overrunNotificationNeeded: true,
      safetyValveTriggered: false,
      possiblyMissedAppointment: false,
    );

    await reportReplanNotifications(appState, onlyOverrun,
        notifications: notifications);
    // Episode over -> the marker is reset.
    await reportReplanNotifications(appState, _noFlags,
        notifications: notifications);
    expect(appState.overrunNotificationSent, isFalse);
    // New episode -> a notification again.
    await reportReplanNotifications(appState, onlyOverrun,
        notifications: notifications);

    expect(notifications.bodies.length, 2);
  });

  // docs/TODO.md T-81: FR-9's valve notification had - unlike FR-6's - no
  // throttling, but `safetyValveTriggered` is re-derived by computeWeekPlan on
  // EVERY replan. And since no alarm rings any more after it fires (T-78),
  // the notification kept coming back on every app open and every setting
  // change.
  group('T-81: FR-9 reports once per episode', () {
    test('three replans with the valve still tripped -> exactly one notification', () async {
      final appState = await _freshAppState();
      final notifications = _RecordingNotifications();

      await reportReplanNotifications(appState, _onlyValve,
          notifications: notifications);
      await reportReplanNotifications(appState, _onlyValve,
          notifications: notifications);
      await reportReplanNotifications(appState, _onlyValve,
          notifications: notifications);

      expect(notifications.bodies.length, 1);
      expect(appState.safetyValveNotificationSent, isTrue);
    });

    test('reporting is allowed again after the episode ends', () async {
      final appState = await _freshAppState();
      final notifications = _RecordingNotifications();

      await reportReplanNotifications(appState, _onlyValve,
          notifications: notifications);
      await reportReplanNotifications(appState, _noFlags,
          notifications: notifications);
      expect(appState.safetyValveNotificationSent, isFalse);
      await reportReplanNotifications(appState, _onlyValve,
          notifications: notifications);

      expect(notifications.bodies.length, 2);
    });
  });

  // docs/TODO.md T-88: the marker was set BEFORE the await - if the
  // notification failed, it still counted as sent and was never caught up
  // for the rest of the episode.
  group('T-88: a failure does not consume the marker', () {
    test('FR-6: a failed notification is caught up on the next replan',
        () async {
      final appState = await _freshAppState();
      final notifications = _RecordingNotifications()..failuresRemaining = 1;
      const onlyOverrun = ReplanResult(
        overrunNotificationNeeded: true,
        safetyValveTriggered: false,
        possiblyMissedAppointment: false,
      );

      await reportReplanNotifications(appState, onlyOverrun,
          notifications: notifications);
      expect(notifications.bodies, isEmpty);
      expect(appState.overrunNotificationSent, isFalse,
          reason: 'nothing sent -> the marker must not be set');

      await reportReplanNotifications(appState, onlyOverrun,
          notifications: notifications);

      expect(notifications.bodies.length, 1);
      expect(appState.overrunNotificationSent, isTrue);
    });

    test('FR-9: same for the safety valve', () async {
      final appState = await _freshAppState();
      final notifications = _RecordingNotifications()..failuresRemaining = 1;

      await reportReplanNotifications(appState, _onlyValve,
          notifications: notifications);
      expect(appState.safetyValveNotificationSent, isFalse);

      await reportReplanNotifications(appState, _onlyValve,
          notifications: notifications);

      expect(notifications.bodies.length, 1);
    });
  });

  // The two T-67 tests that checked the reporting path via the injected
  // `checkpoint`/`report` seams of runForegroundCheckpointSafely have moved
  // to test/checkpoint_test.dart (group "T-67"): there they run through the
  // real wiring instead of a seam, which proves more. What remains here is
  // the pure reporting function.
}
