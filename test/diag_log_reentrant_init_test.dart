import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/utils/diag/diag_log.dart';

// docs/TODO.md T-162: found by reading a real user's exported diagnostics
// log, not by code review. `Diag.init()` was called a second time WITHIN
// THE SAME ISOLATE - `onNotificationCreatedMethod` (`lib/utils/
// notifications.dart`) calls `Diag.init(isolate: LogIsolate.background)`,
// documented as safe because that callback "runs in its own background
// isolate with no AppState" - but `awesome_notifications` only spins up a
// genuinely fresh isolate for that callback when the app process is NOT
// running. `AwesomeNotifications().createNotification()` also fires it
// in-process, in the SAME isolate, whenever the app is alive when a
// notification it just created is created - which is exactly what
// `scheduleSleepReminder()` does at the end of EVERY checkpoint
// (`checkpoint.dart`'s `finally` block, before `Diag.checkpointFinished`).
//
// `Diag.init()` unconditionally overwrites the shared static `_isolate`
// and bumps+persists the shared static `_boot` counter with no protection
// against being called again in an isolate that already has an identity.
// The result, observed in a real export: every event from that point in
// the session onward gets mis-tagged `(bg)` even though it is genuinely
// ordinary main-isolate scheduling-checkpoint activity, the persisted boot
// counter jumps with no corresponding `boot()` event, and because
// `flush()` writes the CURRENT contents of the whole ring buffer to
// whichever key `_isolate` selects at flush time (not just newly-added
// records), the records logged BEFORE the corruption end up persisted
// under BOTH prefs keys - and `readAll()`'s merge has no deduplication,
// so they are exported twice.
//
// `_freshDiag()`'s `resetForTest()` cannot model this: it always clears
// `_ring`/`_seq`, exactly simulating a genuinely fresh isolate. The bug
// only shows up when `init()` runs a second time WITHOUT that reset -
// i.e. in the same isolate.

Future<void> _freshDiag({
  LogIsolate isolate = LogIsolate.main,
  bool enabled = true,
  bool clearPrefs = true,
}) async {
  if (clearPrefs) SharedPreferences.setMockInitialValues(<String, Object>{});
  Diag.resetForTest();
  await Diag.init(isolate: isolate, enabled: enabled);
}

void main() {
  test(
      're-entrant init() in the same isolate does not change boot or '
      'isolate identity', () async {
    await _freshDiag();
    final bootBefore = Diag.bootSeq;
    Diag.alarmDismissed(route: DismissRoute.defaultOverlay, stopFailed: false);

    // Simulates `onNotificationCreatedMethod` firing in-process - the app
    // was already alive, so this never actually left the main isolate.
    await Diag.init(isolate: LogIsolate.background);

    Diag.alarmDismissed(route: DismissRoute.qrScan, stopFailed: false);

    expect(Diag.bootSeq, bootBefore,
        reason: 'a re-entrant init() in the same isolate must not bump the '
            'persisted boot counter a second time - nothing actually '
            'rebooted');
    expect(Diag.records.last.fields[DiagField.isolate], LogIsolate.main.code,
        reason: 'the isolate identity must not flip mid-session for a call '
            'that never left this isolate, or every later event in a '
            'genuinely main-isolate checkpoint gets mis-tagged (bg)');
  });

  test(
      'records flushed before a re-entrant init() are not duplicated on '
      'export', () async {
    await _freshDiag();
    Diag.alarmDismissed(route: DismissRoute.defaultOverlay, stopFailed: false);
    await Diag.flush();

    await Diag.init(isolate: LogIsolate.background);
    Diag.qrGate(outcome: QrOutcome.accepted, codeWasSet: true);
    await Diag.flush();

    final all = await Diag.readAll();
    expect(all.length, 2,
        reason:
            'the first record must not be exported twice just because a '
            'later, re-entrant init() call happened before the next flush');
  });

  test('a genuinely fresh background isolate still gets its own identity',
      () async {
    // The case the guard must NOT break: `onNotificationCreatedMethod`
    // really does sometimes run in a fresh isolate (app not running).
    await _freshDiag(isolate: LogIsolate.background);

    Diag.timezoneCheck(
      offsetChanged: false,
      shape: OffsetChangeShape.none,
      valuesConsidered: 0,
      valuesReinterpreted: 0,
    );

    expect(Diag.records.single.fields[DiagField.isolate],
        LogIsolate.background.code);
  });

  test(
      'readAll() heals a log already corrupted on a device before this fix '
      'shipped', () async {
    // The init() guard above stops this from happening again, but a device
    // that already hit the bug has a real (boot, seq) collision sitting in
    // its SharedPreferences right now - readAll() must not keep exporting
    // it twice forever.
    await _freshDiag();
    Diag.alarmDismissed(route: DismissRoute.defaultOverlay, stopFailed: false);
    final encoded = jsonEncode([Diag.records.single.encode()]);

    SharedPreferences.setMockInitialValues(<String, Object>{
      Diag.prefsKeyMain: encoded,
      Diag.prefsKeyIsolate: encoded,
    });
    final freshPrefs = await SharedPreferences.getInstance();

    final all = await Diag.readAll(prefs: freshPrefs);
    expect(all.length, 1,
        reason: 'the same (boot, seq) coming from both prefs keys is the '
            'exact shape T-162 produced - it must collapse to one record');
  });
}
