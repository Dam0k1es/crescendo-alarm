import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/scheduled_alarm.dart';
import 'package:crescendo_alarm/models/scheduling/apply_alarms.dart';
import 'package:crescendo_alarm/models/scheduling/day_marker.dart';
import 'package:crescendo_alarm/models/scheduling/replan.dart';
import 'package:crescendo_alarm/models/scheduling/stored_values.dart';
import 'package:crescendo_alarm/screens/schedule/screen_schedule.dart';
import 'package:crescendo_alarm/utils/wall_clock.dart';

import 'support/fake_alarm_platform.dart';

// docs/TODO.md T-221, FR-21 (docs/scheduling-v2-spec.md), maintainer request
// (verbatim): "Wenn ich einen scheduled alarm deaktiviere (schieber umlegen)
// wird er nicht nur deaktiviert, sondern auch gelöscht. Ich will, dass der
// alarm als inaktiv gelistet wird." (Switching a scheduled alarm off with
// its toggle did not only deactivate it, it deleted it - it should be listed
// as inactive.)
//
// Cause: planAlarmSync skipped a switched-off day when building the desired
// set, so the existing ScheduledAlarm landed in `toRemove` and
// applyPlannedAlarms deleted it from AppState.scheduledAlarms.
//
// Every instant here is built UTC-tagged and compared by instant
// (`millisecondsSinceEpoch`), never by wall-clock digits or `==`: a
// ScheduledAlarm's `time` is the LOCAL reading of the stored value
// (`localFromStored`), and CI runs this file in six zones.

final _now = DateTime.utc(2026, 3, 10, 6, 0);
const _day = '2026-03-11';
const _otherDay = '2026-03-12';
final _planned = DateTime.utc(2026, 3, 11, 7, 30);
final _other = DateTime.utc(2026, 3, 12, 7, 30);

int _ms(DateTime t) => t.millisecondsSinceEpoch;

ScheduledAlarm _entry(DateTime instant,
        {int id = 1, bool enabled = true, double volume = 0.8}) =>
    ScheduledAlarm(
      time: instant.toLocal(),
      enabled: enabled,
      gentlewake: false,
      tone: 'assets/sounds/lollipop.mp3',
      volume: volume,
      id: id,
    );

Iterable<ScheduledAlarm> _at(AppState s, DateTime instant) =>
    s.scheduledAlarms.where((a) => _ms(a.time) == _ms(instant));

Future<AppState> _fresh({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(Map.of(prefs));
  final appState = AppState();
  await appState.initialized;
  appState.durationToWakeUp = const TimeOfDay(hour: 0, minute: 0);
  appState.durationToGetReady = const TimeOfDay(hour: 0, minute: 0);
  return appState;
}

void main() {
  group('planAlarmSync: a switched-off day is listed, not removed', () {
    test('no entry yet -> one disabled entry is listed, nothing is armed', () {
      final plan = planAlarmSync(
        pendingDayValues: {_day: _ms(_planned)},
        existingScheduledAlarms: const [],
        disabledDays: {_day},
        now: _now,
      );

      expect(plan.toAdd, isEmpty, reason: 'FR-21: it must not be armed');
      expect(plan.toAddDisabled.map(_ms), [_ms(_planned)],
          reason: 'T-221: it must still be listed, as inactive');
    });

    test('the armed entry of a day just switched off is replaced by a '
        'disabled one (the old one is removed, which stops it)', () {
      final armed = _entry(_planned, id: 5);
      final plan = planAlarmSync(
        pendingDayValues: {_day: _ms(_planned)},
        existingScheduledAlarms: [armed],
        platformAlarmIds: const {5},
        disabledDays: {_day},
        now: _now,
      );

      expect(plan.toRemove, [armed],
          reason: 'removal is what stops the armed platform alarm');
      expect(plan.toAdd, isEmpty);
      expect(plan.toAddDisabled.map(_ms), [_ms(_planned)]);
    });

    test('the same with the platform state unknown: still stopped', () {
      final armed = _entry(_planned, id: 5);
      final plan = planAlarmSync(
        pendingDayValues: {_day: _ms(_planned)},
        existingScheduledAlarms: [armed],
        disabledDays: {_day},
        now: _now,
      );

      expect(plan.toRemove, [armed]);
      expect(plan.toAddDisabled.map(_ms), [_ms(_planned)]);
    });

    test('an existing disabled entry absent from the platform is kept - '
        'it is not "missing", it is off', () {
      final off = _entry(_planned, id: 6, enabled: false);
      final plan = planAlarmSync(
        pendingDayValues: {_day: _ms(_planned)},
        existingScheduledAlarms: [off],
        platformAlarmIds: const {},
        disabledDays: {_day},
        now: _now,
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, isEmpty, reason: 'never re-armed behind the user');
      expect(plan.toAddDisabled, isEmpty, reason: 'no duplicate entry');
    });

    test('kept as well when the platform state is unknown', () {
      final off = _entry(_planned, id: 6, enabled: false);
      final plan = planAlarmSync(
        pendingDayValues: {_day: _ms(_planned)},
        existingScheduledAlarms: [off],
        disabledDays: {_day},
        now: _now,
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, isEmpty);
      expect(plan.toAddDisabled, isEmpty);
    });

    test('a disabled entry that is somehow still armed on the platform is '
        'replaced, so its platform alarm gets stopped', () {
      final off = _entry(_planned, id: 6, enabled: false);
      final plan = planAlarmSync(
        pendingDayValues: {_day: _ms(_planned)},
        existingScheduledAlarms: [off],
        platformAlarmIds: const {6},
        disabledDays: {_day},
        now: _now,
      );

      expect(plan.toRemove, [off]);
      expect(plan.toAdd, isEmpty);
      expect(plan.toAddDisabled.map(_ms), [_ms(_planned)]);
    });

    test('a disabled entry follows a plan change of its day, still disabled',
        () {
      final off = _entry(_planned, id: 6, enabled: false);
      final moved = _planned.add(const Duration(minutes: 20));
      final plan = planAlarmSync(
        pendingDayValues: {_day: _ms(moved)},
        existingScheduledAlarms: [off],
        platformAlarmIds: const {},
        disabledDays: {_day},
        now: _now,
      );

      expect(plan.toRemove, [off]);
      expect(plan.toAdd, isEmpty);
      expect(plan.toAddDisabled.map(_ms), [_ms(moved)]);
    });

    test('a disabled entry is not churned by a changed tone or volume - it '
        'does not ring, so its ring properties are irrelevant', () {
      final off = _entry(_planned, id: 6, enabled: false, volume: 0.2);
      final plan = planAlarmSync(
        pendingDayValues: {_day: _ms(_planned)},
        existingScheduledAlarms: [off],
        platformAlarmIds: const {},
        disabledDays: {_day},
        now: _now,
        tone: 'assets/sounds/other.mp3',
        volume: 0.9,
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAddDisabled, isEmpty);
    });

    test('switched back on: the disabled entry is replaced by an armed one',
        () {
      final off = _entry(_planned, id: 6, enabled: false);
      final plan = planAlarmSync(
        pendingDayValues: {_day: _ms(_planned)},
        existingScheduledAlarms: [off],
        platformAlarmIds: const {},
        disabledDays: const {},
        now: _now,
      );

      expect(plan.toRemove, [off]);
      expect(plan.toAdd.map(_ms), [_ms(_planned)]);
      expect(plan.toAddDisabled, isEmpty);
    });

    test('switched back on with the platform state unknown: still armed', () {
      final off = _entry(_planned, id: 6, enabled: false);
      final plan = planAlarmSync(
        pendingDayValues: {_day: _ms(_planned)},
        existingScheduledAlarms: [off],
        disabledDays: const {},
        now: _now,
      );

      expect(plan.toRemove, [off]);
      expect(plan.toAdd.map(_ms), [_ms(_planned)]);
    });

    test('T-116: two disabled entries on one minute -> exactly one survives',
        () {
      final a = _entry(_planned, id: 6, enabled: false);
      final b = _entry(_planned, id: 7, enabled: false);
      final plan = planAlarmSync(
        pendingDayValues: {_day: _ms(_planned)},
        existingScheduledAlarms: [a, b],
        platformAlarmIds: const {},
        disabledDays: {_day},
        now: _now,
      );

      expect(plan.toRemove, [b]);
      expect(plan.toAddDisabled, isEmpty);
    });

    test('counter-test: a day that no longer has a planned value loses its '
        'disabled entry, as before', () {
      final off = _entry(_planned, id: 6, enabled: false);
      final plan = planAlarmSync(
        pendingDayValues: {_day: null},
        existingScheduledAlarms: [off],
        platformAlarmIds: const {},
        disabledDays: {_day},
        now: _now,
      );

      expect(plan.toRemove, [off]);
      expect(plan.toAdd, isEmpty);
      expect(plan.toAddDisabled, isEmpty);
    });

    test('counter-test (FR-18): a past disabled entry is never removed', () {
      final past = _entry(_now.subtract(const Duration(minutes: 5)),
          id: 6, enabled: false);
      final plan = planAlarmSync(
        pendingDayValues: const {},
        existingScheduledAlarms: [past],
        platformAlarmIds: const {},
        disabledDays: {'2026-03-10'},
        now: _now,
      );

      expect(plan.toRemove, isEmpty);
    });

    test('counter-test: an enabled day next to a disabled one stays armed', () {
      final armed = _entry(_other, id: 8);
      final plan = planAlarmSync(
        pendingDayValues: {_day: _ms(_planned), _otherDay: _ms(_other)},
        existingScheduledAlarms: [armed],
        platformAlarmIds: const {8},
        disabledDays: {_day},
        now: _now,
      );

      expect(plan.toRemove, isEmpty);
      expect(plan.toAdd, isEmpty);
      expect(plan.toAddDisabled.map(_ms), [_ms(_planned)]);
    });

    test('counter-test: an enabled entry is not kept for a disabled day just '
        'because the minute matches', () {
      // The trap the old screen code set: it flipped `alarm.enabled` in
      // place. An entry that still says "enabled" for a day the user
      // switched off is the armed one, and it has to go.
      final armed = _entry(_planned, id: 5);
      final plan = planAlarmSync(
        pendingDayValues: {_day: _ms(_planned)},
        existingScheduledAlarms: [armed],
        platformAlarmIds: const {5},
        disabledDays: {_day},
        now: _now,
      );

      expect(plan.toRemove, contains(armed));
    });
  });

  group('applyPlannedAlarms: listed as inactive, never armed', () {
    late FakeAlarmPlatform platform;

    Future<AppState> planned() async {
      final appState = await _fresh();
      platform = FakeAlarmPlatform()..attach(appState);
      appState.pendingDayValues = {
        _day: _ms(_planned),
        _otherDay: _ms(_other),
      };
      await applyPlannedAlarms(appState, now: () => _now);
      return appState;
    }

    test('switching a day off keeps its entry listed, disabled, at the '
        "day's planned time, and cancels the platform alarm", () async {
      final appState = await planned();
      final armedId = _at(appState, _planned).single.id;
      expect(platform.armed.keys, contains(armedId));

      appState.setDayEnabled(_day, false);
      await applyPlannedAlarms(appState, now: () => _now);

      final entry = _at(appState, _planned);
      expect(entry, hasLength(1),
          reason: 'T-221: switched off is listed as inactive, not deleted');
      expect(entry.single.enabled, isFalse);
      expect(platform.armed.keys, isNot(contains(armedId)),
          reason: 'FR-21 assurance 1: off immediately');
      expect(platform.armedAt(_planned), isFalse,
          reason: 'and nothing else is armed in its place');
      expect(platform.armed.keys, isNot(contains(entry.single.id)));
    });

    test('a platform stop that fails keeps the armed entry listed as '
        'enabled - the list never says "inactive" for an alarm that still '
        'rings - and the next replan heals it', () async {
      // Review finding N1: removeAlarm used to drop the entry from the list
      // before stopping it, so a failing stop left an armed orphan while a
      // fresh disabled entry claimed the day.
      final appState = await planned();
      final armedId = _at(appState, _planned).single.id;
      appState.debugPlatformStop = (id) async =>
          throw StateError('platform refused the stop');

      appState.setDayEnabled(_day, false);
      await applyPlannedAlarms(appState, now: () => _now);

      expect(platform.armed.keys, contains(armedId),
          reason: 'the stop failed, so it is still armed');
      final stillArmed =
          appState.scheduledAlarms.where((a) => a.id == armedId).toList();
      expect(stillArmed, hasLength(1),
          reason: 'the armed alarm stays visible in the list');
      expect(stillArmed.single.enabled, isTrue,
          reason: 'and is shown as what it is: enabled');

      // The platform works again: the next replan stops it and lists the
      // day as inactive.
      platform.attach(appState);
      await applyPlannedAlarms(appState, now: () => _now);
      expect(platform.armed.keys, isNot(contains(armedId)));
      expect(platform.armedAt(_planned), isFalse);
      final entry = _at(appState, _planned);
      expect(entry, hasLength(1));
      expect(entry.single.enabled, isFalse);
    });

    test('several further replans: still exactly one disabled entry, never '
        'armed again', () async {
      final appState = await planned();
      appState.setDayEnabled(_day, false);
      await applyPlannedAlarms(appState, now: () => _now);
      final setsAfterOff = List.of(platform.setIds);
      final disabledId = _at(appState, _planned).single.id;

      for (var i = 0; i < 3; i++) {
        await applyPlannedAlarms(appState, now: () => _now);
      }

      expect(_at(appState, _planned), hasLength(1));
      expect(_at(appState, _planned).single.id, disabledId,
          reason: 'a fixed point - no churn on every replan');
      expect(_at(appState, _planned).single.enabled, isFalse);
      expect(platform.setIds, setsAfterOff,
          reason: 'FR-21 assurance 2: nothing arms it behind the user');
      expect(appState.scheduledAlarms, hasLength(2));
    });

    test('counter-test: the other, enabled day stays armed throughout',
        () async {
      final appState = await planned();
      final otherId = _at(appState, _other).single.id;

      appState.setDayEnabled(_day, false);
      await applyPlannedAlarms(appState, now: () => _now);

      expect(_at(appState, _other).single.id, otherId);
      expect(_at(appState, _other).single.enabled, isTrue);
      expect(platform.armed.keys, contains(otherId));
    });

    test('switched back on: listed enabled and armed exactly once', () async {
      final appState = await planned();
      appState.setDayEnabled(_day, false);
      await applyPlannedAlarms(appState, now: () => _now);
      final setsBefore = platform.setIds.length;

      appState.setDayEnabled(_day, true);
      await applyPlannedAlarms(appState, now: () => _now);
      await applyPlannedAlarms(appState, now: () => _now);

      final entry = _at(appState, _planned);
      expect(entry, hasLength(1));
      expect(entry.single.enabled, isTrue);
      expect(platform.armed.keys, contains(entry.single.id));
      expect(platform.setIds.length - setsBefore, 1,
          reason: 'armed exactly once, not on every replan');
      expect(appState.scheduledAlarms, hasLength(2));
    });

    test('a plan change while off moves the disabled entry; switching on '
        'arms the CURRENT planned value', () async {
      final appState = await planned();
      appState.setDayEnabled(_day, false);
      await applyPlannedAlarms(appState, now: () => _now);

      final moved = _planned.add(const Duration(minutes: 20));
      appState.pendingDayValues = {
        ...appState.pendingDayValues,
        _day: _ms(moved),
      };
      await applyPlannedAlarms(appState, now: () => _now);

      expect(_at(appState, _planned), isEmpty);
      expect(_at(appState, moved).single.enabled, isFalse,
          reason: 'follows its day, still disabled');
      expect(platform.armedAt(moved), isFalse);

      appState.setDayEnabled(_day, true);
      await applyPlannedAlarms(appState, now: () => _now);

      expect(_at(appState, moved).single.enabled, isTrue);
      expect(platform.armedAt(moved), isTrue);
      expect(platform.armedAt(_planned), isFalse);
    });

    test('a day that loses its planned value loses its disabled entry',
        () async {
      final appState = await planned();
      appState.setDayEnabled(_day, false);
      await applyPlannedAlarms(appState, now: () => _now);

      appState.pendingDayValues = {..._mapWith(appState, _day, null)};
      await applyPlannedAlarms(appState, now: () => _now);

      expect(_at(appState, _planned), isEmpty);
    });

    test('AppState.addAlarm does not arm a disabled ScheduledAlarm, but lists '
        'it', () async {
      final appState = await _fresh();
      platform = FakeAlarmPlatform()..attach(appState);

      await appState.addAlarm(_entry(_planned, id: 9, enabled: false),
          now: () => _now);

      expect(appState.scheduledAlarms.single.enabled, isFalse);
      expect(platform.setIds, isEmpty);
    });
  });

  group('persistence: a disabled entry survives a restart as disabled', () {
    test('reloaded from the same preferences, then reconciled again',
        () async {
      final first = await _fresh();
      final platform = FakeAlarmPlatform()..attach(first);
      first.pendingDayValues = {_day: _ms(_planned)};
      await applyPlannedAlarms(first, now: () => _now);
      first.setDayEnabled(_day, false);
      await applyPlannedAlarms(first, now: () => _now);
      final disabledId = _at(first, _planned).single.id;

      final second = AppState(
          getPrefsInstance: () async => SharedPreferences.getInstance());
      await second.initialized;
      platform.attach(second);

      expect(second.isDayDisabled(_day), isTrue);
      expect(_at(second, _planned).single.enabled, isFalse);
      expect(_at(second, _planned).single.id, disabledId);

      final setsBefore = platform.setIds.length;
      await applyPlannedAlarms(second, now: () => _now);

      expect(_at(second, _planned).single.id, disabledId,
          reason: 'FR-21 assurance 3 - and no churn after a restart');
      expect(platform.setIds.length, setsBefore);
    });
  });

  group('replan(): the full path keeps the switched-off day listed', () {
    test('after the switch-off and a following ring replan', () async {
      final appState = await _fresh();
      final platform = FakeAlarmPlatform()..attach(appState);
      appState.preferredWakeUpTime = const TimeOfDay(hour: 7, minute: 0);
      final ringDay = DateTime.utc(2026, 3, 10);
      final tomorrow = isoDate(dayMarker(ringDay, 1));

      Future<void> run() => replan(
            appState,
            now: () => DateTime.utc(2026, 3, 10, 6, 0),
            offsetAt: fixedOffset(Duration.zero),
            fetchEvents: (start, end) async => <Meeting>[],
            todayAlreadyRang: true,
          );

      await run();
      final value = localFromStored(appState.pendingDayValues[tomorrow])!;
      expect(platform.armedAt(value), isTrue);

      appState.setDayEnabled(tomorrow, false);
      await run();
      await run();

      expect(_at(appState, value), hasLength(1));
      expect(_at(appState, value).single.enabled, isFalse);
      expect(platform.armedAt(value), isFalse);
      // The other window days are untouched: armed and enabled.
      final others =
          appState.scheduledAlarms.where((a) => _ms(a.time) != _ms(value));
      expect(others, isNotEmpty);
      expect(others.every((a) => a.enabled), isTrue);
      expect(others.every((a) => platform.armed.containsKey(a.id)), isTrue);
    });
  });

  group('T-141: the prune treats disabled entries like the others', () {
    test('an old disabled entry is pruned, today\'s is kept', () {
      final old = ScheduledAlarm(
          time: DateTime(2026, 3, 1, 7, 30), enabled: false, id: 1);
      final today = ScheduledAlarm(
          time: DateTime(2026, 3, 10, 7, 30), enabled: false, id: 2);

      final kept =
          pruneScheduledAlarms([old, today], oldestKeptDay: '2026-03-09');

      expect(kept.map((a) => a.id), [2]);
    });
  });
}

Map<String, int?> _mapWith(AppState s, String key, int? value) =>
    {...s.pendingDayValues, key: value};
