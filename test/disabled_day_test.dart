import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/scheduled_alarm.dart';
import 'package:wakeywakey/models/scheduling/apply_alarms.dart';
import 'package:wakeywakey/models/scheduling/day_marker.dart';
import 'package:wakeywakey/models/scheduling/replan.dart';
import 'package:wakeywakey/screens/schedule/screen_schedule.dart';

// FR-21 (docs/scheduling-v2-spec.md), docs/TODO.md T-03: ein abgeschalteter
// geplanter Wecker klingelt nicht. Die Faelle stammen aus den "Test:"-Punkten
// der Anforderung.

DateTime _utc(int h, int m, {int day = 10}) => DateTime.utc(2026, 3, day, h, m);

ScheduledAlarm _alarmAt(DateTime time, {int id = 1}) => ScheduledAlarm(
      time: time,
      enabled: true,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      volume: 0.8,
      id: id,
    );

Future<AppState> _fresh() async {
  SharedPreferences.setMockInitialValues({});
  final appState = AppState();
  await appState.initialized;
  appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
  appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 0);
  return appState;
}

void main() {
  group('FR-21: der Plan stellt keinen abgeschalteten Tag', () {
    final now = DateTime(2026, 3, 10, 6, 0);

    test('ein abgeschalteter Tag wird nicht angelegt', () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {isoDate(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: const [],
        disabledDays: {isoDate(planned)},
        now: now,
      );

      expect(plan.toAdd, isEmpty,
          reason: 'der Nutzer hat fuer diesen Tag "nicht wecken" gesagt');
    });

    test('ein bereits gestellter Alarm dieses Tages wird entfernt', () {
      // Die "sofort"-Zusicherung auf der Ebene, die sie durchsetzt.
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {isoDate(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: [_alarmAt(planned, id: 5)],
        platformAlarmIds: const {5},
        disabledDays: {isoDate(planned)},
        now: now,
      );

      expect(plan.toRemove.map((a) => a.id), [5]);
      expect(plan.toAdd, isEmpty);
    });

    test('andere Tage bleiben unberuehrt', () {
      // Gegenprobe gegen eine Ueberkorrektur.
      final aus = DateTime(2026, 3, 11, 7, 30);
      final an = DateTime(2026, 3, 12, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {
          isoDate(aus): aus.millisecondsSinceEpoch,
          isoDate(an): an.millisecondsSinceEpoch,
        },
        existingScheduledAlarms: const [],
        disabledDays: {isoDate(aus)},
        now: now,
      );

      expect(plan.toAdd, [an]);
    });

    test('ohne abgeschaltete Tage aendert sich nichts', () {
      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {isoDate(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: const [],
        disabledDays: const {},
        now: now,
      );

      expect(plan.toAdd, [planned]);
    });
  });

  group('FR-21: dauerhaft und ueber Neustarts', () {
    test('der naechste Planungslauf stellt ihn nicht wieder', () async {
      // Die Zusicherung, an der ein blosses Alarm.stop() scheitert: FR-18 baut
      // die Alarmmenge bei JEDER Neuplanung neu auf.
      final appState = await _fresh();
      final ringDay = _utc(0, 0, day: 10);
      final morgen = dayMarker(ringDay, 1);

      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      appState.setDayEnabled(isoDate(morgen), false);

      await replan(
        appState,
        now: () => _utc(6, 0, day: 10),
        deviceUtcOffset: Duration.zero,
        fetchEvents: (start, end) async => <Meeting>[],
        todayAlreadyRang: true,
      );

      expect(
        appState.scheduledAlarms.where((a) => isoDate(a.time) == isoDate(morgen)),
        isEmpty,
        reason: 'FR-21: der naechste Planungslauf darf ihn nicht wiederholen',
      );
      expect(appState.pendingDayValues[isoDate(morgen)], isNotNull,
          reason: 'der geplante Wert bleibt - abgeschaltet ist nicht geloescht');
    });

    test('der Zustand ueberlebt einen Neustart', () async {
      final first = await _fresh();
      first.setDayEnabled('2026-03-11', false);

      final second = AppState();
      await second.initialized;
      expect(second.isDayDisabled('2026-03-11'), isTrue);
    });

    test('wieder eingeschaltet gilt sofort wieder der geplante Wert', () async {
      final appState = await _fresh();
      appState.setDayEnabled('2026-03-11', false);
      appState.setDayEnabled('2026-03-11', true);

      expect(appState.isDayDisabled('2026-03-11'), isFalse);

      final planned = DateTime(2026, 3, 11, 7, 30);
      final plan = planAlarmSync(
        pendingDayValues: {isoDate(planned): planned.millisecondsSinceEpoch},
        existingScheduledAlarms: const [],
        disabledDays: appState.disabledDays,
        now: DateTime(2026, 3, 10, 6, 0),
      );
      expect(plan.toAdd, [planned]);
    });
  });
}
