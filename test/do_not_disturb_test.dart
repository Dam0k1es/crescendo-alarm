import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/utils/do_not_disturb.dart';
import 'package:crescendo_alarm/utils/do_not_disturb_channel.dart';

// docs/TODO.md T-184 (maintainer request): a Do Not Disturb toggle that
// silences notifications during sleep time and restores whatever the device
// was set to beforehand once the alarm's FINAL ring happens (not an
// intermediate snoozed one). This file is the pure "what state do we end up
// in" logic - no platform channel, no AppState, no scheduling - injectable
// getCurrentFilter/setFilter so it's testable without a device, the same
// split as snooze.dart/manual_alarm_enable.dart.

void main() {
  group('activateDoNotDisturb', () {
    test('remembers the current filter, then sets ALARMS-only', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      int? applied;

      final ok = await activateDoNotDisturb(
        prefs: prefs,
        getCurrentFilter: () async => interruptionFilterPriority,
        setFilter: (f) async {
          applied = f;
          return true;
        },
      );

      expect(ok, isTrue);
      expect(applied, interruptionFilterAlarms);
      expect(prefs.getInt(doNotDisturbPreviousFilterKey),
          interruptionFilterPriority,
          reason: 'the ORIGINAL state must be remembered, not the new one');
    });

    test('does not overwrite an already-remembered previous state', () async {
      // Guards against two activations in a row (e.g. a re-scheduled
      // notification firing twice) clobbering the real "before" state with
      // an already-DND'd one.
      SharedPreferences.setMockInitialValues(
          {'doNotDisturbPreviousFilter': interruptionFilterAll});
      final prefs = await SharedPreferences.getInstance();
      var getCurrentFilterCalls = 0;

      await activateDoNotDisturb(
        prefs: prefs,
        getCurrentFilter: () async {
          getCurrentFilterCalls++;
          return interruptionFilterAlarms; // already in our own DND mode
        },
        setFilter: (f) async => true,
      );

      expect(getCurrentFilterCalls, 0,
          reason: 'the real previous state is already known - it must not '
              'be re-read (and potentially overwritten with our own mode)');
      expect(prefs.getInt(doNotDisturbPreviousFilterKey), interruptionFilterAll);
    });

    test('records when it activated, for the staleness safety net', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 3, 10, 22, 0);

      await activateDoNotDisturb(
        prefs: prefs,
        getCurrentFilter: () async => interruptionFilterAll,
        setFilter: (f) async => true,
        now: () => now,
      );

      expect(prefs.getInt(doNotDisturbActivatedAtKey),
          now.millisecondsSinceEpoch);
    });

    test('does not store anything if the current filter could not be read',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final ok = await activateDoNotDisturb(
        prefs: prefs,
        getCurrentFilter: () async => null,
        setFilter: (f) async => true,
      );

      expect(ok, isFalse);
      expect(prefs.containsKey(doNotDisturbPreviousFilterKey), isFalse);
    });
  });

  group('restoreDoNotDisturb', () {
    test('restores the remembered filter and forgets it', () async {
      SharedPreferences.setMockInitialValues(
          {'doNotDisturbPreviousFilter': interruptionFilterPriority});
      final prefs = await SharedPreferences.getInstance();
      int? applied;

      final ok = await restoreDoNotDisturb(
        prefs: prefs,
        setFilter: (f) async {
          applied = f;
          return true;
        },
      );

      expect(ok, isTrue);
      expect(applied, interruptionFilterPriority);
      expect(prefs.containsKey(doNotDisturbPreviousFilterKey), isFalse);
    });

    test('does nothing when nothing was ever activated', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var setFilterCalls = 0;

      final ok = await restoreDoNotDisturb(
        prefs: prefs,
        setFilter: (f) async {
          setFilterCalls++;
          return true;
        },
      );

      expect(ok, isFalse);
      expect(setFilterCalls, 0);
    });

    test('keeps the remembered state if restoring fails, so a retry stays '
        'possible', () async {
      SharedPreferences.setMockInitialValues(
          {'doNotDisturbPreviousFilter': interruptionFilterPriority});
      final prefs = await SharedPreferences.getInstance();

      final ok = await restoreDoNotDisturb(
        prefs: prefs,
        setFilter: (f) async => false,
      );

      expect(ok, isFalse);
      expect(prefs.getInt(doNotDisturbPreviousFilterKey),
          interruptionFilterPriority,
          reason: 'a failed restore must not silently give up - the next '
              'attempt (a later ring, or the safety-net checkpoint) needs '
              'the real previous state still available');
    });
  });

  group('runDoNotDisturbActivation', () {
    // The background-isolate entry point (docs/TODO.md T-184) -
    // `onNotificationCreatedMethod` fires this when the scheduled bedtime
    // notification is created, with no AppState/Provider access at all, the
    // same reasoning `runTimezoneCheckpoint2` already documents - reads
    // `doNotDisturbEnabled` directly via SharedPreferences.

    test('disabled: does nothing', () async {
      SharedPreferences.setMockInitialValues(
          {'doNotDisturbEnabled': false});
      final prefs = await SharedPreferences.getInstance();
      var setFilterCalls = 0;

      await runDoNotDisturbActivation(
        prefs: prefs,
        getCurrentFilter: () async => interruptionFilterAll,
        setFilter: (f) async {
          setFilterCalls++;
          return true;
        },
      );

      expect(setFilterCalls, 0);
    });

    test('enabled: activates, remembering the current filter first',
        () async {
      SharedPreferences.setMockInitialValues({'doNotDisturbEnabled': true});
      final prefs = await SharedPreferences.getInstance();
      int? applied;

      await runDoNotDisturbActivation(
        prefs: prefs,
        getCurrentFilter: () async => interruptionFilterPriority,
        setFilter: (f) async {
          applied = f;
          return true;
        },
      );

      expect(applied, interruptionFilterAlarms);
      expect(prefs.getInt(doNotDisturbPreviousFilterKey),
          interruptionFilterPriority);
    });

    test('missing setting (not yet ever touched): treated as disabled',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var setFilterCalls = 0;

      await runDoNotDisturbActivation(
        prefs: prefs,
        getCurrentFilter: () async => interruptionFilterAll,
        setFilter: (f) async {
          setFilterCalls++;
          return true;
        },
      );

      expect(setFilterCalls, 0);
    });
  });

  group('restoreStaleDoNotDisturb (safety net)', () {
    // docs/TODO.md T-184: availability is this project's own primary
    // threat-model asset (docs/threat-model.svg) - a Do Not Disturb
    // activation that never gets restored (the alarm never rang for any
    // reason: a bug, a killed process, a missed edge case) would silence a
    // device indefinitely, exactly the "self-inflicted alarm shutdown"
    // class T-64/T-78 already were. Checked during the regular scheduling
    // checkpoint, which already runs on every app open (FR-17) regardless
    // of Do Not Disturb specifically - a generous fixed cap, not tied to
    // any particular wake time/snooze budget, so it cannot itself become
    // wrong the way re-deriving those would risk.
    test('restores if activated longer ago than the cap', () async {
      final activatedAt = DateTime(2026, 3, 10, 22, 0);
      final now = activatedAt.add(const Duration(hours: 19));
      SharedPreferences.setMockInitialValues({
        doNotDisturbPreviousFilterKey: interruptionFilterPriority,
        doNotDisturbActivatedAtKey: activatedAt.millisecondsSinceEpoch,
      });
      final prefs = await SharedPreferences.getInstance();
      int? applied;

      final ok = await restoreStaleDoNotDisturb(
        prefs: prefs,
        setFilter: (f) async {
          applied = f;
          return true;
        },
        now: () => now,
      );

      expect(ok, isTrue);
      expect(applied, interruptionFilterPriority);
      expect(prefs.containsKey(doNotDisturbPreviousFilterKey), isFalse);
    });

    test('does nothing while still within the cap', () async {
      final activatedAt = DateTime(2026, 3, 10, 22, 0);
      final now = activatedAt.add(const Duration(hours: 8));
      SharedPreferences.setMockInitialValues({
        doNotDisturbPreviousFilterKey: interruptionFilterPriority,
        doNotDisturbActivatedAtKey: activatedAt.millisecondsSinceEpoch,
      });
      final prefs = await SharedPreferences.getInstance();
      var setFilterCalls = 0;

      final ok = await restoreStaleDoNotDisturb(
        prefs: prefs,
        setFilter: (f) async {
          setFilterCalls++;
          return true;
        },
        now: () => now,
      );

      expect(ok, isFalse);
      expect(setFilterCalls, 0);
      expect(prefs.getInt(doNotDisturbPreviousFilterKey), interruptionFilterPriority,
          reason: 'still legitimately active - must not be touched yet');
    });

    test('does nothing when Do Not Disturb was never activated', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var setFilterCalls = 0;

      final ok = await restoreStaleDoNotDisturb(
        prefs: prefs,
        setFilter: (f) async {
          setFilterCalls++;
          return true;
        },
      );

      expect(ok, isFalse);
      expect(setFilterCalls, 0);
    });

    test('missing activation timestamp (an older stored state, or a bug) '
        'is treated as stale rather than left untouched forever', () async {
      SharedPreferences.setMockInitialValues({
        doNotDisturbPreviousFilterKey: interruptionFilterAll,
      });
      final prefs = await SharedPreferences.getInstance();
      var applied = false;

      final ok = await restoreStaleDoNotDisturb(
        prefs: prefs,
        setFilter: (f) async {
          applied = true;
          return true;
        },
      );

      expect(ok, isTrue);
      expect(applied, isTrue);
    });
  });

  group('isTargetWakeUpRing', () {
    // Independent-review finding (docs/TODO.md T-184, 2026-09-25): "final"
    // alone is not enough to restore Do Not Disturb - an unrelated alarm
    // (e.g. a manual reminder with Snooze switched off) can become "final"
    // and ring hours before the real wake-up Do Not Disturb was scheduled
    // around. This predicate closes that gap by comparing against the
    // WAKE-UP instant `scheduleDoNotDisturbActivation` persisted, not by
    // re-deriving `nextWakeUpTime` fresh (which would trivially match
    // whatever is about to ring anyway, since it is always the soonest
    // not-yet-passed candidate one tick before it fires).

    test('nothing persisted yet (never scheduled, or disabled): trusts this '
        'ring', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(isTargetWakeUpRing(prefs, DateTime(2026, 3, 10, 6, 0)), isTrue);
    });

    test('matches the persisted target exactly: is the target', () async {
      final target = DateTime(2026, 3, 10, 6, 0);
      SharedPreferences.setMockInitialValues(
          {doNotDisturbTargetWakeUpKey: target.millisecondsSinceEpoch});
      final prefs = await SharedPreferences.getInstance();

      expect(isTargetWakeUpRing(prefs, target), isTrue);
    });

    test('within the small tolerance of the persisted target: still counts',
        () async {
      final target = DateTime(2026, 3, 10, 6, 0);
      SharedPreferences.setMockInitialValues(
          {doNotDisturbTargetWakeUpKey: target.millisecondsSinceEpoch});
      final prefs = await SharedPreferences.getInstance();

      expect(
          isTargetWakeUpRing(
              prefs, target.add(const Duration(minutes: 1))),
          isTrue);
    });

    test('an unrelated alarm ringing hours before the persisted target: NOT '
        'the target', () async {
      // The exact scenario the review found: a medication reminder at 02:00
      // (Snooze off, so it becomes "final" immediately) while Do Not Disturb
      // was actually scheduled around a 06:00 wake-up.
      final realWakeUp = DateTime(2026, 3, 10, 6, 0);
      SharedPreferences.setMockInitialValues(
          {doNotDisturbTargetWakeUpKey: realWakeUp.millisecondsSinceEpoch});
      final prefs = await SharedPreferences.getInstance();
      final medicationRing = DateTime(2026, 3, 10, 2, 0);

      expect(isTargetWakeUpRing(prefs, medicationRing), isFalse);
    });
  });
}
