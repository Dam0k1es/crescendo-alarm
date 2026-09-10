import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scheduling/replan.dart';
import 'package:wakeywakey/models/scheduling/replan_notifications.dart';
import 'package:wakeywakey/utils/notifications.dart';

// docs/TODO.md T-67/T-74a/T-74b: die drei Warn-Flags (FR-6, FR-9, FR-12)
// wurden vorher nur im Klingel-Pfad gemeldet, teilten ein gemeinsames try und
// waren nicht testbar. FR-6 forderte zudem "einmalig", meldete aber bei jedem
// Replan neu.

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
  test('alle drei Flags werden zu je einer eigenen Meldung', () async {
    final appState = await _freshAppState();
    final notifications = _RecordingNotifications();

    await reportReplanNotifications(appState, _allFlags,
        notifications: notifications);

    expect(notifications.bodies.length, 3);
    // unterscheidbare Texte (FR-12 muss von FR-6/FR-9 unterscheidbar sein)
    expect(notifications.bodies.toSet().length, 3);
  });

  test('T-74b: eine fehlgeschlagene Meldung unterdrückt die anderen nicht',
      () async {
    final appState = await _freshAppState();
    final notifications = _RecordingNotifications()..failuresRemaining = 1;

    await reportReplanNotifications(appState, _allFlags,
        notifications: notifications);

    // Die erste (FR-6) schlägt fehl, FR-9 und FR-12 kommen trotzdem durch.
    expect(notifications.bodies.length, 2);
  });

  test('T-74a: FR-6 meldet nur einmal pro Overrun-Episode', () async {
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

  test('T-74a: nach Ende der Episode darf wieder gemeldet werden', () async {
    final appState = await _freshAppState();
    final notifications = _RecordingNotifications();
    const onlyOverrun = ReplanResult(
      overrunNotificationNeeded: true,
      safetyValveTriggered: false,
      possiblyMissedAppointment: false,
    );

    await reportReplanNotifications(appState, onlyOverrun,
        notifications: notifications);
    // Episode vorbei -> Merker wird zurückgesetzt.
    await reportReplanNotifications(appState, _noFlags,
        notifications: notifications);
    expect(appState.overrunNotificationSent, isFalse);
    // Neue Episode -> wieder eine Meldung.
    await reportReplanNotifications(appState, onlyOverrun,
        notifications: notifications);

    expect(notifications.bodies.length, 2);
  });

  // docs/TODO.md T-81: FR-9s Ventil-Meldung hatte - anders als FR-6s - keine
  // Drosselung, `safetyValveTriggered` wird aber von computeWeekPlan bei JEDEM
  // Replan neu abgeleitet. Und da nach dem Auslösen kein Alarm mehr klingelt
  // (T-78), kam die Meldung bei jedem App-Öffnen und jeder
  // Einstellungsänderung erneut.
  group('T-81: FR-9 meldet einmal pro Episode', () {
    test('drei Replans mit stehendem Ventil -> genau eine Meldung', () async {
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

    test('nach Ende der Episode darf wieder gemeldet werden', () async {
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

  // docs/TODO.md T-88: der Merker wurde VOR dem await gesetzt - schlug die
  // Meldung fehl, galt sie trotzdem als gesendet und wurde für die ganze
  // Episode nie nachgeholt.
  group('T-88: ein Fehlschlag verbraucht den Merker nicht', () {
    test('FR-6: fehlgeschlagene Meldung wird beim nächsten Replan nachgeholt',
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
          reason: 'nichts gesendet -> Merker darf nicht gesetzt sein');

      await reportReplanNotifications(appState, onlyOverrun,
          notifications: notifications);

      expect(notifications.bodies.length, 1);
      expect(appState.overrunNotificationSent, isTrue);
    });

    test('FR-9: dito für das Sicherheitsventil', () async {
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

  // Die beiden T-67-Tests, die den Meldepfad über die injizierten
  // `checkpoint`/`report`-Nähte von runForegroundCheckpointSafely geprüft
  // haben, sind nach test/checkpoint_test.dart gewandert (Gruppe "T-67"):
  // dort laufen sie durch die echte Verdrahtung statt durch eine Naht, was
  // mehr absichert. Hier bleibt die reine Melde-Funktion.
}
