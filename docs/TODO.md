# TODOs

The single task list for Crescendo Alarm, sorted by priority. Two sources feed it:

- **Device feedback** from the maintainer trying the app on real hardware (intake happens in the
  untracked `tasks.txt`; items are moved here once they are formulated as TODOs).
- **The audit** of project description, documentation, requirements, tests and CI against the
  actual code — both its ranked findings and the underlying per-area survey, so that items the
  ranking cut off (most of the licensing ones) are represented here too.

Every item below was checked against the current code before being written down; where a claim
could not be confirmed from the repository it says so instead of asserting it.

Conventions:

- IDs (`T-01` …) are stable. Reference them in commit messages; never renumber an existing one.
- **The status belongs in the heading**, not only in the body: `RESOLVED`, `DISPROVEN`,
  `ANSWERED`, `PARTIALLY`/`LARGELY RESOLVED`, `DECIDED`, or `OPEN SPEC DECISION`. A heading without
  such a suffix means: open. Whoever closes an item drags the heading along; otherwise the list
  stops being skimmable, and that is its entire value. (On 2026-09-11, 24 long-finished items
  carried their status only in the body.)
  Older headings still use the German words this list was started with (`BEHOBEN`, `WIDERLEGT`,
  `BEANTWORTET`, `TEILWEISE`/`GROSSTEILS`); they are translated as items get touched.
- **P0** blocks any push to `master` / production. **P1** must be resolved or consciously accepted
  before a public release. **P2** is real work that does not block a release. **P3** is
  housekeeping.
- `R1`–`R12` refer to [`REQUIREMENTS.md`](REQUIREMENTS.md).
- *Evidence* cites where the problem is visible, so nobody has to re-derive it.
- *Done when* is the acceptance criterion — if it cannot be checked, the TODO is not finished.

---

## Waiting on a decision, not on work

Seven items are investigated, reproduced, and **not** implemented, because in every one of them the
code follows the spec and the *requirement* has the gap. They need a decision from the project owner,
not further analysis — each item names the question, the possible readings, and what each one costs:

| | Question in one sentence |
|---|---|
| **T-112** | What holds when a curve slips past midnight — may one calendar day carry two wake times while another carries none? |
| **T-113** | Should FR-16's Checkpoint 2 retroactively adjust alarms that are already armed? (Otherwise the first alarm after a flight rings wrong by the full offset difference.) |
| **T-115** | Which direction wins at a gap of exactly 12 hours? |
| **T-119** | Does the day assignment need to use the offset of the respective window day? (Otherwise a genuine morning appointment gets swallowed twice a year.) |
| **T-120** | Which day does a wake value belong to when the lead times push it back past midnight? |
| **T-121** | Does an appointment inside the window also disable FR-9's valve for the days **after** it? |
| **T-122** | Is anchoring decided by a value's origin, or by its meaning? |

The **decided** part of each of these cases is already pinned down by tests (T-118, T-123 … T-128) -
that is the basis a decision can be formulated against.

---

## P0 — blocks a production push

### T-01 · Sleep-Habits durations are not subtracted from the alarm time — RESOLVED (2026-09-10, Phase 6)

- [x] Apply "duration to wake up" and "duration to get ready" when deriving an alarm from a
      calendar entry.
- **Why:** the app's central promise. Confirmed on a real device: a calendar entry at 07:00 with
  both durations set to 15 minutes produced an alarm at 07:00 instead of 06:30.
- **Evidence (at the time):** device test by the maintainer; scheduling path in the since-deleted
  `lib/models/scheduling/scheduling.dart` and `lib/screens/sleep_habits/screen_sleephabits.dart`.
- **Resolution:** the subtraction is now FR-2's definition of `hardFloor` (earliest
  non-all-day appointment − `durationToWakeUp` − `durationToGetReady`), implemented in
  `lib/models/scheduling/scheduling_v2.dart`'s `hardFloor()`. All three worked-through
  FR-2 test cases carry the same numbers in `test/scheduling_v2_test.dart:151-196` — the
  first of them is exactly the reported device example: appointments at 09:00 and 07:00, both
  durations 15 min, expects **06:30** (the earlier appointment counts, minus 15 + 15).
  On a real emulator this is confirmed by the E2E case "injected appointment becomes registered
  platform alarms" (T-63/T-91, run 34532845207). The remaining check on a **real**
  device is tracked as B2/B4 in `docs/device-trial-checklist.md`.
- **Requirement:** R2

### T-02 · Calendar-derived alarm times are discarded for most days — RESOLVED (2026-09-10, Phase 6)

- [x] Fix `_adjustAlarmTimes` so each day keeps its own calendar-derived time, and stop arming the
      synthetic "no calendar entry" placeholder.
- **Why:** the headline calendar feature throws away the data it is derived from.
  `_adjustAlarmTimes` compares each day's alarm against `offset`, an *absolute* `DateTime` built
  from the earliest day, so for every day after that day the comparison is decided by the date
  alone and the day's real time is replaced by the earliest day's wake-up time. On days *before*
  the earliest day the 23:59 placeholder is left untouched and armed as a real alarm. Scheduling
  also returns `null` — arming nothing at all, silently — once seven or more alarms had to be
  estimated.
- **Evidence:** `lib/models/scheduling/scheduling.dart:143` (`offset`), `:151` (the date-dominated
  comparison), `:155-161` (time-of-day replacement), `:66-70` (23:59 placeholder), `:169-171`
  (silent abort).
- **Done when:** unit tests over the production function cover a multi-day schedule with differing
  meeting times, a day without entries, and the ≥7-estimate case; each asserts the resulting alarm
  times per day.
- **Resolution (2026-09-10, Phase 6):** `_adjustAlarmTimes` no longer exists — the file was
  deleted along with the old engine (T-64/T-86). The three reported symptoms each have a named
  requirement in scheduling-v2 that guarantees the opposite: every day keeps its own value
  (FR-6, "every `Tag_i` gets its own, real calendar date"), a day without an appointment drifts
  toward the preferred wake-up time instead of being discarded (FR-4), and there is no abort once
  seven alarms have had to be estimated — FR-9's valve is the one deliberate exception, and it
  notifies the user. The 23:59 placeholder is gone with nothing replacing it; FR-18 only creates
  alarms for values that were actually planned. Covered by the whole scheduling-v2 suite, and for
  the multi-day case by name, `test/scheduling_v2_test.dart`'s `computeWeekPlan` group and
  `test/replan_test.dart`.
- **Requirement:** R2

### T-03 · The per-alarm enable switch does not stop an alarm — RESOLVED (2026-09-16, FR-21)

- [x] Committed to as a requirement: **FR-21** in `docs/scheduling-v2-spec.md`, including the
      interaction that a naive fix fails on (FR-18 rebuilds the alarm set on every replan, so a
      bare `Alarm.stop()` when the switch is flipped does not hold until the next checkpoint) and
      the reasoning for a dedicated `disabledDays` field instead of
      `pendingDayValues[tag] = null`.
- [x] Implemented for planned alarms: `AppState.disabledDays` (persisted, cleaned up with T-82's
      retention limit), `planAlarmSync` skips these days, the switch in
      the alarm list writes the DAY instead of an object field and triggers a checkpoint.
      Tests first, from FR-21's worked-through cases: `test/disabled_day_test.dart` (7 cases;
      the mutation "filter removed" turns 3 of them red).
- [x] The same for `ManualAlarm`s, through FR-21's second section:
      `applyManualAlarmEnabled` (`lib/models/alarms/manual_alarm_enable.dart`) cancels the platform
      alarm, or re-arms it for the **next** occurrence of its time - the same resolution used when
      an alarm is created, so switching off and on again cannot land on a different day than a
      freshly created alarm would. If the platform call fails the flag is left alone: it describes
      what the device will actually do. `addAlarm`/`updateAlarm` no longer arm a switched-off alarm
      at all (the back door: change the title and it is live again), and `nextWakeUpTime()` now
      skips it - a bedtime reminder derived from an alarm that will not ring sends the user to bed
      for nothing. Tests first, from FR-21's "Test:" bullets:
      `test/disabled_manual_alarm_test.dart` (9 cases; three mutations - dropping the flag check,
      dropping the arming guard, setting the flag before the platform call - kill one to two each).
- **Why:** a user switches an alarm off and it rings anyway. The flag is stored, serialized and
  compared, but never consulted when arming or cancelling.
- **Evidence:** `lib/models/alarms/myalarm.dart:6`; the only reads are constructor pass-throughs
  (`lib/app_state.dart:319`, `:343`), the UI switch (`lib/screens/alarms/screen_alarms.dart:152-155`)
  and `==`. No call site cancels a scheduled alarm.
- **Done when:** toggling an alarm off cancels it in `Alarm.getAlarms()`, survives an app restart,
  and a test asserts both.
- **How far the tests actually reach, stated plainly:** the restart half is asserted
  (`test/disabled_manual_alarm_test.dart`, through a real storage round-trip). The
  `Alarm.getAlarms()` half is **not** assertable in the unit suite - `Alarm.set` has no platform
  channel there, so no test can observe a platform alarm appearing or disappearing. What is
  asserted instead is that the applier calls `stopAlarm` with this alarm's id and arms nothing.
  The remaining step is a device check, which fits into the run of
  `scripts/verify-alarm-survival.sh` (T-93).
- **Requirement:** R3

### T-04 · Alarm survival across reboot and force-stop — PARTLY VERIFIED on a real device (2026-09-19), one scenario still open

- [x] Fixed the test that claimed to cover persistence. `integration_test/app_test.dart`'s
      scenario 3 now calls `SharedPreferences.resetStatic()` and `reload()` before re-reading, and
      asserts the alarm's **id and time** plus its presence in `Alarm.getAlarms()` - previously it
      built a fresh `AppState`, which re-read the memoised in-process cache and would have stayed
      green with storage entirely broken. The same hardening went into
      `test/disabled_manual_alarm_test.dart`, where a mutation (dropping the save) proved the
      assertion had been vacuous until the alarm was created **switched on**.
- [x] Verified on a real device, by the maintainer: an armed alarm fires as expected after a
      **reboot**, after the app being **closed**, and after a **force-stop** - in every case tried
      so far, provided the app gets **reopened** at some point before the alarm's due time.
- [ ] Still open: the same three scenarios (reboot / closed / force-stopped) but over a **long
      stretch with no app activity at all** - the app never reopened, not even briefly, before the
      alarm is due. Reopening the app runs `runCheckpointSafely(trigger:
      CheckpointTrigger.appForeground)` (`main.dart`'s `initState`) and FR-17's stale-checkpoint
      recovery, which may be doing work that a long idle period never gets - if so, an alarm
      surviving in the verified cases could still be silently lost in this one. Needs its own real-
      device run: arm an alarm, force-stop/reboot, then wait out the alarm's due time **without**
      ever bringing the app back to the foreground, and confirm it still rings.
- **Why:** for an alarm clock this is the only durability question that matters, and nothing tests
  it. The test named *"a created alarm survives being reloaded from on-device storage"* does not
  touch storage: `SharedPreferences.getInstance()` memoises its instance behind a static
  `Completer`, so rebuilding `AppState` re-reads the same in-process cache. Nothing anywhere
  reboots or force-stops.
- **Evidence:** `integration_test/app_test.dart:186-198`;
  `shared_preferences-2.5.5/lib/src/shared_preferences_legacy.dart:28,79-96` (memoised),
  `:107,129` (in-memory cache), `:223` (`reload()`, never called anywhere in this repo);
  `grep -rniE "reboot|force-stop" .github/` returns nothing; the real-device runs above are the
  maintainer's own manual verification, not yet captured by `scripts/verify-alarm-survival.sh`.
- **Done when:** the test calls `reload()` (or `resetStatic()`) before re-reading and asserts the
  alarm's time and id plus its presence in `Alarm.getAlarms()` (done); and the long-idle,
  never-reopened variant of the reboot/close/force-stop scenarios is confirmed (or found to fail)
  on a real device, ideally captured by `scripts/verify-alarm-survival.sh`'s evidence trail (T-93)
  rather than only observed by hand.
- **T-93's evidence trail now exists (2026-09-19)** but does not close this item's remaining gap:
  that run only checks registration a few seconds after reboot/force-stop, not survival over a long
  dormant period with the app never reopened - see T-93 for that run's own result and an
  unexplained force-stop finding worth re-measuring cleanly regardless.
- **A tool for exactly this gap now exists (2026-09-24, T-164):**
  `scripts/verify-long-idle-alarm-survival.sh` - arms, reboots and force-stops, then waits a full 24h
  with the phone genuinely untouched before checking whether the alarm actually rang, rather than
  only whether it is still registered. Built, self-tested offline, not yet run against a real device.
- **Requirement:** R3

### T-158 · A reboot while the device stays locked can silence the alarm entirely — RESOLVED (2026-09-20), confirmed on a real device

- [x] Found on a real device during T-49's ACCESS_NETWORK_STATE-removal testing: of four scenarios
      tried (open app; backgrounded + locked; reboot with the app closed and the device locked;
      reboot with the app open and the device unlocked), the third did not ring at its scheduled
      time. It rang only after the device was unlocked, roughly two minutes after the alarm's due
      time.
- [x] **Root cause identified, not just observed.** Neither this app's own
      `AndroidManifest.xml` nor the `alarm` plugin's declares `android:directBootAware="true"`, and
      `alarm`'s `BootReceiver` - the component that re-registers the app's `AlarmManager` entries
      after a reboot - listens only for `android.intent.action.BOOT_COMPLETED`, not
      `LOCKED_BOOT_COMPLETED` (confirmed by reading
      `alarm-5.12.0/android/src/main/AndroidManifest.xml` directly; `awesome_notifications` does
      listen for both, but that is its own notification-scheduling receiver, not the one that
      re-arms the actual ringing alarm). On Android's file-based encryption, a non-direct-boot-aware
      app's `BOOT_COMPLETED` is not merely delayed but **withheld by the OS entirely** until the
      user unlocks the device for the first time after that boot - before that, the app's normal
      (credential-encrypted) storage, including the `SharedPreferences` both this app and the
      `alarm` plugin use to persist scheduled alarms, isn't even decryptable yet. So `BootReceiver`
      cannot run, and the old alarm is not re-registered with `AlarmManager` at all - not "delayed",
      genuinely absent - until that first unlock. The observed ~2-minute lag was very likely just
      the gap between the alarm's due time and the moment the device happened to be unlocked in
      that test, not a fixed system delay: once `BOOT_COMPLETED` is finally delivered, the overdue
      alarm is re-armed and fires almost immediately.
- **Why this matters more than it might look:** this is a real, ordinary-use failure mode for an
  alarm clock, not an edge case like `am force-stop` (R3's already-documented, unfixable platform
  boundary). A phone that reboots overnight for an OTA update or after a crash, and is never
  touched again before the alarm's due time because it's sitting locked on a nightstand, would
  **not ring at all** - a silent total failure of the app's core purpose, with no indication to the
  user that anything went wrong. This may well be the actual mechanism behind R3/T-04's still-open
  "long dormant period, app never reopened" scenario, which had no explanation until now beyond
  "structurally can't be tested in CI" (T-93/T-131).
- [x] **Mitigated (2026-09-20) with a fallback siren, deliberately not a full fix.** Patching the
  third-party `alarm` plugin's own storage/receiver was ruled out as too invasive and fragile to
  depend on undocumented internals of a library this project doesn't own (its `AlarmStorage` uses a
  normal, `Context`-scoped `DataStore` - credential-encrypted like everything else, so it wouldn't
  even help). Instead, this app's own module gained a self-contained, Direct-Boot-safe fallback path
  that never touches the real ring pipeline or any credential-encrypted storage:
  - `lib/utils/direct_boot_mirror.dart` - an injectable seam (same shape as `fetchEvents`/`now`)
    that mirrors the next expected wake-up instant to the native side over a
    `MethodChannel('com.wakeywakey.wakeywakey/direct_boot')`.
  - `AppState.refreshDirectBootFallback()` - computes that instant with the same `nextWakeUpTime`
    (T-66) the bedtime reminder already uses, and calls the mirror. Wired into `_setAlarm`/
    `_stopAlarm` - the one place every real arm/cancel already goes through (manual create/edit/
    toggle, and scheduling-v2's own sync via `applyPlannedAlarms`) - and once after loading
    persisted state at app start, so an app upgrading from a version predating this mirror gets it
    populated immediately rather than waiting for the next alarm change. Unit-tested in
    `test/app_state_direct_boot_fallback_test.dart` (the computation and the seam call - not the
    platform channel itself, which has no implementation in `flutter test`, the same as the rest of
    the `alarm` plugin boundary).
  - `android/app/src/main/kotlin/com/wakeywakey/wakeywakey/DirectBootFallback.kt` - the
    device-protected-storage-backed `SharedPreferences` file both the channel handler
    (`MainActivity.configureFlutterEngine`) and the two receivers below read/write; readable before
    the first unlock, unlike the app's and the `alarm` plugin's normal storage.
  - `DirectBootReceiver.kt` - `directBootAware="true"`, listens for `LOCKED_BOOT_COMPLETED`
    (delivered immediately, unlike `BOOT_COMPLETED`). Reads the mirrored due time and arms a plain
    `AlarmManager.setExactAndAllowWhileIdle` targeting `DirectBootFallbackAlarmReceiver` - firing
    immediately instead of being dropped if the due time has already passed by the time this
    finally runs.
  - `DirectBootFallbackAlarmReceiver.kt` - also `directBootAware`, and deliberately does almost
    nothing itself: it only starts `DirectBootFallbackService` and clears the mirrored due time.
    **A first version (2026-09-20, same day) tried to vibrate and post the notification directly
    from `onReceive` - the maintainer's own real-device test caught this as insufficient within
    hours: a single notification chime and one short vibration, then silence while the device stayed
    locked.** A `BroadcastReceiver.onReceive` runs on the main thread for only a few seconds before
    Android may reclaim it, nowhere near long enough to actually wake anyone - real alarm apps use a
    foreground service for exactly this reason.
  - `DirectBootFallbackService.kt` (added the same day, replacing the receiver's own vibrate/notify
    code) - also `directBootAware`, `foregroundServiceType="mediaPlayback"`. A genuine foreground
    service: loops the system's own default **alarm** ringtone via `MediaPlayer.isLooping = true`
    (not the user's actual tone or volume, since neither is reachable before unlock), vibrates on a
    repeating pattern (`VibrationEffect.createWaveform(pattern, 0)`, repeat index `0` rather than
    `-1`), holds a partial wake lock, and shows an ongoing, undismissable, full-screen-intent
    notification with its own "Stop" action. Capped at ten minutes (`MAX_RING_MILLIS`) as a safety
    net, since nothing here can tell whether anyone is actually present to dismiss it and an
    uncapped foreground service plus wake lock running forever on a bug would be its own hazard.
    Tapping the notification (or the Stop action, or the ten-minute cap) tears everything down and,
    for the tap case, opens `MainActivity` normally; once the user has unlocked to get there, the
    app's own FR-17 recovery takes over for real.
  **Third real-device report, same day: vibration ran continuously, but no sound played at all.**
  The likely cause: `RingtoneManager`'s URI can point at a *custom* alarm sound the user picked in
  system settings, which - unlike a built-in system sound - may live on storage that isn't
  mounted/decryptable yet this early in the boot sequence, so `MediaPlayer.setDataSource`/`prepare`
  failed silently into the existing catch block. Fixed with a three-layer fallback in
  `startLoopingSound()`: try the device's actual chosen alarm sound, then its generic default, and
  only then fall back to a tone synthesized in code via `ToneGenerator` (`AudioManager.STREAM_ALARM`,
  looped by re-triggering `startTone` every 1.5s) - which needs no file or URI at all, so it cannot
  hit this failure mode and is the one sound primitive here actually guaranteed to be
  Direct-Boot-safe. If even the device's own default alarm sound can silently fail to resolve this
  early, the earlier assumption that `RingtoneManager` alone was "Direct-Boot-safe" (this entry's own
  first version) was too optimistic - noted here so the same mistake isn't repeated for some other
  primitive later.
  **Known, deliberate limitation, not an oversight:** a snoozed alarm's postponed instant isn't part
  of `pendingDayValues`/`manualAlarms`, so `nextWakeUpTime` can't see it - a reboot during an active
  snooze is not covered by this mirror (`AppState.refreshDirectBootFallback`'s own doc comment says
  so explicitly). Also: what fires is a generic siren, not the user's actual alarm - by design,
  since the real one needs credential-encrypted settings that don't exist pre-unlock.
  **Fourth real-device report, same day: vibration and sound both worked, but unlocking and letting
  the real ring pipeline take over did not stop the fallback siren** - both ran at once. Nothing had
  ever told `DirectBootFallbackService` to stop except its own notification's dedicated "Stop"
  action; tapping the fallback notification's main body, tapping the *real* alarm's own full-screen
  intent, or just opening the app normally all reached `MainActivity` without going through that
  action at all. **First attempted fix:** `MainActivity.onCreate`/`onNewIntent` unconditionally
  stopping the service - **the maintainer's next real-device report found this changed nothing**,
  meaning the assumption that the real alarm's full-screen intent (or the user tapping something)
  reliably launches or resumes `MainActivity` in a way that actually fires one of those two callbacks
  does not hold in practice (plausibly a background-activity-launch restriction lets the real alarm's
  own notification and service post without its full-screen intent actually being allowed to
  present, so nothing ever reaches `MainActivity` at all).
  **Actual fix:** stop depending on `MainActivity`'s lifecycle at all. `DirectBootFallbackService`
  now dynamically registers a `BroadcastReceiver` for `Intent.ACTION_USER_PRESENT` - the system's own
  unconditional signal that the keyguard was just dismissed, which fires whether or not any activity
  ever launches. This broadcast is implicit and cannot be declared in the manifest (undeliverable to
  manifest-registered receivers since Android 3.1); a running foreground service registering it
  dynamically in `onStartCommand` and unregistering in `onDestroy` is the standard pattern. The
  `MainActivity` stop calls stay in place too, as a harmless extra safety net, but
  `ACTION_USER_PRESENT` is now the reliable path.
- [x] **Confirmed working end-to-end on a real device (2026-09-20).** After five same-day revisions,
  each fixing a gap the previous one's real-device test exposed, the maintainer confirmed: a reboot
  with the device staying locked now produces continuous vibration and an audible, looping sound,
  and unlocking the device silences the fallback immediately via `ACTION_USER_PRESENT` - "jetzt tut
  alles" (now everything works). The merged manifest carries all three components with
  `android:directBootAware="true"` (the service also with `foregroundServiceType="mediaPlayback"`),
  and a real `flutter build apk --release` compiled the Kotlin cleanly at every revision.
- **Evidence:** the maintainer's own four-scenario real-device test (2026-09-20) that found the
  original bug; a second same-day real-device report that the first fallback version's single
  chime/vibration was insufficient; a third same-day real-device report that continuous vibration
  then shipped with no sound at all; a fourth same-day real-device report that the fallback then kept
  running after the real alarm took over; a fifth same-day real-device report that the
  `MainActivity`-lifecycle fix for the fourth report changed nothing; a sixth, confirming report that
  the `ACTION_USER_PRESENT` fix resolved it completely; `alarm-5.12.0/android/src/main/
  AndroidManifest.xml` (`BootReceiver`'s intent-filter, no `directBootAware`);
  `alarm-5.12.0/.../services/AlarmStorage.kt` (a normal, `Context`-scoped `DataStore`, ruling out
  patching the plugin's own storage as the fix); `android/app/src/main/AndroidManifest.xml` (all
  three components, confirmed via the merged manifest); `awesome_notifications-0.12.1/android/src/
  main/AndroidManifest.xml:23-24` (listens for both boot actions, but for its own scheduling
  receiver, not the ringing path).
- **Done when:** the maintainer confirms the fallback fires correctly, audibly, and is silenced by
  unlocking the device on a real device across a reboot-while-locked cycle. **Met (2026-09-20).**
- **Requirement:** R3

### T-159 · The first CI run since the repository went public failed twice, for real reasons — RESOLVED (2026-09-20)

- [x] The repository went public today (2026-09-20, GPLv3's Corresponding Source obligation, T-34) -
      the first time `master`'s CI has actually been able to run in a while, rather than failing in
      seconds on the billing block described in `CLAUDE.md`'s "Branches and where work happens". It
      ran for real and found two genuine, pre-existing problems that a blocked CI had simply never
      had the chance to catch.
- [x] **`test/replan_prunes_scheduled_alarms_test.dart` failed only on the `America/St_Johns`
      (UTC-3:30) leg of the timezone matrix.** Root cause: its `_alarmOn` helper built
      `ScheduledAlarm.time` with the local `DateTime(...)` constructor instead of `DateTime.utc(...)`,
      while the test's `now`/`deviceUtcOffset: Duration.zero` only ever pretend the *domain layer* is
      at UTC+0 - `planAlarmSync`'s own frame-safe `_toMinute()` still converts a genuinely local
      `DateTime` via the real OS timezone (`.toUtc()`), which happened to be a no-op on this dev
      machine (UTC+0) but is not on every CI leg. At `America/St_Johns`, that shifted the fixture's
      alarm by 3.5 hours - enough to flip it from "already past" to "still ahead", which made
      `planAlarmSync`'s safety-critical "never remove a possibly-ringing alarm" check treat it as
      removable. This is exactly the frame-confusion bug class `CLAUDE.md` warns about, just landing
      in a test fixture rather than production code (a real device's own local clock has no such
      cross-frame mismatch - `_toMinute`'s use of the real OS timezone is correct there). Fixed by
      building the fixture with `DateTime.utc(...)`; reproduced locally with `TZ=America/St_Johns
      flutter test test/replan_prunes_scheduled_alarms_test.dart` before the fix and confirmed green
      after, across `America/St_Johns`, `UTC` and `Asia/Tokyo`.
- [x] **All seven `integration_test/app_test.dart` scenarios failed**, each timing out waiting for
      `MyHomePage` to appear. Root cause: T-41 (this same session, earlier) made the privacy policy
      the first screen shown on a clean install, requiring a "Continue" tap before anything else -
      `pumpFreshApp`'s helper (which clears prefs to simulate a clean install) was never updated for
      that and still expected `MyHomePage` to appear directly. This suite had not actually run since
      T-41 landed, for the same reason as above (CI was blocked). Fixed by taping the same
      not-`pumpAndSettle` pattern `test/widget_test.dart`/`test/privacy_before_permissions_test.dart`
      already use (the splash screen's rotation `AnimationController` never lets "no more frames
      scheduled" become true) into `pumpFreshApp` itself, tapping "Continue" when present before
      waiting for `MyHomePage`. **Not verified on a real emulator run** - this suite needs a device/
      emulator this environment doesn't have; the fix mirrors an already-verified pattern exactly,
      but the next `master` CI run is what actually confirms it.
- **Separately noted, not fixed (already deliberately non-gating):** `integration_test/
  silent_notification_test.dart` (T-62) failed with `scheduleNotification` returning `-1`
  ("isAllowed: false") - the *first* time this leg has ever actually run, for the same CI-was-blocked
  reason. `.github/scripts/run_e2e_tests.sh` already runs it with `|| true` specifically because "this
  exact mechanism has never been measured on this emulator image before, and an unverified leg must
  not block a release" - so it correctly had no effect on the job's exit code. Worth a real look
  later (is a notification permission missing from the emulator pre-grant step, or did the T-41
  privacy screen shift something here too), but out of scope for getting `master` green again.
- **Evidence:** run 35511187573 (`gh run view 35511187573 --repo Dam0k1es/wakeywakey`); the
  `America/St_Johns` leg's failure output; the E2E job's "Timed out ... waiting for ... MyHomePage"
  stack traces across all seven `app_test.dart` scenarios.
- [x] **Confirmed green (run 35513763937, 2026-09-20):** every leg passed except
      `silent_notification_test.dart` (T-62), which is the already-known, deliberately non-gating
      failure - correctly had no effect on the job's outcome. `Build Android (production)` and
      `MobSF (full static scan of production APK)` both ran (previously skipped, since they need the
      legs above) and both passed.
- **Done when:** the next `master` push's CI run is green (or fails only on the already-known,
  deliberately non-gating legs). **Met.**
- **Requirement:** R2 (the timezone-matrix fixture bug), R3/R4 (the E2E suite's own coverage)

### T-160 · MobSF flags `DirectBootReceiver` as an unprotected exported component — ACCEPTED (2026-09-24), independently reviewed

- [x] Found while reading run 35513763937 (the first fully green `master` run since the repository
      went public): MobSF's full scan of the production APK now reports 15 WARNING-level findings,
      one more than `docs/REQUIREMENTS.md` R1 currently documents (14). The new one:
      `Broadcast Receiver (com.wakeywakey.wakeywakey.DirectBootReceiver) is not Protected.
      [android:exported=true]` - a direct, expected consequence of T-158's fix, not a regression
      introduced by anything else: `DirectBootReceiver` has to be `exported="true"` for the OS to
      deliver `LOCKED_BOOT_COMPLETED` to it at all (an unexported receiver never gets *any*
      broadcast), so this specific warning was unavoidable the moment T-158 shipped.
- **Why this isn't necessarily a real problem, but needed a real look rather than a shrug:**
      `DirectBootReceiver` accepts no data from the `Intent` other than its action string - it reads
      only the due time already mirrored into its own device-protected `SharedPreferences`
      (`DirectBootFallback.getDueAt`), so there is no obvious injection surface a malicious app could
      exploit by sending it a forged `LOCKED_BOOT_COMPLETED` broadcast early. That reasoning had not
      been independently checked the way the two already-accepted findings in
      `.github/security-exceptions.json` were, though - it was this session's own assessment, not a
      reviewed one.
- **Independently reviewed (2026-09-24) under `CLAUDE.md`'s new "Philipp, the Security Researcher"
  review persona, and closed.** The load-bearing question was verified, not assumed:
  `android.intent.action.LOCKED_BOOT_COMPLETED` is itself a **protected broadcast action**, declared
  as such in AOSP's own `frameworks/base/core/res/AndroidManifest.xml`
  (`<protected-broadcast android:name="android.intent.action.LOCKED_BOOT_COMPLETED" />`) - the exact
  same platform-enforced protection `BOOT_COMPLETED` itself relies on, and which the `alarm` plugin's
  own `BootReceiver` already depends on elsewhere in this app, unexamined. That protection is
  enforced by `system_server` at the *sender's* side, before delivery - an ordinary third-party app
  calling `sendBroadcast()` with this action gets a `SecurityException` from the OS itself; only
  system/platform-signed code can originate it. No `android:permission` this app could declare would
  add anything on top of an OS-level check that cannot be targeted by app code at all - which also
  means the textbook "exported receiver, no explicit permission" fix is not merely extra cost here,
  it is **incoherent for this specific action**: the legitimate sender (the OS) is not signed with
  this app's key, so a signature-level permission would either do nothing or actively break the
  feature. Combined with the receiver's own narrow behaviour (no Intent data used beyond the action
  string; the due time comes only from this app's own private storage), the review's verdict was
  **accept, not fix** - the worst case even under a hypothetical bypass (itself requiring
  platform-signature privilege, at which point this receiver is the least of the attacker's
  capabilities) is an early, bounded, non-destructive 10-minute fallback siren using the system's own
  default alarm sound.
- **Resolution:** accepted into `.github/security-exceptions.json` with the full, dated technical
  rationale above (verbatim from the review). `docs/REQUIREMENTS.md` R1 updated to describe three
  accepted findings instead of two, and its status changed from "partially met" (pending this
  triage) to "met" - noting explicitly that a WARNING-severity MobSF finding was never gating under
  R1's own "high-or-above" bar in the first place, so this entry exists for the documented rationale
  and audit trail, not because anything was actually blocked.
- **Evidence:** run 35513763937, job `MobSF (full static scan of production APK)`
      (`gh api /repos/Dam0k1es/wakeywakey/actions/jobs/106089892754/logs`); `android/app/src/main/
      AndroidManifest.xml` (`DirectBootReceiver`'s `android:exported="true"`, required for
      `LOCKED_BOOT_COMPLETED` delivery); the independent review's AOSP source citation
      (`frameworks/base/core/res/AndroidManifest.xml`'s `<protected-broadcast>` list).
- **Requirement:** R1

### T-161 · Independent external-auditor review (licence/legal + shift-worker/business fitness) — REVIEWED (2026-09-24), one open item

- [x] Ran a full independent audit under the new "External Compliance & Fitness-for-Purpose Auditor"
  review persona (`CLAUDE.md`), using a fresh review agent with no prior context on this project -
  see that persona's own entry for its mandate and working method.
- **Mandate 1 (licence/legal): signed off, no material caveats.** The auditor independently verified
  - not merely cited - the GPLv3 dependency-compatibility claim (checked actual `LICENSE` files in
  `~/.pub-cache` for every direct/notable transitive dependency), the licence-header coverage across
  all of `lib/`, the "fully offline" claim (grepped for network calls, confirmed `INTERNET`/
  `ACCESS_NETWORK_STATE` are absent from the merged manifest, not merely unused), and the PII-free
  diagnostics-log design. All held up. Two disclosure items, not defects, acted on below.
- **Mandate 2 (shift-worker/business fitness, Marie/Tom from `docs/personas.md`): NOT signed off
  unconditionally.** The auditor's blocking finding: `docs/REQUIREMENTS.md` R3 stated the 2026-09-18
  "force-stop loses the alarm" observation as a settled, unfixable platform guarantee without ever
  being updated to reflect that T-93's independently-scripted measurement the very next day found
  the opposite (alarms still registered after force-stop) - an unreconciled contradiction in the
  project's own most safety-critical claim. **Fixed:** R3 rewritten to state the force-stop question
  as genuinely unresolved rather than settled either way (see R3 and T-93's own entry for the
  corrected text); this TODO entry and T-93 cross-reference each other. **Still open, and requires a
  real device** (cannot be done from this environment): a clean, longer-wait re-run of
  `check_alarm_survival.sh`, ideally cross-checked against an actual ring, to close the
  disagreement. Until then the auditor's own words stand: *"do not rely on this app as a sole alarm
  for a shift a person cannot afford to miss."*
- **Two more findings, both fixed as documentation corrections:**
  1. `docs/USER_GUIDE.md` claimed the optional diagnostics clock-time switch (`Diag.dayPlanned`,
     T-135) records "bucketed, not exact clock times" - false; it records an exact minute-of-day.
     The in-app Settings > Diagnostics text already said this correctly; only the external guide was
     wrong. Fixed to match.
  2. `assets/text/Privacy.md` had the same omission more absolutely ("no wake-up times, no dates or
     times of day... at all") with no mention of that same opt-in exception, and separately still
     claimed the app "declares an internet-access permission" - stale since T-33/T-101 removed both
     `INTERNET` and `ACCESS_NETWORK_STATE` from the manifest entirely. Both fixed; `Last updated`
     bumped.
- **One finding investigated and deliberately left as-is, with the reasoning recorded so it isn't
  re-investigated from scratch:** the auditor flagged the unused `WRITE_CALENDAR` permission
  (already known since T-17) as worth removing now that it's confirmed vestigial. Checked whether
  that's actually a safe, isolated manifest edit: it is not. `permission_handler`'s Android
  implementation has no "calendar, read-only" request - `Permission.calendarFullAccess`
  (`lib/utils/permissions.dart:139`) is the only option that yields `READ_CALENDAR`, and it requests
  `WRITE_CALENDAR` in the same runtime dialog (verified against
  `permission_handler_android`'s `PermissionConstants.java`: `calendarFullAccess` = read+write,
  there is no read-only Android constant). Removing the manifest declaration while still calling
  `calendarFullAccess` would leave the runtime request asking for a permission the manifest no
  longer declares - undefined/likely-broken behaviour that needs a real device to verify safely, not
  a same-session doc-review fix.
- **Decided (maintainer, 2026-09-24): accepted, not fixed.** `WRITE_CALENDAR` stays declared as the
  necessary cost of `permission_handler`'s only available "read calendar" request shape on Android,
  per the reasoning above - a real fix would mean switching `permission_handler` versions/APIs or
  forking the read/write split, neither of which is planned. Accepting a declared-but-unused
  permission is only defensible for as long as the code genuinely never exercises the write half of
  what it grants, so that claim is no longer just asserted: `test/no_calendar_write_test.dart` (new)
  forbids every `device_calendar` write method (`createOrUpdateEvent`, `deleteEvent`,
  `deleteEventInstance`, `createCalendar`, `deleteCalendar` - the package's full write surface) from
  being called anywhere in `lib/`, the same "forbid the channel, not the symptom" shape as
  `test/no_proprietary_dependencies_test.dart`/`test/diag_log_api_test.dart`. Confirmed red against
  the real codebase before being accepted: temporarily un-commenting the one existing (dead)
  `createOrUpdateEvent` call in `lib/screens/schedule/calendar.dart:204` made the test fail exactly
  as intended, then the file was restored unchanged. `docs/licence-position.md`/R11 should cite this
  test, not just the manifest comment, as what backs the "read-only in practice" claim going
  forward.
- **Requirement:** R3, R9, R11

### T-162 · A re-entrant `Diag.init()` corrupts the diagnostics log mid-session — FIXED (2026-09-24)

- [x] Found by reading a real, maintainer-exported diagnostics log with clock-time logging on
  (68 events), not by code review: three lines (`boot`, the first `checkpointStarted trigger=1`,
  the first `checkpointSkipped trigger=1`) appeared **twice**, byte-identical, at the exact same
  `b<boot>.<seq>` coordinates; the persisted boot counter jumped from 202 to 203 mid-session with
  **no corresponding `boot()` event**; and every event from that point on was mis-tagged `(bg)`,
  including `calendarRead`/`weekPlanComputed`/`alarmSync` - events `runTimezoneCheckpoint2` (the
  actual background-isolate function) structurally never calls.
- **Root cause:** `lib/utils/notifications.dart`'s `onNotificationCreatedMethod` calls
  `Diag.init(isolate: LogIsolate.background)`, documented (correctly, as far as it goes) as safe
  because that callback "runs in its own background isolate with no `AppState`". That is true only
  when the app process wasn't already running when the notification fired. `awesome_notifications`
  also invokes the same callback **in-process, in the app's own isolate**, whenever the app is alive
  when a notification it just created is created - and `checkpoint.dart`'s `runSchedulingCheckpoint`
  does exactly that on **every single checkpoint**, via `scheduleSleepReminder()` in its `finally`
  block, right before logging `checkpointFinished`. `Diag.init()`
  (`lib/utils/diag/diag_log.dart:457-467`, unconditionally overwrote the shared static `_isolate`
  and bumped+persisted the shared static `_boot` counter with no protection against a second,
  in-process call. Because `flush()` persists the CURRENT contents of the whole ring buffer under
  whichever key `_isolate` currently selects (not just newly-added records), records logged before
  the corruption ended up written under **both** prefs keys, and `readAll()`'s merge had no
  deduplication - so they were exported twice.
- **Fixed at the source:** `Diag.init()` is now a no-op if `_boot != 0` - a genuinely fresh isolate's
  static state has never been touched, so `_boot` is still its initial `0`; a second call within an
  isolate that already has an identity means it never actually left that isolate. Verified this
  doesn't break the real fresh-background-isolate case (a notification firing while the app process
  isn't running at all), which still needs its own identity.
- **Hardened defensively too:** `readAll()` now deduplicates by `(boot, seq)` - not just prevents
  future corruption, but heals a log that was already corrupted on a device before this fix shipped,
  instead of exporting doubled events forever until the user clears it.
- **Evidence/tests:** `test/diag_log_reentrant_init_test.dart` - reproduces the bug against the
  pre-fix code (confirmed red: boot bumped, export duplicated) before the fix, then green after;
  separately confirms a genuinely fresh background isolate is unaffected, and that `readAll()`
  collapses an already-duplicated `(boot, seq)` pair seeded directly into mock prefs (the shape a
  pre-fix device's persisted state is actually in).
- **Not itself a PII or reliability bug** - the log stayed structurally PII-free throughout (the
  duplicated/mistagged records carried no more information than correct ones would have), and the
  scheduling engine's own behaviour visible in that log (alarm counts, plan-vs-floor relationships
  across all seven window days, `alarmSync`'s desired/existing counts) was entirely healthy - but a
  diagnostics log that mislabels its own isolate and phantom-increments its own boot counter
  undermines exactly the kind of investigation it exists to support, which is why this was worth
  fixing immediately rather than only documenting.

### T-163 · Enrich the opt-in diagnostics log with per-event calendar times — IMPLEMENTED (2026-09-24)

- [x] Maintainer request, explicit: since the wake/appointment-time logging (T-135) is already
  opt-in, the log may carry a bit more while investigating a scheduling problem - **on the express
  condition that calendar content stays out**: no title, no description, no attendees, no location.
  Times are fine.
- **Why:** `Diag.dayPlanned` already logs each window day's planned wake time and its single
  earliest appointment, but only the one `hardFloor` picked as earliest - not what the day's other
  real candidates were. A wrong pick (an all-day or ignored event miscounted, or the wrong one
  winning among several genuine candidates) could previously only be diagnosed by re-deriving the
  whole candidate set from a fresh calendar read; the log itself couldn't show it.
- **Implementation:** new `Diag.dayEventTime({dayOffset, startMinuteOfDay, endMinuteOfDay})`
  (`lib/utils/diag/diag_log.dart`), gated behind the exact same `Diag.includeClockTimes` switch as
  `dayPlanned` - not a new, third toggle, since it's the same privacy boundary (exact times,
  opt-in, off by default). One record per real, non-all-day, non-ignored calendar event within the
  planning window (not one per day) - `replan.dart`'s existing `dayPlanned` loop already computes
  exactly that list (`eventsForDay(...).removeWhere((e) => e.isAllDay)`, on `allEvents`, which is
  already filtered to exclude ignored events before this layer ever sees it) to find the day's
  earliest event; it now also emits one `dayEventTime` per entry in that same list, not just the
  earliest. An all-day event is never logged this way (no meaningful minute-of-day, and it never
  sets the hard floor either); an ignored event never reaches this code path at all, by the same
  filter that already protects `hardFloor` itself.
- **The boundary that does not move:** the two new `DiagField`s (`eventStartMinuteOfDay`,
  `eventEndMinuteOfDay`) are minute-of-day integers, nothing else - `test/diag_log_api_test.dart`'s
  source-reading guard (which forbids any `String` parameter on the public recording API, and any
  `int` parameter that looks clock-shaped unless explicitly listed and justified) was extended to
  allow exactly these two names, with the same reasoning recorded inline it already carries for
  `dayPlanned`'s own two.
- **Documented transparently, per the maintainer's explicit instruction:** the in-app Settings >
  Diagnostics screen (`lib/screens/settings/page_diagnostics.dart`), `docs/USER_GUIDE.md`, and
  `assets/text/Privacy.md` were all updated together to describe exactly what the switch now adds
  (event start/end times) and to restate, in each place, that calendar content - title,
  description, attendees, location, which calendar - is excluded regardless of the switch, not
  merely by default. `CLAUDE.md`'s diagnostics section records the same boundary for future
  changes to this file.
- **Tests:** `test/diag_log_test.dart` (new group "per-event calendar times (T-163)") covers the
  opt-in gate, one-record-per-event, and the "switch off → no-op" counter-case, mirroring
  `dayPlanned`'s own existing group; `test/replan_test.dart` (new group "T-163: per-event calendar
  times reach Diag when opted in") covers the actual wiring end to end against `replan()` - every
  non-all-day event in a day is logged (not just the earliest), an all-day event produces nothing,
  and nothing is logged with the switch off.
- **Requirement:** none directly (a diagnostics/quality-assurance feature, not a product
  requirement), but touches the same PII boundary as R11/the Privacy Policy - see that document's
  own update.

### T-164 · A scripted, repeatable long-idle alarm survival check — TOOL BUILT (2026-09-24), not yet run

- [x] Maintainer question: how long would the app need to be inactive for a real-device alarm-
  survival test to be robust evidence, and could it be turned into a script they can run themselves?
- **Why 24 hours, not less:** `scripts/verify-alarm-survival.sh` (T-04/T-93) already shows an
  alarm's registration surviving a reboot/force-stop within a few seconds - a shorter idle period
  would not be new evidence, only a re-run of what's already measured. The alarm plugin registers
  with `setExactAndAllowWhileIdle`, which is documented to bypass standard Doze restrictions
  regardless of how long the device has been idle - so no Android platform threshold specifically
  demands 24h. The real, documented risk class for alarm apps is OEM-specific aggressive background/
  battery-optimisation killing, which is not duration-gated in any official, verifiable way either.
  24h was chosen instead because it is the realistic worst case for this app's actual audience
  (`docs/personas.md`'s Marie, a shift worker): a phone rebooted or force-stopped and then genuinely
  left alone for a full day between shifts, not reopened even briefly - exactly the one scenario
  T-04's own "still open" bullet names, and exactly what T-93's own registration-only check cannot
  reach. 48h (spanning a weekend) would be more robust still, but was left for a possible follow-up
  run rather than built into the first version - see "Not built, deliberately" below.
- **Implementation:** `scripts/verify-long-idle-alarm-survival.sh`, split into two subcommands
  because a single script cannot sleep for a day without tying up a terminal (and this session's own
  tooling refuses long blind sleeps for exactly that reason):
  - `arm [--apk PATH] [--yes]` - reuses the exact same UI-driven arming as
    `scripts/verify-alarm-survival.sh` (~24h out, by not touching the pre-filled time and letting
    `AppState` roll it to the next day), then reboots, waits for boot, and force-stops - the combined
    worst case, and a direct, repeatable attempt at T-93's own unresolved contradiction (one
    real-device run said force-stop loses the alarm, a later one said it survives). It then stops:
    no sleep, just a printed "do not touch the phone before &lt;timestamp&gt;" instruction and a
    `resume.env` marker file in the evidence directory.
  - `check <evidence-dir> [--force]` - run separately, after the printed time has passed. Re-reads
    `dumpsys alarm` as a weak corroborating signal only (a fired one-shot alarm removes its own
    registration, so "gone" is consistent with, but not proof of, actually ringing - the log says so
    explicitly rather than claiming more than it can). The actual verdict comes from asking directly
    whether the phone rang, and whether the diagnostics log (if both switches were on) shows an
    `alarmRang` event - the same standard every other real-device confirmation in this project was
    measured against, not a new automated detection heuristic.
- **Shared code, not duplicated:** `node_center`/`ui_dump`/`tap_label`/`ui_self_test` were extracted
  from `scripts/verify-alarm-survival.sh` into `.github/scripts/ui_tap.sh` (parallel to
  `.github/scripts/alarm_detection.sh`'s own existing counting logic) so both scripts share one
  tested implementation - the same reasoning `alarm_detection.sh`'s own header already gives for why
  a second copy is a second chance to repeat T-99/T-103. `scripts/verify-alarm-survival.sh`'s own
  behaviour is unchanged by the refactor; its `--self-test` still passes.
- **`--self-test`:** checks the reused detection and UI-tap self-tests (against the same recorded
  fixtures) plus this script's own new logic - the pure `enough_time_passed()` timestamp arithmetic
  the `check` gate depends on - all without a device, following this project's standing convention
  for exactly this class of script.
- **Not built, deliberately:** a way to arm an alarm further than ~24h out (e.g. 48h for a weekend-
  spanning test) would need to drive the time picker's day/date rather than only rely on the
  "leave the pre-filled time alone" trick, which is meaningfully more UI-automation surface to get
  right without a device to verify it against in this environment. If 24h's result needs
  corroborating further, the straightforward path is simply running `arm` again on a later occasion,
  not stretching a single run.
- **Evidence:** none yet - this entry only records that the tool now exists and passed its own
  offline self-test (`bash scripts/verify-long-idle-alarm-survival.sh --self-test`). It has not been
  run against a real device.
- **Done when:** run once for real, with the phone genuinely left alone for the full 24h, and the
  result recorded here and cross-referenced from T-04/T-93/R3 - the same way every other real-device
  finding in this project is captured.
- **Postponed to the next version (maintainer, 2026-09-24):** not a blocker for the current release
  state - the maintainer plans to run it with an idle period longer than the 24h minimum this tool
  was built for.
- **Requirement:** R3

### T-165 · The `alarm` plugin's exported `AlarmReceiver` could silence a ringing alarm without the QR code — FIXED (2026-09-24), build-verified

- [x] Found by a full-project security assessment under `CLAUDE.md`'s security-researcher review
  persona (`docs/security-assessment-2026-09.md`, Finding F1): the `alarm` plugin (5.12.0) declares
  its own `AlarmReceiver` (`com.gdelataillade.alarm.alarm.AlarmReceiver`) as
  `android:exported="true"` with no `android:permission` - reachable by any other installed app via
  an explicit broadcast naming the component directly. Its `ACTION_STOP` handler
  (`AlarmService.handleStopAlarmCommand`) fully silences a ringing alarm - audio, vibration,
  foreground-service teardown - with **no check of any kind**, completely bypassing this app's
  QR-scan "guaranteed wake-up" gate, which lives entirely in the Dart layer and is never consulted
  by this native receiver. The plugin's own `ACTION_SNOOZE` branch has a narrow guard specifically
  because its authors know the receiver is exported to the world; no equivalent guard exists for
  `ACTION_STOP` - the one action that fully defeats "guaranteed wake-up" was the one left completely
  unguarded.
- **A load-bearing correction made during remediation, before accepting the finding as first
  written:** the initial draft rated this **High**, on the theory that an app holding Android's
  Notification-access permission could extract the ringing alarm's Stop-button `PendingIntent`
  straight from the notification and re-fire it with no ID-guessing needed. That mechanism is real
  in general (Android's own security docs name it explicitly), but checking it against *this
  app's own* configuration - not the plugin's general capability - found it does not apply here:
  `lib/models/alarms/ringing_alarm_settings.dart` never sets a `stopButton`/`androidSnoozeButton` on
  its `NotificationSettings` (a deliberate T-147 choice, unrelated to this finding, that turns out to
  also close this path as a side effect), and the plugin's own `NotificationService.kt` only attaches
  the Stop/Snooze action - and their `PendingIntent`s - to a notification when those fields are
  non-null. **There is therefore no Stop/Snooze `PendingIntent` in any notification this app ships**
  for a Notification-access-holding app to extract. Severity revised to **Medium**: the remaining
  realistic path is a permissionless app brute-forcing the ~10^8-value alarm-ID space via direct
  explicit broadcasts during the ringing window - real, and needing no special permission, but not
  the "instant, no guessing" scenario first assumed.
- **Fixed regardless of the severity revision**, because the fix is cheap and the remaining path is
  still a genuine, zero-permission bypass of the app's core promise: an `AndroidManifest.xml`
  override, using the exact `tools:replace` pattern this file already uses for the camera
  `<uses-feature>` entries -
  ```xml
  <receiver
      android:name="com.gdelataillade.alarm.alarm.AlarmReceiver"
      android:exported="false"
      tools:replace="android:exported" />
  ```
  Confirmed safe (not just assumed): `AlarmManager`'s own delivery of a scheduled alarm, and this
  app's own Dart-side `Alarm.stop()`/`Alarm.snooze()` calls, both resolve to the app addressing its
  own component - unaffected by `exported="false"`, which only blocks a *foreign app's own*
  `sendBroadcast()` call reaching an unexported receiver, not a `PendingIntent` a process already
  holds (irrelevant here regardless, per the correction above, since no such `PendingIntent` is ever
  exposed).
- **Build-verified, not just applied:** a real `flutter build apk --release` was run against the
  patched manifest. The Gradle manifest merger's own blame report
  (`build/app/outputs/logs/manifest-merger-release-report.txt`) confirms `android:exported` was
  `ADDED` from the app's own manifest and `REJECTED` from the `alarm` plugin's, and the final merged
  manifest shows `AlarmReceiver` with `android:exported="false"` in the actual buildable output, not
  merely in the source file.
- **Regression-guarded:** `test/alarm_receiver_not_exported_test.dart` (new, source-reading, in the
  shape of `test/no_proprietary_dependencies_test.dart`) asserts the override is present with
  `tools:replace`, so a future manifest edit can't silently drop it. Confirmed against `git show` on
  the pre-fix commit that this test would have failed against the original manifest (the component
  name did not appear in it at all).
- **Confirmed on a real device (2026-09-24, maintainer):** both Snooze and Stop were tested after
  this change and work; the maintainer has been running the alarm on that device for several days
  since with no problems. Given the app never exposes a Stop/Snooze notification action to begin
  with (see above), there was nothing native-UI-side this change could plausibly break for either,
  and both exercise the same `AlarmService`/`AlarmReceiver` code path this fix touches.
- **Full writeup, including the corrected exploitation-path analysis, PoC-level evidence, and every
  other finding from the same assessment:** `docs/security-assessment-2026-09.md`.
- **Requirement:** none directly (no formal requirement currently covers third-party native-plugin
  IPC exposure) - closest is R4 (alarm-ringing prerequisites), whose "guaranteed" caveat this finding
  sits directly underneath.

### T-166 · Sleep-Habits' always-visible hint texts merged into the T-20 help buttons — FIXED (2026-09-24)

- [x] Maintainer request: now that every Sleep-Habits option has a "?" help button (T-20), four
  small, always-visible grey hint texts sitting directly in the layout - an enforced-minimum note
  under "Max. daily shift" (T-88) and under "Ramp duration" (T-96), a snooze-budget note under
  "Duration to wake up" (FR-20), and a no-QR-code/budget-exhausted note under "Snooze time" (FR-20) -
  became a second, redundant explanation channel for information the help text can now carry
  instead. Removed from the layout, with their content merged into the corresponding tile's `help`
  string rather than simply deleted - explicitly checked, not assumed, since the two channels
  didn't always say quite the same thing (the "Duration to wake up" help text already mentioned the
  snooze-budget connection in passing; the inline hint had the fuller "why" - the merge keeps the
  fact, not the full reasoning, to stay inside T-20's own 140-character phone-screen budget).
- **The four merges, old inline hint → what actually made it into the help text:**
  - "Max. daily shift": "At least 00:15 h - smaller values are raised to that." → folded in
    verbatim in substance ("Minimum 00:15; smaller values are raised to that.").
  - "Duration to wake up": the snooze-budget connection kept ("...and your snooze budget - all
    snoozes together may use at most this much"); the extra reasoning ("so the time you need to get
    ready stays untouched") dropped for space - the actionable fact survives, the mechanism behind
    it doesn't.
  - "Ramp duration" (Gentle WakeUp): "At least 00:01 h..." → "Minimum 00:01 - the alarm stays quiet
    at least that long."
  - "Snooze time": both facts kept ("Never needs a QR code, and stops once that budget is used
    up"), the "only moves it, doesn't switch off" framing dropped as inferable from "postpones".
- **Guarded, not just asserted:** `test/screen_sleephabits_help_test.dart` gained a new group
  specifically asserting the merged content is still present in each of the four affected help
  texts (`00:15`, `snooze`, `00:01`, `QR` + `used up`) - a source-reading or count-only test would
  have missed information quietly being dropped during the merge, which is exactly the failure mode
  a "content survived" guard exists to catch. `test/sleep_habits_order_test.dart`'s now-obsolete
  "the minimum hint stays with Max. daily shift" test (which asserted the *old*, now-removed inline
  widget) was removed rather than left to bit-rot into a permanent failure.
- **Requirement:** none directly - a UI-consolidation request, not a defect.

### T-167 · Bundled alarm-tone names didn't all describe the sound — FIXED (2026-09-24)

- [x] Maintainer feedback: "die bisherigen Töne sind meiner Meinung nach nicht alle sinnvoll
  benannt. vor allem wakey wakey und wakey wakey 2 passen gar nicht" - two of the six bundled tones
  were named after the app itself, not the sound, and one other ("LolliPop") didn't describe its
  sound either.
- **Grounded in the actual source, not guessed:** `assets/sounds/CREDITS.md` already records each
  file's real Mixkit title (kept from the T-29 audio swap, when the file names but not their
  content changed). The new display names are drawn from those:

  | File | Mixkit title | Old name | New name |
  |---|---|---|---|
  | `annoying_alarm.mp3` | Classic alarm | Annoying Alarm | *(unchanged - already sensible)* |
  | `lollipop.mp3` | Game notification wave alarm | LolliPop | Playful Chime |
  | `old_telephone_ring.mp3` | Vintage warning alarm | Old Telephone | *(unchanged)* |
  | `wake_up.mp3` | Alarm clock beep | Wake UP | Wake Up *(capitalisation only)* |
  | `wakeywakey.mp3` | Rooster crowing in the morning | WakeyWakey | Rooster Crow |
  | `wakeywakey2.mp3` | Critical alarm | WakeyWakey 2 | Critical Alarm |

  File names/paths are unchanged - only the six display strings.
- **Found and fixed a real duplication while touching this:** the six name/path pairs were
  hardcoded independently in two places - `screen_alarms.dart`'s `_bundledTones` (the add/edit
  dialog's dropdown, extracted for exactly this drift risk when T-56 shipped) and
  `page_alarmtones.dart`'s six separate `_buildToggle(...)` calls, which T-56 never updated to
  match. Renaming in only one would have left the two screens disagreeing. Consolidated into a new
  `lib/models/alarms/bundled_tones.dart` (public `bundledTones`), imported by both - the same "a
  second copy is a second chance to drift apart" reasoning this project already applies to
  `alarm_detection.sh`/`ui_tap.sh` and the no-proprietary-dependency/diagnostics-log guards.
- **Tests:** `test/bundled_tones_test.dart` (new) - a plain check that the list itself no longer
  names a tone after the app and has no duplicate names, plus a widget test per screen (Settings >
  Alarm Tones, and the manual-alarm dialog's tone dropdown) confirming every current name actually
  renders and neither old "WakeyWakey" name does. The dropdown case needed `tester.ensureVisible()`
  before opening it - the add-alarm dialog scrolls, the same fix this project's other dialog tests
  already needed for the same reason.
- **Requirement:** none directly - a naming/consistency request, not a defect.

### T-168 · Four test-coverage gaps found by a three-way independent review — CLOSED (2026-09-24)

- [x] Maintainer request: before promoting to `master`, independently re-check (a) every test
  touched since the last `master` commit against the requirements it claims to satisfy, (b) every
  doc touched in that range against the actual code, and (c) a fresh, context-free read of the
  repository as an outside visitor would experience it. Run as three parallel, genuinely
  independent review agents (none of them the agent that wrote the code under review), covering
  commit range `bb6f0817..14cff5d` (22 commits).
- **Doc-accuracy findings, fixed as documentation-only changes** (`bcd18d4`): `CLAUDE.md`'s test
  count had gone stale again (two commits in the same range each added a test file without
  updating it - the exact failure mode this section exists to avoid); `docs/security-assessment-
  2026-09.md`'s Confidentiality section claimed the report needed to stay confidential "until
  public release", which was already false when written (the repository has been public and v1.0.0
  released since 2026-09-20, four days earlier) - corrected in place, not silently rewritten, since
  the original claim had already shipped to a public branch; and Philipp's stated mandate ("one
  finding, not a whole-project sweep") was reconciled with how the persona was actually used to
  produce that same assessment - a maintainer-commissioned exception, not an out-of-mandate use.
- **Test-coverage findings, all four closed test-first** (red confirmed via a deliberately
  injected regression, then reverted, for each - not just written and assumed to matter):
  1. `scripts/check_proprietary_native_deps.py` (T-144) was the one verdict-producing script in
     the project without a self-test of its own kind, unlike `.github/scripts/alarm_detection.sh`.
     Added `--self-test` (synthetic BOM components covering every `FORBIDDEN` entry, plus the
     precision cases proving this is a (group, name-prefix) match and not a whole-group ban);
     confirmed it catches a broken prefix check (`startswith` → `endswith`) that the previous,
     self-test-less script would have shipped silently. Wired into `ci.yml`'s UTC leg alongside
     the alarm-survival self-test - no SBOM/Android build needed, so it belongs in the fast lane.
  2. T-163's diagnostics-log group never tested that an ignored event (T-149) stays excluded from
     `Diag.dayEventTime` - the code already filters it correctly (once, upstream, before
     `eventsForDay`/`hardFloor` ever see it), but nothing proved that. New case in
     `test/replan_test.dart` confirmed red against the filter removed.
  3. T-56's orphaned-tone fallback (`test/screen_alarms_orphaned_tone_test.dart`) only ever
     exercised a pre-T-56 dead custom-tone path, never the case of a *bundled* tone's asset path
     being removed from the list entirely (low real-world risk today - T-167's rename only touched
     display strings, not paths - but the gap was real). New case added, confirmed red with the
     fallback disabled.
  4. T-160's accepted-risk rationale for `DirectBootReceiver` ("reads no Intent data beyond the
     action string") had no regression guard, unlike its sibling fix T-165. New source-reading
     test `test/direct_boot_receiver_no_intent_data_test.dart` (same shape as
     `test/alarm_receiver_not_exported_test.dart`) forbids every `Intent.get*Extra`/`.data`/
     `.extras` call in `onReceive`'s body while confirming `.action` is still read; confirmed red
     against an injected `getStringExtra` call.
- **Requirement:** none directly - a test/documentation-quality pass, not a defect fix.

### T-169 · Project renamed: WakeyWakey → Crescendo Alarm — DONE (2026-09-25)

- [x] Maintainer-requested rebrand. No version bump (stays `1.1.0+2`) - this is a rename, not a
  feature release, and the maintainer explicitly asked that it not read as one.
- **Naming clearance done first, before any code changed:** two independent research passes (one
  by this session, one by a fresh agent given no prior context) both concluded LOW trademark/
  naming risk - no product named exactly "Crescendo Alarm" exists anywhere (Play Store, App Store,
  F-Droid, USPTO/Trademarkia), "crescendo" is already used descriptively/generically across the
  alarm-app category by unrelated competitors, and the closest registered marks (NCH Software's
  "Crescendo" music-notation app; Crescendo Interactive's nonprofit-fundraising-software family;
  a record label's media-only registration) sit in unrelated goods/services categories. Not legal
  advice, and disproportionate to formally clear further for a non-commercial GPL hobby project.
- **Backed up before touching anything:** tag `pre-crescendo-rename-2026-09-25` and branch
  `pre-crescendo-rename-backup`, both on the pre-rename `master` HEAD (`4bd3ceb`), pushed and
  verified on origin before any rename edit began.
- **Scope, done in verified phases** (`flutter analyze`/`test`/`build apk --debug` after each):
  Dart package `wakeywakey` → `crescendo_alarm` (every import across `lib/`/`test/`/
  `integration_test/`); Android `applicationId`/`namespace` `com.wakeywakey.wakeywakey` →
  `com.crescendoalarm.crescendoalarm` (Kotlin source directory moved and repackaged, the
  `DirectBootFallback` `MethodChannel` string updated on both the Dart and Kotlin sides, the
  `DirectBootReceiver` finding key in `.github/security-exceptions.json` updated to match what
  MobSF now reports, CI/local verification scripts' `PACKAGE` defaults updated); iOS and Linux
  scaffolding updated too for completeness, though neither is a real deployment target; the CI
  signing keystore filename (`wakeywakey-release.jks` → `crescendo-alarm-release.jks` in both
  `ci.yml` and `release.yml`); every user-facing UI string (About page, app title, notification
  titles, diagnostics export header, deactivation-code semantics label) and the GPLv3 licence
  header text in all 54 `lib/` source files; living docs (`CLAUDE.md`, `README.md`,
  `docs/REQUIREMENTS.md`, `docs/licence-position.md`, `docs/use-cases.md`,
  `docs/device-trial-checklist.md`, `docs/threat-model.svg` + regenerated `docs/risk.png`); and the
  GitHub repository itself, `Dam0k1es/wakeywakey` → `Dam0k1es/crescendo-alarm` (both worktrees'
  `origin` remotes updated afterward).
- **Deliberately left as point-in-time historical record, not silently rewritten:**
  `docs/security-assessment-2026-09.md`'s body (a frozen, dated security report) got a naming note
  instead of having its ~22 in-body "WakeyWakey" references rewritten, so it still accurately
  describes what was assessed under its original name; this file's own quoted historical
  commands/output/filenames (e.g. `UML_WakeyWakey.drawio`, exact `dumpsys`/`gh api` quotes from
  past entries) are exact records of specific past events, not generic prose, and stayed as
  recorded; `assets/sounds/CREDITS.md` and `bundled_tones.dart`'s comment - `wakeywakey.mp3`/
  `wakeywakey2.mp3` are real, unchanged asset filenames (T-167 kept paths stable on purpose), and
  the retired tone display names "WakeyWakey"/"WakeyWakey 2" quoted there are historical fact, not
  the current app name; `.github/scripts/alarm_detection.sh`'s self-test package variable and
  `.github/scripts/fixtures/*` - these test detection logic against real, historical `dumpsys`/
  `uiautomator` recordings made under the old package name, which must stay exactly as recorded or
  the self-test would silently stop testing what it claims to; and `CLAUDE.md`'s real local
  filesystem paths (`/mnt/wakeywakey`, the `~/projects/wakeywakey` example) - environment/
  infrastructure on this dev VM, not part of the project's own identity.
- **Verified at every layer, not assumed:** `flutter analyze` clean, full suite green (543/543),
  a local `flutter build apk --debug` confirmed the new `applicationId` via `aapt2 dump badging`
  before anything was pushed, `actionlint` reported no new findings, `.github/security-
  exceptions.json` stayed valid JSON, and both `.github/scripts/alarm_detection.sh --self-test`
  and `scripts/check_proprietary_native_deps.py --self-test` still passed. After push: `dev`'s own
  seven required checks green, then `master`'s full gate (security-gate, the real E2E emulator
  suite, the signed production build under the new keystore filename, and a full MobSF scan
  against the new `applicationId`) all green on the first real attempt - confirming the
  `security-exceptions.json` key update actually matched MobSF's new finding text, not just in
  theory.
- **Known, accepted consequence - not swept under the rug:** a changed `applicationId` is a
  different app to Android. The maintainer's already-flashed production install cannot update
  in place; it needs manual uninstall (losing all local data - alarms, settings) and a fresh
  install of the new build. No trivial on-device data dump/import path exists for this (checked
  and confirmed separately before the rename started - would need root, a debuggable build, or a
  purpose-built export/import feature, none of which apply here). Accepted by the maintainer in
  advance, in exchange for the new `applicationId` rather than keeping the old one under a new
  display name.
- **Gap found by a second independent audit (2026-09-25) and closed same-day:** the original pass
  above covered the git-tracked repository exhaustively but missed the one piece of project
  identity that lives outside it - the `v1.0.0` GitHub Release. Its title ("WakeyWakey v1.0.0"),
  body (two `github.com/Dam0k1es/wakeywakey/...` URLs - GitHub's rename redirect made them still
  resolve, but the visible text was stale), and one release asset's filename
  (`wakeywakey-v1.0.0.apk`) all still carried the old name. Fixed: title and both URLs updated;
  the asset was re-uploaded as `crescendo-alarm-v1.0.0.apk` (byte-identical, SHA-256 confirmed
  unchanged: `8003d9774817b3a021ed86ccccc5852e1fc1c95de0fdad85778ed7f65849143b`) and the old-named
  one deleted. Left deliberately unchanged: `OU=WakeyWakey` in the body's certificate description
  - that is what the actual signing certificate used for that specific historical build says, not
  a naming artifact to correct.
- **Requirement:** none directly - a rebrand, not a defect fix or new capability.

### T-170 · New out-of-the-box defaults for six Sleep Habits settings — DONE (2026-09-25)

- [x] Maintainer-requested default-value change, not a behaviour change: `maxDailyDelta` 15min →
  **1 hour** (the enforced minimum stays 15min, only the starting point moved), `durationToWakeUp`
  00:00 → **00:15**, `durationToGetReady` 1h → **00:45**, `gentleWakeUpEnabled` false → **true**
  with `gentleWakeUpDuration` 1min → **5 minutes**, `snoozeEnabled` false → **true** (`snoozeTime`
  already defaulted to 5 minutes, unchanged), `followSystemTheme` false → **true**.
- **Spec updated to match, not just the code:** `docs/scheduling-v2-spec.md` FR-3's field table and
  FR-20's own "Defaults" paragraph both stated `snoozeEnabled = false` / `durationToWakeUp = 00:00`
  explicitly - now read `true` / `00:15`, dated, with the old values kept alongside for context.
  `maxDailyDelta`/`durationToGetReady`/gentle-wake/theme have no default stated in the spec (only
  `maxDailyDelta`'s minimum is formally specified, unchanged), so no other spec edit was needed.
- **A real ripple, not just six field initializers:** several tests used the *old* defaults
  (`durationToWakeUp = 00:00`, `snoozeEnabled = false`, `followSystemTheme = false`) as convenient
  setup for unrelated behaviour under test, not as the thing being asserted - e.g.
  `test/snooze_state_test.dart`'s FR-20 budget-boundary tests relied on a fresh `AppState` starting
  at `00:00` to reliably trigger the "arm to 00:10" bump; with the new default already at `00:15`,
  that bump no longer fires from a fresh install at all. Fixed by making every one of those tests
  set its starting state explicitly rather than leaning on whatever the default happens to be -
  the same fix shape in `test/page_appearance_theme_test.dart` (three cases that toggled `Follow
  System Theme` assuming it started off) and `test/app_state_theme_mode_test.dart`. Found by
  running the full suite after the default change and triaging each of the resulting 12 failures
  individually - some genuinely asserted the old default and needed their expectation updated
  (`test/app_state_scheduling_v2_test.dart`'s `gentleWakeUpDuration`/`maxDailyDelta` tests), others
  needed their setup decoupled from the default instead.
- **Requirement:** none directly - a configuration/default-value change, not a defect fix.

### T-171 · T-170's snoozeEnabled default overflowed the ringing screen — FIXED (2026-09-25)

- [x] Found by `dev`'s own required CI checks, not proactively: `Analyze & Test (TZ=Pacific/
  Chatham)` failed on the very next commit after T-170 with `A RenderFlex overflowed by 7.0 pixels
  on the bottom` in `screen_active_alarm.dart:160`, across 7 tests in
  `test/handler_replan_wiring_test.dart`. Reproduced locally (`TZ=Pacific/Chatham flutter test
  test/handler_replan_wiring_test.dart`) before touching anything, to confirm it wasn't CI-runner
  flakiness.
- **Root cause:** `ScreenAlarmActive`'s body is a fixed, non-scrollable `Column` (four `Spacer`s
  distributing remaining space between the date/time text, a 200×200 alarm icon, and the Stop
  button) with `SnoozeButton` sitting above all of that. `snoozeEnabled` defaulting to `true`
  (T-170) means that button now always occupies space on this screen where it previously mostly
  didn't (default was `false`) - just enough extra height to overflow the fixed Flutter test
  viewport (800×600) by 7 pixels. Only the Chatham leg happened to fail because the fixed test
  clock renders at its longest string length there, not because the underlying fragility is
  timezone-specific - the same 7px would be exceeded on a real short/small screen too, so the fix
  had to actually solve that, not just satisfy this one CI leg.
- **Fix:** wrapped the `Column` in the standard Flutter idiom for "centered when it fits, scrollable
  when it doesn't" - `LayoutBuilder` → `SingleChildScrollView` → `ConstrainedBox(minHeight:
  constraints.maxHeight)` → `IntrinsicHeight` → the unchanged `Column`. A plain
  `SingleChildScrollView` alone can't host the existing `Spacer`s (they need a bounded main-axis
  size to compute flex, which an unbounded scroll axis doesn't provide) - `IntrinsicHeight` bounded
  by the `ConstrainedBox` gives them that, while still allowing the whole thing to grow and scroll
  once content genuinely doesn't fit.
- **Verified:** the previously-failing tests green under `TZ=Pacific/Chatham`; the full suite
  (543/543) re-run under all six CI timezones locally, not just the one that had failed;
  `flutter analyze` clean; `flutter build apk --debug` still succeeds.
- **Requirement:** none directly - a regression fix surfaced by T-170, not a new capability.

### T-172 · v1.2.0 released — the first release under the Crescendo Alarm name — DONE (2026-09-25)

- [x] `master` fast-forwarded to `3a39aea` (T-169 rename + 9 Dependabot bumps + T-170 defaults +
  T-171 fix), full gate green (security-gate, real-emulator E2E, signed production build, MobSF),
  tagged `v1.2.0` and pushed - `release.yml`'s own independent gate (security-gate + E2E again)
  green, signed APK produced and attached.
- **Release notes corrected:** GitHub's auto-generated notes only listed the 9 Dependabot PRs
  (the rename, T-170, and T-171 landed as direct commits to `dev`, not PRs, so they never made it
  into the auto-generated "What's Changed" list) - rewritten by hand to actually describe what
  shipped, including the no-in-place-update consequence of the `applicationId` change. Title fixed
  to "Crescendo Alarm v1.2.0" (was the bare tag name). A second, human-readable asset
  `crescendo-alarm-v1.2.0.apk` uploaded alongside the generic `app-release.apk` (byte-identical,
  SHA-256 `e648693899bafc434f487f2d6ce51c2062dcc8409a9ef7ea2ca7d6d2057040f2`), matching the same
  fix already applied to the `v1.0.0` release's own naming gap (T-169's addendum).
- **`current.apk` refreshed** from this release's actual signed artifact - `applicationId`
  `com.crescendoalarm.crescendoalarm`, `versionCode=3`, `versionName=1.2.0`, verified via
  `apksigner verify` before copying.
- **Requirement:** none directly - a release milestone, not a defect fix or new capability.

### T-173 · Diagnostics: log every Sleep Habits change, and make all logging opt-in — DONE (2026-09-25)

- [x] Two maintainer requests, both formal requirements: (1) "the logs should be extended when
  Sleep Habits are changed, no matter which" - previously nothing was logged when the user touched
  any of these controls at all; (2) "the logs should be disabled by default. All of them. That is
  also a requirement" - `AppState.diagnosticsEnabled` (the general on/off switch, distinct from the
  clock-time sub-switch T-135/T-163 already gate) defaulted to `true`, meaning diagnostics were
  collected out of the box unless a user found and disabled the setting themselves.
- **New event, structurally still PII-free:** `Diag.sleepHabitChanged({required
  DiagSleepHabitSetting setting})` carries only WHICH of the 13 Sleep Habits controls changed,
  never the value it changed to or from - most of them are clock-shaped (durations, times of day),
  and this log structurally excludes clock values everywhere except the three fields already gated
  behind the opt-in clock-time switch (`test/diag_log_api_test.dart`'s own structural checks). New
  `DiagSleepHabitSetting` enum enumerates every control: `sleepGoal`, `durationToWakeUp`,
  `durationToGetReady`, `durationToGetReadyPerWeekday`, `reminderDuration`, `preferredWakeUpTime`,
  `maxDailyDelta`, `snoozeTime`, `gentleWakeUpDuration`, `scheduleOnGapDays`, `reminderEnabled`,
  `gentleWakeUpEnabled`, `snoozeEnabled`. Wired into all 15 call sites on
  `screen_sleephabits.dart` (8 through the shared `_changeDuration`, the rest at each toggle's own
  `onChanged`), never gated behind the clock-time switch since it carries no clock value at all.
- **New test seam, same shape as existing ones:** no test in this project drives the real Material
  `showTimePicker` dialog (it's third-party dialog UI, not this screen's own logic to prove
  correct) - `ScreenSleephabits.debugTimePickerOverride` replaces it with a fake result, the same
  pattern as `ScreenAlarmActive.debugRingingStreamOverride`/`QrScanner.debugScanStreamOverride`.
  Needed `tester.ensureVisible()` before every tap, on both pickers and several toggles - several
  controls sit below the fold on the 800×600 test viewport, the same scroll trap other dialog
  tests in this project already hit. `test/screen_sleephabits_diag_test.dart` (new, 16 cases)
  covers all 13 settings, confirmed red first via a deliberately removed `Diag` call
  (`maxDailyDelta`), then reverted.
- **Off by default, at every layer that could matter, not just the one already wired up:**
  `AppState._diagnosticsEnabled` (the one that actually matters for a real install, read by
  `main.dart` into `Diag.init(enabled: ...)`), `Diag._enabled`'s own static default, and
  `Diag.init`'s own `enabled` parameter default - all changed `true` → `false`, so the "off by
  default" contract holds even for a call site that skips the normal `AppState` wiring, not only
  the one real app startup path already used. `test/app_state_scheduling_v2_test.dart`'s existing
  "general diagnostics switch stays independent of [clock-time switch]" test asserted the old
  default explicitly; updated, confirmed red against the old value first.
- **Verified:** full suite green (559/559, +16 for the new file), `flutter analyze` clean, no other
  test broke - everything else already used `Diag.resetForTest()`/explicit `AppState
  .diagnosticsEnabled = true` setup rather than relying on the default, which is exactly the
  isolation this project's test conventions already required.
- **Requirement:** yes - both changes were stated as requirements by the maintainer directly, not
  requests for a nice-to-have.

### T-174 · `docs/risk.png` removed as redundant with `docs/threat-model.svg` — DONE (2026-09-25)

- [x] Maintainer request: "risk.png ist identisch mit threat-model.svg, lösche risk.png." Verified
  before deleting: no markdown file anywhere in the repository actually embeds `risk.png` as an
  image (`![...](...risk.png)`) - `CLAUDE.md` only described how to regenerate it, `docs/TODO.md`
  only referenced it in historical entries (left untouched, same as every other point-in-time
  record in that file). `docs/threat-model.svg` itself carried a one-line caption inside the
  rendered image ("Quelle dieses Bildes: ... Neu rendern mit: rsvg-convert ...") pointing at the
  now-removed regeneration step - removed along with the PNG, since it no longer describes
  anything real.
- **Why this was a defensible removal, not just a deletion:** the PNG was a pure rendering of the
  SVG (`rsvg-convert -w 1400 -b white docs/threat-model.svg -o docs/risk.png`, pixel-identical to
  it), kept only for viewers that couldn't render SVG directly - GitHub (and every modern browser)
  renders SVG natively, so it bought nothing while still being one more generated artifact someone
  could forget to regenerate after editing the real source, silently going stale exactly the way
  `docs/UML_WakeyWakey.drawio` (T-30) did before it was retired for the same reason.
  `CLAUDE.md`'s own section updated to describe the SVG as the only artifact, with no regeneration
  step to keep in sync.
- **Requirement:** none directly - documentation/repo hygiene, not a defect fix.

### T-175 · The gentle-wake ramp felt too fast - switched from linear to exponential — DONE (2026-09-25)

- [x] Maintainer feedback from real-device use, stated as a requirement: "die Ramp duration geht
  meiner Wahrnehmung nach zu schnell nach oben... es soll eher exponentiell als linear ansteigen.
  Das ist auch eine Anforderung, da man nur so wirklich sanft aufsteht" - the ramp reaches full
  volume too quickly to feel gentle, and should stay quiet for longer before catching up, rather
  than climbing at a constant rate.
- **Confirmed against the plugin's own native source before changing anything:** `buildRingingAlarmSettings`
  used `VolumeSettings.fade(fadeDuration: ...)`, whose native implementation
  (`alarm-5.12.0/android/.../AudioService.kt`'s `startFadeIn`) sets `deltaVolume = maxVolume /
  numberOfSteps` and applies it every 100ms - a strictly linear ramp, exactly matching the
  maintainer's perception, not a misperception to correct instead.
- **Fix, without touching the plugin or any native code:** the same plugin version already
  exposes `VolumeSettings.staircaseFade(fadeSteps: List<VolumeFadeStep>)` - an explicit list of
  (time, volume) points its native side linearly interpolates *between* at the same 100ms tick
  (`startStaircaseFadeIn`, same file). `_exponentialFadeSteps` (`ringing_alarm_settings.dart`)
  samples `volume(t) = target * (e^(k·t/T) - 1) / (e^k - 1)` at 40 fixed points regardless of
  `T` (more points than that only bloats the platform-channel payload for no perceptible gain,
  since the plugin already interpolates linearly between whatever points it's given) - `k = 3.0`
  chosen as a noticeably-curved but not extreme middle ground, not measured against a real ear;
  revisit that one constant on further feedback rather than treating it as settled.
- **Tests:** `test/ringing_alarm_settings_test.dart` - the existing "gentle wake produces a fade"
  case updated for `fadeSteps` instead of the now-unused `fadeDuration`, plus four new cases
  pinning down the actual shape: starts at (near-)zero and ends exactly at the target volume,
  monotonically increasing, scales linearly with the target volume at identical time points, and -
  the one that actually distinguishes this from a linear ramp - the midpoint sits *below* half
  volume rather than exactly at it. Confirmed red first by temporarily reverting the formula to
  plain linear (`volume * i / stepCount`): every case but the midpoint one still passed unaffected
  (correctly, since "starts at 0/ends at target/monotonic/scales linearly" all hold for a linear
  ramp too), and the midpoint case failed exactly as it should - proving that specific test, not
  the others, is what actually guards against a regression back to linear.
- **Requirement:** yes - stated as one by the maintainer directly.

### T-179 · Gentle Wake Up disabled for the final snoozed ring — DONE (2026-09-25)

- [x] Maintainer request, verbatim: "die gentle wake up option soll für den finalen alarm im
  falle von snooze nicht mehr gelten. der letzte alarm bei nutzung von snooze soll direkt auf der
  geplanten lautstärke starten." - once postponing again would no longer fit the snooze budget,
  the ring a press arms is the FINAL one: no more snoozing is coming, so it must not be softened
  by a ramp - it needs to wake the user right now, not ease them into it.
- **Fix:** `snoozeRingingAlarm` (`lib/models/alarms/snooze.dart`) now computes a second,
  prospective `canSnooze` check at the moment it arms the new ring - `canSnooze(now: next, ...)` -
  to ask "would postponing again from here still fit the budget?". If not, `gentleWakeAllowed:
  false` is passed to `setAlarm`. `AppState.setSnoozeAlarm`'s signature grew a third parameter to
  receive it, ANDed into the real `gentlewake` flag it hands `buildRingingAlarmSettings`
  (`gentlewake: _gentleWakeUpEnabled && gentleWakeAllowed`) - the global setting can still say yes,
  but the final ring overrides it to no.
- **Callback signature change:** `setAlarm`'s type grew from `(int, DateTime)` to `(int, DateTime,
  bool)`. Only three call sites existed: `AppState.setSnoozeAlarm` (production, updated in place -
  `SnoozeButton`'s `setAlarm: appState.setSnoozeAlarm` tear-off needed no change of its own, since
  it now matches the widened type automatically) and two test files'
  inline fake closures (`test/snooze_state_test.dart`, `test/snooze_per_alarm_override_test.dart`),
  both updated to accept the third parameter.
- **E2E impact: none.** No E2E test exercises snooze at all (confirmed by grep, not assumed).
- **Tests:** three new cases in `test/snooze_state_test.dart`'s new
  `T-179: gentle wake is disabled for the final snoozed ring` group - still allowed while another
  press would still fit the budget, disabled once a press exhausts it, and the exact inclusive
  boundary case (one press before exhaustion, still allowed). Confirmed the middle case actually
  distinguishes the fix by temporarily hardcoding `setAlarm(id, next, true)` and seeing exactly
  that one case (and only that one) fail, then reverting.
- **Requirement:** yes - stated as one by the maintainer directly.

### T-180 · Tighter spacing in Sleep Habits, Alarm Tones, and the manual-alarm dialog — DONE (2026-09-25)

- [x] Maintainer request: "verkleinere die abstände zwischen den text/container-elementen im
  sleep habit reiter und im alarm tone reiter, sowie bei neuen manuellen alarmen."
- **Sleep Habits** (`screen_sleephabits.dart`): inter-tile `SizedBox(height: 16.0)` → `8.0`
  (6 occurrences); section-header padding `top: 24.0, bottom: 8.0` → `top: 16.0, bottom: 4.0`.
- **Alarm Tones** (`page_alarmtones.dart`): inter-tile `SizedBox(height: 16.0)` → `8.0`; the
  larger `32.0` gap before the Volume slider → `16.0`; every `Card`'s `EdgeInsets.all(16.0)` →
  `12.0`.
- **Manual-alarm dialog** (`screen_alarms.dart`): the 7 inter-`Card` `SizedBox(height: 16)` gaps →
  `8`; every `Card`'s `EdgeInsets.all(16.0)` → `12.0`.
- **No new tests:** a pure visual-density change with no behavioral contract to write a failing
  test against - confirmed first, by grep, that no existing test asserts any of these exact
  numeric values (a position-ordering test like `sleep_habits_order_test.dart`'s uses
  `greaterThan`, not an exact-pixel delta, so it is insensitive to the gap actually shrinking).
- **Verified:** full suite green (every test touching these three screens re-run individually,
  62/62, plus the full three-group run, 597/597), `flutter analyze` clean.
- **Requirement:** yes - requested directly by the maintainer.

### T-182 · The deactivation-code "Share" button now actually shares/prints the QR code — DONE (2026-09-25)

- [x] Maintainer request, verbatim: "der qr generate dialog zeigt eine teilen option. diese ist als
  future task kommentiert. bitte implementiere die funktionalität den qr code zu teilen. wichtig
  wäre mir den qr code an einen drucker senden zu können. implementiere das nur, falls es mit
  betriebsystemkomponenten von android direkt geht, nicht wenn externe apps erforderlich sind.
  exportiert werden soll der qr code als png."
- **`lib/models/scan_code/qr_export.dart` (new):** `renderQrCodePng(payload, {size})` renders the
  code via `qr_flutter`'s `QrPainter`, with a white background explicitly painted first -
  `QrPainter.paint`/`toPicture` draws only the QR modules, no background fill of its own, so a
  naive export would come out with a transparent background. Pure, plugin-free, directly
  unit-testable (`test/qr_export_test.dart`: real PNG signature, different payloads render
  differently, the same payload is deterministic, size is respected).
- **Two new dependencies, each checked against pub.dev's own published licence text before
  adding** (see `docs/licence-position.md`): `share_plus` (BSD-3) wraps
  `Intent.ACTION_SEND` - Android's own share-sheet chooser, no external app required, the user
  picks whatever target they want from the OS's own list. `printing` + `pdf` (both Apache-2.0)
  invoke `android.print.PrintManager` - the OS's own print framework - directly, which is what the
  maintainer specifically asked for ("wichtig wäre mir... an einen Drucker"): a generic share does
  not reliably surface a "Print" target on stock/AOSP Android (that's each app's own deliberate
  choice to register for, not automatic for arbitrary shared content), so a dedicated path through
  the OS's real print framework was needed to actually deliver on that request rather than merely
  hoping a print-capable app is installed. All twelve resulting transitive dependencies checked
  individually too, not left to the blocklist test alone.
- **New "Print" button**, alongside the existing "Share" (which now actually works instead of
  showing "This is a future feature!"). The three-button row (`Remove`/`Share`/`Print`) switched
  from a `Row` of `Spacer`s to a `Wrap` - the same overflow lesson T-176 already learned for a
  different dialog's button row, now applied proactively before it could recur.
- **Both actions read `_appState.deactivationCode` directly**, not whatever the screen happens to
  render right now - correct regardless of whether the QR image or the user's own description
  (T-150) is currently shown.
- **A real widget-testing lesson, not just a wiring exercise:** `renderQrCodePng`'s `dart:ui` image
  rasterization (`Picture.toImage`/`Image.toByteData`) never resolves when triggered from inside an
  active `testWidgets` binding via a real button tap - not even inside `tester.runAsync`, which
  `qr_scanner_close_test.dart` already established as the fix for a *different* class of
  never-resolving Future (real platform-channel calls). Confirmed this is specifically about the
  rendering step, not the surrounding test, by first proving `renderQrCodePng` works fine on its
  own in a plain `test()` (`test/qr_export_test.dart`, no widget binding at all). Fixed by adding a
  third test seam (`debugRenderQrCodeOverride`) so `test/page_deactivation_code_share_print_test
  .dart` verifies the Share/Print *wiring* against a fast deterministic fake, leaving the real
  rendering pipeline to the test that already covers it in isolation.
- **A second, unrelated real bug found while writing that test:** `page_deactivation_code.dart`
  has no `Scaffold` of its own (production embeds it inside `screen_scancode.dart`'s
  `Scaffold(body: PageDeactivationCode())`) - a test that only wraps it in a bare `MaterialApp`
  crashes on `displayToast`'s `ScaffoldMessenger.of(context)` the moment a failure path actually
  runs, with no descendant `Scaffold` to present to. Fixed by matching the real embedding in the
  test fixture.
- **E2E impact: none** - no E2E test touches the deactivation-code screen's Share/Print controls
  (confirmed by grep).
- **Verified:** full suite green (608/608 across three sequential groups), `flutter analyze`
  clean, `flutter build apk --debug` succeeds (confirms the three new native Android plugins
  integrate into the Gradle build/manifest merge without conflict).
- **Requirement:** yes - requested directly by the maintainer, with an explicit constraint
  (OS components only) that was verified to actually hold, not assumed.

### T-184 · A Do Not Disturb toggle: silences notifications for sleep time, restores at the final ring — DONE (2026-09-25)

- [x] Maintainer request, verbatim: "Implementiere einen toggle do not disturb. dieser soll in der
  schlafenszeit (sleep goal) vor dem wecker (ohne reminder zeit) benachrichtigungen deaktivieren
  und ab dem wecker (nach snooze time, nur finaler alarm) wieder auf den zustand vorher (vibration,
  ton, etc) setzen."
- **What "vor dem Wecker (ohne reminder Zeit)" actually means, precisely:** the bedtime reminder
  notification already fires at `wakeTime - sleepGoal - reminderDuration` - this feature activates
  later still, at `wakeTime - sleepGoal` alone (`bedtimeInstant`, extracted from
  `scheduleSleepReminder` into a shared, reusable function rather than re-derived - the exact bug
  class this project has hit real regressions from before, `nextManualOccurrence`/`canSnooze`).
  Two genuinely different, independently-scheduled instants: the reminder tells you to go to bed,
  this silences the phone once you're actually there.
- **What "ab dem Wecker (nach snooze time, nur finaler Alarm)" means:** generalizes T-179's own
  "final ring" concept (there, for disabling the gentle-wake ramp on a snoozed ring that can no
  longer be postponed further) to the FIRST ring too, not only a snoozed one - with snooze
  disabled, or the budget already zero, the first ring already IS final. Computed reactively inside
  `Handler.handleAlarm` at ring time (not precomputed at arm time the way T-179's gentle-wake flag
  is, since restoring device state is itself a ring-time action, unlike baking a value into
  `AlarmSettings`).
- **Real Android mechanism, not a third-party plugin:** `android.app.NotificationManager`'s own
  `getCurrentInterruptionFilter`/`setInterruptionFilter` - pure AOSP framework API. The only pub.dev
  package found (`do_not_disturb`) is unmaintained (~21 months stale) and MPL-2.0-licensed -
  GPLv3-compatible, but a different licence category than every other dependency this project
  carries, for four one-line framework calls this project can just make directly. Custom Kotlin
  (`DoNotDisturbChannel.kt`, wired into `MainActivity.kt` alongside the existing `DirectBootFallback`
  channel) instead - zero new dependency, zero licence-review nuance. The *permission* to call it at
  all (`ACCESS_NOTIFICATION_POLICY`, one of Android's "special" permissions - a Settings-screen
  grant, no runtime dialog) goes through the already-present `permission_handler` dependency
  (`Permission.accessNotificationPolicy`), matching `requestCameraPermission`/
  `requestCalendarPermission`'s existing pattern exactly - no manifest change needed either, the
  permission was already declared (pulled in by `permission_handler` itself).
- **Interruption filter used: `ALARMS` (4), never `NONE` (3)** - `NONE` is total silence and would
  silence the alarm clock's own alarm too, defeating the entire point of this app.
- **Architecture, by layer:**
  - `lib/utils/do_not_disturb_channel.dart` - the raw platform-channel wrapper (injectable, no
    channel in `flutter test`) plus the real Android constants.
  - `lib/utils/do_not_disturb.dart` - the pure "what state do we end up in" logic
    (`activateDoNotDisturb`/`restoreDoNotDisturb`/`runDoNotDisturbActivation`/
    `restoreStaleDoNotDisturb`), the same split as `snooze.dart`/`manual_alarm_enable.dart`.
    Persisted via `shared_preferences`, not held only in memory: activation and restoration happen
    from two independent triggers (a scheduled background-isolate notification, and whichever ring
    turns out to be final), possibly across a process death in between.
  - `lib/utils/do_not_disturb_schedule.dart` - `scheduleDoNotDisturbActivation`, mirroring
    `scheduleSleepReminder`'s own structure (a fixed notification id,
    `doNotDisturbActivationNotificationId`, cancelled/rescheduled the same way, including the same
    T-110 past-bedtime handling) at the different `bedtimeInstant` computed above. Called from the
    same two places `scheduleSleepReminder` already is (`checkpoint.dart`'s finally-block, and
    `Handler.onAlarmHandled` - the latter is the ONLY place a `ManualAlarm` dismiss reschedules
    anything at all, T-73 forbids it from running the full checkpoint).
  - `lib/utils/notifications.dart`'s `onNotificationCreatedMethod` now branches by notification id -
    the DND-activation notification routes to `runDoNotDisturbActivation` instead of
    `runTimezoneCheckpoint2`, since the two hooks do unrelated things and neither needs the other.
  - `Handler.handleAlarm` computes `isFinalRing` and calls an injectable `_restoreDoNotDisturb`
    (the same `_runCheckpoint`/`_sleep` injection pattern) when true.
- **Safety net (docs/threat-model.svg names availability as this project's primary asset - a stuck
  Do Not Disturb activation is exactly the "self-inflicted alarm shutdown" class T-64/T-78 already
  were, just for the whole device's notifications instead of one alarm):** `restoreStaleDoNotDisturb`
  checks, during the regular scheduling checkpoint (already runs on every app open, FR-17,
  regardless of Do Not Disturb specifically), whether activation has been active longer than a fixed
  18-hour cap - deliberately NOT tied to any particular wake time/snooze budget, since re-deriving
  those here would risk getting the safety check itself wrong too. A missing activation timestamp
  is treated as stale too, not left untouched.
- **UI:** a new "Do Not Disturb" toggle in Sleep Habits' "Bedtime reminder" group, alongside Sleep
  Goal/Enable Reminder. Turning it ON cannot be confirmed synchronously (Android's special
  permission has no runtime dialog); turning it OFF restores immediately if currently active,
  rather than leaving the phone silenced until whatever alarm eventually rings next.
- **Diagnostics (T-173's own standing requirement, "the logs should be extended whenever any Sleep
  Habits setting changes"):** `DiagSleepHabitSetting.doNotDisturbEnabled` (14th value) added, with a
  matching test case and the enum-completeness assertion updated 13→14.
- **Tests:** `test/do_not_disturb_test.dart` (14 cases: activate/restore/the background-isolate
  entry point/the staleness safety net), `test/do_not_disturb_schedule_test.dart` (5 cases,
  including the specific proof that the DND instant is NOT further reduced by reminderDuration the
  way the reminder notification's own is), `test/app_state_do_not_disturb_test.dart` (3 cases, the
  standard default/persist/notify triple), `test/handler_do_not_disturb_restore_test.dart` (4 cases:
  snooze disabled makes the first ring already final, snooze enabled with budget remaining does
  NOT restore yet, a snoozed re-ring that exhausts the budget IS final, and the AppState wiring
  itself) - the "not final yet" case was confirmed to actually distinguish the fix by temporarily
  hardcoding `isFinalRing = false` and watching the other three cases fail while it alone kept
  passing, then reverting. `screen_sleephabits_help_test.dart`'s help-icon counts (9→10) and
  `screen_sleephabits_diag_test.dart`'s enum-completeness assertion (13→14) updated to match.
- **E2E impact: none** - no E2E test touches Sleep Habits' Do Not Disturb toggle or the native
  channel (confirmed by grep).
- **Verified:** full suite green (635/635 across three sequential groups), `flutter analyze` clean,
  `flutter build apk --debug` succeeds (confirms the new Kotlin platform channel compiles and
  integrates into the Gradle build without conflict).
- **Requirement:** yes - requested directly by the maintainer, with precise, load-bearing timing
  semantics that were worked through carefully rather than approximated.

### T-183 · The QR-scan "Cancel" and the AppBar's own close ("X") button — only one worked — DONE (2026-09-25)

- [x] Maintainer report, verbatim: "der qr scan dialog zeigt zum abbruch ein kreuz und einen
  cancel button. ich will nur eines von beiden sehen, welches dann auch funktioniert - das kreuz
  tut es bisher nicht."
- **Root cause:** `page_import_qr.dart` is pushed via `showFullScreenOverlay`
  (`MaterialPageRoute(fullscreenDialog: true)`), whose default `AppBar` leading widget is an
  auto-generated `CloseButton` that only ever calls `Navigator.maybePop`. `QrScanner` wraps its
  whole `Scaffold` in `PopScope(canPop: false)` - deliberately, so the "guaranteed wake-up" gate
  cannot be dismissed by a system back gesture/button - which blocks exactly that call, so the X
  silently did nothing. `QrScanner(displayExitButton: true)`'s own bottom "Cancel" button, by
  contrast, already called `_closeView()` directly (an explicit `Navigator.pop`, not `maybePop`),
  so it already worked correctly - the screen was showing one working control and one dead one,
  not an actual choice between two.
- **Fix:** `automaticallyImplyLeading: false` on `PageImportQr`'s `AppBar`, leaving only the
  "Cancel" button.
- **Tests:** `test/page_import_qr_dismiss_test.dart` (new) - confirms no `CloseButton` renders at
  all, and that the one remaining "Cancel" button actually dismisses the screen. Confirmed red
  first: the first case failed against the un-fixed code (a `CloseButton` was found), reproducing
  the maintainer's report exactly.
- **E2E impact: none** - `integration_test/app_test.dart` never navigates to or interacts with
  `PageImportQr`; its `QrScanner` usage is the ringing-alarm gate (`Handler.handleAlarm`'s
  `QrScanner(alarmId: ...)`, no `displayExitButton`, no `PageImportQr` in the picture at all).
- **Verified:** full suite green, `flutter analyze` clean.
- **Requirement:** yes - reported directly by the maintainer as a real, reproduced defect.

### T-181 · Regression coverage: a single selected weekday recurs every week, not just once — DONE (2026-09-25)

- [x] Maintainer request, verbatim: "prüfe ob es tests gibt die manuelle alarme darauf prüfen, ob
  sie bei z. B. Auswahl von Sonntag nur einen, oder alle sonntage klingelt. implementiere diese
  falls nicht vorhanden."
- **Gap found:** `test/manual_alarm_repeat_test.dart` (T-14) and
  `test/handler_manual_alarm_rearm_test.dart` each covered one half of the claim - the first that
  `nextManualOccurrence` picks the correct SINGLE next matching day, the second that re-arming
  happens AT ALL on dismiss - but neither proved the two halves compose into actual indefinite
  weekly recurrence: no test ever called `nextManualOccurrence` (or the real re-arm function,
  `applyManualAlarmEnabled`) more than once per test case, so a bug that made a Sunday-only alarm
  ring once and then silently stop repeating would not have been caught by anything in the suite.
- **Added:** two new cases in `manual_alarm_repeat_test.dart`'s new
  `a single selected weekday recurs indefinitely, not just once` group. The first chains 5 calls
  to `nextManualOccurrence` (each one's result feeding the next call's `now`, simulating "rang, was
  dismissed a minute later"), asserting every occurrence lands on a Sunday exactly 7 days after
  the last. The second does the same through `applyManualAlarmEnabled` itself (the actual function
  `Handler.onAlarmHandled`'s re-arm goes through via `AppState.setManualAlarmEnabled`), catching a
  regression in that function's own wiring that the pure-math test alone would miss.
- **Confirmed these tests are not tautological:** temporarily changed
  `nextManualOccurrence`'s day-match check to `if (true) return candidate;` (reverting to the
  pre-T-14 day-agnostic behaviour) and confirmed both new cases fail, along with three pre-existing
  ones - then reverted.
- **A real, previously-unknown production bug found by the new coverage, not by inspection:**
  pushed to `dev`, the `Analyze & Test (TZ=Australia/Lord_Howe)` CI leg failed on the first new
  case - reproduced locally with `TZ=Australia/Lord_Howe flutter test ...`. `nextManualOccurrence`'s
  day-search loop built each candidate day via `today.add(Duration(days: offset))` - adding a fixed
  *real-time* Duration to a local midnight, which lands short of the intended calendar day across a
  daylight-saving transition (exactly the bug class `day_marker.dart`'s own doc comment describes,
  already fixed once for the scheduling engine at T-74d/T-76 - `manual_alarm_enable.dart`, added
  later for T-14, never adopted that fix and reintroduced the same bug independently). Lord Howe's
  DST-end transition landed inside the test's 5-week date range and pushed every subsequent
  candidate's calendar day back by its 30-minute offset delta, so the 7-day search window silently
  missed the actual next Sunday and fell through to the day-agnostic fallback, landing on the wrong
  weekday (Monday) entirely - a real defect that could affect any user whose device crosses a DST
  boundary between two occurrences of their selected repeat day, not just Lord Howe residents.
  **Fixed** by switching both of the function's day-arithmetic sites to `dayMarker` (computed over
  calendar date fields, not an absolute Duration) - the same helper this project already built and
  tested for exactly this reason, simply not reused here before now.
- **The test's own first assertion was also wrong, for the same underlying reason:** once the
  production fix was in place, the "exactly `Duration(days: 7)` apart" assertion itself started
  failing under `TZ=Australia/Lord_Howe` - correctly so, since 7 real-time days across a DST
  transition is `168:30:00`, not `168:00:00`, at that latitude. Replaced with `dayDistance`
  (calendar-day count, DST-independent) plus a same-hour/same-minute check - the correct invariant
  to assert ("the same wall-clock time, 7 calendar days later") rather than the wrong one ("exactly
  168 hours of elapsed real time").
- **E2E impact: none** - no E2E test exercises `repeatOnDays`/`nextManualOccurrence`/
  `applyManualAlarmEnabled` (confirmed by grep: the one match in `integration_test/app_test.dart`
  is a comment, not an interaction).
- **Verified:** full suite green (597/597 across three sequential groups) in all six CI timezones,
  each reproduced locally with `TZ=<zone> flutter test test/manual_alarm_repeat_test.dart`, not just
  the default UTC/dev-machine zone - `flutter analyze` clean.
- **Requirement:** the existing "repeat on" feature (T-14) already was one; this closes both a real
  gap in verifying it and a real defect the gap had been hiding, at the maintainer's direct request.

### T-178 · Sleep Habits: reordered groups, each independently collapsible — DONE (2026-09-25)

- [x] Maintainer request, verbatim: "Sortiere die Option im sleep habit neu: erst wake up time,
  dann when the alarm rings, dann sleep reminder... die optionen im sleep habit sollen nicht nur
  eine überschrift haben, sondern auch durch klicken auf diese (oder eine kleine markierung
  rechts) eingeklappt werden können."
- **Reorder:** the three causal groups (T-95) now read Wake-up time → When the alarm rings →
  Bedtime reminder - swapping the previous second and third groups. "When the alarm rings" sits
  directly after "Wake-up time" (what determines whether/when it rings), with the bedtime reminder
  last as the one genuinely separate concern (it shifts only itself, never the alarm). Each
  group's tiles now live in their own list-returning method
  (`_buildWakeUpTimeTiles`/`_buildWhenAlarmRingsTiles`/`_buildBedtimeReminderTiles`) instead of one
  flat inline `Column`, so the order is a one-line change in `build()` rather than moving a block
  of tile source around.
- **Collapsible groups:** `_buildSectionHeader` is now a tappable `InkWell` row (heading text +
  a small `Icons.expand_less`/`Icons.expand_more` chevron on the right, either one toggling the
  same state) instead of a plain `Text`. Three new local booleans
  (`_wakeUpTimeExpanded`/`_whenAlarmRingsExpanded`/`_bedtimeReminderExpanded`), default `true` -
  purely local UI state, not persisted, the same precedent `_showGetReadyOverrides` (T-52.3)
  already established for this screen: a user who never collapsed a group has nothing to restore
  anyway.
- **E2E impact: none.** `integration_test/app_test.dart` never navigates to or interacts with the
  Sleep Habits screen at all - its one `durationToWakeUp` reference sets the value directly on
  `AppState`, not through this screen's UI - confirmed by grep before assuming so.
- **Existing tests adjusted, not just re-run:** `test/sleep_habits_order_test.dart`'s expected
  order swapped to match; `test/screen_sleephabits_help_test.dart`'s two index-based lookups for
  "Gentle WakeUp"/"Snooze" moved from 7/8 to 5/6, since those tiles now sit earlier in the help-icon
  list. Both confirmed red against the reordered-but-not-yet-updated test first, then green.
- **New test:** `test/sleep_habits_collapsible_sections_test.dart` (5 cases) - expanded by default,
  tapping a heading collapses only its own group, tapping again re-expands it, tapping the chevron
  specifically (not just the heading text) works too, and collapsing all three leaves only the
  headings themselves visible. Confirmed red first (the chevron icons/tap behavior didn't exist).
- **Verified:** full suite green (592/592 across three sequential groups), `flutter analyze` clean.
- **Requirement:** yes - both changes were requested directly by the maintainer.

### T-177 · Privacy Policy still named the app "Wakey Wakey" after the rename — DONE (2026-09-25)

- [x] Found by an independent External Compliance & Fitness-for-Purpose Audit (2026-09-25, a fresh
  agent with no prior involvement in this codebase, per this file's own review-persona independence
  requirement): `assets/text/Privacy.md` still opened with "This Privacy Policy describes how the
  Wakey Wakey app...". The 2026-09-25 rename (T-169) updated every other user-facing surface it
  enumerated - app title, notification titles, About page, diagnostics export header,
  deactivation-code label - but never touched this file, and it is the **first** document a user is
  asked to read and accept (`README.md`, `docs/USER_GUIDE.md`). `docs/REQUIREMENTS.md` R11 ("the
  privacy policy is accurate and complete") was marked "met" against a document that misnamed the
  product it describes.
- **Fix:** one line - "Wakey Wakey" → "Crescendo Alarm" - plus the "Last updated" date, since the
  content changed.
- **Deliberately left untouched, and why:** `docs/personas.md`'s "Goals with the 'Wakey Wakey' App"
  headings (a planning-phase document, annotated elsewhere for claims that no longer hold, not
  scrubbed of its original wording), `docs/security-assessment-2026-09.md` (already carries its own
  explicit 2026-09-25 naming note stating every "WakeyWakey" reference below it is deliberately left
  as assessed, matching this project's standing rule for frozen point-in-time records),
  `assets/sounds/CREDITS.md`'s citation of the actual "Wakey Wakey it's time for scoo" meme this
  bundled tone is traced to (a real external title, not this app's own name), and
  `bundled_tones.dart`'s doc comment explaining why the *tones* used to be misleadingly named after
  the app itself (historical context for a past decision, not a live branding claim). None of these
  are the defect the audit found - only `assets/text/Privacy.md` was.
- **Tests:** `test/privacy_policy_branding_test.dart` (new) - a source-reading test in
  `licence_header_test.dart`'s own style, reading the asset directly off disk rather than through a
  widget pump. Confirmed red first (failed against the un-fixed file with "does not contain
  'Crescendo Alarm'"), then green after the fix.
- **Verified:** `flutter analyze` clean; the new test plus every other privacy/branding-adjacent
  test (`privacy_before_permissions_test.dart`, `widget_test.dart`, `bundled_tones_test.dart`) green.
- **Requirement:** yes - `docs/REQUIREMENTS.md` R11.

### T-176 · Manual-alarm dialog: weekday selector in one row, per-alarm Snooze and Guaranteed Wake-Up toggles — DONE (2026-09-25)

- [x] Maintainer request, verbatim: "Wenn ein neuer manuelle Alarm angelegt wird: ist die Auswahl
  der Wochentage anzupassen. Auch dort soll ein kleiner Titel erscheinen, die Auswahlboxen sollen
  jedoch nicht in 3 Reihen, sondern in einer sichtbar sein. ist eine Aktivierung/Deaktivierung von
  Snooze möglich sein. Soll eine aktivierung/deaktivierung des QR Mechanismus möglich sein."
- **Weekday selector (`screen_alarms.dart`):** the old layout was a `Wrap` of 40dp chips, 10dp
  spacing, with a forced break between the five weekdays and the weekend - on a realistic phone
  width that wraps into three visual rows, and had no title. Replaced with a `Row` of seven
  `Expanded` slots (one per day, 32dp chips), which divides the available width by seven and
  therefore cannot wrap regardless of screen width, under a new "Repeat on" title label (matching
  `docs/USER_GUIDE.md`'s existing term for this control). `test/screen_alarms_dialog_toggles_test.dart`
  sets a realistic narrow test viewport (360×800) before pumping the dialog - the default 800-wide
  test window is wide enough that the old layout would not have visibly wrapped, which would have
  masked the bug entirely - and asserts all seven day labels sit at the same vertical center.
- **Per-alarm Snooze toggle:** `ManualAlarm.snoozeEnabled` (new field, defaults to `true`), a
  per-alarm override of `AppState.snoozeEnabled` following the same "property of the alarm, not
  just an AppState default" pattern as `gentlewake`/`gentleWakeDuration`/`tone`/`volume`/`vibrate` -
  except this one is not part of `AlarmSettings` at all, since it's read only at ring time
  (`snoozeRingingAlarm`, `SnoozeButton`) via `AppState.getAlarm`, never baked into the native
  platform alarm, so it needs no `planAlarmSync` deviation handling. Both read sites now resolve it
  through one new shared function, `effectiveSnoozeEnabled` (`snooze.dart`) - matching that file's
  own existing reasoning for why `canSnooze` itself is shared, rather than risk the two call sites
  drifting apart the way the five checkpoint entry points once did (T-87).
- **Per-alarm Guaranteed Wake-Up (QR gate) toggle:** `ManualAlarm.requireDeactivationCode` (new
  field, defaults to `true` - the only behavior that existed before this override: every alarm
  required the scan whenever a code was configured at all). `Handler.handleAlarm` used to decide
  the QR-vs-default-overlay routing from `_appState.deactivationCode != null` alone; extracted into
  a new pure function, `shouldRequireDeactivationCode(ringingAlarm, codeConfigured)` (matching
  `isAlarmStale`'s own precedent in the same file), so the decision has a test that needs neither a
  `BuildContext` nor the real `alarm` plugin. A global code must still exist at all - an alarm can
  opt out of the gate, but none can opt into one that was never configured.
- **A real bug found along the way, not introduced by this change:** `AppState.addAlarm` never
  stores the `ManualAlarm` it's given directly - it reconstructs a new one from a fixed field
  whitelist (working around the `alarm` plugin's own id-reuse quirk). That whitelist did not
  include the two new fields, so every alarm silently reverted to their constructor defaults the
  moment it was saved, regardless of what the dialog's switches actually showed - the exact
  "setting with a UI that never reaches the alarm" bug class as T-84, this time in `addAlarm`'s own
  reconstruction step rather than the dialog. Caught by
  `test/screen_alarms_dialog_toggles_test.dart`'s own end-to-end save-and-read-back cases, which is
  also why it doubles as that bug's regression test - confirmed by reverting the fix and seeing
  those two cases fail before restoring it.
- **A second, unrelated pre-existing bug found the same way:** the existing "Gentle Wake Up" toggle
  row also overflows at this same narrow width - invisible before because no test had ever pumped
  this dialog at a realistic phone width. Fixed with the same `Expanded`-wrapped-label pattern
  applied to the two new toggles.
- **Tests:** `test/manual_alarm_per_alarm_toggles_test.dart` (the model: construction defaults,
  JSON round-trip, pre-T-176 JSON missing the fields still defaults to `true`, equality),
  `test/snooze_per_alarm_override_test.dart` (`effectiveSnoozeEnabled`'s resolution, and
  `snoozeRingingAlarm` actually refusing to snooze for an opted-out alarm),
  `test/handler_deactivation_code_override_test.dart` (`shouldRequireDeactivationCode`'s four
  cases: no code configured at all, opted-out `ManualAlarm`, opted-in `ManualAlarm`, and a
  `ScheduledAlarm`/unknown id following the global setting), and
  `test/screen_alarms_dialog_toggles_test.dart` (the dialog itself: title label, single-row layout,
  both new switches' defaults and their effect on the saved alarm). Every new test confirmed red
  first (compile failure against the not-yet-existing fields/functions for the brand-new pieces;
  actual failing assertions, reverted and reconfirmed, for both bugs found along the way).
- **Verified:** full suite green (586/586 across three sequential groups, this VM's own memory-safe
  convention for a full local run), `flutter analyze` clean.
- **Requirement:** yes - all three changes were requested directly by the maintainer.

### T-05 · A direct dependency is not open source — GPLv3 conflict — RESOLVED (2026-09-17)

- [x] Replaced, not excepted. `syncfusion_flutter_calendar` (and with it `_core`, `_datepicker`
      and `syncfusion_localizations`) is out; the Schedule screen now draws with `calendar_view`
      (MIT). `Meeting` is unchanged - the scheduling engine and most of the suite depend on it - so
      the migration is a mapping, `meetingToCalendarEvent`, tested in
      `test/schedule_events_test.dart`. The timezone conversion had to move INTO that mapping:
      SfCalendar took a `startTimeZone` per appointment, `calendar_view` has no timezone concept
      and draws the raw fields, so a value left in another frame is drawn at the wrong hour (the
      T-61/T-83 class, one layer out). A mutation dropping `.toLocal()` turns the test red.
      Deleted with it: `appointment_editor.dart` and `color_picker.dart`, 450 lines reachable only
      from commented-out code - porting dead code to a new library would have been pure waste.
      The decision itself is written down in `docs/licence-position.md`.
- **Why:** `syncfusion_flutter_calendar`, `_core` and `_datepicker` ship under the Syncfusion
  Essential Studio licence, which requires a commercial licence or qualifying for their community
  programme (revenue and team-size caps). That makes R8's *"all direct dependencies are
  open-source — met"* factually wrong, and it is a concrete incompatibility with distributing the
  APK under GPLv3 — not merely an unrun licence scan as R9 frames it.
- **Evidence:** `pubspec.yaml:38-40`; `syncfusion_flutter_calendar/LICENSE` ("Under no
  circumstances can you use this product without (1) either a Community License or a commercial
  license").
- **Done when:** either the dependency is gone, or a tracked decision records the licence basis and
  R8/R9 are corrected to match reality.
- **Requirement:** R8, R9

### T-06 · The signed release APK is built and published with no quality gate — RESOLVED (2026-09-20)

- [x] Demonstrate, with a real deliberately-failing check, that the release build actually stops.
- **Why:** in `ci.yml` the release-build job declared no `needs:`, so it ran regardless of whether
  analyze, tests, SCA, secret scanning or SAST failed; `release.yml` ran no SCA/secret/SAST job at
  all. A red run still produced a downloadable, signed, signature-verified APK that the README
  presented as the production artifact.
- **Evidence (before this fix):** `.github/workflows/ci.yml:123` (no `needs:`), `:183` (the only
  `needs:` in the file); a real run concluded Analyze **failure**, SCA **failure**, mobsfscan
  **failure**, MobSF **failure** and still uploaded three artifacts.
- **Resolution so far:** `build-android-release` in `ci.yml` now declares
  `needs: [analyze-and-test, security-gate, e2e-tests]` (until the gate refactoring in T-92, that
  list was called `[analyze-and-test, sca-and-secrets, mobsfscan, e2e-tests]`; `security-gate` now
  combines the two middle ones into a single callable workflow, which `release.yml` also uses) - a
  failure in any of those
  now prevents the job from running at all, per GitHub Actions' own `needs:` semantics (not
  demonstrated live with a deliberately-failing check, to avoid sabotaging a real pipeline run for
  the sake of a test; confirmed instead by a real green run where `build-android-release` correctly
  waited for, and only ran after, all four `needs:` had passed - see T-37's verification note).
  MobSF itself (needs the built APK, so it structurally cannot gate the build that produces it) now
  actively revokes the artifact after the fact instead of just marking the run red - see T-11.
- [x] **Demonstrated live (2026-09-20, run 35515989816).** A throwaway branch (`t-06-demo`, never
  merged, pushed and deleted the same session) got one deliberately invalid Dart file added, then
  `ci.yml` was dispatched against it directly via `gh workflow run ci.yml --ref t-06-demo` -
  `workflow_dispatch` rather than a real push, so the demonstration touches no tracked history on
  `dev`/`master`. Result: all six `Analyze & Test` timezone legs failed, exactly as expected, and -
  more than the original ask - not just `build-android-release` but `security-gate`, `e2e-tests`,
  `Build Android (development)` **and** `Build Android (production)` all show as **skipped**, never
  run at all. The gate holds transitively, not only at the one job this item originally worried
  about. The branch and the run itself were deleted afterward, so nothing about this demonstration
  is left in the repository's real history.
- **Requirement:** R1

### T-32 · The background rescheduling R2 requires does not exist — RESOLVED (2026-09-10, formally dropped and replaced)

- [x] Implement (or formally drop) app-independent rescheduling when fewer than 7 days are armed.
- **Why:** R2 demands that a new alarm is produced "in the background when fewer than 7 days ahead
  are currently scheduled, without requiring the app to be open". There is no such mechanism:
  `scheduleAlarms` is reachable only from four UI call sites and from the handler when an alarm
  actually fires, and the calendar preload runs once at app startup. There is no periodic worker,
  no WorkManager, and no fewer-than-7-days trigger anywhere. R2's status calls this "not verified
  end-to-end", which understates it — it is not implemented.
- **Evidence:** `lib/screens/sleep_habits/screen_sleephabits.dart:72,77`,
  `lib/screens/alarms/screen_alarms.dart:188,231`, `lib/models/alarms/handler.dart:193` are the
  only callers; `lib/main.dart:242` is the only preload;
  `grep -rniE "workmanager|boot_completed" lib/` finds nothing of ours.
- **Done when:** either a background path exists and is tested, or R2 is rewritten to describe what
  the app actually promises.
- **Resolution:** the second half was chosen, deliberately and with reasons given. A periodic
  background worker is explicitly **not** built (battery drain, manufacturer-specific
  background limits — both `docs/choice-of-technologies.md` and FR-16 argue against it).
  Instead, every checkpoint hangs off an event that happens anyway: the alarm ringing
  (FR-8, inside the process the alarm itself started), the bedtime notification (FR-16
  Checkpoint 2), and the app coming to the foreground, as recovery after a reboot/force-quit
  (FR-17). Since every checkpoint replans and applies the **full** 7-day window (FR-8 + FR-18),
  "fewer than 7 days armed" cannot survive a checkpoint. R2 is rewritten accordingly and states
  honestly the one remaining limitation: the chain only keeps carrying itself along as long as it
  keeps ringing — if it breaks entirely and the app is never opened again, nothing gets replanned.
  That is R3/T-04, not T-32.
- **Requirement:** R2

---

## P1 — resolve or consciously accept before a public release

### T-157 · Camera and calendar permissions were requested unconditionally at first launch — FIXED (2026-09-20)

- [x] Request camera access only when the QR scanner actually opens.
- [x] Request calendar access only when the Schedule tab opens or "Sync Alarms" is pressed.
- [x] Leave exact-alarm/notification permissions requested upfront (unchanged).
- **Why:** `PermissionsManager.requestPermissions` (called once from the splash screen) used to
  request all four permissions - exact-alarm, camera, calendar, notifications - unconditionally at
  first launch, regardless of whether the user ever scans a code or opens the Schedule tab. A user
  who never uses the guaranteed-wake-up feature or calendar-derived scheduling was still asked to
  grant camera and calendar access before doing anything at all - the opposite of "ask for a
  permission at the point its need becomes obvious", which the maintainer asked for directly.
- **Fix:** `lib/utils/permissions.dart` gained two top-level, mutable function variables,
  `requestCameraPermission`/`requestCalendarPermission` (the same injectable-seam shape as
  `Handler`'s `runCheckpoint`/`sleep`), each guarded the same way `requestPermissions` already was
  (`Platform.isAndroid || Platform.isIOS`, a no-op under `flutter test`). `requestPermissions`
  itself no longer calls `checkCameraPermission`/`checkCalendarPermission` - only
  `checkScheduleExactAlarmPermission`/`checkAwesomeNotificationPermission` remain there, since an
  alarm clock needs those the moment it can schedule anything, not lazily.
  - `QrScanner.initState` (`lib/screens/scan_code/qr_scanner.dart`) now calls
    `requestCameraPermission()` - the one widget shared by both the initial code-import flow
    (`PageImportQr`) and the alarm-deactivation flow (`Handler.handleAlarm`), so one call site
    covers both.
  - `_ScreenScheduleState.initState` (`lib/screens/schedule/screen_schedule.dart`) calls
    `requestCalendarPermission()` when the Schedule tab is built.
  - The "Sync Alarms" `FloatingActionButton` (`lib/screens/alarms/screen_alarms.dart`) calls
    `requestCalendarPermission()` before running its checkpoint - a sync is meaningless without
    calendar access, so this is the second, explicit moment it's needed.
- **Tests:** `test/lazy_permissions_test.dart` (new) - overrides each seam with a fake and confirms
  it fires exactly when the corresponding screen/button is used, and that opening the alarms screen
  by itself does **not** request calendar access.
- **Interacts with T-41:** with camera/calendar permissions no longer requested on the splash
  screen at all, T-41's original framing ("show the privacy policy before or alongside the first
  permission prompt") needs revisiting against what the splash screen still actually requests
  (exact-alarm, notifications) - see T-41's own entry.
- **Requirement:** R7, R11

### T-156 · Copyright attribution updated to reflect joint authorship — FIXED (2026-09-20)

- [x] Add a second, consenting original developer to every copyright notice in the repository.
- [x] Record the third original developer's consent - to the licence, explicitly not to being
      named. Closed, not pending: their answer is final, not an open item waiting on a reply.
- **Why:** the project grew out of a university project with three original developers, but every
  copyright notice in the repository named only the current maintainer (Dam0k1es) as sole copyright
  holder - both `CLAUDE.md`'s licence line and `docs/licence-position.md` said so explicitly. Once
  more than one person's work is actually reflected in a joint work, attributing copyright to only
  one of them is inaccurate, independent of whether the licence terms themselves (GPLv3) are being
  followed correctly.
- **Fix:** the maintainer confirmed explicit consent from a second original developer, "centron5961",
  both to GPLv3 licensing and to this copyright attribution (2026-09-20). Added `, centron5961`
  after `Dam0k1es` in: the header of all 47 `.dart` files carrying the GPLv3 notice (`lib/` and
  `integration_test/`), the in-app `showLicensePage` legalese
  (`lib/screens/settings/page_aboutpage.dart`), `README.md`'s License section, `CLAUDE.md`'s licence
  line, and `docs/licence-position.md`. Also corrected two now-inaccurate "sole copyright holder"
  claims in living documents (`CLAUDE.md`, `docs/REQUIREMENTS.md` R8) to "the copyright holders" -
  left historical decision records in this file (T-33, T-35) worded as they were at the time,
  since those describe what was true when that specific decision was made, not a live claim.
- **The third original developer has since consented too (2026-09-20), explicitly to the licence
  only, not to being named as a copyright holder.** This is that developer's own deliberate choice,
  not a gap to close later - no third name is added anywhere in the repository, and none should be.
  `CLAUDE.md`'s licence line and `docs/licence-position.md` both now say so explicitly, so a future
  reader doesn't mistake the missing third name for an oversight or a still-open item.
- **Requirement:** R8, R9

### T-155 · The sleep-time reminder's own scheduled notification does not survive a reboot — RESOLVED, was a measurement timing artifact (2026-09-19)

- [x] Confirm whether `awesome_notifications` re-arms its scheduled notifications after a reboot on
      this app - confirmed it does; no boot-recovery path needed.
- **Investigated (2026-09-19):** `awesome_notifications`' native boot-restore path
  (`RefreshSchedulesReceiver` -> `NotificationScheduler.refreshScheduledNotifications`, source at
  `github.com/rafaelsetragni/AndroidAwnCore` - not in the pub-cache, since the "core" module ships
  as a compiled Maven artifact, `me.carda:AndroidAwnCore`, not Dart-package source) is plain native
  Java with **no Flutter engine/Dart isolate dependency at all**: for every persisted schedule id
  not already active on `AlarmManager`, it unconditionally re-arms via `schedule(...)` **unless**
  `notificationModel.schedule.hasNextValidDate()` is false, in which case it deliberately calls
  `ScheduleManager.removeSchedule` instead - correct cleanup, not a failure.
  This app's sleep reminder (`sleepReminderContent`/`scheduleSleepReminder`,
  `lib/utils/sleep_reminder.dart`) is scheduled as a **one-shot** `NotificationCalendar.fromDate`,
  not a repeating schedule. If that specific date/time had already passed by the moment of the
  reboot, `hasNextValidDate()` correctly returns false for a one-shot date in the past, and its
  removal is the *intended* cleanup path, not a restore failure. The real-device run that surfaced
  this (T-93, 2026-09-19T21:13:56Z) came after many hours of unrelated testing earlier the same
  session; whether the reminder scheduled at that point was still genuinely in the future at reboot
  time, or had already legitimately elapsed, cannot be determined from the captured evidence alone.
  **Downgraded from "confirmed gap" to "likely correct behavior, unconfirmed"** - building a custom
  native boot-recovery path (a real undertaking: our own `BroadcastReceiver`, a background Dart
  isolate entry point analogous to `onNotificationCreatedMethod`) is not warranted before a cheap
  re-check settles which case this actually was.
- **Needed to close this either way:** schedule a silent notification a couple of hours out (well
  past any plausible reboot/observation delay) on a real device, reboot, and check `dumpsys alarm`
  for the `me.carda.awesome_notifications.DartScheduledNotificationReceiver` tag specifically - if
  it is still there, this item closes as "not a bug, one-shot schedules simply expire as designed
  once their date passes with the app never reopened to recompute one"; if it is genuinely gone
  despite a still-future target time, the native restore path itself needs investigating further
  (an exception `AwesomeBroadcastReceiver.onReceive` swallows silently is the most likely next
  suspect, since every exception there is caught and only logged internally, never surfaced).
- **Re-check script, redesigned twice (2026-09-19):** `scripts/verify-notification-survival.sh`
  (self-test: `--self-test`, no device needed).
  - **First version:** used `flutter test integration_test/x.dart -d device` to schedule a
    notification 6 hours out through a prelude test, the same shape as
    `integration_test/arm_alarm_test.dart` for T-93. A real run hit
    `scheduleNotification: isAllowed: false` - `POST_NOTIFICATIONS` was never actually granted,
    because `flutter test` installs its own debug APK regardless of an earlier `adb shell pm
    grant`, and that install is a **fresh** one whenever the previously-installed app was signed
    differently (e.g. the maintainer's real production `current.apk`) - wiping the grant, and the
    app's data, before the test body ever ran.
  - **Second version:** fixed the permission race with `adb install -r -g` (grants every
    manifest-declared permission atomically at install time, as `.github/scripts/run_e2e_tests.sh`
    already does for the CI emulator leg) - but this still meant installing a debug build over the
    maintainer's production one, which the maintainer then explicitly ruled out entirely: *"Ich
    will in der Zukunft auf meinem Gerät keine dev version mehr. Nur noch gegen prod. Will keine
    Daten verlieren. Tests müssen das zwingend akzeptieren und sonst nicht ausgeführt werden."*
  - **Current version: fully read-only, no build/install/schedule step at all.** Checks
    `dumpsys package`'s `DEBUGGABLE` flag and **refuses to run** if the installed app is a debug
    build; reads whatever the production app already scheduled from ordinary use (nothing is
    created here - the sleep reminder schedules itself on the app's own next checkpoint); parses
    the specific schedule's `origWhen` epoch (`notification_origwhen_ms`, new in
    `alarm_detection.sh`) against the **device's own clock** to compute real lead time, and
    **refuses to run** if that lead time is below `--min-lead-minutes` (default 30) - the same
    ambiguity a too-short lead time caused for the original observation, now checked instead of
    assumed. Only if both preconditions hold does it proceed to the reboot.
  `has_scheduled_notification`/`notification_origwhen_ms` (`alarm_detection.sh`) match
  `package/receiver-class` together, not the receiver class alone (a shared plugin, other apps
  could use it too - the T-103 trap). Self-test gained four cases (7-10) against the real T-99
  recording and the foreign one.
- **Real run, first pass looked like a confirmed bug (2026-09-19T22:57Z, Fairphone 6):** 107
  minutes of lead time (well past `--min-lead-minutes 30`), rebooted, and the schedule was still
  gone after the script's fixed 20s post-`boot_completed` wait - `RESULT: FAIL`. Not a one-shot
  expiry this time (way too much lead time for that), so this looked like the real restore-path
  bug T-153/T-99's investigation had already made plausible.
- **Resolved by reading `adb logcat -d` right afterward, filtered for the plugin's own tags:**
  `DartRefreshSchedulesReceiver` had run **twice** - once ~15s after `boot_completed`, and again
  ~70 SECONDS after that, with only the second attempt logging
  `"[Awesome Notifications]: Scheduled created (NotificationScheduler:228)"`. The most likely
  explanation: this app's storage is credential-encrypted, so the first (early-boot) attempt
  cannot read the persisted schedule at all until the device is actually unlocked with its
  PIN/pattern - the second attempt, timed with the maintainer unlocking the phone, is the one that
  succeeded. The script's fixed 20-second wait measured **before** that second attempt ever ran,
  producing a false `FAIL`.
- **Fix:** `scripts/verify-notification-survival.sh` now prompts the maintainer to confirm the
  phone is actually unlocked before measuring at all, then polls (every 10s, up to 3 minutes)
  instead of a single fixed-delay check - matching how long the real restore actually took to
  complete once unlocked.
- **Conclusion: not a bug.** `awesome_notifications`' native restore path works correctly; the
  sleep reminder does survive a reboot, once the device is unlocked and enough time has passed for
  the (unlock-gated) second restore attempt to run. No app-side fix needed.
- **Why:** found incidentally while gathering T-93's real-device evidence (Fairphone 6, run
  2026-09-19T21:13:56Z), not the thing that run was measuring. `dumpsys alarm` before the
  intervention showed 9 of this app's own alarms under uid `u0a310`: 3 tagged
  `me.carda.awesome_notifications.DartScheduledNotificationReceiver` (the sleep-time reminder /
  FR-16 Checkpoint 2's hook) and 6 tagged `com.gdelataillade.alarm.alarm.AlarmReceiver` (the
  `alarm` plugin's own ringing alarms). After the reboot: 8 alarms, **all** tagged
  `com.gdelataillade.alarm.alarm.AlarmReceiver` - the three `awesome_notifications` entries are
  gone entirely (the alarm-plugin count going 6 -> 8 is consistent with the app's own
  reboot-recovery checkpoint successfully re-planning and re-registering those, exactly as
  intended - that part is working correctly). The same absence persists after the subsequent
  force-stop. `awesome_notifications` 0.12.1 *does* declare its own `BOOT_COMPLETED` receiver in
  its manifest, so this is not obviously "the library never tries" - whether its restore logic
  actually ran, needed more time than the reboot-recovery checkpoint's, or depends on something
  this app doesn't provide is unconfirmed.
- **Consequence if real:** a user who reboots their phone and does not reopen the app before the
  next scheduled bedtime reminder loses that reminder silently - and loses FR-16 Checkpoint 2's own
  entry point for that night, so a timezone change during the same window would also go
  unreinterpreted until the next checkpoint gets a hook some other way. This is a narrower version
  of T-04's own remaining "long dormant period, never reopened" gap, but specific to the
  notification-scheduling mechanism rather than the alarm-ringing one (which this same evidence run
  confirmed DOES survive both reboot and force-stop).
- **Evidence:** the real-device run above (evidence file not tracked in this repo - see T-93's own
  entry); `~/.pub-cache/hosted/pub.dev/awesome_notifications-0.12.1/android/src/main/AndroidManifest.xml`
  (`BOOT_COMPLETED` receiver declared); `lib/utils/sleep_reminder.dart` (`scheduleSleepReminder`,
  the only place that ever (re-)schedules this notification, and it is not itself called from
  anything a native boot receiver could trigger without the Dart engine already running).
- **Done when:** either confirmed as a real gap and fixed (most likely: re-run
  `scheduleSleepReminder` from wherever the app's own reboot-recovery checkpoint already runs, not
  relying on the plugin's own restore at all), or found to be a measurement artifact of this one
  run and re-verified.
- **Requirement:** R2, R3

### T-07 · Swiping the alarm notification away leaves the alarm screen up — RESOLVED (2026-09-18, see T-147)

- [x] Dismiss the full-screen alarm UI when the alarm ends through the notification.
- **Why:** confirmed on a real device: pressing *Stop* on the screen clears notification, screen and
  alarm correctly, but swiping the notification away ends the alarm while the screen stays on
  display, leaving the user on a dead overlay.
- **Evidence:** device test by the maintainer; `lib/screens/alarms/screen_active_alarm.dart`,
  `lib/utils/notifications.dart`, and the ringing subscription in `lib/main.dart:215-225`.
- **Fixed:** this is the same bug, reported again independently and only then diagnosed and fixed
  as T-147 - see that entry for the root cause (`NotificationSettings.androidStopAlarmOnDismiss`)
  and the fix (`RingingWatch`). Left as two entries rather than deleting this one, so the fact that
  it took a second independent report before it was connected to a root cause stays visible.
- **Done when:** the overlay closes on any path that stops the alarm, and the ringing-stream
  handler covers the notification-dismissal case. ✓

### T-08 · The QR deactivation gate has no negative test — FIXED (2026-09-19)

- [x] Cover the remaining bypass: the first scanned code being silently adopted as the deactivation
      code when none is set.
- **Why:** this is the app's differentiating security property, and only the *correct* payload was
  ever injected — deleting the payload comparison entirely would have kept CI green. Also untested:
  validation returns `true` when no code is stored, and the first scanned code is silently adopted
  as the deactivation code.
- **Evidence:** `integration_test/app_test.dart:141,165-167` (correct payload only, before this fix),
  `:179-180`; `lib/screens/scan_code/qr_scanner.dart:146-148` (the comparison), `:137-141` and
  `:112-119` (the bypasses).
- **Resolution so far (TDD - test written first):** extracted the pure comparison into a top-level
  `isDeactivationCodeValid(DeactivationCode?, String?)` in `qr_scanner.dart`, unit-tested in the new
  `test/qr_scanner_validation_test.dart` (6 cases, including the null-stored-code fail-open branch
  and a wrong/prefix/null scanned payload). `integration_test/app_test.dart`'s QR scenario now
  injects a wrong payload first and asserts `QrScanner` stays mounted and `Alarm.getAlarms()` is
  still non-empty, before injecting the correct payload.
- **Resolution of the remaining bypass (2026-09-19):** the "import this code if none is set" branch
  mutates `_appState` directly inside `setState` and has no pure function to extract the way
  `isDeactivationCodeValid` was - the concern was never that it behaves wrongly, but that nothing
  proved it, and a `Navigator.pop`-based close doesn't unmount the widget synchronously. A second
  scan event arriving on the same broadcast stream before the pop takes effect is still delivered
  to the same `State` object; the only thing preventing that second event from silently overwriting
  the just-imported code is that `_appState.deactivationCode == null` is re-checked on every event,
  so the second scan lands in the validation branch (and is rejected, since it won't match) instead
  of a second import. `test/qr_scanner_gate_test.dart` now has "a second scan arriving before the
  import screen finishes closing cannot overwrite the just-imported code", which fires two scans
  before any `pump()` (so both are dispatched within the same microtask queue, well before the pop
  has had a frame to remove the widget) and asserts the stored code stays the first one and the
  second is not wrongly accepted. Passed on the first run - not a bug found, but the exact gap the
  "was not extracted or tested" note named is now closed with a real regression test instead of
  staying an informal guarantee.
- **Requirement:** R4

### T-09 · The dismissal tests assert navigation, not that the alarm stopped — RESOLVED (2026-09-09)

- [x] Assert alarm state, not screen state — and stop swallowing stop failures in production.
- **Why:** both tests only checked that a screen disappeared, and both production paths navigated
  away even when stopping the alarm threw. No test queried the alarm plugin at all, so an alarm that
  kept ringing behind a dismissed overlay would have passed.
- **Evidence:** `integration_test/app_test.dart:132-133`, `:179-180` (before this fix);
  `lib/screens/alarms/screen_active_alarm.dart:125-135` (pop outside the `try`, before this fix);
  `lib/screens/scan_code/qr_scanner.dart:152-166` (catch → `return true` regardless, before this
  fix); `grep -rn "Alarm\." integration_test/` found no plugin query.
- **Resolution:** both dismissal paths now check the actual outcome instead of discarding it.
  `screen_active_alarm.dart`'s Stop button now checks `Alarm.stop`'s returned `bool` (previously
  discarded entirely) - on failure it shows a `SnackBar` and does not pop, rather than leaving the
  user behind a closed screen with a live alarm. `qr_scanner.dart`'s `_validateDeactivationCode` now
  `await`s `Alarm.stop` (it previously fired-and-forgot, so its own `catch` could never actually
  catch an async failure) and only closes the scanner if `Alarm.isRinging()` confirms nothing is
  still ringing afterward. `integration_test/app_test.dart` now asserts
  `expect(await Alarm.getAlarms(), isEmpty)` after both dismissals, not just that the screen
  changed.

### T-10 · The scheduling engine has no real tests — RESOLVED (2026-09-09)

- [x] Make the production scheduling functions testable and port the existing cases onto them;
      retire the forked scripts.
- **Why:** `flutter test` discovers only `test/**/*_test.dart`, so `test/adjustTime/` and
  `test/getEarliestAlarm/` never ran. They also did not import the app — and `test/adjustTime/`
  implemented helpers (`isBeforeTime`, `isAfterTime`, `isAtSameMomentAsTime`) and a two-pass
  algorithm that existed nowhere in `lib/`. Converting them as-is would have tested a fork, not the
  shipped scheduler. The 17 `getEarliestAlarm` cases were worth keeping; their harness printed
  results and exited 0 either way, so before porting them, this pass actually *ran* that harness
  (`dart run main.dart`) to confirm which of its own 17 cases it considered passing, rather than
  trusting the "expected" values in its `cases.dart` blindly.
- **Evidence (before this fix):** `grep -rn "isBeforeTime" lib/` → 0 hits; neither script imported
  `package:wakeywakey`; `test/getEarliestAlarm/main.dart:15-19` set no exit code.
- **Resolution:** `_getEarliestEvent`, `_adjustAlarmTimes` and `_getStartTimeForDate` were extracted
  out of `Scheduler` into top-level functions (`getEarliestEvent`, `adjustAlarmTimes`,
  `getStartTimeForDate` in `lib/models/scheduling/scheduling.dart`) taking plain values
  (`int sleepGoalMinutes`, `DateTime earliestAlarm`, `Duration wakeUpOffset`, `List<Meeting>`)
  instead of a whole `AppState`, so they're unit-testable without one. `Scheduler.scheduleAlarms`
  now calls these directly. New `test/scheduling_test.dart` (TDD - written and confirmed failing to
  compile before the extraction) has 26 cases: the 17 ported `getEarliestEvent` cases (corrected for
  a real unit mismatch the old script had - it took `sleepGoal` in whole hours and multiplied by 60
  internally, while production's `sleepGoal` parameter is already in minutes; passing the same
  scenarios with `sleepGoal` pre-converted to minutes exercises the identical comparison and expects
  the identical, verified results), plus new cases for `getStartTimeForDate` and `adjustAlarmTimes`
  (including one that pins down, rather than silently fixes, the T-02 date-dominated-comparison
  behavior). `test/adjustTime/` and `test/getEarliestAlarm/` are deleted, not quarantined - their
  value is now fully captured in the real test.
- **Requirement:** R2

### T-11 · Two of R1's five security tools cannot fail a run — RESOLVED (2026-09-09)

- [x] Make the pipeline itself enforce this (un-excepted HIGH findings must fail the run).
- **Why:** R1 asserted "no high-or-above finding — met", but `mobsfscan` ran with `--no-fail` and
  the MobSF step only printed counts with no threshold. The current MobSF report on master carried
  one HIGH (installable on Android 7.0 / `minSdk=24`) and a security score of 51 while the job
  concluded success. The task-hijacking finding R1 cited as a known false positive had its
  rationale written down nowhere.
- **Evidence (before this fix):** `.github/workflows/ci.yml:115` (`--no-fail`),
  `scripts/mobsf_summary.py` (prints only); MobSF report from the newest master run: `HIGH: 1`,
  `WARNING: 14`, `security_score: 51`; `grep -rniE "strandhogg|task.?hijack"` found only the two
  places that *cited* the rationale without recording it.
- **Resolution:** `docs/REQUIREMENTS.md` R1 documents which three tools gate the pipeline and which
  two don't, with the accepted rationale for both outstanding findings recorded in a tracked file
  for the first time. New `.github/security-exceptions.json` makes that rationale
  machine-readable, keyed by `mobsfscan` rule ID and `mobsf` finding title, each with a dated
  reason. New `scripts/mobsfscan_check.py` reads it against `mobsfscan`'s own JSON report and fails
  if any ERROR-severity, actually-triggered finding isn't excepted (tested locally: passes against
  the real current report with the accepted `android_task_hijacking2` exception in place; fails
  against an empty exceptions file with the same report). `scripts/mobsf_summary.py` similarly now
  takes the exceptions file and fails on an un-excepted HIGH (tested locally against synthetic
  reports: passes with the known exception, fails without it, fails when a second, unaccepted HIGH
  is added). `mobsfscan` keeps `--no-fail` deliberately - the new check script is what decides
  pass/fail now, distinguishing accepted from new findings, which a bare exit code couldn't. Since
  `mobsf-full-scan` structurally runs *after* `build-android-release` (it needs the built APK to
  scan), it can't have prevented that job's artifact upload - it now deletes the
  `app-production-apk` artifact via the Artifacts API if it fails, so a red MobSF result actually
  revokes the release rather than just marking the run red (see T-06).
- **Requirement:** R1
- **Requirement:** R1

### T-12 · The evidence several requirements cite is not in the repository — RESOLVED (2026-09-09)

- [x] Decide R6's remaining citation: commit the underlying review, or keep summarising inline.
- **Why:** `docs/quality-baseline-2026-09.md` and `docs/release-readiness-2026-09.md` are excluded
  by `.gitignore`, so anyone cloning this repo got a requirements register whose "checked by" and
  "met" justifications pointed at files that do not exist for them. They were referenced from
  tracked files in about a dozen places, including test-file headers and workflow comments.
- **Evidence:** `.gitignore:438-439`; `git ls-files docs/` lists six files, neither snapshot among
  them; citations were in `docs/REQUIREMENTS.md:19,30,33,71,76,122,140`, `CLAUDE.md:117,119,126`,
  `integration_test/app_test.dart:12,18`, `test/handler_stale_alarm_test.dart:1`,
  `.github/workflows/ci.yml:111`, `.github/workflows/release.yml:61`.
- **Resolution:** every requirement's evidence and rationale is now written directly into
  `docs/REQUIREMENTS.md` - R6's remaining citation was chosen resolved by fully inlining its
  three findings (no network SDKs from `lib/`, sandboxed filesystem access only, the
  `allowBackup` fix) rather than pointing at the gitignored file at all. The comment citations in
  `integration_test/app_test.dart`, `test/handler_stale_alarm_test.dart`, `ci.yml` and
  `release.yml` were also updated to point at tracked files (`docs/REQUIREMENTS.md`,
  `docs/TODO.md`) instead, except `release.yml`'s VM-recommendations pointer, which now says
  plainly that the doc it names is gitignored and only useful if you happen to have a local copy.
- **Requirement:** R1, R2, R6, R11

### T-13 · The tag → GitHub Release path has never run and would fail — RESOLVED (2026-09-09)

- [x] Give the release-attach step the permission it needs and dry-run the tag path once.
- **Why:** the documented release ritual was untested. No tag and no release existed, the attach
  step was skipped in every run so far, and the repository's default workflow token is read-only
  while `release.yml` declared `permissions:` only on its cleanup job — so the first real
  `v*.*.*` tag would have failed on permissions.
- **Evidence (before this fix):** `gh api …/tags` and `…/releases` both empty;
  `default_workflow_permissions: read`; `.github/workflows/release.yml`'s `build-signed-release`
  job had no `contents: write`.
- **Resolution:** added `permissions: {contents: write}` to `build-signed-release` (write implies
  read for the same scope, so no separate `contents: read` entry is needed). Dry-run tag
  `v0.0.0-throwaway-test` was pushed for real; its `release.yml` run's E2E job failed on an
  unrelated, already-known flake (T-23's minute-boundary race - the fail-fast check added
  earlier tonight caught it correctly: "Expected the created alarm to fire in ~1 minute, but it is
  scheduled for [next day] (1439 minutes from now)"), so the tag was deleted and retried as
  `v0.0.0-throwaway-test2`. That run passed end-to-end: `gh release view v0.0.0-throwaway-test2`
  confirmed a real GitHub Release with `app-release.apk` attached. Both the release and the tag
  were then deleted (`gh release delete ... --cleanup-tag`) to avoid leaving permanent clutter;
  `gh api .../releases` and `.../tags` both confirmed back to empty afterward.

### T-14 · Per-weekday repeat is inert — FIXED (2026-09-18)

- [x] Consult `repeatOnDays` when scheduling.
- **Why:** the selector is editable and persisted but never read when deciding when to fire, so
  manual alarms were effectively one-shot (today or tomorrow) while the UI promises a weekly
  pattern.
- **Evidence (before this fix):** `lib/models/alarms/manual_alarm.dart:7,17-19,25,39,53-54,74` and
  `lib/app_state.dart:323` were construction, serialization and comparison only — no scheduling
  decision read it.
- **Fix, part 1 - picking the right day:** `nextManualOccurrence` (`lib/models/alarms/
  manual_alarm_enable.dart`) now takes `repeatOnDays` and searches up to a week ahead for the
  earliest candidate that is both after `now` and falls on a selected day, rather than always
  resolving to "today or tomorrow". It is the single function `AppState._getAlarmTime` (creating an
  alarm), `applyManualAlarmEnabled` (the FR-21 toggle), and `Handler.onAlarmHandled` (see part 2)
  all go through - by design, so none of the three can resolve the same alarm to a different day
  than the others would (that guarantee predates this fix and is exactly why the signature was
  extended in place rather than adding a second function).
- **Fix, part 2 - actually repeating, not firing once:** a platform alarm is one-shot, so honouring
  `repeatOnDays` only when first arming would still make the alarm fire exactly once, on whichever
  selected day came first, and never again. `Handler.onAlarmHandled` - the one place every
  dismissal path already funnels through (the Stop button, the QR gate, and T-147's auto-close) -
  now re-arms a still-`enabled` `ManualAlarm` for its next selected day on every dismiss.
  `ScheduledAlarm`s are deliberately excluded from this (FR-18's domain; re-arming one here would
  reopen exactly the T-64 class of bug: a second, conflicting scheduling path).
- **`nextWakeUpTime` (the bedtime-reminder feed, `lib/models/scheduling/next_wake_up.dart`) had to
  change too:** it hand-rolled its own "today or tomorrow" resolution for manual alarms, which its
  own doc comment said was correct only because nothing else acted on `repeatOnDays` either. Once
  arming did, an independent computation here would have let the bedtime reminder recommend sleep
  for a "tomorrow" wake-up that `repeatOnDays` says will not actually ring. Now calls
  `nextManualOccurrence` too.
- **Test:** `test/manual_alarm_repeat_test.dart` (the day-search itself: a single selected weekday,
  wrapping across a week boundary, today's slot already passed with today selected, and the
  no-day-selected safety net), `test/handler_manual_alarm_rearm_test.dart` (the re-arm-on-dismiss
  wiring, via an injected `setManualAlarmEnabled` - the real `alarm` plugin has no channel in
  `flutter test`), `test/disabled_manual_alarm_test.dart` (unchanged, still green - confirms the
  extended signature doesn't disturb the existing FR-21 toggle behaviour with every day selected),
  and a new case in `test/next_wake_up_test.dart` for the bedtime-reminder fix.
- **Behaviour change worth knowing:** the alarm-creation dialog pre-selects only the current
  weekday (`screen_alarms.dart`), which most users never touch - a manual alarm created and left
  alone now silently becomes "repeat weekly on the day it was created", where before it fired once
  and then sat inert until manually re-armed. This was already what the UI's weekday-picker
  promised; it had simply never been true until now.

### T-15 · The gentle-wake ramp has no evidence of any kind — RESOLVED (2026-09-20, real-device evidence)

- [x] State plainly that it is unverified (the alternative to actually exercising the fade path) -
      superseded by the entry below.
- [x] **Manually validated on a real device (2026-09-20) by the maintainer:** the gentle-wake volume
      ramp (`VolumeSettings.fade`) was exercised directly, confirming the fade path actually runs and
      audibly ramps rather than jumping straight to full volume. This is real-device evidence, not an
      automated E2E scenario - the CI emulator still runs with audio disabled, so this remains outside
      what CI itself can catch a regression in.
- **Why:** a headline feature and half of R4. Gentle wake defaults to off, so no test enables it and
  the `VolumeSettings.fade` branch is never executed in CI; the CI emulator also runs without audio.
  The audio-focus log does show the app taking alarm-usage audio focus, which is genuine but says
  nothing about a gradual ramp.
- **Evidence:** `lib/app_state.dart:44` (`_gentleWakeUpEnabled = false`), `:485-489` (fade vs.
  fixed), `lib/screens/alarms/screen_alarms.dart:263` (dialog default);
  `grep -niE "gentle|fade|volume" integration_test/app_test.dart` → nothing; emulator started with
  `-noaudio`; 3 of 249 audio-focus polls show `usage=USAGE_ALARM`; maintainer's own real-device
  observation above.
- **Resolution:** `docs/REQUIREMENTS.md` R4 updated to record the real-device confirmation. An
  automated E2E scenario for the fade path (the CI-side half of this item's "done when") remains
  open, since the emulator still runs without audio - that is a CI/infrastructure gap, not a
  behavioural unknown any more.
- **Requirement:** R4

### T-16 · The QR test seam does not isolate the camera, and ships in release builds — LARGELY RESOLVED (2026-09-17)

- [x] The override now really bypasses the camera. With the scanner swap (T-33) the live preview is
      not built at all while `debugScanStreamOverride` is set, so nothing can auto-start a
      controller behind the seam's back, and the lifecycle handler no longer cancels and re-listens
      - it has nothing left to do, because the replacement widget owns its own camera. The
      "unrecoverable single-subscription" failure described below cannot occur any more.
- [x] The seam no longer leaks a scanner package's type: it carries the app's own `ScanResult`.
- [ ] Still open: it remains a plain mutable static, compiled into release builds. An injected
      dependency would be the proper fix, but `Handler.handleAlarm` constructs `QrScanner()` with
      nowhere to thread one through, so this needs a small design decision rather than an edit.
      What the seam now buys, and did not before, is the gate's negative unit test
      (`test/qr_scanner_gate_test.dart`, T-08).
- **Why:** with the override set, the scanner widget still starts the real camera because the
  controller auto-starts — so the "Test mode: never touch the real camera" comment is false. Worse,
  the resulting initialised controller defeats the lifecycle guard, so an `inactive` → `resumed`
  pair cancels the injected subscription and re-listens to the camera instead; the injected stream
  is single-subscription, so that is unrecoverable and the test fails for a reason unrelated to the
  app. The seam is also a plain mutable static compiled into release builds.
- **Evidence:** `lib/screens/scan_code/qr_scanner.dart:64-67` (early return), `:42-45` (controller),
  `:236` (`MobileScanner` still built), `:250` (label subscribes to the live stream), `:173-175`
  (the defeated guard), `:185` (resubscribes to the camera);
  `mobile_scanner-7.4.0/lib/src/mobile_scanner_controller.dart:29` (`autoStart = true`),
  `mobile_scanner.dart:208,221` (widget starts it).
- **Done when:** in override mode no camera is started, a lifecycle event cannot drop the injected
  stream, and nothing test-shaped is reachable in a release build (prefer an injected dependency
  over a static).

### T-17 · The privacy policy does not match the app — RESOLVED (2026-09-08)

- [x] Rewrite `assets/text/Privacy.md` against what the app actually does.
- **Why:** R11 reads "met", but that check only covered the contact address. The policy described
  data the app cannot collect (location, NFC) while omitting camera and the locally stored
  deactivation code/alarms.
- **Evidence:** `assets/text/Privacy.md` against the permissions in
  `android/app/src/main/AndroidManifest.xml` and the QR/calendar code paths. Re-verified while
  fixing this: `WRITE_CALENDAR` is declared but unused (`createOrUpdateEvent` is commented out in
  `lib/screens/schedule/calendar.dart:91`) - the app currently only *reads* the calendar (see T-161
  for why this can't simply be deleted from the manifest as-is), and
  `READ_EXTERNAL_STORAGE` is declared but never actually requested at runtime
  (`lib/utils/permissions.dart` requests only exact-alarm, notification, camera and calendar) -
  consistent with T-44's dead gallery-import button.
- **Resolution:** `assets/text/Privacy.md` rewritten to describe calendar reads, camera use for QR
  scanning, and locally stored alarms/settings/deactivation code; the location/NFC claim removed; a
  line added disclosing the plugin-derived `INTERNET` permission and that it sends nothing. R11 in
  `docs/REQUIREMENTS.md` corrected to state what the original review actually covered.
- **Requirement:** R11

### T-33 · Proprietary Google/ML Kit binaries are a second GPLv3 exposure — RESOLVED (2026-09-17)

- [x] Assessed **and** resolved. The maintainer chose to replace the scanner rather than grant a
      GPLv3 §7 linking exception, which as sole copyright holder he could have done in a few lines
      - the reasoning is in `docs/licence-position.md`. `mobile_scanner` is out, `flutter_zxing`
      (MIT, wrapping zxing-cpp under Apache-2.0) is in.
- [x] The swap introduced `ScanResult` (`lib/models/scan_code/scan_result.dart`): nothing outside
      `lib/screens/scan_code/` names a scanner package's type any more. That is what made this
      migration expensive in the first place - `BarcodeCapture` had reached into four widgets, the
      public test seam and the E2E suite - and it makes the next swap a one-file change.
- [x] The gate got the negative test it never had outside E2E
      (`test/qr_scanner_gate_test.dart`, T-08). Worth recording how it got there: the first two
      versions were **vacuous** - a mutation making `isDeactivationCodeValid` accept everything
      stayed green, because "the screen did not close" also depends on the alarm plugin, which has
      no channel in a unit test. The oracle is now `Diag.qrGate`, recorded at the moment the gate
      decides. Mutations in both directions (always accept, always refuse) are red.
- [x] `docs/licence-position.md` records the licence basis for the **whole** shipped set, which is
      what this item's acceptance criterion asked for, and
      `test/no_proprietary_dependencies_test.dart` keeps it true.
- **Why:** T-05 covers Syncfusion, but the QR feature itself links proprietary Google binaries:
  `mobile_scanner` pulls `play-services-mlkit-barcode-scanning` and `com.google.mlkit:barcode-scanning`,
  which ship under Google's terms rather than an open-source licence. For a GPLv3 work these raise
  the same "no further restrictions" question, and this one sits directly under the app's headline
  feature — so it cannot be resolved by swapping a calendar widget.
- **Evidence:** `mobile_scanner-7.4.0/android/build.gradle:66,69`.
- **Done when:** a tracked decision records the licence basis for the whole shipped dependency set,
  not just Syncfusion.
- **Requirement:** R8, R9

### T-34 · GPLv3 source-offer obligations are unaddressed for the distributed APK — RESOLVED (2026-09-20)

- [x] Decided: **the repository becomes public at the first public release**, rather than attaching
      a written §6(b) offer to each release. An offer would bind the maintainer to fulfil requests
      for three years and would need a contact address, which sits badly with this project's policy
      of keeping real personal details out of tracked files. Written down in
      `docs/licence-position.md`.
- [x] **Met (2026-09-20):** the repository was made public, confirmed via
      `gh repo view Dam0k1es/wakeywakey --json visibility` -> `"PUBLIC"`. `v1.0.0` was published as a
      GitHub Release the same day (the signed, verified production APK from CI run 35513763937,
      `apksigner verify` confirming the real production key, not the debug key) - the first actual
      conveyance of a GPLv3 binary, and the Corresponding Source obligation was already discharged
      by the time it happened.
- **Why:** the release workflow attaches a signed APK to a GitHub Release while the repository is
  private, and nothing publishes or offers the corresponding source. Conveying a GPLv3 binary
  carries that obligation; right now there is no mechanism and no written position.
- **Done when:** either the repository is public at release time, or the release carries a written
  source offer that someone could actually act on. **Met.**
- **Requirement:** R9

### T-35 · The LICENSE header breaks licence detection and strips the copyright from the build — PARTIALLY RESOLVED (2026-09-08)

- [ ] Confirm GitHub re-detects GPL-3.0 after the fix, and give the app an in-app notices surface.
- **Why:** two lines were prepended above the licence text, which was enough for GitHub to classify
  the repository as `NOASSERTION / Other` — so the README badge was the only licence signal a
  visitor got — and it also meant Flutter's licence collector shipped the bare GPLv3 text without
  the project's own copyright notice anywhere in the app.
- **Evidence:** `LICENSE:1-2` (before this fix); `gh api repos/Dam0k1es/wakeywakey` returned
  `license.spdx_id: NOASSERTION`.
- **Resolution so far:** the two lines are removed from `LICENSE`, which now starts directly with
  the canonical GPLv3 text; the copyright notice moved to `README.md`'s License section instead
  (`Copyright (C) 2026 Dam0k1es`).
- **GitHub detection confirmed (2026-09-18):** `gh api repos/Dam0k1es/wakeywakey --jq '.license'`
  now returns `spdx_id: GPL-3.0`, not `NOASSERTION`.
- **Still open:** the app itself still has no in-app licence/notices screen to carry the copyright
  to an end user - that's T-36, unchanged by this fix.
- **Requirement:** R9

### T-36 · The app has no third-party licence or notice surface — FIXED (2026-09-18)

- [x] Add a licences screen (e.g. `showLicensePage`) reachable from the About page.
- **Why:** Flutter embeds the dependency notices in the binary, but nothing in the app displayed
  them, so the notice-retention obligations of the BSD/MIT/Apache dependencies — and GPLv3's own
  requirement to make the licence available to the user — were not met in the shipped product.
- **Evidence (before this fix):** `grep -rn "showLicensePage\|LicensePage\|NOTICES" lib/` → 0 hits.
- **Fix:** two buttons at the bottom of the About page (`lib/screens/settings/page_aboutpage.dart`):
  - **"License"** opens a new `PageLicense` (`lib/screens/settings/page_license.dart`) showing the
    project's own GPLv3 text as plain, selectable text - not Markdown, since a licence's exact
    indentation and line breaks are part of the document, and a Markdown renderer reflowing it is
    exactly the corruption this page exists to avoid. It reads the real root `LICENSE` file
    directly (`pubspec.yaml` now bundles `LICENSE` itself as an asset, not a copy under `assets/`),
    so there is exactly one copy to ever go out of sync.
  - **"Third-Party Licenses"** calls Flutter's own `showLicensePage()`, which already collects
    every dependency's licence text at build time - the fix here was making it reachable at all,
    not collecting anything new.
- **Test:** `test/page_aboutpage_licenses_test.dart` and
  `test/page_aboutpage_third_party_licenses_test.dart`. Two files, not one, for the same reason
  `qr_scanner_gate_test.dart`/`qr_scanner_close_test.dart` are split: the two cases fail paired in
  one isolate but pass alone and in every other pairing tried - `LicensePage`'s own progress
  indicator animates indefinitely while it enumerates every bundled licence, which is also why that
  test uses explicit `pump()` calls rather than `pumpAndSettle()` (which would wait on it forever).
- **Done when:** a user can read the licence and third-party notices from inside the app. ✓
- **Requirement:** R9

### T-37 · The E2E suite runs on no routine trigger — RESOLVED (2026-09-09)

- [x] Run the integration tests on pushes/PRs, not only on a tag or a manual dispatch.
- **Why:** the E2E gate is the project's strongest quality evidence, but `ci.yml` did not reference
  the integration tests at all — they existed only in `release.yml`, which fires on a `v*.*.*` tag
  or manual dispatch. Since no tag had ever been pushed, the gate had never protected a normal
  change; every commit so far reached `master` without it.
- **Evidence (before this fix):** `grep -c integration_test .github/workflows/ci.yml` → 0;
  `.github/workflows/release.yml:3-7` (triggers).
- **Resolution:** the `e2e-tests` job was extracted out of `release.yml` into a reusable workflow
  (`.github/workflows/e2e-tests.yml`, triggered via `workflow_call`), so its ~80 lines of emulator
  setup exist in one place. Both `release.yml` and `ci.yml` now call it (`uses:
  ./.github/workflows/e2e-tests.yml`) - in `ci.yml`, scoped to `master` pushes and PRs into it, same
  as the other heavier checks, to keep `dev` pushes fast per the "consider the runtime cost"
  guidance here. `build-android-release` in `ci.yml` now also depends on it (see T-06).
- **Verification note:** confirmed by a real run - pushing the commit that made this change
  triggered `ci.yml` on `master`, and its `E2E tests (real emulator) / E2E tests (real emulator)`
  job (the `workflow_call` naming convention, confirming the reusable workflow is genuinely being
  invoked, not just parsed) completed successfully, followed by `build-android-release` actually
  running (all its `needs:` had passed) and `mobsf-full-scan` passing with the expected accepted
  exceptions applied (see T-11).

### T-38 · The QR gate has unconditional bypasses — FIXED (2026-09-19)

- [x] A real-device report found the emergency-stop bypass itself could be permanently withheld:
      fixed.
- [x] The handler's own 3-second fallback gave up after a single failed attempt to show the
      overlay: now retries, at the maintainer's request.
- [x] An honest sentence about these fail-safes in the feature description itself, and a written
      rationale beyond the code comments below - the original ask.
- **Why:** the "guaranteed wake-up" promise has escape hatches: if no overlay can be shown, the
  handler waits three seconds and calls `Alarm.stopAll()`; the scanner also offers an emergency-stop
  button when the camera fails. These are defensible as fail-safes — being locked out by a broken
  camera is worse — but they are undocumented, untested, and not mentioned where the feature is
  advertised.
- **Real-device report, the emergency-stop bypass itself had a gap:** "wenn ich mit meinem HW
  Killswitch die Kamera deaktiviere kommt kein Notfall-Stopp-Button" (disabling the camera with a
  hardware kill-switch does not bring up the emergency stop button). Root cause: the button's
  trigger, `_proofOfLifeTimer` (20s at the time), is cancelled by `_noteScannerAlive()` the moment
  ANY scan attempt runs - success, wrong code, or a plain "no code in this frame" `onScanFailure`. A
  hardware kill-switch (or a lens physically covered) can leave the camera producing a permanently
  black/blank feed: frames keep arriving, `ReaderWidget` keeps attempting to decode them, and each
  attempt legitimately reports "no code found" - proof-of-life stays satisfied forever, which is
  indistinguishable, from this screen's side, from "the user just hasn't held the code up yet". The
  escape hatch could therefore be withheld permanently from someone whose camera is physically
  blocked, which is worse than the six already-documented "camera never even starts" failure modes
  this timer was built for - at least those left proof-of-life unsatisfied.
- **Fix:** a second, independent `_maxScanDurationTimer` that fires regardless of
  `_scannerProvedAlive` - "the camera is running" and "the camera can see anything useful" are
  different questions, and only the first one was previously checked.
- **Tightened further (2026-09-19), at the maintainer's request:** `_proofOfLifeTimeout` 20s → 10s,
  `_maxTimeWithoutValidScan` 60s → 30s. Both escape hatches now offer themselves noticeably sooner.
- **Tests:** `qr_scanner_gate_test.dart`'s new case keeps proof-of-life continuously satisfied
  (repeated wrong-code scans) throughout and confirms the button still appears once the longer
  timeout elapses - red before the second timer existed, confirmed by reverting it and re-running.
- **A second, related gap the maintainer asked for directly:** the handler-side 3-second fallback
  (`Handler.handleAlarm`, `lib/models/alarms/handler.dart`) used to try showing the ringing overlay
  exactly once - a single `context.mounted` failure (the likeliest cause, e.g. the app is still
  finishing its own startup right as the alarm fires) gave up immediately and fell straight through
  to `Alarm.stopAll()` after 3 seconds, with no chance for `context.mounted` to flip back to true a
  moment later. Fixed by retrying: `_showOverlayWithRetries` tries up to `maxOverlayAttempts` (5)
  times, `overlayRetryDelay` (3s) apart, before the same final 3-second wait and `Alarm.stopAll()`
  as before - roughly 15 seconds of genuine retrying, matching the maintainer's own numbers,
  instead of giving up after the very first failure. `Handler` gained an injectable `sleep`
  function purely for testability (`Future.delayed` would otherwise make a test wait real
  wall-clock seconds).
- **Test:** `handler_overlay_retry_test.dart` - a context unmounted right after constructing the
  `Handler` (so every overlay attempt fails exactly like a real "no longer mounted" case) proves
  exactly 5 attempts happen, 3 seconds apart (asserted against `Handler.maxOverlayAttempts`/
  `overlayRetryDelay` directly, not a hardcoded number, so the test can't silently drift from the
  constants it's meant to guard); a counter-test confirms a context that stays mounted succeeds on
  the first attempt and never sleeps at all.
- **Also renamed and enlarged, at the maintainer's request:** the emergency-stop button's label was
  a generic "Stop alarm" - the same wording a "just give up" button would use, with nothing telling
  the user *why* they're seeing it. Now "Camera not working - Stop alarm" with a matching
  `Icons.videocam_off` icon (was `Icons.notifications_off`, which reads as "mute", not "camera
  broken"), and bigger (larger padding and text) - this is the one control standing between someone
  and an alarm they otherwise cannot stop, and it should read and hit like it.
- **Evidence:** `lib/models/alarms/handler.dart:169-176` (the still-undocumented handler-side
  bypass); `lib/screens/scan_code/qr_scanner.dart` (`_proofOfLifeTimer`/`_maxScanDurationTimer`).
- **Written rationale and honest sentence (2026-09-19):** `README.md`'s "Guaranteed Wake-Up" bullet
  now says plainly that "guaranteed" isn't absolute and points to the full rationale;
  `docs/REQUIREMENTS.md` R4 gained a "Fail-safes, and why 'guaranteed' isn't absolute" paragraph
  covering both bypasses, why each exists, and how each is tested - a place a reader looking for
  the feature's actual guarantees would find it, rather than only in code comments.
- **Done when:** each bypass has a test, a written rationale, and an honest sentence in the feature
  description.
- **Requirement:** R4

### T-39 · The QR gate is enforced only in the Flutter UI layer — FIXED (2026-09-19)

- [x] Make alarm dismissal depend on validation somewhere the UI cannot bypass.
- **Why:** the whole gate hung off one `Alarm.ringing` subscription in `_MyHomePageState`
  (`lib/main.dart`) plus a `context.mounted` check. If that one screen widget was not alive when an
  alarm fired, nothing enforced the scan requirement — the strength of the app's differentiating
  feature depended on widget lifecycle. It also meant the gate was not wired at all while
  `SplashScreen` was showing, before the first permission grant.
- **Evidence (before the fix):** `lib/main.dart:215-225` (the old inline subscription);
  `lib/models/alarms/handler.dart:140,154`.
- **Fix:** new `lib/models/alarms/alarm_ring_gate.dart` (`AlarmRingGate`) owns the one
  `Alarm.ringing` subscription and diffing logic, injectable (`ringingStream`, `buildHandler`) for
  testing without the real plugin. Ownership moved from `_MyHomePageState` up to `_MyAppState` -
  `MyApp` is now a `StatefulWidget` holding a `GlobalKey<NavigatorState>` and constructing
  `AlarmRingGate(navigatorKey)` in its own `initState`/`dispose`. That key is passed to
  `MaterialApp(navigatorKey: ...)`, so `AlarmRingGate` dispatches through the root Navigator's own
  context - which lives inside `MaterialApp`'s `Overlay` (required for `Handler` to show the
  ring/QR overlay) but, unlike any individual screen, is not recreated when `MaterialApp`'s `home:`
  switches between `SplashScreen` and `MyHomePage`. The gate is therefore now wired for the whole
  app run rather than for as long as `MyHomePage` specifically stays mounted - and it now also
  covers the splash-screen window, closing a second, previously undocumented gap.
  Deliberately **not** a bare process-wide static: `_MyHomePageState`'s own history (see the
  comment this replaced) already found that exact failure mode once - a static subscription
  guarded by `??=` kept the first `Handler`/`AppState` pairing alive forever, ignoring every
  `AppState` created afterwards, which happens routinely across `flutter test`'s separate
  `pumpWidget` calls sharing one process. Scoping the gate to `_MyAppState`'s own lifecycle (one
  real app run, or one test's pumped widget tree) avoids reintroducing that bug while still moving
  ownership up and out of a swappable screen widget.
- **Tests:** `test/alarm_ring_gate_test.dart` (new) - injects a fake stream and a recording
  `Handler` subclass (the same subclassing approach as `test/handler_overlay_retry_test.dart`,
  since `Handler`'s constructor itself needs a `Provider<AppState>` ancestor). Covers: no dispatch
  before any Navigator context exists (skipped, not crashed); dispatch once a context exists;
  diffing (a repeated event for a still-ringing alarm is not re-dispatched, two simultaneous alarms
  are each dispatched exactly once); `stop()` cancels the subscription. `test/widget_test.dart` (the
  plain `MyApp` smoke test) continues to pass unchanged, confirming the gate does not break the
  splash-screen path it now also covers.
- **Requirement:** R4

### T-40 · No CI check is actually enforceable — RESOLVED (2026-09-24)

- [x] Decide how the "must pass before master" rule is enforced, given the repository's plan.
- **Why:** the requirements register says its checks must be guaranteed "before any push to
  `master`", but branch protection and rulesets were unavailable on this repository while private,
  every commit went straight to `master` with zero pull requests, and CI runs after the push anyway.
  A red run cannot stop anything on its own. This undercuts T-06 and T-11: gating the release build
  is necessary but not sufficient while nothing can block a push.
- **What changed (2026-09-24):** the repository is now public (T-34) - the original 403 ("Upgrade
  to GitHub Pro or make this repository public") is gone, and rulesets are genuinely available now.
  That does **not** solve the core problem, though, for a structural reason confirmed against real
  GitHub behaviour: a ruleset's "required status checks" rule blocks a push unless the commit being
  pushed already has a passing check recorded against its SHA - and a commit's `master`-only checks
  (`security-gate`, `e2e-tests`, `build-android-release`, `mobsf-full-scan`) cannot possibly exist
  before that same push triggers them for the first time. Requiring them would make every direct
  push to `master` fail immediately, forever - not a partial gap, a chicken-and-egg dead end for
  exactly the checks that matter most. The only status check that *can* legitimately already exist
  on a commit before it reaches `master` is `ci.yml`'s `dev`-push check (`Analyze & Test`), since
  `master` is always a fast-forward of `dev` - the identical commit SHA, already checked, moving to
  a new branch pointer rather than a new commit being created.
- **Decided (maintainer, 2026-09-24): the release-tagging half is a process rule, not a GitHub
  ruleset.** Never tag a release until `ci.yml`'s own `master`-push run for that commit is confirmed
  green - documented in `CLAUDE.md` next to `release.yml`'s own description. A GitHub ruleset on
  `refs/tags/v*.*.*` requiring the `master`-gate checks *would* have been technically possible here
  (a tag is created strictly after the `master` run completes, so the chicken-and-egg problem this
  entry describes above doesn't apply to tags) - explicitly considered and declined as unnecessary
  GitHub-config surface for what a documented habit already covers, especially since `release.yml`
  independently re-verifies everything at tag time regardless (a bad tag still cannot produce a
  signed release either way - this rule is about not burning the expensive gate a second time on a
  commit already known red, not about release safety, which doesn't depend on it).
- **Done (maintainer, 2026-09-24): the inert ruleset now actually targets `master`.** "Branch
  Protection" (id 23728728) had `deletion`/`non_fast_forward` rules but targeted no branch at all
  (`conditions.ref_name.include` was empty, apparently left that way since being auto-created around
  when the repo went public) - re-pointed at `refs/heads/master` via `gh api .../rulesets/23728728`
  (PUT), on the maintainer's explicit request. `master` can no longer be deleted or force-pushed/
  history-rewritten; a normal fast-forward push (the only kind this project's own workflow ever
  does) is unaffected. Confirmed live via a follow-up `GET` on the same ruleset.
- **Done (maintainer, 2026-09-24), after an explicit request to check for problems first - none
  found that weren't already mitigated:** the same ruleset now also requires all seven of `dev`'s
  own checks (`Analyze & Test (TZ=UTC)`, `...Europe/Berlin`, `...Asia/Tokyo`, `...America/St_Johns`,
  `...Pacific/Chatham`, `...Australia/Lord_Howe`, and `Build Android (development)`) to already show
  `success` on a commit's SHA before it can be fast-forwarded onto `master`. Verified live, not just
  configured: pushed a real commit to `dev`, watched all seven checks actually reach `success`
  (`gh api repos/.../commits/<sha>/check-runs`), confirming both the exact context-name strings and
  that this genuinely completes for a normal push - not just that the ruleset accepted valid JSON.
  - **Why this is enforceable at all, when `master`'s own gate isn't (see above):** `dev`'s checks
    are already complete by the time a promotion is attempted - promoting is a separate, later
    action, not the same push that triggers them. No chicken-and-egg problem here, unlike requiring
    `master`-only checks (`security-gate`, `e2e-tests`, `build-android-release`, `mobsf-full-scan`)
    against `master` itself, which remains structurally impossible for the reason above.
  - **Real, checked-for consequences, not hidden:** promoting now means waiting for `dev`'s CI
    (~8 minutes, six timezones in parallel) to actually finish before `git -C /mnt/wakeywakey merge
    --ff-only dev && git push` will succeed - a genuine process change, not just a formality, from
    whatever was possible before. A commit made directly on `master` (bypassing `dev` entirely) can
    no longer be pushed there at all, by design - matches the project's own stated workflow ("work
    goes on `dev`") rather than contradicting it.
  - **The one real fragility identified, and mitigated:** if `ci.yml`'s timezone matrix or the
    `build-dev-apk` job's name ever changes, the required-checks list must be updated in the same
    change or `master` becomes permanently un-fast-forwardable (a check name that will never report
    again can never be satisfied). Mitigated with a `bypass_actors` entry (the repository owner,
    `bypass_mode: "always"`) - the same escape hatch that also covers a GitHub Actions outage/quota
    exhaustion like September 2026's, which without a bypass this rule would have turned into "and
    now `master` cannot be updated either," compounding rather than helping that incident.
  - **Full configuration recorded in `CLAUDE.md`** ("Branches and where work happens") rather than
    only here, since it changes the day-to-day promotion workflow, not just a policy decision.
- **Requirement:** R1

### T-41 · Permissions are requested before the privacy policy is reachable — FIXED (2026-09-20)

- [x] Present the data-handling information before or alongside the first permission prompt.
- **Why:** calendar, camera, exact-alarm and notification permissions used to all be requested from
  the splash screen at first launch, while the privacy policy was only reachable later through
  Settings. For a project claiming GDPR alignment, the transparency step came after the consent
  step.
- **Narrower after T-157 (2026-09-20):** camera and calendar are no longer requested on the splash
  screen at all - they moved to the point of actual need (opening the QR scanner, opening the
  Schedule tab / pressing "Sync Alarms"). The splash screen now only requests exact-alarm and
  notification access, so this item's remaining scope is smaller than originally written, but the
  same ordering problem still applied to those two.
- **Fix:** `SplashScreenState` (`lib/main.dart`) now shows `assets/text/Privacy.md` (the same file
  and `Markdown` widget the About page already used) as its own first screen, with a "Continue"
  button, and defers `_requestPermissions()` until that button is pressed
  (`_onPrivacyAcknowledged`). Nothing is requested before the user has at least been shown what the
  app collects.
- **Tests:** `test/privacy_before_permissions_test.dart` (new) - the policy is shown and
  `AppState.permissionsGranted` stays false until "Continue" is pressed, at which point it becomes
  true (the oracle is `AppState`, not the transient "Checking permissions..." frame - on the test
  host platform the whole permission flow is a no-op that resolves within the same pump as the tap,
  too fast to reliably observe the intermediate frame). `test/widget_test.dart` updated for the new
  first screen.
- **Done when:** a first-run user can read what is collected before granting anything.
- **Requirement:** R7, R11

### T-49 · Requirement claims about permissions do not match the built APK — PARTIALLY RESOLVED (2026-09-08, again 2026-09-17)

- [x] The merged manifest is now compared against what the app actually does, not just read. The
      scanner swap (T-33) changed the set in three ways, found by diffing `aapt2 dump permissions`
      on the APKs before and after:
      **`INTERNET` disappeared** - it came with the proprietary ML Kit stack, so an app that
      advertises itself as fully offline stopped asking for network access as a side effect of a
      licence fix (R7 updated);
      **`RECORD_AUDIO` appeared**, merged in by `camera_android_camerax`, which the new scanner
      pulls. The scanner creates its controller with `enableAudio: false`, so it is never used -
      an alarm clock asking for the microphone is exactly the unexplainable permission this item
      is about, and it is removed again with `tools:node="remove"`;
      **`WRITE_EXTERNAL_STORAGE` (maxSdk 28) appeared** and is removed the same way. It comes from
      the same camera plugin; an independent audit corrected an earlier claim here that blamed
      `image_picker`, whose manifest declares no permissions at all. `image_picker` did lose its
      direct entry in `pubspec.yaml` - nothing in `lib/` had used it since the gallery button went
      (T-44).
- [x] **A fourth change the permission diff could not show:** the merged manifest gained
      `<uses-feature android:name="android.hardware.camera.any">` **without** `android:required`,
      which defaults to true, where the previous scanner declared the camera not required. That
      would have let the Play Store hide an alarm clock from camera-less devices over an optional
      QR gate. Both camera features are now declared `required="false"` with `tools:replace`.
      Lesson for this item: `aapt2 dump permissions` does not show `uses-feature`, so the
      comparison has to be `aapt2 dump badging` or the merged manifest itself.
- [ ] Still open: the full "name every permission and say why" table, and a traffic capture during
      an E2E run.
- [x] **`ACCESS_NETWORK_STATE` removed and now confirmed safe (2026-09-20).** Traced (2026-09-18)
      via `aapt2 dump permissions` plus Gradle's
      `android/app/build/outputs/logs/manifest-merger-blame-*-report.txt` to two transitive
      sources, not one: `androidx.media3:media3-common:1.9.0` (the `alarm` plugin's audio playback
      stack) **and** Google's `transport-runtime`/`transport-backend-cct` (pulled in by
      `awesome_notifications`, its own internal event-transport plumbing, not this app's calendar
      sync) - not to anything network-related in this app's own code, consistent with `INTERNET`
      already being gone. Removed with `tools:node="remove"`, the same pattern as
      `READ_EXTERNAL_STORAGE`/`RECORD_AUDIO`/`WRITE_EXTERNAL_STORAGE` above; confirmed absent from
      a real release build's merged manifest and `aapt2 dump permissions` output. The caution this
      entry originally raised - that `media3` uses `ConnectivityManager` internally, so removing the
      permission could plausibly break an audio codepath silently - is now closed: the maintainer
      ran tone selection, the gentle-wake ramp and a custom tone across four real-device scenarios
      (open app, backgrounded+locked, and two reboot scenarios) on this exact build, and audio
      played correctly in every one. One of those four scenarios surfaced an unrelated, more
      significant finding - see T-158.
- **Why:** R7 asserted "no user data leaves the device — met" on the basis of a check scoped to
  Dart source in `lib/`, but the shipped APK declares `INTERNET` and `ACCESS_NETWORK_STATE`, pulled
  in through plugin manifest merging. That does not prove data leaves the device, and the offline
  claim may well still hold — but it cannot be closed with a source grep while the app has network
  capability. R4 had the mirror-image problem: it cited the app manifest as evidence that the
  camera permission is declared, and the app manifest does not declare `CAMERA` at all; it too
  arrives via merge.
- **Evidence:** `android/app/src/main/AndroidManifest.xml:51-64` (no `INTERNET`, no `CAMERA`);
  the merged manifest and `aapt2 dump permissions` on the built APK show `INTERNET`,
  `ACCESS_NETWORK_STATE`, `CAMERA`, `BROADCAST_CLOSE_SYSTEM_DIALOGS`, `READ_APP_BADGE` and several
  vendor launcher-badge permissions.
- **Resolution so far:** R4 and R7 in `docs/REQUIREMENTS.md` now both cite the merged manifest
  rather than the app's own, name the specific permissions involved (`INTERNET`,
  `ACCESS_NETWORK_STATE`, `CAMERA`), and state explicitly that the offline claim rests on an
  absence of evidence rather than a positive check. `assets/text/Privacy.md` also now discloses the
  plugin-derived `INTERNET` permission to end users.
- **Still open:** neither requirement yet names *every* permission the shipped app holds
  exhaustively, and no traffic capture during an E2E run has been added as positive evidence for
  the offline claim (a code/CI change).
- **Requirement:** R4, R7

---

## P2 — real work, does not block a release

### T-18 · Add a snooze button with configurable limits — CLOSED, superseded by T-138 (2026-09-24)

- [x] Implement snooze, plus Sleep-Habits settings for maximum snooze count and interval.
- **Why:** requested feature; the ringing UI currently offers only stop.
- **Done when:** snoozing re-arms the alarm after the configured interval, stops after the
  configured maximum, and both settings persist. **All three met, via a different mechanism than
  originally asked for:** T-138 (FR-20, written and implemented separately, before this item was
  revisited) gives snooze a configurable interval (`snoozeTime`, in Sleep Habits) and re-arms the
  alarm after it (`SnoozeButton`/`snoozeRingingAlarm`) - both settings persist. What it does **not**
  do is a plain snooze *count* limit; instead it bounds snoozing by a time *budget*
  (`durationToWakeUp`, "the time to become awake"): `SnoozeButton` only renders while
  `canSnooze()` says budget remains, and disappears once it's spent - functionally the same
  guarantee ("stops after a configured maximum") this item asked for, deliberately implemented as a
  budget rather than a raw count because a count alone can't guarantee the user is out the door on
  time regardless of the interval chosen (see T-138 and T-19, which explains why
  `durationToWakeUp` was given this specific role).
- **Requirement:** R2, R3, R4

### T-19 · Merge "duration to wake up" and "duration to get ready" into one field — CLOSED, no longer applicable (2026-09-20)

- [x] ~~Collapse the two durations into a single value.~~ Decided against, at the maintainer's
      request: the two fields are no longer redundant.
- **Why originally raised:** at the time, both durations were just subtracted from the appointment
  time with no other distinction, and "the user has to fill in two numbers that do the same thing"
  was a fair complaint.
- **Why it no longer applies:** FR-20 (snooze, T-138) gave `durationToWakeUp` its own, disjoint
  role - it is the snooze budget (`lib/models/alarms/snooze.dart`: "the budget is `wakeUpBudget` -
  `durationToWakeUp`, the time to become awake"), consumed on its own by
  `lib/screens/alarms/snooze_button.dart`. `durationToGetReady` kept its original role (time to get
  ready before leaving) and additionally gained a per-weekday override
  (`durationToGetReadyByWeekday`) that has no equivalent for `durationToWakeUp` at all. Both are
  still added together in `scheduling_v2.dart` (`appointment - durationToWakeUp -
  durationToGetReady`) to compute the wake instant, but they now answer two different questions -
  merging them would collapse the snooze-budget concept back into an undifferentiated number,
  losing exactly the distinction FR-20 needed.
- **Done when:** closed as "no change wanted", as of this entry.

### T-20 · Add explanatory help buttons to every Sleep-Habits option — IMPLEMENTED (2026-09-24)

- [x] Put a "?" button in the top-right of each Sleep-Habits element showing a short explanation.
- **Why:** requested; the options are not self-explanatory.
- **Done when:** every option has one, the text is concise enough to read on a phone, and the
  styling follows the existing elements. All met: nine tiles, nine distinct explanations
  (`test/screen_sleephabits_help_test.dart` checks both the count and that no two are the same
  copy-pasted text), each capped at 140 characters.
- **Implementation:** `_buildTile`'s optional `help` parameter renders a small `IconButton`
  (`Icons.help_outline`, `Positioned(top: 0, right: 0)` over the tile's `Card`) that shows the text
  via a `SnackBar`. **A `Tooltip` with `triggerMode: TooltipTriggerMode.tap` was tried first**, since
  it needs no extra state and looks like the obvious fit for "tap a small icon, see a short
  explanation" - but its tap gesture proved unreliable once embedded in this screen's
  `SingleChildScrollView` with several tiles stacked on top of each other: it worked in an isolated
  repro widget, not on the real screen, and chasing the gesture-arena interaction wasn't worth it
  for a "?" button. `IconButton` + `SnackBar` are both plain, well-tested Material widgets and were
  reliable immediately.
- **Test-writing note, not a product bug:** the widget test that taps through all nine buttons in a
  loop needed two fixes that have nothing to do with the feature itself - `pumpWidget`ing an
  unrelated tree between iterations (Flutter reuses `ScaffoldMessenger` state, and with it a
  previous iteration's `SnackBar`, across `pumpWidget` calls that build an equivalently-shaped
  tree), and `tester.ensureVisible()` before tapping (the screen scrolls, so later icons exist in
  the tree before they're actually on screen).
- **Known, accepted follow-up (independent review, 2026-09-24):** on a narrow phone (~360px width)
  the help `IconButton` overlaps a tile's own trailing `Switch` by roughly 4px×30-40px on the three
  tiles whose entire content is a bare `SwitchListTile` ("Schedule an alarm on days without an
  appointment", "Enable Reminder", "Gentle WakeUp") - confirmed geometrically by the review agent,
  not just eyeballed. Both controls remain individually tappable (the overlap is visual, not a hit-
  test conflict), and the agent's own verdict was this doesn't block the push. Left undone rather
  than rushed into this same change: reserving trailing padding on just those three tiles so the
  Switch never sits under the icon.
- **Follow-up (2026-09-24, T-166):** four tiles' separate, always-visible grey hint texts were
  merged into this feature's help texts and removed from the layout, once this button gave the
  screen a single place to explain itself instead of two.

### T-21 · Write a user manual — IMPLEMENTED (2026-09-24)

- [x] A complete version under `docs/`, and a minimal one in the README.
- **Why:** requested; there is no usage documentation beyond four bullet points.
- **Done when:** the manual covers every screen and control that the GUI exposes. Met:
  `docs/USER_GUIDE.md` walks every tab (Alarms' Scheduled/Manual sub-tabs and the add/edit dialog,
  Schedule's views/Today/Calendars/ignore-event gesture, Scan Code's Generate/Import/description/
  Remove/Share, all nine Sleep Habits options, Settings' four sub-pages including the growable
  custom-tones list from T-56, and the ringing screen's Snooze/Stop), plus the lazy-permission
  behaviour from T-157 and T-41's privacy-first splash screen. README's own "Usage" section is the
  minimal version - five bullets instead of four, still short - with a link to the full guide, and
  a new "Project Documentation" entry points at it too.

### T-22 · Rework the README for a reader who is not a developer — RESOLVED (2026-09-09)

- [x] Remove the note about removed Windows/macOS/web scaffolding; remove the launcher-icon
      regeneration step (the icons are static); remove the VirtualBox/`vboxsf` note; rewrite
      "Quality Checks" so it does not address the reader as a contributor who will push tags; and
      replace the "Testing status" section with something shorter in a different form.
- **Why:** requested. Most of that material belongs in `CLAUDE.md`, not in the project's front page.
- **Resolution:** the Windows/macOS/web note, the vboxsf gotcha and the launcher-icon step were
  removed from README (all three were already duplicated in `CLAUDE.md`, or moved there - the
  launcher-icon command now lives under `CLAUDE.md`'s "Build & run"). "Quality Checks" and "Testing
  status" were replaced by a single short "Quality & Testing" paragraph pointing to `CLAUDE.md` (now
  home to a new "CI/CD pipeline" section) and `docs/TODO.md` for detail. `CLAUDE.md` also gained a
  "Development process" section recording the project's new test-driven-development rule.
- **Done when:** the README reads as a description of the app for someone evaluating or using it,
  with contributor-only detail moved or dropped.

### T-23 · Remove the known flake mechanisms from the E2E harness — PARTIALLY RESOLVED (2026-09-09)

- [ ] Reduce reliance on 500 ms widget-presence sampling itself (the third mechanism below).
- **Why:** three mechanisms produce red runs that misdescribe their own cause: state is sampled once
  per 500 ms so short-lived screens can be missed; the "now + 1 minute" default is minute-truncated,
  so a save crossing a minute boundary schedules the alarm 24 hours out and the test reports "alarm
  never rang"; and no teardown stops leftover alarms, so one failure cascades into the next
  scenario.
- **Evidence (before this fix):** `integration_test/app_test.dart:38-52,56-70` (sampling), `:104`
  (save after `pumpAndSettle`); `lib/screens/alarms/screen_alarms.dart:266-268` (truncation),
  `lib/app_state.dart:455-459` (`isBefore(now)` → `+1 day`); `integration_test/app_test.dart:113-115`
  (teardown nulled the override only).
- **Resolution:** `createManualAlarmOneMinuteFromNow` now reads back the created alarm via
  `Alarm.getAlarms()` and fails immediately with a clear message (naming the actual scheduled time
  and how far off it is) if it's more than ~2 minutes from now, instead of letting a later
  `pumpUntilFound` time out with a misleading "never rang" failure. `setUp`/`tearDown` now call
  `Alarm.stopAll()` around every test, so one test's leftover alarm can't affect the next.
  `barcodeController.close()` moved into `addTearDown`, so it runs even if an earlier assertion
  throws. Final correctness assertions now also check `Alarm.getAlarms()` (durable state, see T-09)
  alongside the widget-presence checks.
- **Still open:** `pumpUntilFound`/`pumpUntilGone` themselves are unchanged - they still sample
  widget presence once per 500 ms, so a screen that mounts and unmounts within one polling gap could
  still be missed in principle. Not touched in this pass because no currently-reproducing failure
  needs it; revisit if one appears.

### T-24 · Stop evidence collection from degrading silently, and keep failure evidence — RESOLVED (2026-09-09)

- [x] Report what was actually collected, and retain the newest failure as well as the newest
      success.
- **Why:** the evidence artifact is the only human-inspectable proof of on-device behaviour, and it
  was both incomplete-by-silence and unread. In the last green run 7 of 12 recording segments were
  lost to "Operation not permitted" without affecting the job result, because both `screenrecord`
  and `adb pull` were followed by `|| true`; an entirely empty directory would only warn. The
  retention script kept only the newest run and the newest *successful* run, so it deleted the
  evidence of both earlier failed runs — the project's own "2 passed, 1 failed" claims could no
  longer be re-derived from artifacts.
- **Evidence (before this fix):** `.github/scripts/run_e2e_tests.sh:48-49` (`|| true`),
  `.github/workflows/release.yml:93` (`if-no-files-found: warn`),
  `.github/scripts/cleanup_old_artifacts.sh:22-25` (success-only keep); artifact listings for the
  two earlier E2E runs returned `total_count: 0`.
- **Resolution:** `run_e2e_tests.sh`'s `record_segments` now checks `screenrecord`'s and `adb
  pull`'s real exit status and logs every segment's outcome (collected / screenrecord failed / pull
  failed) to a new `manifest.log` inside the evidence artifact, instead of swallowing both with
  `|| true`. `stop_evidence_collection` now writes a summary - what's in `$EVIDENCE_DIR`, plus the
  manifest if non-empty - to `$GITHUB_STEP_SUMMARY`, so a missing segment is visible on the run's
  summary page without opening the artifact or the logs. Because `README.md` and `manifest.log` are
  now always created regardless of recording success, the evidence directory can no longer be
  entirely empty, which was the case `if-no-files-found: warn` existed to catch.
  `cleanup_old_artifacts.sh` now also computes `KEEP_FAILURE_RUN_ID` (the most recent *other* failed
  release.yml run) alongside the existing success-keep logic, so a run's evidence survives pruning
  if it is the newest of either outcome.

### T-25 · Investigate the system ANR during E2E runs — PARTIALLY RESOLVED (2026-09-09)

- [ ] Determine the actual root cause (resource pressure vs. something else) and, if resource
      pressure, size the fix without guessing at unverified emulator flags.
- **Why:** the evidence video of the green run showed an Android "Process system isn't responding"
  dialog in every sampled frame, across the whole test window. The tests pass anyway because
  `integration_test` drives the widget tree rather than the visible screen — which means the suite
  is insensitive to a system-level dialog that a real user would face, and it weakens how much
  weight "it works on a device" carries.
- **Evidence:** `e2e-evidence` recordings from the newest release run (dialog present in 22 of 22
  sampled frames, alongside the app's genuine "Your alarm is ringing" notification).
- **Investigation:** the most plausible, evidence-backed hypothesis is memory/CPU pressure -
  `docs/quality-baseline-2026-09.md`'s VM notes recorded 7.7 GB RAM as sufficient for building but
  not for also running the emulator, and `run_e2e_tests.sh` runs `flutter build apk --debug`
  (a heavy Gradle/JVM process) *while the emulator is already booted and alive*, on a
  `ubuntu-latest` GitHub-hosted runner with a fixed, similarly modest RAM budget. Deliberately not
  acted on tonight: `reactivecircus/android-emulator-runner`'s exact handling of a hand-set
  `emulator-options` value (whether it's appended to, or replaces, the flags it already applies by
  default - which the prior evidence log showed included `-no-window -gpu swiftshader_indirect
  -no-snapshot -noaudio -no-boot-anim`) isn't confirmed from documentation on hand, and guessing
  wrong risks silently breaking a currently-working emulator boot during an unattended run.
- **Resolution (the safe half - explicit recording):** `run_e2e_tests.sh` now captures
  `ActivityManager` logcat output for the whole run into `activity_manager.log`, and
  `stop_evidence_collection` greps it for `"ANR in"` and reports the count prominently in
  `$GITHUB_STEP_SUMMARY` ("ANR detected: N occurrence(s)" or "No ANR detected") - satisfying the
  "or" branch of this item's own acceptance bar even without yet eliminating the ANR.

### T-26 · `scripts/security-scan.sh` can report a false all-clear — RESOLVED (2026-09-09)

- [x] Add trufflehog's `--fail` flag and describe the script's real coverage.
- **Why:** it is the only pre-commit gate contributors are told to run, and its header promised a
  non-zero exit on findings — but the trufflehog step omitted the `--fail` that CI uses, so the
  script could print "All checks completed cleanly" while findings existed. It also covers two of
  R1's five tools and excludes paths CI scans.
- **Evidence (before this fix):** `scripts/security-scan.sh:44` vs `.github/workflows/ci.yml:98`.
- **Resolution:** added `--results=verified,unknown --fail` to the trufflehog invocation, matching
  CI's flags exactly. Added a header note stating this script covers 3 of R1's 5 tools and does not
  run mobsfscan or MobSF (both need the built APK; MobSF also needs a local Docker instance).
  Verified locally: `bash scripts/security-scan.sh` still exits 0 and reports "All checks completed
  cleanly" against this repo's current, clean state (`flutter analyze`: no issues; `osv-scanner`:
  131 packages, no issues; `trufflehog`: 0 verified/unverified secrets).
- **Requirement:** R1

### T-142 · The scanner's compiled-in native code has no licence notices — FIXED (2026-09-19)

- [x] Ship the Apache-2.0 and BSD-3 notices for the C/C++ that is statically linked into
      `libflutter_zxing.so`.
- **Why:** `flutter_zxing` vendors third-party native code that is invisible to Flutter's own
      licence collector - Apache-2.0 §4(a) requires the licence text to travel with the
      distribution, and BSD-3 requires the copyright notices to be retained. The package ships
      exactly one licence file (zint's), and the APK's `NOTICES` contains flutter_zxing's own MIT
      block and nothing else.
- **Correction found while fixing this:** the original investigation counted **four** vendored
      bodies, including a separate "libzueci (BSD-3)". Re-checked against `flutter_zxing` 3.0.1's
      actual vendored source: there is no separate zueci source tree or CMake target anywhere in
      the package - only a comment in zint's own BSD-3 `eci_sb.h` noting that its generated data
      tables are "zueci-compatible". It's **two** bodies, not four: zxing-cpp (Apache-2.0,
      including its bundled "librscpp" Reed-Solomon implementation, `Copyright 2016 ZXing authors` /
      `Copyright 2017-2026 Axel Waggershauser`) and zint (BSD-3, `Copyright (C) 2009-2025 Robin
      Stuart <rstuart114@gmail.com>`, full licence text already vendored at
      `zint/LICENSE`/per-file headers).
- **The trap (confirmed):** T-36 (`showLicensePage`) does **not** cover this - Flutter's licence
      collector reads package-root `LICENSE` files; C++ compiled by CMake is invisible to it.
- **Fix:** `assets/text/NativeCodeNotices.txt` - hand-assembled from the vendored source's own SPDX
      headers and licence files, reproducing the full Apache-2.0 text and the full BSD-3 text with
      its copyright notice. Registered in `pubspec.yaml`; readable via a new "Native Code Notices"
      button on the About page (`page_native_notices.dart`, mirroring `page_license.dart`'s
      existing pattern for this app's own GPLv3 text - plain text, not Markdown, since a licence
      text's indentation and line breaks are part of the document).
- **Tests:** `test/page_aboutpage_native_notices_test.dart` (the button is reachable and the
      rendered page contains both "Apache License" and the "Robin Stuart" copyright line) - kept in
      its own file, matching the isolate-pairing precedent already documented in
      `page_aboutpage_licenses_test.dart`.
- **Requirement:** R9

### T-143 · The QR gate has never decoded through a real camera — RESOLVED (2026-09-19, confirmed on a real device)

- [x] `cropPercent`/`tryHarder`/`tryInverted` tuned, per the maintainer's own real-device report.
- [x] `scanDelay` shortened, per a second round of real-device feedback (recognition worked but was
      slow/inconsistent).
- [x] **Confirmed fixed by the maintainer** after the `scanDelay` change: "Sieht deutlich besser
      aus. Kann man mMn schließen." (looks noticeably better, can be closed) - closing on that
      real-device confirmation rather than requiring a separately logged
      `docs/device-trial-checklist.md` entry, since the maintainer's own repeated hands-on testing
      (~5 trials) across two tuning rounds is the actual evidence this item asked for.
- **Why:** the migration to `flutter_zxing` (T-33) changed the decoder, and nothing in any suite
      instantiates `ReaderWidget` or loads the zxing native library - the unit tests inject through
      the seam, and the E2E scenario now skips building the preview because the seam is set. A
      `ReaderWidget` that throws on mount would ship green.
- **Confirmed on a real device (2026-09-19):** the maintainer reported "die allermeisten qr codes
      werden absolut nicht erkannt" (almost no QR code is recognized at all) - exactly the failure
      mode this item had predicted from reading the defaults, now observed rather than theorized.
      `ReaderWidget` only decodes within a centre crop (`cropWidth`/`cropHeight` derived from
      `cropPercent`), and the pre-fix default (0.5, i.e. 50% of the shorter frame side) is a real
      constraint on anything not small and perfectly centred - normal for a QR code already printed
      on some real-world object (R13's whole point) rather than shown close-up on a second device's
      screen. `tryHarder`/`tryInverted` being off removes decode passes for exactly the conditions
      such a code is likely to have (an angle, a curved surface, light-on-dark colouring) that this
      app's own generated codes never do.
- **Fix:** `lib/screens/scan_code/qr_scanner.dart`'s `ReaderWidget` now sets `cropPercent: 0.85`,
      `tryHarder: true`, `tryInverted: true`. Also widened `codeFormat` from `Format.qrCode` to
      `Format.any`, at the maintainer's explicit follow-up request - see `docs/REQUIREMENTS.md` R13,
      now "any pre-existing QR code or barcode".
- **A second, independent bug the same report also surfaced:** "einige wenige [Codes] schon, dann
      terminiert die kamera-sicht (erfolgreich?), aber kein qr code ist angelegt" (a few DO get
      recognized - the camera view closes as if it worked - but no code ends up configured). Root
      cause had nothing to do with scanning: `PageDeactivationCode` read `AppState` with
      `Provider.of<AppState>(context, listen: false)` in `initState`, so it never rebuilt when the
      *separate* `QrScanner` route (`PageImportQr`) mutated `AppState.deactivationCode` on a
      successful import - the import had actually succeeded and persisted, but the screen
      underneath, having subscribed with `listen: false`, had no way to find out and kept showing
      "no code configured" until something unrelated happened to rebuild it. Fixed by adding
      `context.watch<AppState>();` to `build()`, the same reactive pattern used elsewhere in the
      app, so the screen reacts to a change made by any widget, not only its own Generate/Remove
      buttons (whose `onPressed` handlers had been masking the same gap for themselves with a local
      `setState`). A pre-existing, unrelated layout bug was hit by the regression test for this: the
      "code set" view's `Column` (QR image + button row) sized purely from screen *width*
      overflowed vertically on a short screen - wrapped in a `SingleChildScrollView` while there.
- **Second real-device report (2026-09-19, after the first fix): recognition works, but is slow
      and not fully reliable.** `scanDelay` - the pause `ReaderWidget` inserts between decode
      attempts whenever a frame comes back empty - was still at the library's own default (1000ms),
      so the gate only tried roughly once a second, where mobile_scanner (before the T-33
      licence-driven swap) decoded at frame rate. Shortened to 150ms: every extra attempt per
      second is another chance to catch a well-aligned, in-focus frame, which speaks to both halves
      of the report at once - a slow gate is also a less reliable one when it means giving up
      before a good frame comes along. `scanDelaySuccess` (the pause after a successful decode,
      already 500ms) was not the bottleneck reported and stays as it is.
- **Also check:** that the snooze button at the top of the screen is still hit-testable through the
      scanner's own full-bleed overlay and pinch-zoom detector.
- **Tests:** `qr_scanner_gate_test.dart`'s existing cases are unaffected (the debug scan stream seam
      bypasses `ReaderWidget` entirely, so it cannot exercise `cropPercent`/`tryHarder`/`scanDelay` -
      a real device trial remains the only way to verify those);
      `page_deactivation_code_reactivity_test.dart` (red before the `context.watch` fix - mutating
      `AppState.deactivationCode` directly, not through the screen's own buttons, left the "no code
      configured" text showing); `qr_scanner_reader_config_test.dart` (source-reading, guards
      `codeFormat`/`scanDelay` against regressing back to their library defaults, the same
      "forbid the channel, not the symptom" shape as `no_proprietary_dependencies_test.dart`).
- **Done when:** a device trial records a decode at a realistic distance and light level with the
      now twice-tuned values - **met**, see the confirmation above.
- **Requirement:** R4, R13

### T-144 · The proprietary-dependency guard cannot see the channel the offender used — RESOLVED (2026-09-24)

- [x] Extend `test/no_proprietary_dependencies_test.dart` to the resolved tree and to Gradle.
- **Why:** the guard reads `pubspec.yaml` and the imports in `lib/`. ML Kit - the offender it was
      written for - never appeared in either: it arrived through `mobile_scanner`'s own
      `build.gradle`. A different package linking a proprietary AAR would be just as invisible, and
      so would a forbidden package returning transitively, since the test never reads
      `pubspec.lock`. R8 credits this test with more than it can do.
- **Done when:** the guard also fails on a forbidden name in `pubspec.lock`, and something checks
      the Android artifacts the build actually resolves. Both done:
  - [x] `test/no_proprietary_dependencies_test.dart` gained a fourth case reading `pubspec.lock`'s
        actually-resolved package set (every top-level key under `packages:`, 2-space indent) - a
        transitive return with no `pubspec.yaml` line and no `dependency_overrides` entry now fails
        the same way a direct one already did. The counter-test ("the guard would actually catch
        something") was extended to cover the lockfile parser too, not just the pubspec.yaml one.
  - [x] `scripts/check_proprietary_native_deps.py` (new) checks the Android side - a forbidden
        native artifact (`com.google.mlkit`, `com.google.android.gms:play-services-mlkit*`,
        `com.syncfusion`) arriving through a plugin's own `build.gradle`, invisible to both Dart-side
        checks above. Deliberately reuses the CycloneDX SBOM `:app:cyclonedxBom` already produces
        for the native `osv-scanner` pass (`docs/TODO.md` T-148) rather than resolving the
        dependency tree a second time - one new step in `ci.yml`'s `build-android-release` and
        `release.yml`'s `build-signed-release`, right after the existing SBOM generation. Forbids by
        (group, name-prefix) pairs, not a whole-group ban, so a legitimate future use of the (large,
        otherwise-fine) `com.google.android.gms` group wouldn't become a standing false positive -
        only its ML Kit "unbundled" artifact family is forbidden. Verified against the real,
        currently-clean SBOM (162 resolved components, none flagged) and against a copy with three
        synthetic offenders injected (all three correctly caught, exit code 1) - this project has no
        Python test scaffold, so this stands in for a proper unit test, the same as
        `scripts/mobsfscan_check.py`/`mobsf_summary.py` have none either.
  - Not run in `scripts/security-scan.sh`: that script deliberately has no native-Android
    `osv-scanner` pass either, for the same reason (`docs/TODO.md` T-148/CLAUDE.md's own text) - it
    needs a resolved Gradle build this lightweight local script doesn't do.
- **Requirement:** R8

### T-145 · Opening the Schedule screen no longer triggers a calendar fetch — FIXED (2026-09-20)

- [x] Fetch on open and on view switch, not only when the user pages.
- **Why:** `SfCalendar.onViewChanged` fired on initial layout; `calendar_view`'s `onPageChange` is
      wired to `PageView.onPageChanged`, which does not fire for the first page (T-05). Switching
      view through the menu and the Today button do trigger a fetch now, but opening the screen
      does not. Mostly masked by `preloadCalendarData` at startup - the case that bites is a
      preload that ran before calendar permission was granted: the screen then shows an empty week
      until the user pages away and back.
- **Superseded in practice by T-60 (2026-09-20):** `_syncCalendarAndAlarmsOnOpen`
  (`lib/main.dart`) now runs `resyncCalendarData(appState, pastWeeks: 2, futureWeeks: 1)` on
  **every** cold start (`initState`) and **every** resume (`didChangeAppLifecycleState`,
  `AppLifecycleState.resumed`) - not just once at startup, which is what T-145 was originally
  written against. Since the Schedule screen cannot be opened without the app itself having just
  been opened or resumed, a broad ±multiple-week resync has already run moments before the user
  could reach it in the overwhelming majority of real cases - closing the specific gap this item
  was about for normal use. The one residual case T-60 does not cover: switching to the Schedule
  **tab** from another tab within an already-foregrounded app session, with no resume in between
  (in-app tab switches don't trigger `didChangeAppLifecycleState`) - narrow enough, and now
  low-impact enough given the on-resume resync already covers the common paths, that it is not
  worth chasing further on its own.
- **The remaining month-view issue, fixed (2026-09-20):** `onPageChange` was shared across
  week/day/month views and always called `updateCalendarData` with a fixed 7-day window - correct
  for week/day, wrong for month view, whose grid (`calendar_view`'s `MonthView`) is a fixed 6-week
  (42-day) span starting from the Monday of the week containing the 1st
  (`datesOfMonths`/`_height = _cellHeight * 6`, checked against the package source). Paging into
  month view therefore only ever fetched (and marked as fetched) the single week containing day 1
  - the other ~5 weeks of the visible grid were silently left unfetched. `getStartOfWeek` already
  normalizes any date to that Monday correctly (so the specific "collects non-week keys" framing in
  the original write-up wasn't quite right - the real gap was the fetch *window*, not the recorded
  *key*), but `updateCalendarData` only ever recorded one `fetchedCalendarWeeks` entry regardless of
  how wide a range it was asked to cover.
  Fix: a new `_onMonthPageChange` (month view's `monthViewBuilders.onPageChange`, separate from
  `_onPageChange`, which week/day views keep using unchanged) requests
  `updateCalendarData(appState, const Duration(days: 42))`; `updateCalendarData` now records every
  week its fetch window actually spans (a loop from `startOfWeek - backwards` to
  `startOfWeek + timeToFetch`, one entry per 7 days) instead of only `startOfWeek` - for the
  existing 7-day callers this is still exactly one entry, unchanged.
- **A real, pre-existing async bug found while testing the above fix:** `updateCalendarData` was
  declared `async` but returned bare `void`, not `Future<void>` - so `loadCalendarData`'s own
  `await updateCalendarData(...)` was a no-op that could never actually wait for it, and
  `preloadCalendarData`'s follow-up `markWeekFetched` loop could run before `updateCalendarData`'s
  own fetch-and-record work had finished. Invisible before now because both sides usually finished
  "fast enough" by luck against test fakes; the wider 42-day loop above took just long enough to
  reliably lose that race, producing a different `fetchedCalendarWeeks` count on every run
  (`test/resync_calendar_data_test.dart`'s repeated-resync test caught this immediately - failed
  non-deterministically with 3 entries instead of the expected, dynamically-computed count).
  Fixed by giving `updateCalendarData` its true `Future<void>` return type and awaiting it inside
  `loadCalendarData`.
  Also promoted `_markWeekFetched` (`lib/utils/utils.dart`) to a public `markWeekFetched` and
  reused it inside `updateCalendarData`'s new loop, instead of a second, non-deduplicating copy of
  the same "skip if this week is already recorded" check `preloadCalendarData` already had.
- **Tests:** `test/month_view_calendar_fetch_test.dart` (new) - a wide fetch window marks every
  week it covers, not just the first. `test/resync_calendar_data_test.dart`'s existing repeated-
  resync test is what caught the async race (it went from reliably red to reliably green once
  `updateCalendarData` was properly awaited - no test changes needed there beyond that fix).
- **Requirement:** R2

### T-146 · Custom alarm tone import — IMPLEMENTED (2026-09-17)

- [x] Let the user pick their own audio file as a tone via the system file picker.
- [x] Copy it into the app's own storage so it keeps working after the source file is gone.
- [x] Restrict to file types the alarm plugin's player can actually play.
- [x] Found and removed a dead permission along the way.
- **Why:** a follow-up to T-29 - the six bundled tones turned out to include an unlicensed meme
  rip (see that entry). Letting the user supply their own file sidesteps the whole class of
  problem: the app distributes nothing, the user brings their own content, exactly like any other
  ringtone app.
- **Copy, not a reference:** the picked file is copied into
  `<Documents>/custom_tones/custom_tone.<ext>` immediately (`lib/models/alarms/custom_tone.dart`,
  `importCustomTone`), and only that copy is ever played from afterward. The source the system
  picker pointed at - a Downloads folder, an SD card, an SAF URI-scoped grant - can disappear or
  have its access revoked independently of the app; a file the app owns in its own sandbox cannot.
  Re-importing replaces the previous copy outright, so switching tones doesn't leave dead files
  behind.
- **Why the returned path has no `assets/` prefix and isn't absolute:** `AlarmSettings
  .assetAudioPath` (package:alarm) resolves an unprefixed relative path against the app's
  Documents directory on the native side (its own doc comment, and `AudioService.kt`'s
  `baseAppFlutterPath`) - and warns that an absolute path breaks across an app update, since the
  app's data directory UUID can change. The stored value therefore doubles as a first-class
  `MyAlarm.tone`/`AppState.selectedTone` value with no special-casing anywhere else in the
  scheduling pipeline - `_setAlarm` and `apply_alarms.dart` already treat any non-`assets/`,
  non-absolute string this way.
- **Supported types:** `mp3`, `wav`, `m4a`, `aac`, `ogg` - what `android.media.MediaPlayer`
  (what the plugin's `AudioService.kt` actually uses) plays reliably. Enforced both at the picker
  (`FileType.custom`/`allowedExtensions`) and again in `importCustomTone` itself
  (`UnsupportedToneFormatException`), so a caller can't bypass the check by constructing a path
  directly.
- **Permissions - the actual finding:** picking a single file needs no Android permission at all
  (Storage Access Framework); confirmed by diffing `aapt2 dump permissions` on the built debug APK
  before and after adding `file_picker`/`path_provider` - identical. While checking that,
  `android.permission.READ_EXTERNAL_STORAGE` turned up already declared in
  `AndroidManifest.xml`, unconditionally, with no comment, since the very first commit - and no
  runtime request for it anywhere in the Dart code. It comes from the `alarm` plugin's own
  manifest, for the case where `assetAudioPath` points into *shared* external storage; this
  feature deliberately never does that (see "copy, not a reference" above), so nothing in the app
  needs it. Removed (`tools:node="remove"`, alongside the existing RECORD_AUDIO/
  WRITE_EXTERNAL_STORAGE entries and their own T-49 rationale) rather than left as unexplained
  dead weight.
- **Test:** `test/custom_tone_test.dart` (the pure copy/validation logic - supported/unsupported
  extensions including case-insensitivity, the copy surviving the source file's deletion,
  re-import replacing rather than accumulating files, a missing source propagating a clear
  error) and `test/app_state_custom_tone_test.dart` (the `AppState` wiring: persistence round
  trip, notifying listeners, an unsupported type leaving `customTonePath` untouched) - both
  test the real `dart:io` copy against a temporary directory, with `documentsDirectory` injected
  the same way `fetchEvents`/`now` are elsewhere in this codebase, so neither needs a platform
  channel or a device.
- **UI:** `Settings > Alarm Tones` gets a seventh tile that opens the picker if nothing is
  imported yet, or previews/selects the current import otherwise, plus a folder icon to import a
  different file at any time. The per-alarm tone dropdown in `screen_alarms.dart` offers it too,
  once one exists.
- **Requirement:** R4, R10

### T-147 · A ring screen could get stuck open after its alarm was already stopped — FIXED (2026-09-18)

- [x] `ScreenAlarmActive`/`QrScanner` notice when their own alarm stops ringing and close themselves.
- **Bug report:** an alarm was deactivated via its notification (swiped away, app UI closed) with
  no app process handling it; reopening the app afterward still showed the full-screen ring
  overlay, with nothing actually ringing behind it and `PopScope(canPop: false)` blocking every
  way out except the Stop button - which itself calls `Alarm.stop` again, gets `false` back
  (there is nothing left to stop), and leaves the user on a "Failed to stop the alarm - please try
  again" screen with no working retry.
- **Root cause:** `NotificationSettings.androidStopAlarmOnDismiss` (package:alarm) defaults to
  `true` and has since plugin 5.0.3 - swiping the alarm notification away runs the native stop
  action directly, with no Dart code involved at all. `main.dart`'s `Alarm.ringing.listen`
  subscription only reacted to alarms newly appearing in the ringing set (to call
  `Handler.handleAlarm` exactly once per ring); nothing anywhere reacted to an alarm disappearing
  from it, so the screen that `handleAlarm` had already pushed had no way to learn its alarm was
  gone.
- **Fix:** `lib/models/alarms/ringing_watch.dart`'s `RingingWatch` - both `ScreenAlarmActive` and
  `QrScanner` (only when opened for a ringing alarm; a plain code-import scan has nothing to
  watch) now subscribe to `Alarm.ringing` themselves and pop the screen (via `Navigator.pop`/
  `_closeView`) plus run `Handler.onAlarmHandled` the moment their own `alarmId` is no longer in
  the set - the same outcome the Stop button produces on a normal dismiss, just triggered by the
  plugin's own stream instead of a button press.
- **The first event is deliberately ignored:** `Alarm.ringing` is a `BehaviorSubject`, so a new
  subscriber's first delivery is the stream's *current snapshot*, not a change. Reacting to it
  would auto-close the screen the instant it opens whenever nothing has (yet) told the real,
  static `Alarm.ringing` subject that this alarm is ringing - which is exactly the state of
  `flutter test`'s unpopulated subject in every existing test that drives `Handler.handleAlarm`
  directly rather than through the plugin (`test/handler_replan_wiring_test.dart`). `RingingWatch`
  only calls `onGone` on a later event, a genuine disappearance.
- **Test:** `test/ringing_watch_test.dart` (the reusable watcher in isolation: ignores the seed,
  fires on a real transition, ignores an unrelated alarm's id, stops after `cancel()`),
  `test/screen_alarm_active_ringing_test.dart` and `test/qr_scanner_ringing_test.dart` (both
  screens, via a `debugRingingStreamOverride` test seam matching the existing
  `debugScanStreamOverride` pattern in `qr_scanner.dart`) - covering the stuck-open bug itself, an
  unrelated alarm's disappearance not closing the wrong screen, and the no-`alarmId` code-import
  path staying unaffected.
- **Still stuck on a real device after this fix, and a new crash - continued (2026-09-18):** the
  maintainer reported the screen still getting stuck open in some runs, plus a new `Navigator`
  `!_debugLocked` assertion after pressing Stop. Two further, related causes found:
  1. **`RingingWatch` didn't fully solve the underlying problem, only reacted to it** - and the
     maintainer's own call was that a notification should not be able to deactivate a "guaranteed
     wake-up" style alarm at all: "Eigentlich sollte der Alarm nur per Stop Button deaktiviert
     werden können." Fixed at the source instead: `lib/models/alarms/ringing_alarm_settings.dart`'s
     `buildRingingAlarmSettings` (a pure function extracted from `AppState._setAlarm`/
     `setSnoozeAlarm` specifically so this has a test that needs no platform channel) now sets
     `androidStopAlarmOnDismiss: false`. A stray swipe puts the notification straight back for as
     long as the alarm keeps ringing, per that field's own doc comment - only the Stop button (or a
     QR scan) can end it now. `RingingWatch` stays as a safety net for what remains (e.g. the QR
     gate's emergency-stop-all button silencing an alarm a *different* screen is showing), but the
     scenario that originally caused T-147 can no longer happen at all.
  2. **The Navigator crash's real cause: `Alarm.stop()` updates `Alarm.ringing` as part of the same
     call the Stop button awaits** - which `RingingWatch` also observes. A normal, successful Stop
     therefore raced its own `Navigator.pop()` against `RingingWatch.onGone`'s, both reacting to
     the one underlying change; whichever ran second hit the Navigator mid-transaction from the
     first. The same hazard applies to a successful Snooze (`snoozeRingingAlarm` stops the *old*
     alarm as its last internal step) - in practice, `RingingWatch`'s listener fires *before* the
     snooze's own completion handler gets a chance to say "this one was a postponement, not a real
     stop", so the naive fix of "flag it after success" doesn't close the race. Fixed by claiming
     responsibility as early as possible instead: `ScreenAlarmActive`/`QrScanner` each guard
     `Handler.onAlarmHandled` against a second call (`_callOnAlarmHandledOnce`/`_handleAlarmOnce`),
     and `SnoozeButton` gained an `onBeforeSnooze` callback that fires synchronously the instant the
     button is pressed - before `Alarm.stop()` even runs - so a screen's "this is a snooze, not a
     stop" flag (`_snoozing`) is reliably in place *before* the race can happen, not set reactively
     after. Popping itself was already idempotent (`ModalRoute.isCurrent`) once QrScanner's
     `_closeView` pattern was applied consistently to `ScreenAlarmActive` and to both screens'
     Snooze buttons (which previously popped directly, ungated).
  3. **`RingingWatch` itself had a second, compounding bug**, found while fixing the above: it
     fired `onGone` on *every* event where the watched alarm was absent, not only on the
     present-to-absent transition - so an unrelated alarm's own ring/stop later on the same shared
     stream re-confirmed "still absent" and called `onGone` again, multiplying however many pop/
     `onAlarmHandled` attempts a single real disappearance produced. Now tracks the previous
     presence explicitly and only fires on a genuine edge - which also subsumes the original
     "ignore the seed event" rule for free (with nothing observed yet, there is no edge to have
     crossed).
- **Test:** `test/ringing_alarm_settings_test.dart` (the notification-swipe guarantee, in
  isolation from the real plugin), `test/ringing_watch_test.dart`'s new edge-triggering case, and
  `test/screen_alarm_active_ringing_test.dart`'s new case (two present-to-absent edges fired
  back-to-back with no pump in between, verifying `Handler.onAlarmHandled` - observed via a new
  `debugOnAlarmHandledOverride` seam - still fires exactly once).
- **Requirement:** R3

### T-148 · Security-gate audit findings: history-only secret scanning, no native-Android SCA, no update automation — FIXED (2026-09-18)

- [x] `trufflehog` only ever scanned the current checkout, never git history.
- [x] `osv-scanner` only ever covered `pubspec.lock` (the Dart side) - the native Android
      dependency tree had zero SCA coverage.
- [x] No Dependabot/Renovate - vulnerability scanning was purely reactive against whatever was
      currently pinned, with nothing proactively flagging outdated dependencies.
- **Why:** an audit of the SAST/SCA/secret-scan configuration itself (not just its output) turned
  up three real gaps rather than tuning nitpicks:
  1. **`trufflehog filesystem` vs. `trufflehog git`.** `.github/workflows/security-gate.yml`'s
     checkout step already fetched `fetch-depth: 0` (full history), but the scan itself only
     covered the current working tree - a secret committed and later removed would never have been
     flagged. This is exactly the shape of gap T-29's unlicensed audio blobs were in git history for
     ten days across many green CI runs, just for credentials instead of copyright.
  2. **No native Android SCA at all.** `osv-scanner --lockfile=pubspec.lock` cannot see
     AndroidX/media3/the camera plugin's own transitive Java/Kotlin dependencies - there is no
     `gradle.lockfile` for it to read, and it doesn't resolve `build.gradle.kts` manifests directly.
     Confirmed real, not theoretical: a properly-scoped scan (below) immediately found
     `gson:2.8.8`, carrying GHSA-4jrv-ppp4-jm57/CVE-2022-25647 (CVSS 7.7), transitively via
     `device_calendar`.
  3. **No Dependabot/Renovate.** `flutter pub outdated` showed 14 packages behind during this same
     session - nothing had ever proposed catching any of them up automatically.
- **Fix 1:** `trufflehog git file://.` replaces `trufflehog filesystem` in both
  `security-gate.yml` and `scripts/security-scan.sh` - same flags otherwise, verified locally
  against the full (already-rewritten, per T-29) history in ~2 seconds, 0 findings.
- **Fix 2:** `android/settings.gradle.kts`/`android/app/build.gradle.kts` apply the
  `org.cyclonedx.bom` Gradle plugin, scoped via `includeConfigs = ["releaseRuntimeClasspath"]` -
  deliberately not the unscoped default, which also pulled in `androidTestImplementation`/
  instrumentation-test infrastructure and flagged a long list of real CVEs against `netty`
  (transitively via `com.google.testing.platform:core`/`com.android.tools.emulator:proto`, which
  never reach a shipped build). `ci.yml`'s `build-android-release` and `release.yml`'s
  `build-signed-release` now run `:app:cyclonedxBom` right after `flutter build apk --release`
  (the release configuration is already resolved by then, so this is cheap - a few seconds warm)
  and feed the resulting SBOM to `osv-scanner`. The one real finding it turned up, `gson:2.8.8`
  (see above), was forced to the patched `2.8.9` (`resolutionStrategy.force`) rather than accepted
  as an exception - a same-minor-series patch bump carries essentially no compatibility risk, and
  there is no reason to carry a fixable HIGH.
- **Fix 3:** `.github/dependabot.yml`, covering `pub`, `gradle`, and `github-actions`. All three
  target `dev`, never `master` (the pinned "work-on-dev-not-master" project rule) - a `master`
  push triggers the full, ~45-minute gated pipeline, and Dependabot PRs have no business paying
  that cost on every open.
- **Deliberately not done as part of this item** (out of scope for the audit that was asked for,
  and each is a separable decision): pinning GitHub Actions to commit SHAs instead of floating
  major-version tags, and adding a Dart-specific security-focused static analyzer (`flutter_lints`
  is a style/quality ruleset, not a security one - though this app's own attack surface here is
  low, given no crypto beyond `Random.secure()` and no network calls anywhere in `lib/`).
- **Requirement:** R1

### T-149 · Ignore a calendar event for scheduling — IMPLEMENTED (2026-09-18)

- [x] Let the user mark a calendar appointment as ignored: it is excluded from `hardFloor`
      derivation, shown grayed out with an X on its tile, persisted, and never written back to the
      calendar itself.
- **Why:** feature request. An appointment can drive a wake-up time the user doesn't actually want
  to get up for - a recurring standing invite they never attend, a shared/family calendar entry
  that isn't theirs to act on (and must not be, since writing to it would be writing to someone
  else's calendar).
- **Persistence, deliberately never touching the calendar:** `AppState.ignoredEventIds` is a bare
  `Set<String>` of `device_calendar` event ids (`Meeting.ids`), not a set of `Meeting` objects and
  not anything written through `device_calendar`'s own event-mutation API (which this app has
  never used - see `calendar.dart`'s commented-out `meetingToEvent`/`addEvent` scaffolding, T-30).
  Keyed by id rather than by value so a later calendar sync's freshly-constructed `Meeting` for the
  same real-world appointment is still recognised (`AppState.isEventIgnored`/`setEventIgnored`,
  mirroring `disabledDays`' own shape from FR-21).
- **Scheduling side, kept pure:** `replan()` (`lib/models/scheduling/replan.dart`) filters
  `allEvents` against `appState.isEventIgnored` exactly once, immediately after the calendar fetch
  - every pure function downstream (`eventsForDay`/`hardFloor` in `scheduling_v2.dart`) never has
  to know ignoring exists at all, the same "keep the domain layer pure" shape FR-15 (manual alarms)
  and FR-21 (`disabledDays`) already use.
- **UI:** the grey tint is free - `meetingToCalendarEvent`'s new `ignored` parameter just
  overrides the `CalendarEventData`'s `color`, and `DefaultEventTile` (calendar_view) already
  paints that as the whole tile background. The X mark needs an actual custom `eventTileBuilder`
  (`_ScreenScheduleState._eventTileBuilder`), wired into `DayView`/`WeekView` only - `MonthView` has
  no equivalent per-event tile hook, only a whole-cell `cellBuilder`. Tapping an event (`onEventTap`)
  opens a bottom sheet with a switch per overlapping event at that tap point, toggling
  `setEventIgnored` and immediately triggering `runCheckpointSafely(..., trigger:
  CheckpointTrigger.settingsChanged)` - the identical trigger FR-21's own toggle uses, for the
  identical reason (a setting that feeds the computation must take effect immediately, not wait for
  the daily lock).
- **A real calendar_view 2.0.0 bug found along the way, and worked around rather than fought:**
  wiring the same tap-to-toggle interaction into `MonthView` threw `type
  '(CalendarEventData<Meeting>, DateTime) => void' is not a subtype of type
  '(CalendarEventData<Object?>, DateTime) => void)?'` the moment a month cell with an event
  rendered - a generics mismatch somewhere between `MonthViewBuilders<T>` and `FilledCell`'s
  internal tap wiring that a non-generic (`Object?`) `onEventTap` never triggers, because a null
  callback is never type-checked. `MonthView` therefore still shows the grey tint (via the same
  `meetingToCalendarEvent` path) but has no tap-to-toggle or X mark - only `DayView`/`WeekView` get
  the full interaction. Not filed as a project bug since it lives in the third-party package.
- **Test:** `test/ignored_events_test.dart` (persistence: default state, toggle round trip,
  keyed-by-id survives a freshly-refetched `Meeting`, restart round trip, listener notification),
  `test/replan_ignored_events_test.dart` (an ignored event's day becomes a gap day; a non-ignored
  event on the same day still wins; un-ignoring restores the hardFloor), `test/meeting_data_test
  .dart` (the grey-colour override, including all-day events), and `test/ignore_event_ui_test.dart`
  (the tap-to-open-sheet interaction and the X mark appearing/disappearing with the toggle).
- **Requirement:** R2

### T-150 · The deactivation code screen showed a QR image the user couldn't recognize — FIXED (2026-09-19)

- [x] Let the user attach a free-text description to the deactivation code, shown instead of the
      re-rendered QR image, so they always know what to scan.
- **Why:** carried forward from real-device use of R13. `PageDeactivationCode` always re-renders a
      fresh QR image from the stored payload (`QrImageView(data: code.payload, ...)`) - but a QR
      code is not a fixed picture for a given string: the same text has many equally valid
      encodings (error-correction level, version/size, mask pattern, encoding mode all vary
      independently by encoder), so the app's own re-rendered image looks nothing like whatever
      physical QR code or barcode the user actually scanned. Detection still worked correctly
      (`isDeactivationCodeValid` compares the decoded *text*, never an image), but the user had no
      way to tell from the screen what object to go find and scan again.
- **Fix:** `DeactivationCode` gained an optional `description` field (persisted alongside
      `payload`, `null` for data saved before this existed - `fromJson` tolerates the missing key).
      `PageDeactivationCode` prompts for one (`_showDescriptionDialog`) the moment a code with none
      exists - whether just imported or just generated - scheduled via
      `WidgetsBinding.addPostFrameCallback` rather than called directly during `build()` (which
      would try to push a dialog route mid-build). Tracked by the code's own payload
      (`_promptedForPayload`), not a bare flag, so a genuinely new code (after Remove, or a fresh
      Import) is prompted for again without re-prompting on every rebuild of the same one. Once a
      non-empty description exists, it replaces the QR image entirely rather than being shown
      alongside it (the image conveys nothing useful once something better exists); an "Edit
      description" button stays available either way. The prompt is skippable (`description` stays
      `null`, and the QR image is shown as the fallback - still useful for a *generated* code, which
      the app itself is the sole source of, unlike an imported one).
- **A caught mistake:** disposing the dialog's `TextEditingController` immediately after
      `showDialog` returned raced its own closing transition, which was still reading the
      controller through its `TextField` ("A TextEditingController was used after being disposed").
      Left undisposed instead - a short-lived dialog's controller going out of scope with it is a
      negligible cost against a real crash.
- **Tests:** `deactivation_code_description_test.dart` (default `null`, `toJson`/`fromJson`
      round-trip, tolerates data saved before the field existed);
      `page_deactivation_code_description_test.dart` (the prompt appears for a fresh code and
      saving replaces the QR image; skipping leaves the QR image showing; the same code is not
      re-prompted on an unrelated rebuild; a genuinely new code is prompted for again; "Edit
      description" reopens the dialog pre-filled).
- **Requirement:** R13

### T-151 · Repository hygiene pass — FIXED (2026-09-19)

- [x] Dead code removed, remaining non-English content translated, PII/commit-message/test-vs-
      requirements audits run.
- **Why:** routine hygiene sweep across code quality, documentation accuracy, and the "everything in
      English" / no-PII standing rules.
- **A real bug found, not just a hygiene item:** `Meeting.hashCode` (`lib/screens/schedule/
      meeting_data.dart`) called `jsonEncode(this).hashCode`, relying on dart:convert's fallback of
      calling a `toJson()` method - which had been commented out (along with a `TODO: verify
      correct de/serialization of meeting objects` that was never separately tracked). With the
      method gone entirely, every call to `hashCode` threw `JsonUnsupportedObjectError` instead of
      returning an int, violating the basic hashCode contract (must never throw; must agree with
      `==`). Nothing currently puts a `Meeting` in a `Set` or uses one as a `Map` key - confirmed by
      grep across `lib/`/`test/` and by checking `calendar_view`'s own `EventController`/
      `CalendarEventData` internals, which use their own fields for hashing, never delegating to the
      generic event payload - so the break went unnoticed in practice, but it was a live landmine
      regardless. Fixed with `Object.hash` over the exact fields `==` already compares; the dead
      `toJson()` comment and its now-moot TODO were removed along with it.
- **Dead code removed:** two other genuinely-unused commented-out blocks in `lib/app_state.dart`
      (a disabled `_loadVisibleDate()` method, and disabled persistence lines inside the
      `visibleDate` setter it belonged to - the setter's own "Must not persist" comment stands fine
      on its own); two stray disabled lines in `lib/screens/scan_code/page_deactivation_code.dart`
      (`//errorCorrectionLevel: QrErrorCorrectLevel.M`, `//importQrCodeButton`); and
      `AppState.currentPageIndex`'s setter, which persisted the tab index via `_prefs.setInt` on
      every tab switch even though the matching load-back line was already commented out - the
      write was pure unread disk I/O. Removed the write rather than restoring the load: always
      opening on the first tab is a deliberate, common choice, not an oversight to change here in a
      hygiene pass. Left `lib/screens/schedule/meeting_data.dart`'s commented-out `meetingToEvent`
      scaffolding alone - it mirrors `calendar.dart`'s existing, explicitly-labelled "For future
      development" block, an established pattern in this codebase, not orphaned dead code.
- **Non-English content translated:** five remaining spots (`app_state.dart` x2, a doc comment and
      a `ISO-Datum` fragment; `page_appearance.dart`'s spec-quote paraphrase; `notifications.dart`'s
      `"Voraussetzung, noch zu bauen"`; `test/snooze_state_test.dart`'s trailing comment) - found by
      a targeted audit for German words across `lib/`/`docs/`, cross-checked against the project's
      existing "quote then translate" convention for verbatim spec/user citations (several such
      citations in `docs/TODO.md` were confirmed already compliant and left alone).
- **PII audit:** no real personal names, emails, or addresses found beyond already-accepted cases
      (the Privacy Policy's intentional alias contact address; a third-party licence's author email,
      reproduced because BSD-3 requires retaining it, in the T-142 write-up).
- **Commit-message audit:** the full `dev` history (110 commits) was reviewed for typos, vague
      subjects, and embedded secrets - none found. A few commits quote German source material
      (the maintainer's own words, or the spec document) verbatim in the body, consistent with the
      same citation convention as the code comments above; not corrected, since rewriting already-
      pushed history is a destructive operation this project treats with standing caution and none
      of the messages actually need it.
- **Documentation corrected:** `docs/REQUIREMENTS.md` R9 didn't yet mention the T-142 native-code-
      notices fix; R4's QR-gate framing still cited T-08/T-16 by their older, since-superseded
      wording instead of T-143's current, narrower gap (and didn't cross-reference R13); R3 didn't
      yet reflect T-04's 2026-09-19 narrowing to specifically the long-idle/never-reopened scenario.
      All three updated. `docs/TODO.md` T-46's evidence line didn't cite the in-code `0x39A` marker
      in `lib/main.dart` (a gap in the original T-31 triage's numbering) even though it names the
      identical still-open concern - cross-referenced.
- **Tests:** `test/meeting_data_test.dart` gained "hashCode does not throw" and "hashCode is
      consistent with ==" (red before the `Object.hash` fix, confirmed by reverting it and re-
      running).
- **Requirement:** R12

### T-152 · A manual alarm's weekly repeat pattern was invisible outside the edit dialog — FIXED (2026-09-19)

- [x] Show which day(s) a manual alarm rings on directly on the alarm list, as a small pill per
      weekday.
- **Why:** feature request. `ManualAlarm.repeatOnDays` already existed and was already editable (a
      row of day-circles in the edit dialog), but nothing on the list itself said which days were
      actually selected - the only way to find out was to open the edit dialog for each alarm.
- **Fix:** `lib/screens/alarms/screen_alarms.dart`'s alarm-list tile subtitle now includes a row of
      seven small `CircleAvatar` pills (`_buildWeekdayPills`) below the alarm's title, one per
      weekday, filled with the accent colour when `repeatOnDays[day]` is true and a muted surface
      colour otherwise - read-only, unlike the edit dialog's identical-looking but tappable
      `_buildDaySelector` circles. Scheduled alarms have no `repeatOnDays` of their own (each is a
      single calendar-derived day, not a weekly pattern), so they get no pill row.
- **A pre-existing "everything in English" violation found and fixed along the way, missed by
      the 2026-09-19 hygiene pass (T-151):** `_getDayLabel` (shared by the new pills and the
      existing edit-dialog circles) returned German abbreviations shown directly in the UI - "DIE"
      (Dienstag), "MI" (Mittwoch), "DO" (Donnerstag), "SA" (Samstag), "SO" (Sonntag) - missed by
      that pass's grep-based audit because none of them are full German words. Now "Mo"/"Tu"/"We"/
      "Th"/"Fr"/"Sa"/"Su" throughout, both list pills and the edit dialog now show the same,
      correct English labels. Used two-letter labels rather than a single initial specifically to
      keep Tuesday/Thursday and Saturday/Sunday visually distinct at a glance.
- **Tests:** `screen_alarms_weekday_pills_test.dart` - all seven pills render for a manual alarm;
      an active day's pill uses the accent colour and an inactive day's does not; a scheduled alarm
      shows no pill row at all.
- **Requirement:** R12

### T-141 · Past scheduled alarms pile up in the list forever — FIXED (2026-09-19)

- [x] Prune scheduled alarms that are safely in the past, without touching FR-18's rule that a past
      alarm is never cancelled.
- **Why:** seen on the Linux desktop build on 2026-09-17: the Scheduled tab listed seven alarms,
  11. to 17. September, on the 17th. Six of them are for days that are over. They look live - each
  carries an enabled toggle - and the list only grows.
- **Cause, and it is a deliberate rule rather than an oversight:** `planAlarmSync` skips every
  alarm whose minute is not after `now` when computing `toRemove`, because a past alarm might be
  *ringing at this very moment* and `Alarm.stop()` on it would defeat the guaranteed wake-up
  (`lib/models/scheduling/apply_alarms.dart`, the `if (!minute.isAfter(nowMinute)) continue;` in
  the removal loop). Nothing else ever removes them, so `AppState.scheduledAlarms` accumulates.
  `pendingDayValues` and `disabledDays` both have a retention bound (T-82, FR-21); this list does
  not.
- **Interaction worth noting before fixing:** since FR-21 the toggle on a scheduled alarm writes
  into `disabledDays` for that alarm's day. On a past entry that writes a veto for a day that is
  gone - harmless, because `pruneDisabledDays` clears it, but it shows these entries are not inert.
- **Done when:** an alarm older than the retention bound disappears from the list, an alarm from
  *today* does not (it may still be ringing), and a test covers both - the second case is the one
  that matters, and a naive "remove everything in the past" fix gets it wrong. ✓
- **Fix:** `pruneScheduledAlarms` (`lib/models/scheduling/apply_alarms.dart`), a pure function kept
  deliberately apart from `planAlarmSync`'s own removal loop - that loop's job is safety-critical
  ("never touch anything that could be ringing") and stays exactly as narrow as before. Uses the
  same "yesterday" retention bound `replan()` already computes for `pendingDayValues`/`disabledDays`
  (T-82), keyed by `isoDate(alarm.time)` - the same wall-clock frame FR-21's toggle already uses for
  `disabledDays`, so a day is never split across two different readings of "which day is this
  alarm on". Wired into `replan()` right alongside the existing `pruneDisabledDays` call.
- **The "assign and persist" half lives in `AppState.setPrunedScheduledAlarms`,** not inside the
  pure function itself: `AppState` currently imports nothing from `lib/models/scheduling/` (every
  scheduling file imports it, never the reverse), and giving it the retention policy directly would
  have been the first crack in that one-way layering. `replan()` computes the pruned list with
  `pruneScheduledAlarms` (which it already has access to) and hands the result to `AppState`, which
  only assigns, persists (`_saveScheduledAlarms`) and notifies.
- **Test:** `test/prune_scheduled_alarms_test.dart` (the pure function: an old alarm is dropped,
  today's alarm survives even though its own time has already passed, the retention-bound day
  itself is kept and the day before it is not, a future alarm is always kept, a mixed list drops
  only the stale ones), `test/app_state_prune_scheduled_alarms_test.dart` (persistence round trip,
  notifies listeners, an unchanged list is a no-op), and `test/replan_prunes_scheduled_alarms_test
  .dart` (the actual wiring: an old alarm is pruned on replan, today's alarm - already past its own
  time by the moment replan runs, exactly the state it would be in while still ringing - is not).
- **Requirement:** R3

### T-27 · The global volume setting never reaches calendar-derived alarms — STALE DUPLICATE, ALREADY RESOLVED (confirmed 2026-09-19)

- [x] Thread the configured volume through to scheduled alarms.
- **This was already fixed, by T-84 (2026-09-10), well before this item was picked off the ranked
  top-10 list and looked at again.** `ScheduledAlarm` has carried a `volume` field since then
  (`lib/models/alarms/scheduled_alarm.dart`), `applyPlannedAlarms` sets it from
  `appState.selectedVolume` when creating a new alarm, and `planAlarmSync`'s `propertiesMatch`
  replaces an already-armed alarm whose volume differs from the current setting - so a volume
  change reaches alarms that already exist, not only ones planned afterward. Verified again
  directly: `test/apply_alarms_test.dart`'s "T-84: picks up tone, volume, and gentle-wake from the
  settings" and "T-84: a changed volume affects already-planned alarms" both pass against the
  current code.
- **Lesson for this list:** this entry's own wording ("carried forward from `lib/main.dart`'s old
  TODO backlog") was never updated when T-84 closed the identical gap - the same staleness class as
  T-07/T-03 (docs/TODO.md, 2026-09-18). Left here rather than deleted, so a duplicate discovered
  this way stays visible instead of just vanishing.
- **Evidence:** `lib/models/alarms/scheduled_alarm.dart` (the `volume` field);
  `lib/models/scheduling/apply_alarms.dart` (`applyPlannedAlarms`/`propertiesMatch`).

### T-28 · Correct the stale claims in `CLAUDE.md` and `REQUIREMENTS.md` — RESOLVED (2026-09-08)

- [x] Bring both in line with what is now verified.
- **Why:** both stated that no build had ever been installed or run on a real or emulated Android
  device, and `CLAUDE.md` additionally stated that no integration/E2E tests exist. The release
  workflow runs E2E tests on an API-34 emulator and gates the signed build on them.
  `REQUIREMENTS.md` used the falsified claim as the single root cause of R2/R3/R4, so its register
  mis-attributed which gaps actually remain. Neither document mentioned the E2E gate, the evidence
  artifact, or how to run the suite.
- **Evidence:** `CLAUDE.md:116-121` (before this fix), `docs/REQUIREMENTS.md:138-141` (before this
  fix); the newest release run passed all three E2E scenarios on the emulator.
- **Resolution:** `CLAUDE.md`'s "Testing status" section rewritten to list what
  `integration_test/app_test.dart` actually covers, what it doesn't, and that a real on-device run
  now happens on every release; the "Quality baseline snapshot" section clarified that both
  snapshot docs predate the E2E work and are gitignored. `REQUIREMENTS.md`'s R2, R3 and R4 statuses
  and the closing summary rewritten to attribute the real remaining gaps (no background
  rescheduling mechanism, no reboot/force-stop test, no audio/ramp/camera-isolated coverage)
  instead of "never ran on a device". README's "Quality Checks" section now documents the E2E gate
  and the local command to run it.

### T-42 · Six persisted settings are unreachable or unused — FIXED (2026-09-20)

- [x] Five of the six removed: `doNotDisturbEnabled`, `turnOffNotifications`, `turnOffCalls`
      (feature never built), `wakeUpSteps` and `rescheduleOnAlarm` (both belonged to the old
      engine and disappeared with it - Phase 6, T-86). `grep -rn` no longer finds them anywhere
      in `lib/`; the one remaining hit for `rescheduleOnAlarm` is a historical comment in
      `handler.dart` explaining what used to be there.
- [x] **`startOfWeekDay` removed (2026-09-20), at the maintainer's request.** It was worse than "no
      UI": its one reader, `getStartOfWeek` (`lib/utils/utils.dart`), used the value only as a
      *condition*, never as a *target* - if the weekday didn't match, it always computed
      `subtract(weekday - 1)` back **to Monday** regardless, so the setting only decided WHETHER a
      correction happened, never WHAT it corrected to; `AppState.isCalendarWeekFetched` had the
      identical dead condition inline. Both now simply always normalize to Monday
      (`dateTime.subtract(Duration(days: dateTime.weekday - 1))`), which is exactly what the
      condition always produced anyway - subtracting 0 days is already a no-op when `dateTime` is
      already Monday, so dropping the condition changes nothing observable. `getStartOfWeek` lost
      its now-unused `AppState` parameter; call sites in `screen_schedule.dart` and
      `preloadCalendarData` updated. The field, its getter/setter and its `SharedPreferences` load
      are gone from `AppState`.
- **Why:** three are fully dead — `doNotDisturbEnabled`, `turnOffNotifications`, `turnOffCalls` are
  declared and persisted but have zero readers outside `AppState`, for a feature the use cases mark
  as never implemented. Three more are read by logic but have no UI: `wakeUpSteps`, which drives the
  entire `_adjustAlarmTimes` comparison window, `startOfWeekDay`, and `rescheduleOnAlarm`. So the
  single knob that governs how aggressively alarms are estimated cannot be changed by a user, while
  settings that do nothing are stored.
- **Evidence:** `grep -rn "doNotDisturbEnabled\|turnOffNotifications\|turnOffCalls" lib/` → no hits
  outside `lib/app_state.dart`; `wakeUpSteps`/`startOfWeekDay`/`rescheduleOnAlarm` have 0 hits under
  `lib/screens/`; `lib/models/scheduling/scheduling.dart:141` consumes `wakeUpSteps`.
- **Done when:** every persisted setting is either user-changeable and consumed, or gone.

### T-43 · The gentle-wake ramp duration is hardcoded — RESOLVED (already fixed by T-96, confirmed 2026-09-18)

- [x] Already made configurable, as a side effect of fixing T-96 (the ramp duration had to become a
      per-alarm property anyway so `planAlarmSync` could recognize a changed value as a deviation
      on an already-armed alarm - see that item's own write-up). No code change was needed here;
      this entry is closed by confirming the state of the code against T-43's own "Done when" bar.
- **Why (historical):** the whole tuning surface of a headline feature used to be a single
  `const Duration(seconds: 60)`. The one user-facing duration that sounds related ("duration to wake
  up") feeds scheduling, not the ramp - so a user adjusting it changed something else entirely.
- **Current state:** `AppState.gentleWakeUpDuration` (`lib/app_state.dart`) is a persisted setting,
  enforced to a one-minute minimum, adjustable in Settings > Sleep Habits ("Gentle WakeUp",
  `lib/screens/sleep_habits/screen_sleephabits.dart`); a manual alarm can override it per-alarm via
  `gentleWakeDuration` in the alarm editor (`lib/screens/alarms/screen_alarms.dart`), inheriting the
  global setting at creation time only new alarms - the same FR-15 rule this session's T-50 followed
  for `vibrate`. The one remaining hardcoded `Duration(seconds: 60)` in the codebase is a comment in
  `lib/models/alarms/ringing_alarm_settings.dart` documenting the value that used to be there, not
  a live default.
- **Evidence:** `lib/app_state.dart`'s `gentleWakeUpDuration` getter/setter and
  `_gentleWakeUpDurationMinimum`; `grep -rn "Duration(seconds: 60)" lib/` returns only that comment.
- **Tests:** `test/app_state_scheduling_v2_test.dart` ("gentleWakeUpDuration - round-trip and
  enforced minimum"), plus the T-96 propagation tests in `apply_alarms_test.dart`,
  `ringing_alarm_settings_test.dart` and `manual_alarm_inherits_settings_test.dart`.

### T-44 · A dead gallery-scan button would bypass the camera gate if wired in — RESOLVED (2026-09-17)

- [x] Gone with the scanner swap (T-33): `scanner_button_widgets.dart` was deleted along with the
      rest of the mobile_scanner-specific widgets, and the replacement's own gallery button is
      switched off explicitly (`showGallery: false`, with the reason at that line). Decoding a
      stored image would let a user photograph the code once and defeat the gate from bed.
- **Why:** the widget picks an image from the gallery and runs it through the scanner. It is
  currently never instantiated, but it sits in the scanner's own button file — wiring it into the
  alarm-dismissal scanner would let a screenshot of the QR code dismiss the alarm, defeating the
  "physical code in another room" premise. It is also the reason the app requests gallery access.
- **Evidence:** `lib/screens/scan_code/scanner_button_widgets.dart:5-49`; no instantiation anywhere
  in `lib/`.
- **Done when:** the code is gone, or it exists only on the import screen and cannot reach the
  dismissal path.
- **Requirement:** R4

### T-45 · A failure loading preferences can still prevent the app from starting — FIXED (2026-09-18)

- [x] Bring the `SharedPreferences.getInstance()` call inside the guard its own comment promises.
- **Why:** `_loadFromPreferences` carried a comment stating that a failure must never throw out of
  the method, because `main()` awaits initialisation before `runApp` — but the `getInstance()` call
  itself sat outside the `try`. If it threw, the app did not start at all, which for an alarm
  clock meant every armed alarm was silently unreachable.
- **Fix:** `getInstance()` now has its own `try`/`catch`, ahead of the existing settings-loading
  one. Deliberately a separate `try` rather than merging the call into the existing block: with
  `_prefs` a `late final`, a failure here leaves it unassigned, and the existing block's own
  `LateInitializationError` on its first `_prefs.getBool(...)` read already degrades to defaults
  and reaches `notifyListeners()` at the end - so isolating the risky line was the only change
  actually needed, not a rewrite of the fallback logic.
- **Testability:** how the instance is obtained is injected (`AppState({getPrefsInstance})`), the
  same pattern as `documentsDirectory`/`fetchEvents`/`now` elsewhere in this class, so a throwing
  plugin call can be simulated without a platform channel.
- **Accepted residual limitation:** this only guarantees the app *starts*. `_prefs` stays
  unassigned on this path, so any later code that writes through it (a settings toggle, an alarm
  being saved) would still throw an uncaught `LateInitializationError` when it runs - out of scope
  for what this item's "done when" asked for, and a real `SharedPreferences.getInstance()` failure
  on a real device is itself an unlikely, largely theoretical trigger.
- **Test:** `test/app_state_prefs_failure_test.dart` - a throwing `getPrefsInstance` no longer
  blocks `initialized` from completing, and listeners still get notified so the UI (a
  `ChangeNotifierProvider` consumer) still builds.
- **Requirement:** R3

### T-46 · The scheduling window is hardcoded — ANSWERED (2026-09-10, by scheduling-v2)

- [x] **Justified rather than made configurable.** FR-8 fixes the window explicitly: "only the
      visible 7-day window, no larger horizon", with the reasoning given in the spec text. The
      abort-after-seven-estimated-alarms behavior no longer exists (it belonged to the old
      engine); in its place is FR-9's valve, with a named threshold (`gapDayValveThreshold`) and
      a notification to the user. What remains of the original task:
- [ ] Make the forward window, preload range, and estimate-abort threshold configurable, or justify
      the constants.
- **Why:** scheduling covers a fixed 7-day forward window, the preload is a hardcoded two past / one
  future week, and `_adjustAlarmTimes` aborts scheduling entirely once 7 alarms needed estimating -
  none of the three is user-changeable. `lib/main.dart`'s old TODO backlog named exactly these three
  as unfinished (`0x49`, `0x392`, `0x395` - see T-31); they were not separately re-tracked because
  they are this same gap. The preload range specifically is still marked with its own in-code
  reminder at `lib/main.dart`'s `_syncCalendarAndAlarmsOnOpen` (`// TODO user configurable preload
  range - 0x39A`) - that id was missed by the original T-31 triage (it's a gap in the numbered
  sequence there) but names the identical, still-open concern as this item.
- **Evidence:** `lib/models/scheduling/scheduling.dart:54` (window), `:169` (`>= 7` threshold);
  `lib/main.dart:242` (preload).
- **Done when:** the ranges/threshold are either settings or documented as deliberate constants with
  a reason.

---

### T-50 · Manual alarms don't respect two global settings — PARTLY FIXED (2026-09-18)

- [x] (a) Make manual alarms honor a vibration switch.
- [x] (b) Dropped — see below.
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31). Two distinct gaps: (a)
  there was no vibration setting anywhere in the app at all - `vibrate: true` was hardcoded in
  `buildRingingAlarmSettings` for every alarm, regardless of type; (b) "respect time of day change"
  was never specified precisely enough in the original note to know what behavior was wanted.
- **Evidence (before the fix):** `lib/main.dart`'s pre-triage TODO block, item `0x502`/`0x503` (see
  T-31); the hardcoded `vibrate: true` was in `lib/models/alarms/ringing_alarm_settings.dart`.
- **Fix (a):** `vibrate` is now a property of `MyAlarm` itself (default `true`, matching the
  previously hardcoded behaviour so existing installs don't change), threaded through
  `ScheduledAlarm`/`ManualAlarm`'s `toJson`/`fromJson`/`==` and into
  `buildRingingAlarmSettings`, following the same shape T-84/T-96 already established for
  tone/volume/gentle-wake duration: a setting that must reach an *already-armed* alarm has to be a
  property of the alarm the reconciliation (`planAlarmSync`'s `propertiesMatch`) can compare
  against, not just an `AppState` default a new alarm happens to inherit at creation time. A global
  `AppState.vibrationEnabled` (persisted, default `true`) is the value new alarms inherit and the
  one `applyPlannedAlarms` passes into `ScheduledAlarm` construction/reconciliation; a new
  "Vibration" toggle in Settings > Alarm Tones (`page_alarmtones.dart`) sets it and, like the
  existing tone/volume controls there, calls `runCheckpointSafely(..., trigger:
  CheckpointTrigger.settingsChanged)` so an already-planned alarm picks up the change immediately
  rather than only on the next incidental replan. A manual alarm inherits the current
  `vibrationEnabled` value at creation (`screen_alarms.dart`), the same FR-15 rule tone/volume/
  gentle-wake already follow for manual alarms - they're user-owned and edited directly, never
  auto-regenerated the way scheduled alarms are, so a global setting only reaches a *new* manual
  alarm, not retroactively into one that already exists.
  - Along the way, found and fixed a pre-existing bug this change exposed:
    `AppState.addAlarm` reconstructs a brand-new `ManualAlarm`/`ScheduledAlarm` object field-by-field
    (to normalize a possibly past-dated time) instead of using the object passed in, and neither
    reconstruction's field list included `vibrate` - so it silently reset to `MyAlarm`'s hardcoded
    default on every add, regardless of what had actually been set. Fixed by adding `vibrate:
    alarm.vibrate` to both reconstructions.
- **Dropped (b):** "respect time of day change" remains too vague to implement against - the
  original note doesn't say what device-clock/DST change it means an alarm should react to, or
  what reacting should look like (re-fire? re-time? just re-notify?). Rather than guess at a
  behavior nobody asked for, this half is dropped without an implementation. Revisit only if a
  concrete scenario is reported.
- **Tests:** `test/app_state_vibration_test.dart` (default, persistence, notifies listeners);
  `apply_alarms_test.dart` gained a `propertiesMatch` case (a differing `vibrate` triggers
  replacement) and an `applyPlannedAlarms` case (the setting reaches newly-planned alarms);
  `ringing_alarm_settings_test.dart` gained a case asserting `vibrate` passes through unchanged;
  `manual_alarm_inherits_settings_test.dart` gained an assertion that a new manual alarm inherits
  the current vibration setting.

### T-51 · Theme does not follow the system light/dark setting — FIXED (2026-09-19)

- [x] Add a "follow system" option alongside the existing manual dark-mode toggle.
- **Why:** `MyApp.build` set `themeMode` from `appState.darkMode` (a manual boolean), never
  `ThemeMode.system` - so the app could not automatically match the OS theme, only be switched by
  hand.
- **Fix:** `AppState.followSystemTheme` (persisted, alongside the existing `darkMode`) and a new
  computed `AppState.themeMode` getter that combines the two into the `ThemeMode` `MaterialApp`
  actually takes - `ThemeMode.system` when following, otherwise `darkMode`'s manual value. Computed
  in one place so `main.dart` can't independently re-derive it and drift, the same "one source of
  truth" shape as every other computed `AppState` value. Turning "Follow System Theme" back off
  restores the manual choice rather than losing it - the flag is a separate field, not a
  replacement of `darkMode` itself.
- **UI, per the maintainer's own spec:** a new "Follow System Theme" switch in Settings > Appearance,
  above the Dark Mode toggle it overrides. While it's on, the Dark Mode switch is disabled
  (`onChanged: null` - what actually makes Flutter's own `Switch` render itself greyed out, not a
  no-op callback that leaves it looking interactive) and its label dims to
  `Theme.of(context).disabledColor`.
- **Test:** `test/app_state_theme_mode_test.dart` (the `themeMode` combination logic and
  persistence) and `test/page_appearance_theme_test.dart` (the Dark Mode switch is enabled/disabled
  correctly as "Follow System Theme" toggles, and a disabled switch genuinely can't be toggled by
  tapping it).
- **Evidence (before this fix):** `lib/main.dart:106-108`; `lib/app_state.dart`'s `darkMode`
  getter/setter.

### T-52 · Several scheduling/sleep-habit options were hardcoded, not user-configurable — FIXED (2026-09-19)

- [x] T-52.1: a toggle for scheduling (or not) on days without a calendar entry.
- [x] T-52.2: 24h-vs-AM/PM display, adapted to the phone's own setting.
- [x] T-52.3: a per-weekday override for "duration to get ready".
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31), the parts of it not
  already covered by T-42/T-43/T-46. A day with no calendar entries always got FR-4's drift/hold
  treatment with no way to opt out; times were always displayed in one fixed format regardless of
  the device's own setting; and "duration to get ready" was a single global value with no
  per-weekday override, unlike `repeatOnDays` which is at least per-weekday (T-14).
- **Evidence (before the fix):** `lib/main.dart`'s pre-triage TODO block, items `0x393`, `0x398`,
  `0x399` (see T-31).
- **T-52.1 fix:** `computeWeekPlan` (`lib/models/scheduling/scheduling_v2.dart`) gained a required
  `scheduleOnGapDays` flag, applied as a **mask over its own output** rather than folded into the
  drift math itself - every day without a real `hardFloor` (i.e. no calendar entry of its own) is
  nulled out in the two `return` points when the flag is off, and every day that DOES have one is
  completely unaffected, byte-for-byte the same as before. Chosen deliberately over threading the
  flag through the drift/distribute/gap-or-run-start functions themselves: those are the most
  heavily spec-reviewed part of the app (FR-4/5/6/7/9/10, the "OPEN SPEC DECISION" items T-112-122),
  and a masking pass cannot change how a real appointment day is computed, only whether a day
  without one is allowed to keep a value at all - the smallest change that could deliver the
  feature without touching that core's carefully-audited invariants (anchor propagation across the
  window, FR-9's counter, the safety valve). `AppState.scheduleOnGapDays` (persisted, default
  `true` - the only behaviour that existed before) is the new Settings > Sleep Habits toggle
  ("Schedule an alarm on days without an appointment"), wired into `replan.dart`'s
  `computeWeekPlan` call.
- **T-52.2 fix:** the Schedule screen's hour-axis label (`screen_schedule.dart`'s `_timeLineMark`)
  used to hardcode `DateFormat('HH:mm')` regardless of the device's own setting. Now reads
  `MediaQuery.of(context).alwaysUse24HourFormat` - the same source `showTimePicker` itself already
  defaults to - and formats as `'h:mm a'` when the device is not set to 24-hour time, matching the
  actual phone setting instead of a second, independent decision.
- **T-52.3 fix:** `MyAlarm`'s scheduling input `durationToGetReady` became a resolvable-per-day
  value. `computeWeekPlan`'s `durationToGetReady: Duration` parameter became
  `durationToGetReadyForDay: Duration Function(DateTime day)`, since a single 7-day window can
  legitimately span every weekday in one call - its only use site (feeding `hardFloor` once per
  window day) made this a strictly localized change, not a rework of the distribution math.
  `AppState.durationToGetReadyByWeekday` (persisted) holds only the days that have been explicitly
  overridden - absent from the map means "follow the global `durationToGetReady` value", so an
  empty map (every existing install) behaves exactly as before; a day's own value is exposed via
  `durationToGetReadyForWeekday(day)`, which `replan.dart` calls per window day.
  Settings > Sleep Habits gained a collapsible "Customize per weekday" section under the existing
  "Duration to get ready" control, one switch + time picker per day, following the same
  optional-override shape already established (a day's override, once cleared, reverts to
  following the global value rather than freezing at whatever it last was).
- **Tests:** `scheduling_v2_test.dart` (a per-window-day `durationToGetReadyForDay` callback
  produces two different hardFloors for the same appointment time; `scheduleOnGapDays=false` masks
  every day without an appointment, both the cold-start-with-no-anchor-anywhere path and the
  main-loop drift path, while leaving a real appointment day completely untouched);
  `app_state_scheduling_v2_test.dart` (both new fields' persistence round-trip, and the
  weekday-override resolver's fallback/override/clear behaviour); `screen_schedule_test.dart`
  (the hour axis is 24h with the flag on, 12h AM/PM with it off);
  `sleep_habits_gap_day_and_per_weekday_test.dart` (both new Sleep Habits controls, end to end).

### T-53 · No way to choose which calendar counts as "the work calendar" — FIXED (2026-09-19)

- [x] Let the user select which calendar(s) feed the scheduling algorithm.
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31). `use-cases.md` describes
  "Select Calendar for interconnection" as a use case, but no per-calendar selection UI existed -
  `grep -rn "workCalendar\|selectedCalendar" lib/` found nothing, and `calendar.dart`'s
  `retrieveCalendars()` result was used without a filtering step.
- **Fix, per the maintainer's own spec:** a checkable dropdown list of calendars, reachable from a
  corner button on the Schedule screen's app bar (`Icons.event_note`, tooltip "Calendars"). Tapping
  it opens a modal bottom sheet - one `CheckboxListTile` per `device_calendar` `Calendar`, following
  the exact same `StatefulBuilder`-wrapped-tile shape already established for T-149's
  "ignore this event" sheet (`_showIgnoreEventSheet`), so the sheet stays open while more than one
  calendar is toggled rather than closing after the first tap. Toggling one runs the same
  `CheckpointTrigger.settingsChanged` checkpoint that sheet already uses (a selection change feeds
  `hardFloor` derivation and must take effect immediately) plus a `resyncCalendarData` call (T-60)
  so the Schedule display picks it up without waiting for the next natural resync.
- **AppState:** `deselectedCalendarIds` (persisted `Set<String>` of `Calendar.id`) stores what's
  explicitly opted **out**, not what's opted in - an empty set (every existing install) means every
  calendar counts, unchanged from before, and a calendar the device adds later (never seen before,
  so absent from the set either way) is included by default rather than silently dropped until
  the user notices and opts it in by hand.
- **Filter applied in exactly the two places that read the calendar list:** `getCalendarEntries`
  (feeds the Schedule display's `appState.meetings`) and `fetchMeetingsUncached` (feeds
  scheduling-v2's `replan()`) both now loop over `calendars.where((c) =>
  appState.isCalendarSelected(c.id!))` instead of the raw list - the one shared filter both paths
  read the same module-level `calendars` list through. `fetchMeetingsUncached`'s own diagnostic
  (`Diag.calendarRead`) was updated to count the *selected* calendars, not every calendar
  `device_calendar` returned, so a user who deselected everything reads the same as one with no
  calendars at all instead of masking that state.
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, item `0x48` (see T-31);
  `lib/screens/schedule/calendar.dart`; `lib/screens/schedule/screen_schedule.dart`'s
  `_showCalendarSelectionSheet`.
- **Bug found and fixed the same day, via real-device use, not review:** the sheet's list of
  calendars was a plain, non-scrolling `Column` - a device with several accounts (each contributing
  its own holiday/birthday calendars) overflowed it ("A RenderFlex overflowed by N pixels on the
  bottom"), since nothing there could shrink to fit. Fixed by making the sheet `isScrollControlled`
  and wrapping the calendar list in `Flexible(child: ListView(shrinkWrap: true, ...))`, so the sheet
  grows up to the full screen height before the list itself starts scrolling.
- **Tests:** `app_state_calendar_selection_test.dart` (default-selected, deselect/reselect
  round-trip, clearing an override rather than freezing a flag, notifies listeners);
  `screen_schedule_calendar_selection_test.dart` (the corner button opens the sheet with one row
  per calendar; unchecking one updates `AppState` and is still reflected after closing and
  reopening the sheet; an empty calendar list shows a fallback message instead of an empty sheet;
  twenty calendars at a narrow screen width no longer overflow - red before the
  `isScrollControlled`/`Flexible`/`ListView` fix, reproducing the real-device report exactly).

### T-55 · Wrong "already fetched" answer for any day that isn't its own week's start — FIXED (2026-09-18)

- [x] Verified reproducible, then fixed.
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31): "wrong scheduled alarm
  infos if opening scheduled alarm page before preloading finished" and "duplicate calendar entries
  for preloaded weeks (on first load only?)". The concurrency framing in the original note turned
  out not to be the mechanism - `AppState.isCalendarWeekFetched` was reproducibly wrong even with
  no race involved at all.
- **Root cause:** `preloadCalendarData` (`lib/utils/utils.dart`) records each preloaded week in
  `AppState.fetchedCalendarWeeks` keyed by the **start of that week**. But
  `screen_schedule.dart`'s `updateCalendarData` calls `isCalendarWeekFetched(appState.visibleDate)`
  - and `visibleDate` is normally "today", an arbitrary day within the week, not its Monday. The old
  comparison checked that raw day against the start-of-week entries directly, so it only ever
  matched on the one day per week that happened to already be the start-of-week day; every other
  day reported an already-preloaded week as not fetched, triggering a redundant `getCalendarEntries`
  call that appended a second copy of the same week's entries to `appState.meetings` - exactly the
  duplicate-entries symptom the original note described, and unconditionally reproducible on any
  non-start-of-week day, no timing race required. A second, smaller bug in the same method: its
  "not fetched" debug log referenced `screen_schedule.dart`'s file-level `appState` variable instead
  of `this` - harmless when a widget had already set that global, but a `LateInitializationError` in
  any context that calls `isCalendarWeekFetched` without one (e.g. a plain unit test).
- **Fix:** `isCalendarWeekFetched` now normalizes its argument to its own start of week before
  comparing, the same rule `getStartOfWeek` already applies elsewhere - so a mid-week query matches
  a start-of-week entry for the same week. `updateCalendarData`'s own successful-fetch branch was
  also storing the raw `visibleDate` instead of `startOfWeek` in `fetchedCalendarWeeks`; changed it
  to store `startOfWeek` too, so every entry in that list means the same thing. Fixed the stray
  `appState.` debug-log reference along the way.
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, items `0x461`/`0x462` (see T-31);
  `lib/app_state.dart`'s `isCalendarWeekFetched`; `lib/utils/utils.dart`'s `preloadCalendarData`;
  `lib/screens/schedule/screen_schedule.dart`'s `updateCalendarData`.
- **Tests:** `test/calendar_week_fetched_test.dart` - a mid-week day is reported as fetched once its
  week's start date is in `fetchedCalendarWeeks` (red before the fix, since the raw day never
  matched a start-of-week entry), and a mid-week day whose week was never fetched still correctly
  reports `false`.

### T-57 · No fallback scheduling target when there are no calendar entries at all — RESOLVED (2026-09-10, by scheduling-v2)

- [x] **Decided and built.** A day with no appointment is no longer a special case, but FR-4's
      gap day: the value drifts toward `preferredWakeUpTime`, bounded by `maxDailyDelta`, and
      without a `preferredWakeUpTime` holds at the last-rung time. If no anchor exists at all,
      FR-10's cold start applies (nothing is invented); if the appointment situation breaks down
      permanently, FR-9's valve applies and **notifies the user**, instead of silently scheduling
      nothing. The original wording referred to `scheduleAlarms`, which no longer exists.
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31). Today,
  `scheduleAlarms` logs "No events in calendar. Aborting." and schedules nothing at all - there is
  no user-configurable fallback wake-up target for days/weeks with no calendar data, distinct from
  T-02's per-day 23:59-placeholder handling (which only applies once *some* days in the window do
  have entries).
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, item `0x53` (see T-31);
  `lib/models/scheduling/scheduling.dart:78-79`.
- **Done when:** either a fallback target is implemented and tested, or the app's behavior with zero
  calendar entries is explicitly documented as "schedule nothing" and surfaced to the user (rather
  than only logged).

## P3 — housekeeping

### T-29 · Record the provenance and licence of bundled assets — RESOLVED (2026-09-18)

- [x] `assets/sounds/*.mp3`: all six replaced with sources under `assets/sounds/CREDITS.md`.
- [x] The icon assets (`assets/icons/icon.png`, `icon_no_shadow.png`): confirmed AI-generated by
      the maintainer (2026-09-18) - own content, not a copy of a third party's copyrighted work, so
      nothing further to trace. Worth recording as a fact for anyone reading this later, since
      inspection alone (no embedded metadata either way) could not have told the difference between
      "AI-generated" and "unknown, possibly infringing".
- **Why:** R10 was unverified and no record existed for either the sounds or the icons.
- **What inspection actually found, not just "unknown":** ID3-tag inspection (`ffprobe`) on the six
  original sound files turned up real evidence, not just an absence of one. `annoying_alarm.mp3`
  carried `title=Annoying Alarm`, `publisher=__KIKO__`, `comment=Rate And Subscribe` - the signature
  of a YouTube-to-MP3 rip, not a licensed asset. A PRIV frame in `wakeywakey.mp3`
  (`{"note":"","date":"2021-04-27T10:49:17.637Z"}`) led to identifying both `wakeywakey.mp3` and
  `wakeywakey2.mp3` as sourced from the "Wakey Wakey it's time for school" meme (originally a
  private family video) via a fan remix ("Wakey Wakey it's time for scoo Meme (J.JAX Remix)") -
  neither the original video nor the remix carries any redistribution licence, and the original
  traces to an identifiable real person. The remaining three (`lollipop.mp3`,
  `old_telephone_ring.mp3`, `wake_up.mp3`) carried no metadata either way, but given this track
  record for the set, all six were replaced rather than assuming the unlabelled three were clean.
- **Fix:** all six replaced with Mixkit Sound Effects Free License tracks (free commercial use, no
  attribution required) - see `assets/sounds/CREDITS.md` for the exact source URL per file.
  Filenames kept unchanged so no other reference (`pubspec.yaml`, `AppState`'s default tone,
  `page_alarmtones.dart`, `screen_alarms.dart`, test fixtures) needed to change.
- **The old files didn't only need replacing in HEAD - they were still sitting in git history**,
  which `git clone` (and the public release T-34 requires) hands out just as readily as the current
  tree. Rewritten out (2026-09-18) with `git filter-repo --strip-blobs-with-ids` against the six
  exact blob hashes of the original 2026-09-08 versions (each file was only ever touched twice -
  added once, replaced once - so this was a precise six-blob list, not a guess): a fresh mirror
  clone of the repo had those blobs stripped, then both `dev` and `master` were force-pushed back
  and every local worktree hard-reset to match. Chosen deliberately over resetting the whole
  history to a single squashed commit (discussed and considered): this keeps every commit message,
  author, and date - the six bad blobs are simply gone from every tree that ever referenced them,
  and any commit whose tree included one now has that path missing there instead of rewritten
  content, rather than every commit being collapsed into one with no history at all.
  **Consequence, not a bug:** every commit hash on both branches changed as a result (blob removal
  changes tree hashes, which changes commit hashes all the way forward) - anyone with an existing
  clone needs to re-clone rather than pull. And since `master` had not yet been fast-forwarded past
  the 2026-09-17 sound replacement at the time of the rewrite, its current tip now has **no**
  `assets/sounds/*` files at all (the old blob it referenced is gone, and it never had the new one)
  - resolved automatically the next time `master` is fast-forwarded to a `dev` commit at or after
  the replacement, which needs to happen before `master` is built from again regardless.
- `flutter analyze`/`flutter test` unaffected by the sound swap (confirmed).
- **Requirement:** R10

### T-30 · Annotate or retire the planning artifacts — RESOLVED (2026-09-20)

- [x] ~~Annotate the risk graphic~~ - **replaced** rather than annotated: `docs/risk.png` has been
      a real threat model since 2026-09-10, generated from `docs/threat-model.svg` (see T-101).
- [x] Annotate the UML diagram (or retire it) - **retired**: `docs/UML_WakeyWakey.drawio` was
      deleted (2026-09-20). It modelled the original planning-phase design (including the removed
      old scheduling engine and never-built NFC deactivation) with no annotation of its own, and a
      `.drawio` binary can't be annotated inline the way the markdown planning docs were. Rather
      than hand-edit a diagram file to describe a codebase it never matched, the decision is to
      redraw it from scratch once there is a drawio-integration workflow in place (tracked
      separately, not yet scheduled) - until then, `docs/TODO.md` and `CLAUDE.md`'s architecture
      tables are the accurate structural description of the app.
- **Why:** the descriptive documents miss the app in both directions: the README's three headline
  features understate the shipped surface, while `personas.md`, the UML diagram and `risk.png`
  still model features and classes that were never built and carry no annotation saying so.
  `use-cases.md` stated that everything unmarked shipped, which was not the case.
- **Resolution:** `use-cases.md` annotated inline (the "Disable alarm" switch is a no-op;
  "Manage/Disable Deactivation Codes" only has Generate/Remove for a single code, no separate
  disable; "Print as QR Code" is only partially implemented - the code renders on-screen, but
  share/print is an explicit "future feature" stub; the Settings inventory extended to list
  Diagnostics, Licence and Native Code Notices alongside Appearance/Tone/About) and its blanket
  top-note corrected to acknowledge shipped-but-broken items as a third category, tracked in
  `docs/TODO.md` rather than as planning gaps. `personas.md` given its own annotation note plus a
  specific correction to Tom's jetlag/timezone claim (the app only reads the device's current
  timezone; there is no dedicated jetlag-adjustment feature). `choice-of-technologies.md` annotated
  on its iOS cross-platform claim (unverified - iOS has never been built or run) and on Flutter's
  own description now naming the actual replaced dependencies (Syncfusion, `mobile_scanner`) it
  previously didn't mention. `risk.png` remains a diagram (not annotatable inline) but is now a
  real, current threat model rather than a stale planning artifact - see T-101 - so it needed no
  further action here.
- **Done when:** each planning document either matches the code or says plainly where it does not.
  Met: the UML diagram, the one artifact that could be neither corrected nor meaningfully
  annotated, is retired rather than left stale.

### T-31 · Triage the `main.dart` TODO backlog — RESOLVED (2026-09-09)

- [x] Decide which of the numbered TODOs at the top of `lib/main.dart` are real commitments and
      move those here.
- **Why:** the block mixes cosmetic wishes with items that mean an advertised setting does not
  exist. Several overlap with T-01, T-02, T-14 and T-27.
- **Evidence:** `lib/main.dart:21-63` (before this triage).
- **Resolution:** each of the 13 numbered items was checked against the current code individually.
  Four were confirmed already superseded by existing tracked gaps (`0x391`/`0x397`/`0x39B` by T-42,
  `0x39C` by T-43) and three more by T-46 (`0x49`, `0x392`, `0x395`, the last one verified still
  hardcoded at `scheduling.dart:169`). One (`0x28`'s "read color from calendar" sub-item) was
  confirmed already implemented (`calendar.dart:61`) and dropped. The remaining eight genuine,
  still-open items became T-50 through T-59 (skipping the numbers already used), each with its own
  evidence and acceptance criterion. `lib/main.dart`'s TODO block itself was reduced to a single
  pointer comment; `lib/models/alarms/handler.dart`'s duplicate copy of the `0x39B` note was
  updated to cite T-42 instead.
- **Done when:** the block is reduced to genuine in-code markers, and anything user-visible lives
  in this file with a priority.

### T-47 · `CLAUDE.md` contains several inaccurate statements — RESOLVED (2026-09-08)

- [x] Correct the specific errors, independently of the broader status rewrite in T-28.
- **Why:** the file is the agent-facing instruction sheet, so wrong detail there propagates. Known
  errors: it stated the timezone override is `^0.11.1` while `pubspec.yaml` pins `^0.11.0`, and it
  explicitly instructs keeping those in sync; it pointed readers to `MissingPluginException`
  handling that does not exist anywhere in `lib/`; it claimed `personas.md` is annotated where
  features were never implemented, which it was not; and it described both scheduling script
  directories as using `stdin`, which only one does.
- **Evidence:** `CLAUDE.md:86` vs `pubspec.yaml:61,84`; `CLAUDE.md:16-17` vs
  `grep -rn "MissingPluginException" lib/` → 0 hits; `CLAUDE.md:134-137` vs `docs/personas.md`;
  `CLAUDE.md:111-113` vs `test/getEarliestAlarm/main.dart`.
- **Resolution:** timezone override corrected to `^0.11.0`; the Linux/`device_calendar` note now
  describes the real generic `try/catch` around `retrieveCalendars()` in
  `lib/screens/schedule/calendar.dart` instead of a handler that doesn't exist; `personas.md` is now
  actually annotated (see T-30), making the claim true; the stdin description now says "in
  `adjustTime/`'s case also `stdin.readLineSync()`", matching that only one script uses it.
- **Done when:** each statement in the file is either true or removed.

### T-48 · No source file carried a licence header — FIXED (2026-09-19)

- [x] Add per-file GPLv3 notices.
- **Why:** none of the Dart sources carried a copyright or licence header, so a file copied out of
  the repository lost any licence trace. Recommended GPLv3 practice rather than a strict
  requirement - and weighs more than "recommended" for an F-Droid submission specifically, whose
  inclusion review commonly expects clear per-file licensing across the whole tree.
- **Fix:** the FSF's own short-form notice, naming the actual project rather than the generic
  `<program>` placeholder, prepended to all 45 `.dart` files under `lib/` (the standard "Copyright
  (C) 2026 Dam0k1es … This file is part of WakeyWakey … WITHOUT ANY WARRANTY … GNU General Public
  License … <https://www.gnu.org/licenses/>" text). Applied as a pure mechanical prepend - no
  reformatting bundled in, even where `dart format` found unrelated, pre-existing line-length drift
  in a handful of files while checking the result; that drift predates this change and is out of
  scope for it.
- **Tests:** `test/licence_header_test.dart` - a source-reading test (the same shape as
  `test/no_proprietary_dependencies_test.dart`/`test/diag_log_api_test.dart`) asserting every file
  under `lib/` contains the notice, so a new file added without it, or an existing one stripped
  during an edit, fails the suite instead of silently regressing.
- **Requirement:** R9

### T-54 · No custom Android notification icon — FIXED (2026-09-19)

- [x] Set a proper small icon for the alarm/reminder notifications instead of the default.
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31). `Notifications`'s channel
  setup passed `null` for the icon, so Android fell back to the app's launcher icon (or a generic
  system icon, depending on OS version) rather than a purpose-made small monochrome notification
  icon.
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, item `0x511` (see T-31);
  `lib/utils/notifications.dart:11`.
- **Fix:** Android renders a status-bar notification icon purely from its alpha channel, ignoring
  colour - feeding it the full-colour launcher badge would have rendered as an undifferentiated
  white blob. `android/app/src/main/res/drawable-*dpi/ic_notification.png` isolates just the black
  alarm-clock glyph from `assets/icons/icon_no_shadow.png` (the app's most recognisable single
  mark) and recolours it white on a transparent background, keeping the source's own antialiasing
  as a soft alpha gradient rather than a hard-edged cutout. Wired into both notification paths:
  `AwesomeNotifications().initialize()`'s default icon (`lib/utils/notifications.dart`, used by the
  pre-alarm warnings and the sleep-time reminder) and `NotificationSettings.icon` inside
  `buildRingingAlarmSettings` (`lib/models/alarms/ringing_alarm_settings.dart`, the alarm-plugin's
  own ringing notification).
- **Tests:** `test/ringing_alarm_settings_test.dart` ("shows the app notification icon instead of
  the OS default").
- **Done when:** a proper notification icon asset exists and is wired up.

### T-153 · The alarm-ringing notification cannot be removed or its heads-up banner suppressed

- [x] Investigated on maintainer's request; no code change - documenting the platform limit found.
- **Why:** the maintainer asked for the notification shown while an alarm is ringing to be removed
  entirely, since the full-screen alarm screen already covers it ("die stört nur"), while keeping
  the sleep-time reminder untouched and not breaking anything.
- **Finding:** the ringing notification is not optional UI chrome - it is the notification a
  foreground service is required to keep visible while it plays audio in the background; Android
  kills the service (silencing the alarm) if it disappears. It also cannot be made quieter from
  this app's code: the `alarm` plugin (`~/.pub-cache/hosted/pub.dev/alarm-5.12.0/android/.../
  NotificationService.kt`) hardcodes `NotificationManager.IMPORTANCE_HIGH` for its
  `alarm_plugin_channel` in native Kotlin, with no `NotificationSettings` field exposed from Dart to
  change it - and Android does not let an app lower an existing channel's importance from code once
  created on a device, only the user can do that from system settings. The heads-up banner the
  maintainer is actually bothered by only appears when `androidFullScreenIntent: true` (already set)
  cannot auto-launch the full-screen alarm screen - which is itself intentional Android behaviour:
  the system shows a heads-up notification instead of forcibly taking over the screen while the
  user is actively using an unlocked device, precisely to avoid apps hijacking the foreground
  without warning. Confirmed via `pub.dev`'s changelog that no `alarm` release after 5.12.0 adds a
  way to control this either.
  Cosmetic half-measures were considered and rejected: an empty title/body would still show a
  blank banner (no less intrusive, more likely to look broken) - forking the `alarm` plugin to
  lower the channel importance was offered as an option but the maintainer chose to accept the
  platform limitation instead.
- **Decision (maintainer, 2026-09-19):** keep the ringing notification and its content exactly as
  is. Sacrificing the persistent notification (and therefore background audio reliability) or the
  full-screen wake-up guarantee for a cosmetic banner complaint was explicitly rejected as not worth
  the risk to R3 (alarm survival/reliability).
- **Evidence:** `lib/models/alarms/ringing_alarm_settings.dart`; `~/.pub-cache/hosted/pub.dev/
  alarm-5.12.0/android/src/main/kotlin/com/gdelataillade/alarm/services/NotificationService.kt`.
- **Done when:** closed as "no change wanted", as of this entry.

### T-154 · Launcher icon had no adaptive-icon layers — FIXED (2026-09-19)

- [x] Add proper Android adaptive-icon layers instead of only a legacy flat icon.
- **Why:** the maintainer reported the icon showing "a light blob in the middle" specifically in
  dark mode, and looking noticeably smaller on the home screen than icons like Spotify's.
  `pubspec.yaml`'s `flutter_launcher_icons` config only ever set `image_path`, `android` and `ios` -
  no `adaptive_icon_background`/`adaptive_icon_foreground` - and
  `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` (the file that tells API 26+
  launchers to use an adaptive icon at all) did not exist. Without it, a launcher treats the app's
  icon as "legacy": it scales the flat PNG down and composites it onto a backplate of its own
  choosing, since it cannot safely mask an image it doesn't know is transparent outside a defined
  shape - both source PNGs (`assets/icons/icon.png`, `assets/icons/icon_no_shadow.png`) already had
  correct alpha transparency and content spanning ~100% of their canvas, so the backplate (visible
  as a light circle in dark mode, unnoticed in light mode where it blends into a light background)
  was the launcher's own re-shaping, not a flaw in the artwork.
- **Fix:** added `adaptive_icon_background: "#00000000"` (fully transparent, per the maintainer's
  explicit ask for no background plate at all) and `adaptive_icon_foreground:
  "assets/icons/icon_foreground.png"` to `pubspec.yaml`, then ran `dart run flutter_launcher_icons`.
  The foreground asset was generated from `icon.png`'s own artwork (the circular badge, tightly
  cropped to its alpha bounding box), initially scaled to fill ~87-92% of its canvas -
  `flutter_launcher_icons` additionally wraps every adaptive-icon foreground in its own hardcoded
  16% `<inset>` regardless of how the source image is padded, which would have shrunk the icon back
  down to roughly the same size as before; that generated `<inset>` was removed by hand from
  `mipmap-anydpi-v26/ic_launcher.xml` afterwards (see that file's own comment - re-running the
  generator re-adds it and requires removing it again).
  The maintainer then found that first pass too large ("Das Icon ist jetzt viel zu groß") and asked
  for ~60% of it - `assets/icons/icon_foreground.png` was regenerated at ~55% canvas fill
  (0.92 × 0.6) accordingly, with the `<inset>` removed again the same way.
  Once the size was right, the maintainer reported the background rendering as **black** on their
  actual home screen rather than the wallpaper showing through - most launchers paint an opaque
  surface behind an adaptive icon instead of truly compositing it as see-through, so a fully
  transparent `adaptive_icon_background` does not mean "no background", it means "whatever opaque
  colour this launcher happens to fall back to". Changed `adaptive_icon_background` to
  `"#ffffffff"` (opaque white) - the foreground artwork itself still stays transparent outside the
  badge shape, so only the background plate changed, not the logo.
- **Tests:** `test/launcher_icon_config_test.dart` - source/file-presence checks (no Flutter API
  reads back what a launcher would actually render for an adaptive icon), guarding the
  `pubspec.yaml` keys, the background colour, the foreground asset, and the generated
  `mipmap-anydpi-v26/ic_launcher.xml`.
- **Evidence:** `pubspec.yaml`; `assets/icons/icon_foreground.png`;
  `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`.
- **Done when:** an adaptive icon is configured with a transparent background and a foreground that
  fills most of its canvas.

### T-56 · Alarm tones are a static bundled list — IMPLEMENTED (2026-09-24)

- [x] Source available tones dynamically (e.g. from device storage or a user-added set) instead of
      a fixed list.
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31) - a nice-to-have, not a
  bug; the current static list works, it's just inflexible.
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, item `0x55` (see T-31);
  `lib/screens/settings/page_alarmtones.dart`.
- **Done when:** either implemented, or explicitly deprioritised with a reason. Implemented: custom
  tones are now a growable, named list, not the single replaceable slot T-146 originally added.
- **Implementation:**
  - `lib/models/alarms/custom_tone.dart`'s `importCustomTone` no longer deletes `custom_tones/`
    before writing - it keeps the source file's own name, only appending a numeric suffix
    (`name (1).ext`, `name (2).ext`, …) if that exact name is already taken, so a second import
    can never silently overwrite a first one. New `CustomTone` (name + path, JSON round-trippable)
    and `defaultCustomToneName()` (the picked file's own name, minus its extension - the sensible
    default label most imports won't even need to change).
  - `AppState.customTones` (a `List<CustomTone>`, persisted as JSON) replaces the old single
    `customTonePath`; `addCustomTone(sourcePath, {required name, ...})` replaces
    `importCustomTone(...)`, appending rather than replacing.
  - `page_alarmtones.dart`: each imported tone now renders as its own tile (name, tap-to-preview,
    switch-to-select - the same shape a bundled tone's tile already had), with a permanently
    present "Add custom tone" tile below the list rather than one fixed slot that's either empty
    or full. Picking a file now opens a naming dialog first, pre-filled with
    `defaultCustomToneName(pickedPath)`, before the import actually happens.
  - `screen_alarms.dart`'s manual-alarm tone dropdown now offers every entry in
    `AppState.customTones`, not a single conditional item.
- **Follow-up (2026-09-24, T-167):** the six *bundled* tones' names/paths were still hardcoded
  independently in `page_alarmtones.dart`, never updated to share `screen_alarms.dart`'s own
  `_bundledTones` list this feature had already extracted - consolidated into one shared
  `lib/models/alarms/bundled_tones.dart`, and two of the six names (which described neither sound
  nor use) were renamed at the same time.
- **Test-writing note, not a product bug:** the new widget test
  (`test/page_alarmtones_custom_tones_test.dart`) hung indefinitely the first time it combined real
  `dart:io` calls (creating a temp directory, writing a file) with `testWidgets` - real async file
  I/O inside `flutter_test`'s fake-async zone can hang rather than resolve. Fixed by moving that
  setup inside `tester.runAsync(...)`, the same escape hatch this project's own tests already use
  for real platform-channel futures elsewhere. A second, unrelated fix: a tile below the default
  600px test viewport needs `tester.ensureVisible()` before it can be tapped, the same fix T-20's
  test needed for the same reason.
- **Not done, deliberately out of scope:** no rename/delete UI for an already-imported tone - not
  requested, and adding it would have doubled this change's surface for a feature nobody asked for
  yet. If it turns out to matter, it belongs in its own item.
- **Fixed (independent review, 2026-09-24): orphaned-tone dropdown crash risk.** Because there is no
  migration off the old, single-slot `customTonePath` key (accepted data loss - the setting itself
  is exactly what "ignore data loss during the test phase" covers), any alarm or `AppState
  .selectedTone` created before this change can still point at the pre-T-56 fixed path
  (`custom_tones/custom_tone.<ext>`), which this version never writes to again. The review agent
  showed that's a step beyond plain data loss: `screen_alarms.dart`'s tone `DropdownButton<String>`
  requires its `value` to exactly match one `items` entry, so opening the edit dialog on such an
  alarm threw an assertion in a debug build and would have rendered blank in release. Fixed by
  extracting the six bundled tones into one `_bundledTones` const (so the dropdown's `items` and the
  fallback check can't quietly drift apart) and falling back `selectedTone` to
  `_bundledTones.first.$2` whenever it matches neither a bundled nor a custom tone path, before the
  dialog builds. `test/screen_alarms_orphaned_tone_test.dart` reproduces a pre-upgrade alarm with
  the dead path, confirms no exception and the dialog opens, and confirms saving persists the
  fallback tone rather than the dead path.

### T-58 · Consider a toast instead of a notification for some feedback — CLOSED, no change wanted (2026-09-20)

- [x] ~~Decide where (if anywhere) a toast would be more appropriate than the current
      notification.~~ Decided: nowhere. See below.
- **Why originally raised:** carried forward from `lib/main.dart`'s old TODO backlog (T-31) - a UX
  design question, not a defect, and under-specified (which notification(s) it refers to was never
  recorded).
- **Resolution:** the app has exactly three system notifications left, and every one of them
  specifically needs to keep working while the app is backgrounded - the one property a toast/
  `SnackBar` cannot provide at all (it only exists while that screen's widget tree is alive):
  1. The FR-6/FR-9/FR-12 pre-alarm warnings (`replan_notifications.dart`) - must reach the user well
     before an alarm, regardless of whether the app happens to be open at that moment.
  2. The sleep-time reminder (`sleep_reminder.dart`) - the same reasoning, and its silent variant is
     also FR-16 Checkpoint 2's only entry point (T-62/T-155).
  3. The ringing-alarm notification (T-153) - a foreground-service notification Android requires to
     exist for the service to keep playing audio at all; already investigated and kept as-is.
  Everything else the app already gives as transient, in-app feedback (settings saved, a code
  imported, an action confirmed) already uses `SnackBar` throughout the UI
  (`page_alarmtones.dart`, `page_diagnostics.dart`, `snooze_button.dart`, `screen_active_alarm.dart`,
  `page_deactivation_code.dart`, `screen_alarms.dart`, `utils.dart`) - the toast-like treatment this
  item asked about was already the established pattern for that category, just never phrased as
  "closing T-58" before now. There is no remaining notification left that a toast could replace
  without breaking the one thing it exists for.
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, item `0x52` (see T-31);
  `grep -rln "Toast\|SnackBar" lib/`.
- **Done when:** closed as "no change wanted", as of this entry.

### T-59 · `AppState`'s calendar meetings are not modeled as a proper 1:n map

- [ ] Refactor the internal meetings data structure.
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31) - an internal data-model
  cleanup with no user-visible effect, lowest priority of the carried-forward items.
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, item `0x45` (see T-31); `AppState`'s
  meetings-related fields.
- **Done when:** the refactor is done and existing tests (once T-10 exists) still pass, or this is
  closed as not worth the churn.
- **Postponed to the next version (maintainer, 2026-09-24):** not a blocker for the current release
  state.

### T-60 · Calendar data was cached forever per week, never re-fetched for the app's lifetime — FIXED (2026-09-19)

- [x] Force a fresh re-read on every app open, per the maintainer's explicit instruction, rather
      than a time-boxed invalidation.
- **Why:** found while checking scheduling-v2's feasibility (`docs/scheduling-v2-spec.md` FR-11/
  FR-12). `preloadCalendarData` (`lib/utils/utils.dart`) marked 2 past + 1 future week as "fetched"
  in `_fetchedCalendarWeeks` at startup, but only ever actually called `retrieveEvents` for the
  single week containing "now" - the other weeks were marked fetched without ever having been
  fetched. Once a week-start-date was in `_fetchedCalendarWeeks`, `updateCalendarData`
  (`screen_schedule.dart`) skipped fetching it again for as long as the process lived, since
  nothing anywhere ever cleared or reassigned that list. A calendar edit for a day already in this
  set was silently invisible to the app until the next process restart.
- **Fix:** a new `resyncCalendarData` (`lib/utils/utils.dart`) clears `appState.meetings` and
  `appState.fetchedCalendarWeeks` before calling `preloadCalendarData` again, so the fresh fetch
  replaces the stale state instead of appending to it. `lib/main.dart` calls it - via a shared
  `_syncCalendarAndAlarmsOnOpen` - on **every app open**: the cold-start path (`initState`'s
  post-frame callback) and every resume (`didChangeAppLifecycleState`). Each call is followed by a
  `CheckpointTrigger.manualSync` checkpoint - the same "reconcile now" the alarm list's own sync
  button already uses (`screen_alarms.dart`) - deliberately bypassing FR-17's once-a-day lock, so a
  calendar edit reaches the user's actually-armed alarms on the same open that made it visible in
  the Schedule tab, not only once a day. This is a deliberate widening beyond FR-17's normal
  cadence, at the maintainer's explicit request, not an accidental relaxation of that lock.
- **Also fixed along the way:** `preloadCalendarData`'s own two loops added a week to
  `fetchedCalendarWeeks` unconditionally, so even a single call double-counted the current week
  (once from its internal `updateCalendarData` call, once from the loop itself) - now deduplicated
  via a small `_markWeekFetched` helper, so repeated resyncs don't grow the list without bound.
- **UI:** while a calendar read is in flight, the Schedule tab in the bottom navigation bar
  (`lib/main.dart`) shows a small `CircularProgressIndicator` in place of its static
  `Icons.calendar_month` icon, driven by the existing `AppState.isReadingCalendarMutex` flag
  (already toggled around every fetch in `updateCalendarData` - previously set but read by nothing).
- **Evidence:** `lib/utils/utils.dart`'s `resyncCalendarData`/`preloadCalendarData`;
  `lib/main.dart`'s `_syncCalendarAndAlarmsOnOpen`, `initState`, `didChangeAppLifecycleState`, and
  the `BottomNavigationBar`'s Schedule item.
- **Tests:** `test/resync_calendar_data_test.dart` (clears stale state before re-fetching; repeated
  resyncs don't accumulate duplicate weeks); `test/schedule_tab_spinner_test.dart` (the Schedule
  tab's icon swaps for a spinner while `isReadingCalendarMutex` is set, and back once it clears).

### T-61 · scheduling-v2's wall-clock arithmetic assumes `deviceUtcOffset == 0` — RESOLVED

- [x] **Resolved (2026-09, second pass).** The first pass had only captured half the root cause:
      making `applyGapDayDrift`/`coldStart` offset-aware was correct, but the assessment that
      "`distribute`/`groupTarget` are frame-invariant" was wrong - `_wallClockDelta` compares
      **digit fields**, and `hardFloor` was passing `Meeting.from` through as a `TZDateTime` in the
      **appointment's own zone**, while every other value was UTC-tagged. Verified empirically
      (probe with a real `TZDateTime`): a 09:00 Europe/Berlin appointment produced a wake time two
      hours too late.
      Now fixed at **four** frame boundaries, all pinned down with `TZDateTime` fixtures
      (`test/scheduling_v2_tz_test.dart`, including `tz.initializeTimeZones()` - the infrastructure
      the test-structure plan called for and that was previously missing):
  1. `hardFloor` normalizes its return value via `.toUtc()` - the same real moment (FR-1/FR-16: the
     appointment itself doesn't move), but in the layer's shared frame.
  2. `AppState._setAlarm` now uses the new `alarmPlatformTime()` (`lib/utils/utils.dart`): `.toLocal()`
     first, then truncated to the minute - previously UTC digits were interpreted as local wall-clock
     time and the alarm rang too early by the offset (FR-18's boundary to the plugin, the planned
     test level 4).
  3. `scheduleSleepReminder` now also passes the bedtime instant through `alarmPlatformTime()` -
     `NotificationCalendar.fromDate` reads local digits, otherwise FR-16's Checkpoint 2 would have
     fired at the wrong local time.
  4. `planAlarmSync`'s `_toMinute` normalizes both sides to UTC, and the function itself normalizes
     the platform alarm set it's given - the comparison previously ran between UTC plan values and
     local `AlarmSettings.dateTime`, so on any device outside UTC+0 it would have judged every
     correctly-set alarm to be "missing from the platform" and re-set it on every replan.
- **Note for future work:** the last two boundaries (3 and 4) only became visible once fixes 1 and 2
  were in place - anyone changing something here should check whether a value leaves the domain layer
  and gets read by a plugin as *local wall clock*. That is exactly where this class of bug lives.
- [x] **Level 5 (FR-16 reinterpretation) also done** - which completes Phase 5:
      `computeWeekPlan` now returns `instantAnchoredDays` (days whose value comes directly from a
      real `hardFloor`), `replan()` persists that as `AppState.pendingDayInstantAnchored` (the same
      directly-readable-from-`SharedPreferences` format as `pendingDayValues`, because Checkpoint 2
      runs in the background isolate), and `runTimezoneCheckpoint2` reacts to a detected offset
      change: digit-anchored values that haven't rung yet keep their local digits via
      `reinterpretForNewOffset`, instant-anchored ones keep their instant, and already-past ones are
      left untouched (FR-11). Checkpoint 1 deliberately doesn't need this - the replan that follows
      it immediately recomputes everything and applies it via FR-18. Tests: `test/replan_test.dart`
      (the Checkpoint-2 group), `test/scheduling_v2_test.dart` (`instantAnchoredDays`),
      `test/app_state_scheduling_v2_test.dart` (persistence).
- **Remaining, deliberately accepted limitation:** Checkpoint 2 corrects the stored plan, not the
  alarms already handed to the platform - FR-16 explicitly defers the full recomputation to the next
  regular planning run. An alarm that fires between the offset change and the next replan therefore
  still uses the old instant.
- **Why:** found while wiring Phase 4's `replan()` to a real (potentially non-zero) `deviceUtcOffset`.
  `hardFloor()` returns `earliest.from` (a genuine, un-adjusted absolute instant) minus fixed
  durations - `eventsForDay()` computes a device-offset-adjusted `local` variable only to decide
  which calendar day an event belongs to, then discards it; the returned `hardFloor` value never
  gets that adjustment. Meanwhile `distribute()`/`groupTarget()`/`applyGapDayDrift()` (all added this
  session, see `docs/scheduling-v2-spec.md` FR-4/FR-5/FR-6) compare values purely via their raw
  `.hour`/`.minute` fields ("wall-clock-only", the fix for the real cross-midnight ΔT bug found while
  building `computeWeekPlan`). Whenever `deviceUtcOffset != Duration.zero`, a real calendar event's
  `hardFloor` instant (in true UTC hour/minute) and a `wunschzeit`-derived value (constructed to
  directly encode the device-local hour/minute) end up being compared as if they were in the same
  frame, when they aren't - `distribute`/`groupTarget` would silently compute a wrong ΔT/violation
  check. Every existing test in `test/scheduling_v2_test.dart` passes `deviceUtcOffset: Duration.zero`
  exclusively, so this never surfaces there; it also interacts with FR-16's two different storage
  semantics (`hardFloor` values must stay a genuine, unconverted instant per FR-16 - "only the local
  display changes"; `wunschzeit`/drift-derived values are digit-snapshots that need active
  reinterpretation on an offset change, `reinterpretForNewOffset`) - so the fix isn't a one-line
  change, it needs `computeWeekPlan` to consistently convert `hardFloor` values into the same frame
  as wall-clock-derived ones for comparisons/curve-building, while still persisting the original,
  unconverted instant whenever a day's final value is clamped exactly to its own `hardFloor`.
- **Evidence:** `lib/models/scheduling/scheduling_v2.dart` - `hardFloor()`, `eventsForDay()`,
  `_wallClockDelta()`/`_timeOfDayMicros()`, `computeWeekPlan()`'s `ownHardFloor`/`HardFloorPoint`
  construction; `test/scheduling_v2_test.dart` (no test anywhere uses a non-zero `deviceUtcOffset`
  together with a real `hardFloor` value in `distribute`/`groupTarget`/`computeWeekPlan`).
- **Done when:** `hardFloor`/`computeWeekPlan`/`distribute`/`groupTarget` are confirmed correct (via
  a new test with `deviceUtcOffset` != 0 and a real calendar event) for a device not in UTC+0, and
  `reinterpretForNewOffset`'s Instant-vs-wall-clock distinction (FR-16) still holds afterwards.
- **Consequence for Phase 4:** `runAlarmRingCheckpoint()` (`lib/models/scheduling/replan.dart`)
  deliberately does **not** call `reinterpretForNewOffset` on `pendingDayValues` yet, even though it's
  FR-16 Checkpoint 1's other stated job - `coldStart`/`applyGapDayDrift` currently bake no offset into
  their `wunschzeit`-combination at all (see above), so a stored wall-clock-anchored value carries no
  offset-dependent encoding for `reinterpretForNewOffset` to meaningfully undo; calling it now would
  introduce a spurious shift, not fix one. The checkpoint only compares/persists
  `lastCheckedUtcOffset` for now. Once this item is resolved, Checkpoint 1 needs that reinterpretation
  step wired in for the still-pending (not yet rung) entries. The same reasoning applies to
  Checkpoint 2 (`runTimezoneCheckpoint2`, Phase 5 step 22).
- **Planned test structure** (designed 2026-09, not yet implemented):
  - **Decide the semantics first, then test** - a test encodes the answer, so the answer has to
    exist first: the recommendation is "the whole domain layer computes in device-local wall clock",
    i.e. `hardFloor()` converts the appointment instant into the device zone via `deviceUtcOffset`
    *before* the durations are subtracted. FR-2 needs a sentence for this, and FR-16's
    instant-vs-wall-clock split has to be re-checked against this decision (what gets persisted, what
    gets reinterpreted).
  - **New test infrastructure:** so far *no* test initializes timezone data. Needed:
    `tz.initializeTimeZones()` (via `package:timezone/data/latest.dart`) in `setUpAll`, plus a fixture
    helper `_meetingInZone('Asia/Tokyo', …)` that - like `device_calendar` does in production -
    supplies a `tz.TZDateTime` in the **appointment's own** zone (`TZDateTime implements DateTime`,
    so it's directly usable as `Meeting.from`). `deviceUtcOffset` always stays explicit; the test
    machine's system timezone must never leak in (FR-2 "testability").
  - **Level 1 - `eventsForDay`/`hardFloor` with `deviceUtcOffset != 0`** (the missing dimension):
    same zone as the device; a zone foreign to the appointment (Tom's Tokyo appointment with the
    device in Berlin - this time the *return value* is checked, not just the day assignment); a DST
    boundary day.
  - **Level 2 - frame mixing in the arithmetic** (the actual bug, red here first):
    `groupTarget`/`distribute` with an anchor from a `preferredWakeUpTime` value and a target from an
    appointment-foreign `hardFloor` → ΔT must be the device-local difference; likewise for
    `applyGapDayDrift`.
  - **Level 3 - `computeWeekPlan` integrated:** (a) invariance property: if all appointments are in
    the device's zone, the planned wall-clock digits must be **independent** of `deviceUtcOffset` -
    the same numbers as today's UTC+0 tests; (b) Tom's scenario with mixed zones.
  - **Level 4 - FR-18/real alarms:** after planning under `deviceUtcOffset != 0`, the alarm that gets
    set must land on the *correct real instant* (not just have the correct digits) - this catches a
    wrong frame at the boundary to `Alarm.set()`.
  - **Level 5 - FR-16 interaction:** after an offset change, a `preferredWakeUpTime`-derived value must
    keep its **digits** (this is where `reinterpretForNewOffset` finally gets a real job), while a
    `hardFloor`-derived one must keep its **real instant** (the appointment itself doesn't move). These
    two guarantees must not be confused with each other - they are the real touchstone for FR-16's
    two categories.
  - **Order:** Level 2 first (fails against today's code and proves the bug), then Level 1 (the fix
    in `hardFloor`), then Level 3a as an invariance guard, then Levels 4 and 5.
  - **Deliberately not unit-testable:** a real timezone change on the device (airplane mode/travel) -
    that stays with `integration_test` or a manual device check, as with T-62.
- **Second thing to fix together with this:** `runTimezoneCheckpoint2` writes
  `lastCheckedUtcOffsetMinutes` straight to `SharedPreferences` from the background isolate, but a
  *live* `AppState` in the main isolate keeps its own in-memory copy and never re-reads it - so that
  write is invisible to (and gets overwritten by) the running app. Harmless today, because nothing
  yet branches on the comparison's outcome and both checkpoints write "the offset as of now"; it
  becomes a real missed-detection path the moment a reinterpretation step depends on the previously
  stored value.

### T-67 · FR-6/FR-9/FR-12: the warning flags are discarded on two of three paths — RESOLVED

- [x] **Resolved** (`lib/models/scheduling/replan_notifications.dart`): `reportReplanNotifications()`
      is now called from all three paths (ring, FR-17 recovery, settings change), each notification
      has its own try/catch (T-74b), and FR-6 reports only once per overrun episode (T-74a, new
      field `AppState.overrunNotificationSent`). Tests: `test/replan_notifications_test.dart`.
- **Why:** only `Handler._runReplanCheckpointSafely` (`handler.dart:81-89`) translated the flags into
  notifications. `runForegroundCheckpointSafely` (`replan.dart:245`) and
  `onSchedulingSettingsChanged` (`settings_changed.dart:37`) discarded the return value. For FR-12 the
  loss is **permanent**, not just delayed: the flag only arises inside `if (needsDayAdvance)`, and
  `replan` then sets `lastReplanDate = ringDay` - so the evening's real ring finds
  `needsDayAdvance == false` and never reports again. FR-12 names FR-8 **or** FR-17 explicitly as a
  trigger.
- **Done when:** all three flags are reported on every path, with a test.

### T-68 · FR-17 never fires on a real foreground transition — RESOLVED

- [x] **Resolved** (`lib/main.dart`): `didChangeAppLifecycleState` triggers
      `runForegroundCheckpointSafely` on `AppLifecycleState.resumed` - the previously dead
      `addObserver` call now has an effect. Idempotent thanks to FR-17's own lock.
- **Why:** `_MyHomePageState` declares `with WidgetsBindingObserver` (`main.dart:155`) and calls
  `addObserver(this)` (`main.dart:164`), but never overrides `didChangeAppLifecycleState` - the
  observer was dead code. The only call sat in `initState`'s `addPostFrameCallback`
  (`main.dart:207`), so it only fired on the very first mount (cold start). That covers FR-17's
  reboot/force-quit case, but not the third case it names ("opening the app in between is an
  additional, cheap opportunistic re-read"). Especially relevant because after FR-9's safety valve
  has tripped, no alarm rings any more - so the ring checkpoint drops out as a recovery path. Side
  finding: "immediately, before any UI interaction" was likewise not satisfied by the post-frame
  callback.

### T-69 · Checkpoint 2's reinterpretation gets reverted by the stale AppState — RESOLVED

- [x] **Resolved**: new `AppState.reloadSchedulingStateFromPreferences()` (using `prefs.reload()`) is
      now called as the first instruction of every `replan()` - a write from the background isolate
      is no longer overwritten by a stale in-memory copy.
- **Why:** `runTimezoneCheckpoint2` writes `pendingDayValues` directly to prefs (`replan.dart:324`),
  but `AppState` holds its own in-memory copy (`app_state.dart:54`) and never re-reads it. The next
  `replan` merges onto `Map.from(appState.pendingDayValues)` (`replan.dart:145`) - i.e. onto the old
  state - and writes it back. Today's day is not in the new window (which starts tomorrow), so its
  reinterpreted value falls back, and `applyPlannedAlarms` sets the alarm wrong accordingly. As long
  as the process stays alive (the normal case in FR-16's own example: Tom lands at 14:00, the app is
  running), Checkpoint 2 therefore has **no effect** beyond persisting the offset.

### T-70 · The calendar window only delivers 6 of 7 days of appointment data — RESOLVED

- [x] **Resolved** (`lib/screens/schedule/calendar.dart`): `endDate` now only subtracts 1 ms instead
      of a whole day - the window now genuinely covers 7 days of appointment data.
- **Why:** `replan` fetches `[fetchStart, windowStart + 7 days)` (`replan.dart:77`),
  `fetchMeetingsUncached` computes `endDate: end.subtract(const Duration(days: 1))`
  (`calendar.dart:116`) from that = midnight of the last window day. An appointment at 09:00 on that
  day therefore falls outside it. `hardFloor(window[6])` is consequently always `null`, and FR-7's
  lead time is one day shorter than specified. The doc comment claims `[start, end)`; the code
  implements `getCalendarEntries`'s inclusive-day convention. Invisible to every test, because they
  inject `fetchEvents`.

### T-71 · replan()'s day model only holds for the ring trigger — RESOLVED

- [x] **Resolved**: `replan()` now has `todayAlreadyRang` (default `false`). Only
      `runAlarmRingCheckpoint` sets it to `true`; FR-17's recovery and a settings change treat today
      as not yet concluded - the day stays in the window (FR-11) and is not counted by FR-9. Tests:
      `test/replan_test.dart` (ring vs. recovery semantics).
- **Why:** `replan` hard-coded the assumption "the day of `now` just rang": `ringDay = _midnight(now)`,
  window starting at `ringDay + 1`, the FR-9 loop up to and including `ringDay`. That's correct for
  the ring, but `replan` is also reached from `onAppForegroundCheckpoint` and
  `onSchedulingSettingsChanged` at an arbitrary time of day. Cold start at 06:00 after an overnight
  reboot (FR-17's core scenario): today's 07:30 value doesn't get re-derived (violating FR-11, for
  exactly the day that matters), and `gapDayCounter` counts today, even though FR-9 says "today does
  not count".

### T-72 · No UI for `preferredWakeUpTime`/`maxDailyDelta` - half of FR-4/FR-7 unreachable — RESOLVED

- [x] **Resolved** (`lib/screens/sleep_habits/screen_sleephabits.dart`): new tiles "Preferred wake-up
      time" (switch + time picker, nullable) and "Max. daily shift"; both call
      `onSchedulingSettingsChanged`. FR-4's drift, FR-7's partial clamping, and FR-10's
      preferred-wake-up-time branch are now reachable.
- **Why:** `grep -rn "wunschzeit\|maxDailyDelta" lib/screens/` found nothing - no screen sets them.
  `preferredWakeUpTime` was in practice always `null`, `maxDailyDelta` always the 15-minute minimum.
  So FR-4's drift branch, FR-7's partial-drift clamping (binary search), and FR-10's "with a preferred
  wake-up time: these days use it" were dead code. Practical consequence on a fresh device with an
  empty calendar: **nothing** gets planned, so nothing rings, so there is no ring checkpoint - and
  after 7 counted days, FR-9's valve trips.

### T-73 · A ringing ManualAlarm drives the ScheduledAlarm chain (FR-8/FR-15 boundary) — RESOLVED

- [x] **Resolved** (`lib/models/alarms/handler.dart`): `_fireReplanCheckpoint` now checks
      `_appState.getAlarm(event.id) is ScheduledAlarm` and returns otherwise. Regression test in
      `test/handler_replan_wiring_test.dart` ("a ringing ManualAlarm does NOT trigger a replan
      checkpoint").
- **Why:** `_fireReplanCheckpoint()` is the first instruction of `handleAlarm` (`handler.dart:95-96`),
  with no type check - but `Alarm.ringing` fires for every alarm (`main.dart:181`). A manual alarm at
  00:30: `ringDay` = today, FR-9 counts today as concluded, FR-12 is evaluated for today,
  `lastReplanDate = today` (suppressing FR-17 for the rest of the day), and
  `pendingDayValues[today]` - the value that hasn't rung yet - becomes `lastEffectiveWakeTime`. FR-15's
  *value* isolation stays intact (no ManualAlarm ever becomes a `hardFloor` or anchor), but the
  *trigger* isolation does not.

### T-74 · Smaller, confirmed deviations (collected) - **all resolved** — RESOLVED

- [x] (a) **FR-6 "once"**: the overrun flag is set anew on every replan, nothing persists "already
      reported" - during a multi-day overrun run, the notification arrives daily
      (`handler.dart:63-71`, `scheduling_v2.dart:131-132`).
- [x] (b) **One shared try for all three notifications** (`handler.dart:61-90`): if the first one
      fails, the other two are skipped; `Notifications()` is created inline, so it can't be tested.
- [x] (c) **False FR-12 notification on the very first replan**: `lastReplanDate == null` ⇒
      `needsDayAdvance == true`, and the `storedValue == null` branch notifies for every appointment
      today (`replan.dart:111-115`).
- [x] (d) **DST window**: `windowStart.add(Duration(days: i))` adds absolute time to a local marker
      (`replan.dart:68-69`) - across the autumn transition two `_isoDate` keys collide, one day is
      doubled, another never planned.
- [x] (e) **resolved:** `QrScanner` now gets the `alarmId` and stops only the ringing alarm instead of
      all stored ones; `planAlarmSync` additionally takes `platformAlarmMinutes`
      (`Alarm.getAlarms()`) and re-sets a planned day whose alarm is missing from the platform.
      Original finding: **FR-18 modeled "existing alarms" from `AppState`**, not from
      `Alarm.getAlarms()` (`apply_alarms.dart:98-102`); the QR dismissal stops all stored alarms via
      `Alarm.stop` (`qr_scanner.dart:171-177`) without updating the AppState lists - after Phase 6
      nothing repairs that any more. In addition, `planAlarmSync` only compared minutes, so tone
      changes didn't propagate.

### T-66 · Phase 6 would delete `Scheduler.nextAlarmTime()`, which scheduling-v2 itself depends on — RESOLVED

- [x] **Done** (`lib/models/scheduling/next_wake_up.dart`): `nextWakeUpTime()` derives the next
      wake-up from scheduling-v2's `pendingDayValues` **and** the user's `ManualAlarm`s (resolving a
      manual alarm's `TimeOfDay` to today-or-tomorrow, matching `AppState._getAlarmTime`).
      `scheduleSleepReminder()` uses it instead of `Scheduler.nextAlarmTime()`, so nothing outside
      the old `scheduling.dart` references that class's alarm-time helper any more. Tests:
      `test/next_wake_up_test.dart` (incl. "both sources, ManualAlarm is earlier -> ManualAlarm wins").
- **Why:** `scheduleSleepReminder()` (Phase 5 step 21, the FR-16 Checkpoint 2 hook) computes the
  bedtime from `Scheduler.nextAlarmTime(appState)`, i.e. scheduling-v2's own platform wiring depends
  on a function Phase 6 is supposed to delete. Note `nextAlarmTime()` deliberately considers
  **both** `ManualAlarm`s and `ScheduledAlarm`s - a v2 replacement must not narrow that to
  `pendingDayValues` alone, or the bedtime reminder would ignore manual alarms (which would be a
  behavior regression, not an FR-15 violation: FR-15 only forbids *scheduling* logic from touching
  manual alarms, not a reminder from reading them).
- **Evidence:** `grep -rn nextAlarmTime lib/` → only `lib/utils/sleep_reminder.dart:37` outside the
  old `scheduling.dart` itself.
- **Done when:** the sleep reminder gets its "next wake-up time" from a source that survives Phase 6,
  with a test covering the manual-alarm-only case.

### T-65 · Changing sleep-habit settings never triggers a scheduling-v2 replan — RESOLVED (2026-09-10)

- [x] **Done** (`lib/models/scheduling/settings_changed.dart`): `onSchedulingSettingsChanged()`
      re-plans (and re-applies per FR-18) and then re-schedules the bedtime notification, in that
      order. Wired into `screen_sleephabits.dart`'s `_changeDuration` for **all four** settings -
      `durationToWakeUp`/`durationToGetReady` (feed `hardFloor`) *and* `sleepGoal`/`reminderDuration`
      (shift the bedtime), the latter two previously triggering nothing at all. It calls `replan()`
      directly on purpose, so FR-17's "already replanned today" guard cannot suppress an explicit
      settings change. Any future settings UI for `wunschzeit`/`maxDailyDelta` must call it too.
      Tests: `test/settings_changed_test.dart`.
- **Why:** all four are inputs to `computeWeekPlan` (`durationToWakeUp`/`durationToGetReady` feed
  `hardFloor` directly), but scheduling-v2 has exactly two entry points - the ring checkpoint (FR-8)
  and the app-foreground checkpoint (FR-17, once per day) - and neither reacts to a settings change.
  Today the *old* `Scheduler.scheduleAlarms()` is still called right there
  (`lib/screens/sleep_habits/screen_sleephabits.dart`, on wakeUp/getReady change), so "I changed my
  wake-up duration and my alarms moved" still appears to work via the old path. Phase 6 removes those
  calls - at which point changing a duration would silently have **no effect** until the next daily
  checkpoint. The spec has no FR for a settings-change trigger either, so this is a plan gap like
  T-63 was.
- **Evidence:** `grep -rn "replan(\|runAlarmRingCheckpoint(\|runForegroundCheckpointSafely(" lib/` →
  only `lib/main.dart:207` and `Handler.handleAlarm()`; `AppState`'s setters for those four fields
  only persist and `notifyListeners()`.
- **Done when:** changing any of the four re-plans (and re-applies, FR-18) immediately, covered by a
  test, and the spec records the trigger.

### T-64 · Both scheduling systems now set alarms - and the old one can leave ZERO alarms — RESOLVED (2026-09-10, Phase 6)

- **Severity corrected upward (2026-09):** the earlier description ("the times flip between the two
  algorithms") was too mild. `Scheduler.scheduleAlarms()` **first** deletes every `ScheduledAlarm`
  (`scheduling.dart:164-169`) and then returns at two points without setting anything new:
  `existingTimes.isEmpty` (`:212-215`) and `adjustAlarmTimes() == null` (`:254-267`). In doing so it
  reads `appState.meetings` (`:190`), which is typically empty in a process started by the alarm
  itself. Sequence: v2 sets the week's alarms -> the user dismisses -> `onAlarmHandled`
  (`rescheduleOnAlarm` default `true`, no UI) -> everything deleted, abort -> **not a single alarm
  left**, and the next replan wouldn't come until the next ring (which there isn't one for) or the
  following day. Tapping the "Scheduled" tab triggers the same thing (`screen_alarms.dart:188`). For
  an app with a "guaranteed wake-up" promise, this is the worst possible outcome - so Phase 6 wasn't
  cleanup any more, it was the most urgent open item.


- [x] Remove (or disable) the old `Scheduler.scheduleAlarms()` call sites so only scheduling-v2
      controls `ScheduledAlarm`s - this is Phase 6 of `docs/scheduling-v2-spec.md`, but it stopped
      being mere cleanup and became a correctness issue the moment T-63 landed.
- **Why:** with T-63's apply step in place, `applyPlannedAlarms()` syncs `ScheduledAlarm`s to
  scheduling-v2's plan on every replan, while the old `Scheduler.scheduleAlarms()` still wipes **all**
  `ScheduledAlarm`s and recreates them from its own, unrelated algorithm. Both are live, so whichever
  ran last wins and the user's calendar-derived alarms can flip between the two algorithms' times.
  Remaining old call sites (down from 5 - `screen_sleephabits.dart`'s two are gone, replaced by
  T-65's `onSchedulingSettingsChanged()`): `lib/models/alarms/handler.dart` (`onAlarmHandled`, behind
  `rescheduleOnAlarm`) and `lib/screens/alarms/screen_alarms.dart` (x2, UI buttons).
- **Evidence:** `grep -rn "scheduleAlarms(" lib/`; `lib/models/scheduling/scheduling.dart:164-169`
  (removes every existing `ScheduledAlarm` first); `lib/models/scheduling/apply_alarms.dart`
  (`applyPlannedAlarms`, called from `replan()`).
- **Done when:** exactly one system schedules `ScheduledAlarm`s. Note T-61 should be fixed before or
  with this - once v2 is the only scheduler, its UTC-offset inconsistency becomes the user-visible
  wake time for any appointment whose own timezone differs from the device's.
- **Status:** Resolved 2026-09-10 (Phase 6). `lib/models/scheduling/scheduling.dart` is deleted,
  along with `Scheduler`, `getEarliestEvent`, `getStartTimeForDate`, `adjustAlarmTimes`,
  `nextAlarmTime` and `setScheduledAlarmToNow`; `test/scheduling_test.dart` went with it. The three
  call sites are resolved: `Handler.onAlarmHandled` now only schedules the bedtime reminder (the ring
  has already fully replanned via `_fireReplanCheckpoint` anyway), switching tabs in the alarm list
  plans **nothing** any more (FR-11: calendar changes deliberately have no trigger of their own), and
  the sync button calls `runCheckpointSafely(trigger: manualSync)`.
  `test/handler_on_alarm_handled_test.dart` pins down the finding and was red against the old code -
  proven with the real case: after a dismissal, the alarm for tomorrow was gone (0 instead of 1).
  This also makes T-02 and T-32 moot.

### T-106 · A day value that had already rung was overwritten by the next non-ring checkpoint — RESOLVED (2026-09-11)

- [x] Concluded window days keep their recorded value.
- **Why:** FR-11 says "only the value actually triggered is fixed **forever**" - and "forever"
  includes the rest of that same day. Only the ring sets `todayAlreadyRang`; for `settingsChanged`
  and `manualSync` the window therefore starts again at TODAY, and the merge in `replan()` rewrote
  the already-triggered value.
- **Two consequences, the second one is the more serious:**
  1. A **second alarm the same morning**. FR-18 schedules every plan value that is still in the
     future; the revised value for today is one of them. Sequence: 06:00 rings, the user dismisses,
     changes a setting at 06:05 - and at 06:30 it rings again.
  2. The ring day then holds a value that **never rang**. That is exactly the entry the next
     checkpoint reads as `lastEffectiveWakeTime` (FR-3: "always the entry in `pendingDayValues` for
     the most recently concluded day"). The foreground checkpoint the next morning - before it
     rings, where the day-lock no longer applies - then smooths the whole week from a fabricated
     anchor.
- **Reachability (individually chased down by the independent reviewer):** `manualSync` is the sync
  button in the alarm list; `settingsChanged` hangs off six one-tap paths (tone, volume, the four
  duration pickers, the preferred-wake-up-time switch, the gentle-wake switch). Neither is subject to
  the day-lock, deliberately. **`appForeground` does not carry the case** - there FR-17's day-lock
  already catches it, because the ring has already set `lastReplanDate` to today; this part of the
  original finding is disproven. Also, the damage requires a *changed* situation: if the appointment
  stays in the calendar, the revision is a no-op. But "meeting got cancelled, I check the app and
  sync" is about the most obvious mid-morning sequence there is.
- **Fix:** window days that are not after the progress marker are skipped during the merge - both
  values **and** `pendingDayInstantAnchored`. The window is explicitly **not** shortened: the day
  still carries the curve, only its recorded value stays put.
- **Test:** `test/replan_audit_test.dart` - the case itself plus two counter-tests (the following day
  remains revisable; the ring checkpoint still writes).
- **Requirement:** R2

### T-107 · FR-9's valve forgot itself as soon as it had fired — RESOLVED (2026-09-11)

- [x] Report the valve state in the cold-start branch too.
- **Why:** once the valve has set every window value to `null`, the next checkpoint sees
  `lastEffectiveWakeTime == null`. `computeWeekPlan` then takes FR-10's cold-start branch, which
  hard-coded `safetyValveTriggered: false` in return - even though the counter keeps running (8, 9,
  …), no `preferredWakeUpTime` is set, and still nothing gets planned. The state claimed "no
  episode" while the episode was ongoing.
- **Why this is dangerous, not just untidy:** `reportReplanNotifications` reads `needed == false`
  with `alreadySent == true` as "episode over" and resets `safetyValveNotificationSent`. If the
  notification fails on the day it triggers (the flag deliberately stays `false` so it retries), the
  retry attempt **never** comes - from the following day on, `needed` is permanently `false`. Result:
  a permanently silent alarm with no notification at all. FR-9's own reasoning names exactly this
  "the wrong outcome".
- **Second manifestation, carried by the same branch:** if the counter reaches the threshold
  **without** an anchor ever having existed - fresh install, calendar granted with no appointments,
  no `preferredWakeUpTime`, app opened daily - `safetyValveTriggered` was **never** `true`. The user
  never learned that nothing was being planned. The first reviewer considered this undecidable from
  the spec; the independent reviewer decided it, and the reasoning holds up: FR-9 names **exactly
  one** exception to "counter >= 7 -> stopped and notified", namely a set `preferredWakeUpTime`.
  FR-10 in this branch governs only the *values* ("without one: no alarm planned"), never the
  notification. "No anchor" is not an exception stated there.
- **Evidence:** a run probe over eleven days - counter 11, no planned value, zero valve
  notifications.
- **Fix:** `safetyValveTriggered: gapDayCounter >= gapDayValveThreshold && preferredWakeUpTime ==
  null`. The threshold went from two literals to one named constant in the process - it is now
  checked in two places (with and without an anchor) and must not drift apart.
- **Test:** `test/scheduling_v2_audit_test.dart`, group "FR-9" - four cases, including FR-9's own
  threshold test case with **6**. That was missing: the suite only ever called `computeWeekPlan`
  with 0, 7 and 42, so a change to `>= 6` would have gone green and would have shut off the alarm one
  day too early.
- **Requirement:** R2, R3

### T-109 · FR-17's daily lock silenced everything for up to 48 hours after a date rollback — RESOLVED (2026-09-11)

- [x] Switch the lock to equality ("!= today"), instead of "not before today".
- **Why:** FR-17 literally says "If `lastReplanDate` **!=** today's calendar date (device time
  zone): immediately, before any UI interaction, the same sequence as FR-8's ring checkpoint […]
  Otherwise: no additional checkpoint." The code read `!midnight(last).isBefore(midnight(now))`
  — i.e. ">=". For a marker in the **future**, that meant it was skipped.
- **How the marker ends up in the future — with no action by the app at all:** it is a
  device-local digit date with no bracketing. A zone change across the date line, or a backward
  correction of the system clock, makes the local date jump backward. No code path bounds it
  against "not in the future".
- **Evidence:** a tz-based probe (real IANA zones, not `DateTime.utc` — on a UTC+0 VM a UTC
  fixture cannot represent a date rollback at all). Apia (+13) Mar 10 → Pago Pago (−11), the same
  instant carries **Mar 9** there: of five app opens, only **two** ran instead of the four FR-17
  literally requires, and `fetchCount == 2` proves that not a single uncached calendar re-read
  happened on those two local days. Duration: the entire local Mar 9 **and** the entire Mar 10,
  i.e. up to ~48 local hours.
- **Why it hurts exactly there:** an `alarmRing` checkpoint is not subject to the lock and repairs
  the marker as a side effect — that genuinely limits the damage. But it does **not** limit it
  exactly where FR-17 was built for in the first place: reboot, force-quit, and a missed daily
  ring are FR-17's three named gaps, and in all three there is no ring that could repair it. So
  after flying west, exactly the mechanism that would still heal a stale plan and stale platform
  alarms is the one that fails.
- **Fix:** the comparison is via `dayDistance(...) == 0`, **not** via `==` on two `DateTime`s. The
  marker comes locally tagged from preferences, `currentTime` can be a `tz.TZDateTime`, and
  Dart's `==` requires the same `isUtc` frame — that would be exactly this module's bug class
  (T-61/T-76/T-83) in a new spot.
- **Test:** `test/checkpoint_audit_test.dart` — marker tomorrow/today/yesterday plus the real
  date rollback, with fixture checks (the local date really jumps backward; the second instant
  is genuinely later).
- **Requirement:** R2, R3

### T-110 · A past bedtime took away FR-16's checkpoint 2 entry point — RESOLVED (2026-09-11)

- [x] Never schedule for a past instant; catch up the hook instead.
- **Why:** `scheduleSleepReminder` **unconditionally** cancelled the existing notification and
  then rescheduled — without checking whether the computed instant is still in the future. If
  `sleepGoal + reminderDuration` is greater than the distance to the next wake instant, the
  bedtime is in the past. Example: a setting changed at 22:00, next wake instant 05:00, sleep
  goal 9h → bedtime 20:00. `settingsChanged` is not subject to any daily lock, so it runs.
- **What Android actually does with it — looked up, not guessed:** the reviewer unpacked
  `AndroidAwnCore-0.12.1.aar` from the Gradle cache and read it with `javap -c`.
  `CronUtils.getNextCalendar` returns `null` for any result before "now";
  `NotificationScheduler.doInBackground` then calls `cancelSchedule`, logs "Date is not more
  valid." and aborts; `onPostExecute` only sends the Created event on the non-null branch. The
  old notification is already cancelled by that point.
- **Consequence:** for that night, FR-16's checkpoint 2 does not run at all. A time zone change
  that happened during the day is then only noticed at the next ring — exactly the scenario the
  second checkpoint was introduced against. On top of that, the visible reminder is missing too.
- **The fix, and the decision inside it:** if the bedtime is no longer in the future, the hook is
  placed at "in two minutes" (two, not one: `alarmPlatformTime` truncates to whole minutes) — and
  **silently**, even with the reminder enabled. **The spec does not decide this case:** FR-16
  says when the checkpoint should run, not what applies once that instant has passed. The reading
  chosen is the one closest to FR-16's purpose (catch up the hook as early as possible), without
  a misleading "time to sleep" message hours after the intended instant — FR-16 explicitly
  separates visibility from the hook. **If a different behaviour is wanted here, it belongs in
  FR-16, and then here.**
- **No loop risk:** the isolate entry point (`onNotificationCreatedMethod`) only calls
  `runTimezoneCheckpoint2()` and does not reschedule the reminder. Checked.
- **Test:** `test/sleep_reminder_always_scheduled_test.dart`, group T-110 — placed in the future,
  silent, plus a counter-check that a bedtime already in the future stays visible and on time,
  unchanged.
- **Requirement:** R2, R3

### T-140 · The log did not carry the planning INPUTS — RESOLVED (2026-09-16)

- [x] `Diag.planInputs`: `maxDailyDelta`, both lead durations, and the preferred wake-up time, per
      planning run.
- **Where from:** the maintainer's note on the first device log — *"I changed the maximum drift
  time partway through, in case that doesn't show up in the log"*. They were right: it didn't.
- **The gap:** the log carried `maxStepBucket` (how big the largest step **was**) and
  `hasPreferredWakeUpTime` as a bare yes/no — but not how big a step was **allowed** to be, or
  what it was drifting toward. A logged plan therefore couldn't be checked by recomputation: for
  T-139 the limit had to be **reverse-engineered** from the step sizes, which is self-confirming.
  That the value had been changed partway through didn't show up in the log at all.
- **The distinction that supports including it:** a **duration** is not a **time of day**.
  "90-minute limit" or "30-minute lead time" reveal nothing about sleep and are therefore
  **always** in the log. The preferred wake-up time, by contrast, is a wake time and is gated
  behind the clock-time switch (T-135), otherwise `-1`. The rule "no clock value without a
  switch" thus stays untouched — and the three duration names are named explicitly, with their
  reasoning, in the source-reading guard, not as a silent exception.
- **Effect on T-139:** the reconstruction there (90 min) fits all seven logged values and the
  overrun flag exactly, but remains a back-calculation. The next log will answer the question
  directly.
- **Requirement:** R2

### T-139 · FR-5's ΔT=0 rule cuts off the lookahead — `maxDailyDelta` gets blown by 50% as a result

- [ ] Decide FR-5/FR-7, THEN fix test-driven.
- **Where from:** the first diagnostics log from the device with clock-time logging enabled
  (T-135) — the feature found a bug on its very first use that the suite doesn't have.
- **Reported plan** (preferred wake-up time 09:00, `maxDailyDelta` 90min, lead times 30min):

  | | Thu | Fri | Sat | Sun | Mon | Tue | Wed |
  |---|---|---|---|---|---|---|---|
  | Wake time | 04:30 | 06:00 | 07:30 | **09:00** | **06:45** | 04:30 | 04:30 |
  | Earliest appointment | 05:00 | 08:00 | 12:00 | 10:00 | 08:00 | 05:00 | 05:00 |

  The Sun→Mon→Tue steps amount to **−2:15**, 1:30 is allowed. `overrunFlag=1`, the user got a
  notification. **Reproduced exactly** from these numbers.
- **A rule-compliant plan exists:** capping Sunday at 07:30 keeps every step <= 90min with no
  notification. So the drift toward the preferred wake-up time consumed budget that the early
  Tuesday would have needed — exactly what FR-7's backward check is supposed to prevent.
- **Why it doesn't fire:** on Sunday the value stands at 07:30, and Monday's `hardFloor` is also
  07:30 — ΔT = 0. FR-5 step 2 ("a point with ΔT=0 ends the run immediately at itself") therefore
  makes Monday the target, and the lookahead ends there. Tuesday's 04:30 no longer appears in
  FR-7's feasibility check at all, so any drift is "feasible".
- **Caveat on the reconstruction:** `maxDailyDelta` wasn't in the log (that's T-140, since
  fixed), the 90 minutes are back-calculated from the step sizes — they fit all seven values and
  the overrun flag exactly, but are self-confirming to that extent. The maintainer also changed
  the value partway through. The next log will settle it directly; it changes nothing about the
  mechanism (ΔT=0 cuts off the lookahead) — that is independent of the number.
- **No regression from T-132, and none from T-104** — both specifically checked: without T-132's
  shortcut the same plan comes out, and T-104 changes nothing here, because the ΔT=0 point is
  `points.first` anyway. The bug is as old as FR-5.
- **To decide:** *May a ΔT=0 point end the lookahead, or only the run?* The two are not the same.
  FR-5's sentence governs **grouping** (it should not be grouped with a following point); that it
  also cuts off FR-7's **feasibility horizon** appears nowhere and is presumably unintended. An
  obvious fix: FR-7 checks feasibility against the earliest binding point in the whole window,
  not just against the run's target.
- **Impact:** high and everyday. Every "early appointment — free days — early appointment again"
  pattern hits it, and the user gets two nights at one-and-a-half times the allowed step, plus a
  notification they cannot turn off.
- **Postponed to the next version (maintainer, 2026-09-24):** the spec decision needed before this
  can be fixed test-driven is not a blocker for the current release state.
- **Requirement:** R2

### T-138 · Snooze (FR-20) — IMPLEMENTED (2026-09-12)

- [x] `snoozeEnabled`, `snoozeTime`, an origin-call marker; a button on both ring screens;
      settings in Sleep Habits.
- **Requirement written first** (FR-20 in `docs/scheduling-v2-spec.md`), then worked through, then
  implemented — the test cases' numbers come from the requirement, not from the code.
- **The budget is `durationToWakeUp`, and that is what carries the actual guarantee.** FR-2 sets
  the wake call to `appointment − durationToWakeUp − durationToGetReady`. Snooze may only consume
  the **first** duration. From this follows, without a separate check: **someone who only
  snoozes still gets out the door on time** — the time to get ready stays untouched.
- **Defaults:** snooze off, `snoozeTime` 5 min, `durationToWakeUp` **00:00** (previously 00:30). If
  snooze is switched on while the duration is 00:00, it is raised to 00:10 — otherwise the budget
  would be zero and the feature just switched on would be dead from the start. A value already
  set stays; switching off resets nothing.
- **Two interactions that would have been missed without the spec round:**
  1. The postponed call is a **plain platform alarm with a new id**, not a `ScheduledAlarm`.
     Otherwise FR-18 would have removed it at the next reconciliation — it lies in the future and
     has no planned counterpart. That a platform entry with no counterpart is left untouched is
     specifically checked (T-127) — that safeguard pays off here for the first time.
  2. The postponed call triggers **no** ring checkpoint. It is unknown to `AppState`, so the
     existing rule "only a ringing `ScheduledAlarm` drives the chain" (T-73) applies on its own.
     No special rule needed.
- **Safety behaviour:** the new call is armed first, then the old one is ended. If arming fails,
  the old one keeps ringing — the user is never left without an alarm. Its own test.
- **The origin call is carried over to the new id,** otherwise the budget would restart from zero
  on every press. It is persisted, otherwise a process death would have the same effect.
- **QR:** snooze is reachable on the scanner screen without a scan. Requiring the code just to
  **keep being woken up** would be pointless — and would risk pushing the user to switch the
  device off entirely. Switching off still requires a scan.
- **One widget for both screens** (`SnoozeButton`), not two copies: the budget check in two
  places would be exactly the bug class of the five checkpoint entry points (T-87).
- **Tests:** `test/snooze_test.dart` (the pure budget calculation, including the worked case
  "exactly six postponements, ends at 06:30"), `test/snooze_state_test.dart` (defaults, the raise
  on switching on, persistence, the process itself with injected platform calls).
- **Requirement:** R2, R3, R4

### T-137 · "Scheduled" is the first tab, "Manual" the second — IMPLEMENTED (2026-09-12)

- [x] Tabs, contents and index constants swapped.
- **Why:** at the maintainer's request, and it fits the product: the calendar-derived alarms
  are the app's actual purpose, manual alarms the exception. The screen now opens on
  what a user sees every day.
- **Consequence worth knowing:** the button at the bottom right depends on the tab. On "Scheduled"
  it is the **Sync** button, on "Manual" the **Add** button. Creating a new manual alarm therefore
  costs one more tap - that is the intended weighting, but it is a change to the
  familiar flow.
- **The real danger in swapping** is not the order but a divergence: whoever swaps the
  `tabs:` list and forgets `TabBarView.children` (or the index constants) gets a screen that
  shows one list while the button belongs to the other - and both tabs still look plausible.
  Exactly this **coupling** is guarded by `test/screen_alarms_tab_order_test.dart`: it creates
  a manual alarm and checks that it does **not** appear on tab 1 and **does** appear on tab 2.
  Both mutations (only the contents swapped back; only the indices swapped back) go red.
- **In passing:** `manualTabIndex`/`scheduledTabIndex` were `static int`, mutable from anywhere
  despite describing a fixed order. Now `static const`.
- **An existing test had to change its path** (not its assertion):
  `manual_alarm_inherits_settings_test` tapped the Add button right after opening. That button
  now sits one tab further; the test switches there first. What it checks - that a new
  manual alarm inherits ramp duration, volume and tone - is unchanged.
- **Requirement:** R12

### T-136 · Messages stayed on screen although 5 seconds had been set since the very first commit — RESOLVED (2026-09-12)

- [x] `persist: false` on `displayToast`'s SnackBar.
- **Reported by the maintainer:** messages like "Can not edit scheduled alarms!" do not disappear
  on their own.
- **The confusing part:** `displayToast` sets `duration: const Duration(seconds: 5)`, and has done
  so since the very first commit (`git log -S` confirms it) - the line is present in **every**
  shipped APK. The setting was therefore never the problem.
- **Cause in the framework, not the call site:** `SnackBar` defaults its `persist` field to
  `persist ?? action != null`, and `ScaffoldMessengerState.build` aborts the fade-out timer with
  `if (snackBar.persist) return;`. A SnackBar **with an action** therefore ignores its own
  `duration`. The framework documentation says it in so many words: *"If not provided, but the
  snackbar action is not null, the snackbar will persist as well."* And `displayToast` supplies a
  "Dismiss" button - exactly that turned off the timeout.
- **Fix:** `persist: false` explicitly. The button stays (whoever has already read the message
  taps it away right away), and after 5 seconds the message disappears on its own.
- **Only this one call site affected:** the other three SnackBars in the project (barcode result,
  "Diagnostics copied", alarm screen) have no action, so `persist` is `false` for them anyway.
  `displayToast` is the only call site with a `SnackBarAction`.
- **Test:** `test/display_toast_test.dart` - disappears on its own once the duration elapses (and
  is still showing shortly before that), and the Dismiss button keeps working. Mutation probe
  (`persist: false` removed) goes red.
- **A test trap that nearly led astray:** `ScaffoldMessenger` only starts its timer once the
  **fade-in animation** has completed (`_snackBarController!.isCompleted` in its `build`). A test
  that pumps too little never measures the timer at all and wrongly reads the message as
  "stays on screen" - that is exactly what the first run after the fix looked like. The test
  therefore explicitly pumps the animation to completion before measuring the time.
- **Requirement:** R12 (usability)

### T-135 · The log records wake times and early appointment times — at the maintainer's request (2026-09-12)

- [x] `Diag.dayPlanned`: per window day, the planned wake time and the day's earliest appointment.
- [x] Own switch, default **off**, separate from the general diagnostics switch.
- **Requested by the maintainer**, and the need is documented: T-132 (the appointment that pulled
  the wake time later) could **not** be diagnosed from the log. It contained counts and buckets,
  but not the one piece of information that answers the question: *why* does this day have this
  wake time - is it the appointment, the curve, or the preferred wake-up time? The bug was found
  via screenshots and hand arithmetic.
- **What this costs, and why it has its own switch:** the load-bearing property of this log so far
  was that a clock value structurally cannot enter it - *"a history of wake times plus offsets is
  a sleep pattern and a travel trace, identifying without any name"*. That is exactly what is
  loosened here. Therefore:
  - it is **not** hung off the general diagnostics switch (which is **on** by default), but off a
    second one that is **off** by default;
  - `Diag.dayPlanned` is a no-op without it, and the main switch remains the overriding one (both
    tested);
  - the export's header **states itself** which of the two modes produced it - whoever attaches it
    to a bug report can see it;
  - `-1` means "no value"/"no appointment". Not `0` - that would be midnight and thus a
    valid time of day.
  - The date stays out: what gets logged is the minute of the local day plus a **relative**
    day offset. A calendar day cannot be recovered from that.
- **Two bugs found while building this:**
  - The source-reading guard in `test/diag_log_api_test.dart` would have **let the new parameters
    through** - its pattern checks suffixes like `...Minutes`/`...Time`, and `plannedMinuteOfDay`
    ends in `Day`. A naming gap, not a deliberate allowance. The pattern now also recognizes
    `...MinuteOfDay`/`...HourOfDay`, and the two exceptions are listed **by name** in the test,
    with justification. Probe: a newly added `wakeMinuteOfDay` gets caught.
  - `Diag.resetForTest()` did not reset the new switch, so it leaked between tests. The same
    global-state trap as with `Diag.init` (T-89). Found by its own test; fixed.
- **Learned along the way:** the Dart matcher's `Actual` display truncates a multi-line string at
  its first line. That looked as if `render()` only returned one line and briefly sent the search
  in the wrong direction - only a print statement inside the test itself showed the real state.
- **Test:** `diag_log_test.dart` (T-135 group: default writes nothing, switched on both numbers
  appear, `-1` meaning, header, main switch remains overriding), `diag_log_api_test.dart`
  (tightened guard), `app_state_scheduling_v2_test.dart` (persistence round trip, independence of
  the two switches).
- **Requirement:** R7 (data minimization), R2 (diagnosability)

### T-133 · A capping jump at an appointment stayed silent — RESOLVED (2026-09-12)

- [x] FR-6's notification duty now also applies on the capping path.
- **Why:** FR-6 says "on **every** overrun of `maxDailyDelta` (`N=1` or distributed), the user is
  notified once". T-105 added this for the branch with no following points; the second path by
  which a day's value gets capped at an appointment - capping a running curve value at its own
  `hardFloor` - still notified nothing.
- **How it came up:** while working through an everyday case (see T-134). The wake time had
  drifted over appointment-free days down to the `preferredWakeUpTime` of 07:00, after which work
  was entered into the calendar. The first workday was capped at its `hardFloor` of 06:15 - a step
  of **45 minutes** where 30 were allowed, and the user was told **nothing** about it.
- **Why the first review only grazed it:** it had been noted as a "secondary finding (weaker)" to
  B-2, because in its own probe the notification happened to fire anyway - a following day started
  a new run there and notified via `distribute`. The case without that coincidence went unchecked.
- **Fix:** the same division-free formula as in the neighboring branch and in `distribute`, so the
  three cannot drift apart.
- **Test:** `test/scheduling_v2_audit_test.dart`, T-133 group - the jump above the limit notifies,
  a capping within the limit (25 min) does not. Mutation probe (notification removed again) goes
  red as intended.
- **Requirement:** R2

### T-134 · DISCARDED: a weekend/weekday concept in the scheduling layer (2026-09-12)

- **What was requested:** weekends should only affect the rhythm when an appointment falls earlier
  than during the week; otherwise they should generate no drift, or only drift toward the
  `preferredWakeUpTime`. Plus a configurable set of free weekdays with its own UI, from which
  `startOfWeekDay` would also be derived.
- **Discarded on the maintainer's decision,** and it is the better abstraction: *"really the
  'weekday' logic doesn't matter, you either have an appointment or you don't."* The engine
  already separates days with a real `hardFloor` from gap days, and that is the distinction that
  actually means something - a free Tuesday and a free Sunday are the same thing. For an app
  explicitly built for irregular sleep schedules and shift work, "the weekend" does not sit where
  the calendar assumes it does anyway.
- **What writing it down first bought** (the spec stood finished as FR-19 before a single line of
  code existed): worked through against the running engine, the requirement was **largely already
  satisfied**. FR-7's backward check already caps `preferredWakeUpTime` drift far enough that the
  next binding `hardFloor` stays reachable - an appointment-free weekend therefore does not
  overshoot in the first place, as long as the workday's appointment is visible within the 7-day
  window. Worked out (`preferredWakeUpTime` 07:00, `maxDailyDelta` 30 min, Friday 06:15, a later
  Saturday appointment, Monday 06:15): **Sat 06:45, Sun 06:45, Mon 06:15**, no jump, no
  notification. My hand-written expected value ("Sun 07:00") was wrong; the engine was right.
- **What actually followed from this:** exactly one case carries weight - when the workday's
  requirement is not yet visible while planning (the appointment not yet entered, or beyond the
  window edge). Then the correction falls into a single step, and that step was additionally
  **silent**. That is T-133, and it needs no weekday concept.
- **For future designs:** no rules on `DateTime.weekday` in `lib/models/scheduling/`. When a rule
  seems to need "weekend", phrase it in terms of the presence or absence of a `hardFloor` -
  that is almost always what is meant, and it needs no setting and no UI.

### T-132 · An appointment pulled the wake time LATER — RESOLVED (2026-09-11)

- [x] A `hardFloor` can now only be a target if it is earlier than today's value.
- **Source:** device feedback from the maintainer, first run against a **real** calendar. The wake
  time ran from **06:45 through 08:00 to 11:00** - "notably more than drift and than needed, also
  not close to the preferred time. the 11 o'clock seems completely groundless."
- **Reproduced** (anchor 06:45, `preferredWakeUpTime` 07:00, `maxDailyDelta` 30min, appointments at
  08:00 and 11:00 on the following days): exactly `08:00`, then `11:00`. And the second part of the
  report ("reacts extremely to free days") likewise: a **single** appointment at 11:00 in four
  days, everything else free, produced `07:48 / 08:52 / 09:56 / 11:00` - the free days were used as
  a ramp to climb up toward a late appointment.
- **Cause:** `hardFloor` is an **appointment cap**, but the engine treated it as a **curve
  target** - in both directions. A point later than the current wake time thereby became the
  target of a run, and the run pulled the wake time up toward it; `maxDailyDelta` was bypassed in
  the process, because FR-6 allows the full jump for `N=1`.
- **The spec says the opposite twice,** just not as a procedural rule:
  - FR-2: "`hardFloor` is an **upper bound** ('not later than'). The planned value may be
    earlier (**always allowed**), but never later."
  - FR-5, step 1: "`hardFloor` is exclusively an upper bound (FR-2), **never a directional
    target**."
  So this is **not** one of the open decision questions but a bug with a clear basis: whoever gets
  up at 06:45 has long since met an appointment at 11:00. Toward later, the wake time is moved
  exclusively by FR-4's drift toward the `preferredWakeUpTime`.
- **Fix in two places:** `planGapOrRunStartDay` no longer starts a run if the grouped target is not
  earlier than the anchor; and `computeWeekPlan`'s branch with no following points now drifts and
  **caps** afterward, instead of assigning its own `hardFloor` unchecked. FR-5's warning against a
  "directional filter" remains honored: the points are not removed from the list and continue to
  take part in the violation check - they are only no longer eligible as a *target*.
- **Result after the fix,** same inputs: every day **07:00**, no overrun notification. An
  **earlier** appointment (05:00 in four days) is still smoothed toward
  (`06:18 / 05:52 / 05:26 / 05:00`) and then led back toward the `preferredWakeUpTime` - the actual
  purpose of FR-5/FR-6 therefore remains unaffected.
- **Spec updated:** FR-5 now has the precondition as its own paragraph together with two worked
  test cases. Without them, someone would rebuild this bug.
- **An existing test had to be re-derived:** `T-118c`'s secondary assertion was pinned at `08:00`,
  thereby locking in exactly this bug. The correct value is `07:00` (without a
  `preferredWakeUpTime` FR-4 holds at the anchor, and FR-2 explicitly allows any earlier value).
  The test's load-bearing assertion - that FR-9's valve does not set an appointment day to `null` -
  is unchanged.
- **What this says about the test suite:** 267 tests, two independent review rounds and a
  timezone matrix did not find this - the first run against a real calendar did. Every suite
  fixture moved the wake time either earlier or held it steady; the case "appointment is later
  than the current wake time" appeared in not a single one, even though it is the everyday case.
- **Requirement:** R2

### T-131 · The reboot procedure structurally cannot measure anything: `flutter test` uninstalls the app

- [x] Name the root cause instead of booking it a third time as a pattern-matching question.
- [ ] **Decision needed:** by what path should the alarm be armed for the measurement?
- **The finding, from run 34627328009:** the three resolution paths report in agreement
  - `pm list packages -U` → no line contains the package name
  - `dumpsys package` → `Unable to find package: com.wakeywakey.wakeywakey`
  - `stat /data/data/<package>` → `No such file or directory`
  The app is **not installed** at measurement time. A debug suffix is ruled out as an explanation
  (`applicationId` carries none, `android/app/build.gradle.kts:44`), and `arm_alarm.log` from the
  same run shows a successful installation plus `🎉 1 test passed`.
- **Why this explains everything:** `flutter test integration_test/...` installs the app for the
  run and removes it again afterward. Android discards that package's AlarmManager entries along
  with it. The procedure "arm an alarm in a test, then query `dumpsys`" can therefore **structurally**
  measure nothing - regardless of any search pattern.
- **And with that, T-99's original interpretation was wrong.** There, the zero was read as "the
  pattern was guessed wrong" and answered with **more** patterns; that produced T-103's false
  finding. The actual root cause was one level deeper and had been the same the whole time. Lesson:
  when a piece of evidence finds nothing, the first question is not "am I searching wrong?" but
  "is what I'm looking for even there?".
- **What happens now:** the script checks `pm path` and reports
  `RESULT: not measurable - the app is NOT INSTALLED at measurement time`, instead of booking a
  measurement gap. No run can turn that into a statement about the product any more.
- **To decide before building further here:** *should CI arm the alarm via an installed app plus
  UI automation (`adb install` + `am start` + `input tap`), or does reboot survival remain a matter
  of the manual device test?* The former is real work and makes the E2E job dependent on UI
  labeling; the latter already exists as section C in `docs/device-trial-checklist.md` and needs
  only a device and five minutes. Until that is decided, **T-93 stays open** - and specifically as
  *unanswered*, not as *failed*.
- **Requirement:** R3

### T-130 · uid resolution failed silently — RESOLVED (2026-09-11)

- [x] Every resolution attempt logs its raw output into the evidence file.
- **State after the first run with the repaired measurement (34622086175):** the script now
  behaves correctly - the self-test passes, there is **no** false finding any more, and instead of
  a fabricated `FAIL` it honestly reads `RESULT: inconclusive - this app has no alarm
  registered even BEFORE the reboot`. That is exactly how a piece of evidence should fail.
- **What it named itself in the process:** `app uid: <not resolvable>`. Without a uid token, only
  the package name carries the match, and that apparently does not appear in `dumpsys alarm` on
  this image - hence the zero. The raw excerpt shows a uid with exactly one pending alarm
  (`u0a160:1`) that very likely is the app; but that cannot be proven without resolution.
- **Why this needs its own fix:** both resolution paths redirected their errors to `/dev/null`.
  The evidence therefore could not show **why** they failed - even though `arm_alarm_test.dart`
  had demonstrably set an alarm in the same run ("1 test passed") and the app was installed (no
  uninstall in `arm_alarm.log`). Guessing the format has already led this script astray twice
  (T-99, T-103); a third time it gets recorded instead of guessed.
- **Fix:** three paths, each with raw output into the evidence file - `pm list packages -U`
  (plus a less strict second pass), `dumpsys package` on `userId=`/`appId=`, and
  `stat -c %u /data/data/<package>`. The next run will show which one succeeds and where the
  others fail.
- **T-93 remains open** - the question "does an alarm survive a reboot?" is still unanswered.
  It is now, however, honestly marked as unanswered and one step closer to a measurement.
- **Requirement:** R3

### T-129 · A sick emulator posed as a product bug — RESOLVED (2026-09-11)

- [x] Check whether the emulator is usable at all before measuring.
- **What happened:** run 34622327599 reported `❌ a created alarm survives being reloaded from
  on-device storage` with the reasoning "Alarm … was created in AppState but never reached the
  native alarm plugin". That reads like a serious product bug. It was not one: the same run had
  previously logged `Unable to connect to adb daemon on port: 5037` and
  `adb: device 'emulator-5554' not found` - the emulator had never properly come up.
- **How this could be shown:** this run's commit (`6aa2325`) changed only test files and
  documentation; `git diff b0d6662 6aa2325 -- lib/` is **empty**. The immediately preceding run on
  byte-identical `lib/` had the E2E suite green. That ruled out a code regression without reading
  a single test.
- **Why this is its own item:** `adb wait-for-device` already returns once the device entry
  exists - not once the system is actually usable. The run therefore continued and ultimately
  produced a statement about the product where one about the environment was due. That is the
  same bug class as T-99 and T-103, just one level up: **a piece of evidence that reports an
  environment fault as a product bug is worse than one that finds nothing** - it gets believed.
- **Fix:** `run_e2e_tests.sh` now waits for `sys.boot_completed=1` (up to five minutes) and
  otherwise aborts with `::error::EMULATOR NOT USABLE … This is an environment fault, NOT
  a test result`, together with `adb devices -l` for diagnosis. On success it logs the device's
  API level - previously the evidence nowhere recorded which Android version the measurement was
  taken on.
- **Requirement:** R3

### T-123 to T-128 · Six further uncovered properties — RESOLVED (2026-09-11)

Second hardening batch from the test-case review. Each has a documented mutation that turns it
red and that stays invisible in the rest of the suite today.

- **T-123 · FR-18's equality boundary against now.** The most dangerous minute in the module, and
  it was uncovered. FR-18 explicitly forbids removing an alarm in the current minute - "the app
  also runs from FR-8's ring checkpoint, i.e. *while* an alarm is ringing […] removing it would
  silence it mid-ring via `Alarm.stop()`". The existing test works with a **five-minute** gap; but
  the bug only occurs in the 60 seconds in which it matters. Documented: a reformulation of the
  past-check (`isAfter` -> `isBefore`) leaves apply_alarms, replan, replan_audit, checkpoint,
  app_state and next_wake_up fully green and only shows up on the two new lines.
  Written as a boundary-value table over four cases. The fifth case (planned value **exactly** in
  the current minute) is deliberately left without an assertion: it has no observable effect,
  because `AppState.addAlarm` rejects a value before `DateTime.now()` anyway - both readings end
  in the same visible result, the question is cosmetic and must not block a safety-critical
  hardening.
- **T-124 · Leap day.** The classic hand-rolled day-of-year calculation (month table plus
  `(a.year - b.year) * 365`) is off by one day across 2028-02-29 - and stayed invisible in **all**
  sixteen test files, `day_marker_test` included, i.e. precisely in the file responsible for this
  arithmetic. The year change does **not** catch it (the table is correct for 2026/2027); only the
  leap day does.
- **T-125 · Offsets of a half and three-quarter hour.** Every offset in the suite was a whole
  hour. The bug class "someone computes with `offset.inHours` instead of `offset`" was therefore
  visible in **not a single** test. Important: the CI timezone matrix does not catch it either, even though it includes St. John's,
  Chatham and Lord Howe - the matrix sets the **test machine's** zone, while the domain layer
  receives the offset as an explicit parameter (FR-2 "testability"). The matrix and the unit test
  cover different things and do not substitute for each other; that had not been recorded anywhere
  before.
- **T-126 · FR-2 as an invariant over a full appointment week.** FR-2 is a universal statement
  ("the planned value may be earlier, but **never later**"), so it is checked as an invariant
  rather than as a list of hand-computed individual values - such a list gets adjusted on every
  legitimate curve change anyway, the invariant does not. Documented: FR-2's capping could be
  deleted outright without a single existing test going red.
- **T-127 · A platform alarm the app does not know about.** Uncovered was the combination "own ID
  **and** a foreign one": the existing T-88 case passes a foreign ID *without* the own one.
- **T-128 · Idempotence of two ring checkpoints.** For this bug class - a run touches state a
  second time even though it has already processed it - there was no safety net at the checkpoint
  level, and it has already struck this project six times (T-67, T-71, T-77, T-80, T-106, T-114).
- **Requirement:** R2, R3

### T-119 · OPEN SPEC DECISION: a daylight-saving transition WITHIN the 7-day window

- [ ] Decide whether day assignment must use the offset of each window day individually.
- **Situation:** the device offset is read as **one number** at checkpoint time and used for all
  seven window days. If a transition falls within the window, this number is wrong for the days
  after it by the transition difference, and appointments whose local time is closer to midnight
  than that difference lands on the **neighboring day**.
- **Reproduced:** an autumn transition in Europe/Berlin, an appointment on Oct 27 at 23:30 local
  time and one on Oct 28 at 08:00. The first one slips to Oct 28, where it displaces the real
  morning appointment as the *earliest* appointment (FR-13) - and on the morning of Oct 28
  **nothing at all** rings. The week plan additionally tips over to evening values. In the spring
  direction the bug shows a mirror-image one day too early, so it is not simply "always off by
  one hour".
- **Why this is not a pure bug fix:** FR-2 says literally "the device time zone **at evaluation
  time**" - the status quo is therefore spec-compliant. The spec text knows only *one* offset and
  did not consider that the window reaches into the future and can span a transition.
- **The actual finding is a different one:** FR-16's explicitly accepted limitation on the
  transition day claims that real appointments are not affected. That is not true - exactly one
  such case gets swallowed here. This passage needs correcting in any case, independent of how the
  question below is decided.
- **To decide:** *must the day assignment of a window day use the offset that applies on THAT
  day?* Then FR-2 needs a zone-rule lookahead, which FR-16 deliberately does not have. The
  alternative would be to do the assignment via the local calendar fields of the `tz.TZDateTime`
  that `device_calendar` supplies anyway - that needs no lookahead, but changes the origin of the
  zone, and that is exactly what FR-2 pins down.
- **Already hardened (T-118a):** day assignment near midnight under a **constant** offset.
- **Postponed to the next version (maintainer, 2026-09-24):** not a blocker for the current release
  state.
- **Requirement:** R2

### T-120 · OPEN SPEC DECISION: which day does a wake value belong to when it falls back over midnight?

- [ ] Decide, THEN implement test-driven.
- **Situation:** an appointment shortly after midnight pushes `hardFloor`, via the lead times,
  back onto the **previous day**. The value for a day then falls on a different calendar day than
  its key - and subsequently becomes the anchor for continuation.
- **Reproduced:** a single appointment on 03/12 at 00:30 (lead times of 30 min each) produces two
  wake times on 03/11 (03:15 and 23:30) and **none** on 03/12; after that FR-4 holds the wake time
  permanently at 23:30 - the user gets woken up every evening from then on, and the chain can no
  longer find its way out without a `preferredWakeUpTime`. Along with that, an FR-6 warning
  explains the effect as "adjustment due to an appointment".
- **Additional finding that raises the stakes:** in this situation FR-11's "fixed forever"
  guarantee does **not** apply. The safeguard (T-106/T-114: the window starts after
  `lastConcludedDay`) only holds as long as a day's value falls on that day's own calendar date.
  Probe: the 23:30 value rings, the appointment had been cancelled in the evening - the value just
  triggered gets overwritten and a new alarm is set for 03:15 of **the same night**, 3 hours 45
  minutes after the alarm that had just rung.
- **Why no implementation without a decision:** no single FR sentence is violated. What is
  violated is a basic assumption the spec nowhere states - that a value's date and its day key
  coincide.
- **To decide:** *what is the day key of a wake value when `hardFloor` falls back over midnight?*
  - **"value stays with the appointment day" (status quo):** literal FR-2, the appointment is
    reliably not missed. Price: two wake times on one day, none on the appointment day, FR-4 turns
    the 23:30 value into a permanent anchor, and FR-11 cannot be enforced for this value. FR-3,
    FR-4 and FR-11 would then have to explicitly cover this case.
  - **"`hardFloor` is a one-time cap, not an anchor":** the chain then continues from the previous
    anchor. Price: FR-4 needs a second anchor concept ("last *regular* value"), which the spec
    deliberately does not have today.
  - **"value gets clamped to its own day":** simple, but it violates FR-2's core statement and the
    00:30 appointment would be guaranteed to be missed. Ruled out from a reviewer's perspective.
- **Already hardened (T-118b):** that `hardFloor` may fall before midnight of its own day - the
  precondition of every one of these readings.
- **Postponed to the next version (maintainer, 2026-09-24):** not a blocker for the current release
  state.
- **Requirement:** R2

### T-121 · OPEN SPEC DECISION: the asymmetry of FR-9's valve

- [ ] Decide whether an appointment in the window also disables the valve for the days AFTER it.
- **Situation:** the valve exempts days **before** a real appointment in the window
  (`remaining.isEmpty`), but not days **after** it. After the first appointment reappears, the user
  therefore loses every alarm for the days after it - and gets the "automatic continuation
  stopped" message, while an appointment-derived alarm for tomorrow morning is showing on screen.
- **The state heals** when that alarm rings (the day is then concluded and the counter resets to
  0) - but only if it rings.
- **To decide:** *does a real `hardFloor` visible in the window also disable the valve for the days
  after it?*
  - **"no" (status quo):** literally FR-9-compliant, but the asymmetry then belongs explicitly in
    FR-9 - otherwise it reads like an oversight.
  - **"yes":** the condition would be "no real `hardFloor` anywhere in the window", and that is at
    the same time exactly the wording FR-9's **own three test cases** describe ("no `hardFloor`
    in the window") - to that extent the smaller change to the spec text.
- **Already hardened (T-118c):** both restrictions present today.
- **Postponed to the next version (maintainer, 2026-09-24):** not a blocker for the current release
  state.
- **Requirement:** R2, R3

### T-122 · OPEN SPEC DECISION: anchoring by origin or by meaning?

- [ ] Decide; the complete solution is an extension of FR-3, not a bug fix.
- **Situation:** a curve value that lands *exactly* on its own `hardFloor` counts as
  **digit**-anchored (because the curve computed it) and travels along on a timezone change - of
  all days, on the appointment day. But the value is at the same time the appointment's cap.
- **Bigger than the equality case:** FR-16's checkpoint 2 **fundamentally** cannot honor FR-2's
  upper bound, because it is not allowed to read the calendar. Probe: after an offset change, a
  value lands 8 hours **after** the appointment it was planned for.
- **To decide:** *does `pendingDayInstantAnchored` get decided by origin (the curve computed the
  value) or by meaning (the value is at the same time the appointment's cap)? And is checkpoint 2
  allowed to push a digit-anchored value past a `hardFloor`?*
  - **"origin" (status quo):** no code change needed, but FR-2's upper bound then explicitly holds
    only **until the next timezone change**, and that needs to be written into FR-2 and FR-16. The
    consequence is real: a genuine appointment can be missed after a trip westward, even though
    the alarm was planned for it.
  - **"meaning":** a one-line change (`ownHardFloor != null &&
    !candidate.value.isBefore(ownHardFloor)`), but it only resolves the equality case.
  - **Complete:** checkpoint 2 would only be allowed to shift a value up to its respective
    `hardFloor` - which would require persisting that value too (a third map alongside values and
    anchors), because checkpoint 2 is not allowed to read the calendar. An extension of FR-3.
- **Already hardened (T-118d):** the capping case.
- **Postponed to the next version (maintainer, 2026-09-24):** not a blocker for the current release
  state.
- **Requirement:** R2, R3

### T-118 · Four decided properties were uncovered — RESOLVED (2026-09-11)

- [x] Hardening for the parts that need no spec decision.
- **Why:** four of the new test cases have, at their *core*, an open spec decision (T-119 to
  T-122). Each one, however, contains a part that the spec very much does decide, that is
  correctly implemented today - and that was covered by no test. These parts are now pinned down;
  they are at the same time the foundation against which a later decision can be formulated at
  all.
- **(a) FR-2, day assignment at the midnight boundary** (unambiguous under a constant offset):
  local 23:30 belongs to the current day, local 00:30 to the next day. Mutation
  `add(deviceUtcOffset)` -> `subtract(...)` in `eventsForDay` goes red; it was invisible in
  `scheduling_v2_test`, `_dst_test` and `_tz_test`, because the existing FR-2 timezone test checks
  the *origin* of the offset, never its sign, and never a day boundary (its appointment sits at
  18:00 UTC).
- **(b) FR-2, `hardFloor` may lie before midnight of its own day.** The formula has no clamping;
  such clamping would be exactly the harm case FR-2 names. Mutation "clamp the result to
  midnight" goes red - it was invisible in four test files and is exactly the kind of "cleanup"
  someone could mistake for an obvious improvement.
- **(c) FR-9, the valve never clears a day that has something to do** - neither one with its own
  real `hardFloor` (a `null` there would mean guaranteed missing the appointment, and FR-18 would
  remove the alarm) nor one before which a real point still lies within the window (FR-5/FR-7: a
  run must be planned toward it). Both sub-conditions were uncovered, because **every** existing
  valve test runs with an empty calendar - there they are never false. This guards against the
  simplification to "counter >= 7 -> everything null", the most literal reading of FR-9 and thus
  the most likely cleanup change; its loss would be a silent alarm on a day with a real
  appointment.
- **(d) FR-3, a day capped at its own `hardFloor` is instant-anchored** - it must not travel along
  digit-wise on a timezone change. The capping branch was never exercised in `test/`: the only
  positive assertion about `instantAnchoredDays` concerns a day from the `remaining.isEmpty`
  branch, and the only neighboring test explicitly checks the opposite case.
- **A methodological note that saves time:** two of my first five mutations did not take hold at
  all (the string did not match), which looked like "the test doesn't catch it". A mutation whose
  insertion is not verified proves nothing - the insertion itself has to be checked before drawing
  any conclusion from a green run.
- **Requirement:** R2, R3

### T-117 · The seam between "plan computed" and "alarm registered" was uncovered — RESOLVED (2026-09-11)

- [x] Assert that `replan()` actually applies the computed plan.
- **Why:** not a behaviour bug, but a coverage gap — and the most dangerous one this review found.
  `test/apply_alarms_test.dart` tests `planAlarmSync` in isolation and `applyPlannedAlarms`
  directly; **nothing** checks that `replan()` even calls them. The binding existed only as a
  comment at the call site.
- **Evidence:** remove `await applyPlannedAlarms(appState, now: nowFn);` from `replan()`, and
  **nine** test files stay fully green: `replan_test` (21/21), `apply_alarms_test` (32/32),
  `checkpoint_test` (20/20), `replan_audit_test` (the remaining 6/6), `checkpoint_audit_test`
  (4/4), `handler_replan_wiring_test` (4/4), `handler_on_alarm_handled_test` (3/3),
  `next_wake_up_test` (8/8), `app_state_scheduling_v2_test` (12/12). Reported by the reviewer and
  reproduced by me.
- **Why this is not a hypothetical regression:** this is exactly how scheduling-v2 was already
  **completely inert** once before — the week was computed correctly and never became an alarm
  (T-63). The comment at the call site names the danger explicitly ("that way no code path can
  compute a plan and forget to apply it, which is exactly how the whole engine ended up
  functionally inert before"); from now on a test names it too.
- **Two assertions:** the alarm set after `replan()` matches exactly the planned values **after
  now** (FR-18's own wording), and a *changed* plan pulls the already-registered alarms along on
  the next run. The latter is also FR-16's decidable half ("no full recomputation … that only
  follows at the next regular planning run") — the other half is T-113.
- **Deliberately using real future times:** `AppState.addAlarm` compares against `DateTime.now()`
  and doesn't even accept a past instant in the first place; an injected past "now" would prove
  nothing here. Today's own window day drops out depending on runtime — correctly so, and the
  test derives that from FR-18's "after now" rather than just accepting it.
- **Requirement:** R2, R3

### T-116 · Two alarms on the same minute were a stable fixed point — RESOLVED (2026-09-11)

- [x] At most one alarm may survive per planned value.
- **Why:** `planAlarmSync` decided via `desiredMinutes.contains(...)` — mere **set membership**,
  not a pairing. If two `ScheduledAlarm`s land on the same minute, both were considered worth
  keeping and neither as surplus; because `keptMinutes` then contained the minute, `toAdd` stayed
  empty too. The state was thus a **stable fixed point**: every further replan confirmed the
  duplicate. The user is woken twice, permanently, and nothing in the engine ever cleans it up.
- **Why this isn't an interpretation dispute:** FR-18's lead sentence is a postcondition over the
  SET ("reconciled so that it **matches exactly the planned values**"), and FR-18's own test case
  names the same goal ("a matching alarm already exists -> **no duplicate**, no removal
  (idempotent)"). The second bullet rule, by contrast, is a condition *per alarm* and doesn't
  apply to a duplicate under either reading — the lead sentence governs: it states the goal, the
  bullets the means. Independent of any spec reading, the function also misses its **own**
  documented contract: "computes what has to change so the set of `ScheduledAlarm`s matches
  [pendingDayValues] **exactly**".
- **Evidence:** `planAlarmSync` with one planned value and two identical alarms on its minute
  yields `toRemove=[] toAdd=[]` — in both operating modes, with and without platform knowledge.
- **Fix:** the first matching alarm claims the value, every further one is dropped. Deliberately
  order-dependent, and the survivor specifically does **not** appear in `toRemove` — removal is by
  alarm id, and removing the same id would stop it on the platform too. That was the
  counter-reviewer's point, not the original proposal's.
- **Untouched: FR-18's safety-critical rule** that an alarm in the past is never removed (it could
  be ringing right now). A dedicated test case with two duplicates in the past.
- **Test:** `test/apply_alarms_test.dart`, group T-116 — two and three alarms on the same minute,
  the fixed point afterward, the past-duplicate case, and two alarms on different minutes as a
  counter-check against over-correction.
- **Requirement:** R2, R3

### T-115 · OPEN SPEC DECISION: what applies at a distance of exactly 12 hours?

- [x] Secure the two values NEXT TO the boundary (that doesn't need a decision).
- [ ] Decide which reading wins at exactly 12:00, and write it into FR-6.
- **Situation:** FR-6's clarification resolves the direction ambiguity by "the variant with
  `|Δ| <= 12h` wins". But at a distance of **exactly** 12:00, **both** readings satisfy
  `|Δ| <= 12h` — the rule doesn't choose. FR-1 doesn't help here: FR-1 computes over real
  instants, where the ambiguity never arises in the first place; the `|Δ| <= 12h` criterion
  exists exclusively for FR-6's pure time-of-day comparison.
- **Today** "later" is chosen — but only as a side effect of the operator choice in
  `scheduling_v2.dart:61-68` (`> halfDay` in the first branch, `<= -halfDay` in the second), not
  as a deliberate decision.
- **To decide:** *Which reading wins at exactly 12:00, and should that go into the spec text?*
  - **"later"** (today's behaviour): the path from 07:00 via 13:00 to 19:00 runs through the day.
    Then FR-6 needs an addition "on a tie, the positive variant wins", and `_wallClockDelta`'s
    second branch must keep its `<=`.
  - **"earlier"**: the intermediate day would land at 01:00, dragging the user through the middle
    of the night. The worse choice for an alarm app, but equally covered by today's text.
- **What's already done:** the two values immediately next to the boundary (11:59 and 12:01) are
  now tested — there the spec decides unambiguously, and the two cases bracket the boundary on
  both sides at 12:00 +/- one minute. That covers the actual danger: any shift or accidental
  removal of the wraparound resolution. A mutation probe (boundary 12h -> 11h) goes red.
  Previously the suite covered none of this — the largest distance ever checked was two hours,
  and this boundary carries the module's entire midnight handling.
- **A finding from the review that saves work:** the obvious mutation `>` -> `>=` in the **first**
  branch is an *equivalent* mutant, uncatchable by any test — the two `if`s are not `else if`, at
  exactly +12h the first branch subtracts 24h and the second immediately adds it back. The
  boundary case depends solely on the second branch.
- **Postponed to the next version (maintainer, 2026-09-24):** not a blocker for the current release
  state.
- **Requirement:** R2

### T-114 · The following week's anchor hung off the trigger instead of the state — RESOLVED (2026-09-11)

- [x] Derive `lastConcludedDay` from the progress marker, bounded against the future.
- [x] Sharpen the too-weak assertion from T-106.
- [x] Remove the write lock that this made dead, instead of leaving it as a fake safeguard.
- **Why:** FR-3 says "`lastEffectiveWakeTime` is deliberately **not** its own field: it is
  **always the entry in `pendingDayValues` for the most recently concluded day**, and as a second
  source could only drift apart from it". But `replan()` read the anchor from a day derived from
  the **trigger**: "yesterday" for everything except the ring. If today has already rung, the
  most recently concluded day is **today** — and that lives in `lastProcessedConcludedDay`,
  precisely the field T-75 split off from `lastReplanDate` for this.
- **Impact, measured:** `maxDailyDelta` is the one guarantee this app gives its users about their
  sleep — "never shift my wake time by more than X per day". It was broken by any
  planning-relevant setting change made in the morning:
  - *An anchor present, but the wrong one:* a daily step of **2 hours** with one hour allowed.
  - *No entry for yesterday* (the normal state after the T-82 prune, or after a gap): the anchor
    is `null`, `computeWeekPlan` takes FR-10's cold start — which jumps **straight to the
    preferred wake-up time**, with no bound at all. Measured: **3 hours** with half an hour
    allowed. FR-10 doesn't even apply here; a `lastEffectiveWakeTime` does exist, it's just dated
    today.
  Every planning-relevant setting and the sync button are affected — an everyday action — and the
  user learns nothing about it: FR-6's overrun notification only fires within runs, not in
  gap-day drift.
- **T-71 does not contradict this,** though it looks like it might. T-71 says a checkpoint must
  not *assume* today is concluded — hence `todayAlreadyRang`. Whether today **is** concluded is a
  question of state. Specifically searched for by the counter-reviewer: no FR and no existing
  test contradicts this (21 occurrences of `todayAlreadyRang` in `test/`, reviewed individually).
- **A bug I introduced myself on the same day also falls with this:** T-106's write lock read the
  progress marker **unbounded**. If it stood in the future (clock set back, a zone change across
  the date line — the same root cause as T-109), the **entire window** counted as concluded and
  nothing at all got planned any more. A regression test exists; `dayDistance(markerDay, today)
  <= 0` now bounds it.
- **And a safeguard that no longer safeguarded anything:** since `windowStart = lastConcludedDay +
  1` follows the state, no window day can be considered concluded any more — the lock was
  provably dead code. The mutation probe confirmed it (removed: all tests stay green). Removed
  rather than left in place: a safeguard that fakes protection is worse than none. FR-11 now
  arises at exactly one place — window construction — and that's noted there in the comment.
- **My own gap, found by the reviewer:** the T-106 test "the following day stays revisable"
  checked `isNot(06:00)` — "something other than". The spec-correct value 06:30 satisfies that,
  but so does the wrong value 09:00. The test sat exactly on this case and stayed green while
  `maxDailyDelta` was exceeded sixfold. It now checks the actual amount.
- **Comparisons throughout are via `dayDistance`,** not `isAfter`: the marker comes locally tagged
  from preferences, `currentTime` can be a `tz.TZDateTime` — an instant comparison of two
  midnights from different frames would be this module's bug class in a new spot.
- **Test:** `test/replan_audit_test.dart`, group T-114 — three cases; both mutations (reverting to
  the trigger-derived anchor; removing the bound) go specifically red.
- **Requirement:** R2

### T-112 · OPEN SPEC DECISION: what applies when a curve crosses midnight?

- [ ] Add a midnight rule to FR-6, THEN implement test-driven.
- **Situation:** if an interpolated wake time slides past midnight, one calendar day can get
  **two** alarms (00:30 and 01:00 in the worked example) and another can get **none**. No FR
  literally forbids this: FR-18 requires one alarm *per planned value*, seven values yield seven
  alarms, and a rule "exactly one alarm per calendar day" exists nowhere.
- **Why this isn't simply a bug:** FR-6 simultaneously demands two things that are **not jointly
  satisfiable** across the crossing - "every `Day_i` gets its own, real calendar date, `A`'s date +
  i" and the step formula `Day_i = A ± (ΔT/N)·i`. Example: anchor local 23:30, step +30min. The
  strict date reading would put `Day_1` at the next day 00:00 - that is **23.5 hours before** the
  anchor and is exactly not a "+30min" step. The code chose the formula (instant monotonicity,
  step <= `maxDailyDelta`) and let the date follow. That is a permissible reading, not provably
  the required one.
- **On top of that:** the crossing is a direct consequence of another spec rule. FR-1's direction
  resolution "`|Δ| <= 12h` wins" forces it. And "key date != instant date" is not per spec a sign of
  error - FR-2 produces it itself (an appointment local 01:00 yields a `hardFloor` instant on the
  previous day, which per FR-2 is the value for the appointment day).
- **Both originally suspected consequences were checked and disproven:** a value that slides
  backward is **never** silently dropped on the ring path (the value for `window[0]` structurally
  lies >= anchor + 12h); on the FR-17 recovery path one does fall away, but it is one that had
  already passed at planning time - which is exactly what FR-18 prescribes. No night is left
  without an alarm.
- **To be decided:** either extend FR-6 with "the instant stays monotonic, the key date stays the
  window day; a window day may as a result be left without its own alarm" - that is today's
  behaviour, the change would be purely editorial - **or** with "the value is pulled back onto its
  own window day", which would be a real behaviour change with consequences for FR-5's violation
  check (which would otherwise compare curve values against another day's `hardFloor`).
- **Do not implement before a decision:** without one there is no test that could turn this case
  red without inventing the intended behaviour itself first.
- **Postponed to the next version (maintainer, 2026-09-24):** not a blocker for the current release
  state.
- **Requirement:** R2

### T-113 · OPEN SPEC DECISION: should FR-16's Checkpoint 2 also update the already-armed alarms?

- [ ] Decide FR-16/FR-18, THEN implement test-driven.
- **Situation:** on a detected offset change, Checkpoint 2 reinterprets the stored plan but does not
  touch the already-registered platform alarm. The **first** alarm after a flight therefore rings
  wrong by the full offset difference - 17:00 instead of 09:00 local time in the worked example -
  and is only corrected by that wrongly-set alarm's own ring. For an alarm clock this is the worst
  failure case there is.
- **Why this is (today) not an implementation bug:** four independent decisions speak for the code.
  FR-18's preamble says FR-1 through FR-17 describe **exclusively computation and triggers** - FR-16's
  test case therefore cannot say anything at all about armed alarms. FR-18 ties the reconciliation
  to "after **every** replan", and CP2 is explicitly **not** one per FR-16. FR-16 itself defers the
  effect ("that follows only at the next regular planning run"). And FR-16's section "Known limit
  on the changeover day" literally accepts the same user-visible effect.
- **What speaks against that:** FR-16's own worked "location change" test case claims "**without the
  second checkpoint this would only have been corrected at the next ring (>12h later)**" - i.e. an
  immediate effect. In its weak reading it is satisfied (the stored plan value afterward carries the
  right figures), in the strong reading it is not.
- **To be decided:** does the weak reading stand (then FR-16's test case needs tightening so it no
  longer promises more than the requirement does), or does a requirement get added: "after a CP2
  reinterpretation, FR-18 is to be reapplied"?
- **What the second option means technically:** `planAlarmSync` is pure and callable from the
  isolate; `Alarm.set` from the background isolate, by contrast, is its own question that FR-16
  does not address - a plugin channel inside the isolate, the same failure class FR-16 already
  sidestepped once with direct SharedPreferences access (T-79). That is the real cost here, not
  the arithmetic.
- **Postponed to the next version (maintainer, 2026-09-24):** not a blocker for the current release
  state.
- **Requirement:** R2, R3

### T-111 · Checked and DISPROVEN: migration path `lastProcessedConcludedDay` → `lastReplanDate` (2026-09-11)

- **The claim was:** if the new key is missing, `lastReplanDate` is adopted as the progress
  marker; since the old key was set to today on *every* replan before T-75, the migration would
  reimport the T-75 bug a second time - the first ring after an update would not count one day and
  would not check it against FR-12.
- **Result: disproven.** The mechanism is reproducible (probe goes red: `gapDayCounter` 0 instead
  of 1), but the triggering preferences state is **unreachable**: today's code always writes both
  keys together, FR-16's Checkpoint 2 never touches them, and `git log -S` shows that
  `lastReplanDate` has existed since the very same commit as `lastProcessedConcludedDay`. There are
  **zero** tags and no published artifact in which the old key was ever written alone. The spec
  does not govern migration, and the assumed effect additionally falls under FR-9's explicitly
  accepted residual risk.
- **Why this is recorded here even though there is nothing to do:** so the same suspicion is not
  investigated a third time. The fallback deliberately stays as is - it costs nothing and is the
  more conservative of the two readings (the alternative, `null`, would count the same day twice).
- **What the check actually did turn up:** the missing persistence round-trip test for
  `lastProcessedConcludedDay` - that is T-108, and it is done.

### T-108 · Three FR-3 fields with no persistence round-trip — RESOLVED (2026-09-11)

- [x] Round-trip tests for `lastProcessedConcludedDay`, `overrunNotificationSent` and
      `safetyValveNotificationSent`.
- **Why:** of the ten FR-3 fields, seven had a round-trip test, these three did not. They are used
  functionally in `replan_test`, `checkpoint_test` and `replan_notifications_test` - but none of
  those rebuilds `AppState`, so none ever checks whether the value survives an app restart. Both
  bool flags carry FR-6's and FR-9's "once" promise across exactly this boundary; without
  persistence, every restart would report again.
- **Result:** the behaviour was correct, just uncovered - all four tests were green immediately.
  Guarded against a false-green test: with the `setBool` line removed, the test goes red (tried
  it), so the round trip really does go through the preferences and not through a shared instance.
- **In addition:** a test now pins down that `lastProcessedConcludedDay` and `lastReplanDate` stay
  separate - that was the entire point of T-75 and had only been guarded implicitly.
- **Requirement:** R2

### T-105 · FR-6's notification duty fell silent in exactly the most common overrun case — RESOLVED (2026-09-11)

- [x] Also set the overrun notification on the path that assigns a day its own `hardFloor`
      directly.
- **Why:** FR-6 says "on **every** overrun of `maxDailyDelta` (`N=1` **or** distributed) the user
  is notified once", and even works through the `N=1` case as its own test example
  (`A=08:00, F=02:00, N=1, maxDailyDelta=60min` -> full 6h jump **plus** notification). The
  exception FR-6 grants for `N=1` concerns the jump size ("cannot be distributed"), not the
  silence. `computeWeekPlan`'s `remaining.isEmpty` branch, however, assigned the `hardFloor`
  directly, without `distribute()` - and `distribute()` is the only place that ever set the flag.
- **Impact:** exactly `window[0]` is affected, i.e. the everyday case "get up early once tomorrow,
  then an appointment-free week". For every later window day, the previous day still runs through
  FR-7's check, which either keeps the remaining jump small or starts a run there (in which case
  `distribute` reports it). `window[0]`'s anchor is the value that rang yesterday - no such check
  applies to it any more. So the user got no warning for a wake-time jump of several hours.
- **Evidence:** found independently and then independently cross-checked (both times with an
  executed probe). Anchor 31 Dec 07:00Z, a single appointment on 1 Jan 01:00Z,
  `maxDailyDelta = 30min` -> value 01:00Z (FR-compliant), `overrunNotificationNeeded: false`
  (spec-violating). The cross-checker also **narrowed** the original claim: an "arbitrarily large
  jump without notification" does not arise at every final window point, only on `window[0]`.
- **Fix:** the same expression as in `distribute` (`ΔT/N > maxDailyDelta`, written
  division-free), so the two paths cannot drift apart.
- **Test:** `test/scheduling_v2_audit_test.dart`, group "FR-6: the overrun notification must not
  fail even at N=1" - three cases: a jump over the limit notifies, a jump under it does not, a
  jump **exactly at** the limit does not (FR-6's condition is `>`, not `>=`). This also closes a
  second gap: `overrunNotificationNeeded` had **never** been checked as `true` at the
  `computeWeekPlan` level anywhere in the suite - only directly on `distribute` and on hand-built
  `WeekPlanResult`s in `replan_notifications_test.dart`. That is exactly why the finding could go
  undetected: the unit level and the notification level were each individually green, the
  connection between them untested.
- **Requirement:** R2

### T-104 · FR-5's ΔT=0 rule only applied to the first point — RESOLVED (2026-09-11)

- [x] Bound the run at every ΔT=0 point, not only at `points.first`.
- **Why:** FR-5 step 2 states "A point with `ΔT=0` relative to `A` ends the run immediately at
  itself - counts as compatible for no direction, **is never grouped with a following point**".
  No positional caveat. `groupTarget`, however, only checked `points.first`; the subsequent
  shrink loop only ever looks at the *violation* for intermediate points
  (`interpolated.isAfter(intermediate.value)`), never their ΔT=0 property.
- **Why this went undetected for so long:** the spec's own test bullet places the ΔT=0 point at
  position 1 (`A=07:00, t1(Tue)=07:00, t2(Fri)=09:00`) - exactly where checking `points.first`
  alone is already sufficient. The existing test mirrors this bullet and was green.
- **Evidence:** found independently and cross-checked. Anchor 07:00, `t1(+1)=08:00`,
  `t2(+2)=07:00` (ΔT=0), `t3(+3)=05:00`, `maxDailyDelta=60min` -> `t3` was delivered, `t2` is
  required.
- **Impact:** small but clear. The run gets grouped across a day whose wake time already exactly
  matches the current one; the curve becomes flatter than intended and shifts precisely the day
  that needed no smoothing at all. Requires a minute-exact time reading.
- **Fix:** the candidate list is now cut off at the first ΔT=0 point (inclusive), instead of
  returning immediately at it - this way step 1's shrinking below it stays effective. A flat
  curve can very well violate a stricter intermediate point; then `t_m` has to keep shrinking like
  for any other target.
- **Test:** `test/scheduling_v2_audit_test.dart`, group "FR-5 step 2" - four cases, including two
  counter-tests against overcorrection (without a ΔT=0 point, grouping still extends to the last
  point; a ΔT=0 point keeps shrinking further if it violates an intermediate point).
- **Requirement:** R2

### T-103 · The alarm survival measurement reported a FAIL it could not substantiate — RESOLVED (2026-09-11)

- [x] Switch the counting pattern to fully qualified identifiers.
- [x] A self-test against recorded `dumpsys` output that runs without an emulator.
- **Why:** `check_alarm_survival.sh` passes a verdict on the product's central promise
  ("guaranteed wake-up"). In the script's first run (T-99), the pattern found **nothing**, even
  though `arm_alarm_test.dart` had provably set an alarm. The reaction to that was to add **more**
  patterns - among them the bare substring `AlarmReceiver`. In the second run (34566962847), that
  matched exactly Google's `com.android.wallpaper.module.DailyLoggingAlarmReceiver`, twice. The
  counter thus stood at 2 instead of 0, the script sailed past its own `BEFORE == 0` guard, and
  wrote `RESULT reboot: FAIL - no alarm survived the reboot` into the evidence file. That line
  proves nothing: the app's own alarm had never been found in **either** measurement.
- **Evidence:** `alarm_survival.log` from run 34566962847 - `registered alarm lines before
  reboot: 2`, while the raw excerpt beneath it shows exclusively foreign entries
  (`android`, `com.android.settings`, `com.google.android.gms`, `…apps.wallpaper`) and the
  `app-uid alarms` section stays empty. The file lives verbatim as
  `.github/scripts/fixtures/dumpsys_alarm_foreign.txt` in the repo and is the self-test's negative
  fixture. Reproduced: `grep -cE "com.wakeywakey.wakeywakey|AlarmReceiver|…"` returns **2** on it,
  the correct answer would be **0**.
- **Resolution:** the counting now reads the summary line
  `Pending alarms per uid: [… u0a161:2 …]` - the kernel's own per-uid counter, with no text-pattern
  search at all - and only falls back to entry lines with the **package name** as a secondary
  option. The uid is resolved via `pm list packages -U`, with `userId=`/`appId=` as a fallback
  (`userId=` alone stayed empty in the real run). Generic word fragments are forbidden, and the
  uid token is digit-bounded so `u0a16` cannot match `u0a161`.
  Above all: **the instrument now proves itself before it measures.**
  `check_alarm_survival.sh --self-test` checks the detection against two fixtures (the real
  foreign recording must yield 0, the app's own alarm must be found - otherwise the negative test
  would be trivially satisfied by a pattern that matches nothing at all), runs without an emulator
  in CI's UTC leg, and aborts the measurement if it fails. Both mutations (generic `AlarmReceiver`
  put back; uid token without digit bounding) were tried and go red.
- **What is still open:** what an app's own alarm **actually** looks like in `dumpsys alarm` has
  still never been observed. `dumpsys_alarm_own.txt` is therefore explicitly marked as
  **constructed** (`fixtures/README.md`). The next run has to show whether the detection holds up
  in reality; if it again finds nothing, the script now reports **inconclusive** instead of FAIL
  and names the three places to look.
- **Lesson, in general:** a blind piece of evidence that reports "nothing found" is harmless - you
  notice it. One that finds something wrong is dangerous: it looks like a result. Whoever widens a
  pattern because it matches nothing must, in the same step, check what it matches **additionally**.
- **Requirement:** R3

### T-102 · The Gradle cache took down the release build — RESOLVED (2026-09-11)

- [x] Narrow the cache down to what pays off.
- [x] Delete the caches that had piled up.
- [ ] Confirm in the next run that the build job goes through (after that, T-06's remaining task -
      a live proof that the gate really stops something - is still separately open).
- **Why:** in run 34535358135, `Build Android (production)` showed `failure`, and the obvious
  interpretation would have been "the desugaring or override change broke the build". That was
  **wrong**. The job's step list shows that it died in **step 6** (`actions/cache`, Gradle) after
  2m49s, and `flutter build apk --release` (step 9) **never ran**. The logs were already
  unretrievable by that point (`BlobNotFound`), but the step list still was.
- **Cause:** the cache block stored `~/.gradle/caches` **in full**. That grows without bound - it
  holds not only the downloaded dependencies but every transformed AAR and every build-cache entry
  too. Measurement: **6436 MB** Actions cache, of which two Gradle entries with **3746 MB** and
  **2397 MB**. Two, because changes to `android/**/*.gradle*` change the cache key - the old
  multi-GB entry stays lying next to it. A restore of this size takes longer than the build saves
  and occasionally just falls over.
- **Status:** now only `~/.gradle/caches/modules-2` (the downloaded modules) and
  `~/.gradle/wrapper` are cached, with `restore-keys` for partial hits - across all four
  workflows. All accumulated caches deleted (the list is empty; GitHub's usage display lags
  behind).
- **Lesson that outlasts this specific case:** on a red job, look at the **step list** first, not
  at your own most obvious hypothesis. Here, the wrong interpretation would have led to reverting
  a correct and demonstrably verified change (T-90/T-97).

### T-101 · risk.png was a planning-phase picture, now it's a threat model — RESOLVED (2026-09-10)

- [x] Replace `docs/risk.png` with a real threat model.
- [x] Generate it from a maintainable source, not store it as a mere binary image.
- **Why:** `risk.png` dated from the planning phase, modelled features that were partly never
  built, and carried no note saying so (T-30). A risk picture that cannot be checked against the
  code is worse than none at all - it suggests review took place where none did.
- **Status:** rebuilt as a data-flow diagram with trust boundaries and a STRIDE assessment. The
  source is `docs/threat-model.svg` (text, diffable); `docs/risk.png` is rendered from it with
  `rsvg-convert -w 1400 -b white docs/threat-model.svg -o docs/risk.png`. Deliberately **no**
  additional `threat-model.md`: the analysis lives entirely in the diagram, and two sources drift
  apart - exactly the problem this pass had to repair repeatedly.
- **The substantive core that sets it apart from a standard checklist:** the primary asset here is
  **availability**. For an alarm clock, "outage" means oversleeping, so denial of service is the
  heaviest category rather than the most annoying one - and the project's two most severe findings
  (T-64, T-78) were exactly that: self-inflicted alarm shutdowns. Second, in the
  "guaranteed wake-up" feature the adversary is partly the **user themself**, trying to defeat
  their own gate; that inverts the usual assumptions. Third, "no network access in lib/" is a
  load-bearing countermeasure, not a footnote - it eliminates an entire threat class.
- **What the model names as open:** R8/R9 (non-free dependencies - both a licence AND a control
  problem), R3 (reboot survival unproven), over-permissioning in the manifest
  (`WRITE_CALENDAR`, `READ_EXTERNAL_STORAGE` with no code path), no dynamic analysis, and the
  residual risk that the QR code is copyable by design.

### T-100 · Artifact storage ran at 2.75x the quota — RESOLVED (2026-09-10)

- [x] Remove old artifacts.
- [x] Fix the cause.
- **Why:** **1375 MB** of non-expired Actions artifacts against a 500 MB quota (private repo,
  free plan). Cause: `ci.yml` uploads a release APK (~39 MB) and a debug APK (~94 MB) on every
  `master` push, and **none** of the uploads had `retention-days` - so GitHub's default of 90 days
  applied. `cleanup_old_artifacts.sh` exists, but prunes only `release.yml` runs; nothing ever
  cleaned up the CI runs. Breakdown: `app-production-apk` 19x/748 MB, `app-debug-apk` 3x/281 MB,
  `app-development-apk` 2x/188 MB, `app-release-apk` 2x/79 MB, `mobsf-report` 22x/51 MB,
  `e2e-evidence` 7x/29 MB.
- **Status:** 70 artifacts deleted from old runs, **1282 MB** freed - 11 artifacts / 93 MB
  remaining. Kept: the two newest CI runs and the newest release run; artifacts are reproducible
  from the commit, and run 34532845207's evidence ("7 tests passed") additionally lives
  permanently outside `/tmp`. Every upload now has an explicit `retention-days` (development APK
  5 days, release APK and reports 30) - so it cannot build up again without someone maintaining a
  cleanup script.

### T-98 · The E2E time limit was sized for the state before the engine scenarios — RESOLVED (2026-09-10)

- [x] Raise the limit.
- [ ] Tighten it again after a few measured runs (then with actual numbers instead of an estimate).
- **Why:** `e2e-tests.yml` had `timeout-minutes: 25`, matching the 19m53s the job needed before the
  new scenarios. On top of that came four engine scenarios (one of which waits for a real ring), a
  second `flutter test` invocation for `arm_alarm_test.dart`, and the reboot proof with up to 240s
  of boot wait time. The first run afterward (34532845207) promptly ran into the timeout and was
  **cancelled**, which skipped the release build and the MobSF scan - even though everything was
  fine content-wise. A time limit is meant to cut off a hung job, not a slow one.
- **Status:** provisionally 60 minutes. Important for the next diagnosis: `timeout-minutes` is
  read at a run's **start** - a change made while a job is running has no effect on it any more.

### T-99 · Two pieces of evidence in the E2E job were blind — PARTIALLY RESOLVED (2026-09-10)

- [x] Make both spots diagnosable.
- [x] Read the real `dumpsys alarm` patterns from a real run and lock the counting to them.
- [ ] Confirm that `adb root` actually sets the timezone on the CI image.
- **Why:** run 34532845207 brought both of these to light - both things I had previously only
  **assumed**, and the review pass had explicitly flagged them as unverified:
  1. **The reboot proof found nothing.** `arm_alarm_test.dart` had, in the same run, provably set
     an alarm ("🎉 1 test passed", `TimeOfDay(23:55)`), but
     `dumpsys alarm | grep -c com.wakeywakey.wakeywakey` returned **0**. The expected dumpsys
     signature had been guessed wrong. "inconclusive" therefore does not mean "no alarm set", but
     "my pattern doesn't match".
  2. **The emulator timezone did not take effect.** `manifest.log` says `Etc/UTC` -
     `adb shell setprop persist.sys.timezone` has no effect as a normal shell user. Consequence:
     the T-61 scenario passed **trivially true**. It showed green in the report but proved
     nothing - exactly the caveat stated in its own test comment.
- **Status:**
  - `check_alarm_survival.sh` now checks several patterns (package name, `AlarmReceiver`,
    `com.gdelataillade.alarm`) and writes a **raw excerpt** of `dumpsys alarm` plus the app's UID
    into the evidence file on every run. That makes it possible to pin the patterns down from
    evidence next time, instead of guessing again. The "inconclusive" message now explicitly says
    it does not mean "no alarm".
  - `run_e2e_tests.sh` tries `adb root` before the `setprop`, reads the value back, and emits a
    visible `::warning::` on mismatch - including a note that the T-61 scenario then proves
    nothing in this run. Deliberately **no** abort: the suite stays valid at UTC, just
    inconclusive on this one point. That belongs in the evidence, not in silence.
  - **The dumpsys pattern is now locked to real evidence (2026-09-19), without needing a CI run**:
    `scripts/verify-alarm-survival.sh` and `.github/scripts/check_alarm_survival.sh` share the same
    `alarm_detection.sh`, and a real Fairphone 6 run of the former (T-93) captured genuine
    `dumpsys alarm` output showing this app's own alarms under a real uid token, with the reliable
    `Pending alarms per uid: [..., u0aNNN:N]` summary line present and correctly parsed.
    `.github/scripts/fixtures/dumpsys_alarm_own.txt` now holds that real recording (replacing the
    previous hand-constructed one) and `alarm_detection.sh`'s self-test asserts against its real
    uid/count. Not captured on the CI emulator image itself, but the summary-line format comes from
    AOSP's own `AlarmManagerService.dump()` - identical platform code on real or virtual hardware -
    so this is treated as sufficient rather than spending a full, costly CI/security-gate run only
    to re-observe the same platform-level format. The `adb root`/timezone question remains
    genuinely CI-emulator-specific and unanswered by this (a real, non-rooted retail phone always
    refuses `adb root` regardless of what a debug AVD image permits, so testing it against a real
    phone would prove nothing either way).
  - **A byproduct of gathering that evidence, not something this item was measuring:** the same
    real run showed the sleep-time reminder's own scheduled notification NOT surviving a reboot,
    unlike the `alarm` plugin's ringing alarms, which did - see the new T-155.
- **What the run actually did prove, on the other hand (T-91 is redeemed):** `🎉 7 tests passed`
  on a real emulator, including all four engine scenarios. Visible in the log:
  `applyPlannedAlarms: removed 0, added 7` - an injected appointment produces exactly the seven
  alarms the fixture predicts, and a dismiss leaves them standing (T-64). This is the first
  confirmation of FR-18 all the way to the alarm plugin, on a device.

### T-97 · Project hygiene: leftover cruft in pubspec, build, and docs — RESOLVED (2026-09-10)

- [x] Remove unused direct dependencies.
- [x] Remove dead state in `AppState`.
- [x] Correct outdated doc claims.
- **Approach:** nothing removed without a reason. Planning artifacts (`risk.png`,
  `UML_WakeyWakey.drawio`, `personas.md`, `use-cases.md`, `choice-of-technologies.md`) are
  untouched — they were created by the maintainer. The gitignored point-in-time snapshots
  (`quality-baseline-*`, `release-readiness-*`) likewise.
- **Dependencies (`pubspec.yaml`), all checked before removal:**
  - `cupertino_icons`, `flutter_spinkit` — imported nowhere in `lib/`, and no longer in
    `pubspec.lock` after removal either. So genuinely unused.
  - `syncfusion_flutter_core`, `syncfusion_flutter_datepicker` — not imported, but
    `syncfusion_flutter_calendar` requires both itself (`^34.2.6` in its own pubspec). The direct
    entries were redundant; they now show as `transitive` in the lock. **Correcting an obvious
    assumption:** this does NOT reduce the license surface from R8/R9 — the packages come along
    either way.
  - `awesome_notifications_core` — **the interesting find.** `awesome_notifications` 0.12.1
    doesn't require it at all; the entry was leftover cruft from the 0.9.x/0.10.x era. After
    removal it has vanished from resolution entirely.
  - `awesome_notifications: any` -> `^0.12.1`. An `any` constraint is an open flank: a broken
    version could have come in silently.
  - `flutter_lints` moved from `dependencies` to `dev_dependencies`. It only ships analysis rules
    and is never imported at runtime — under `dependencies` it was a runtime dependency.
- **Build:** the compileSdk override in `android/build.gradle.kts` has therefore **been dropped**.
  Its only reason was `awesome_notifications_core`'s hardcoded `compileSdkVersion 33`; without the
  dependency, the offending AAR is out of the build. `CLAUDE.md` had the invitation for exactly
  this ("If a future dependency bump makes this override redundant, it's safe to remove - but
  check `flutter build apk` still succeeds first"). Verified with a **`flutter clean`** release
  build (33.9 s, 83.8 MB), not just an incremental one — an incremental run could have skipped the
  AAR-metadata check as UP-TO-DATE.
- **Assets:** `assets/icons/icon.png` is no longer in the asset bundle. It is exclusively the
  source for `dart run flutter_launcher_icons` (which reads the path from its own configuration on
  disk); nothing loads it at runtime. The file stays in the repo. All six sound files, by contrast,
  are genuinely in use (tone selection) and stay bundled.
- **Dead state:** `AppState.isPreloadingCalendarMutex` removed — the field, getter, and setter had
  **zero** readers and **zero** writers outside `app_state.dart`. Same bug class as the findings in
  T-86. A pass over every AppState getter found no further ones.
- **Test correction:** the E2E scenario for T-84 set `assets/sounds/mozart.mp3` — a file that
  doesn't exist. The test still passed, because it only compares the path read back, but on a
  device the plugin would have referenced a missing asset. Now `annoying_alarm.mp3`, which genuinely
  exists and differs from the default.
- **Docs:** `CLAUDE.md`'s test status (199/22 -> 209/24), the E2E description (three -> seven
  scenarios, with an explicit note that the four new ones **have never run**), and the section on
  the compileSdk override.
- **Deliberately NOT touched:** `docs/TODO.md`'s completed entries. They are the evidence that a
  finding has been fixed — this project's convention is that a fixed finding stays documented.
  "No longer current" is not the same as "throw it away" here.

### T-96 · Gentle Wake had no control for the ramp duration — RESOLVED (2026-09-10)

- [x] Make the duration adjustable and pass it through to the alarm plugin.
- **Why:** the ramp was hardcoded in `lib/app_state.dart` as `Duration(seconds: 60)` — a user
  could switch Gentle Wake on and off, but not decide how long the alarm stays quiet. The plugin
  takes the value as a parameter (`VolumeSettings.fade`), so the setting was only missing at the
  surface.
- **Status:**
  - New `AppState.gentleWakeUpDuration`, persisted as `gentleWakeUpSeconds`. Default one minute —
    exactly the previously hardcoded value, so existing installations sound unchanged. Bounded
    below at one minute, because the plugin requires `assert(fadeDuration > Duration.zero)`, but
    the hh:mm picker allows 00:00, and assertions are off in the release build.
  - **The duration hangs off the ALARM, not just AppState** (`MyAlarm.gentleWakeDuration`, carried
    through `ScheduledAlarm` and `ManualAlarm` including JSON and `==`). That's the lesson from
    T-84: `planAlarmSync` decides whether an already-armed alarm must be replaced based on the
    alarm's own properties — if the value lived only in AppState, a change could never be
    recognized as a deviation, and the setting would have a UI with no effect on existing alarms.
    `planAlarmSync` now compares it too, but only with Gentle Wake switched on (otherwise
    `_setAlarm` doesn't use the ramp at all, so a difference would be no reason to re-arm).
  - Old stored alarms without the field fall back to the default.
  - UI: a "Ramp duration" control under the Gentle Wake switch, visible only when it's on (the
    reminder switch's pattern), with a visible hint about the minimum — like `maxDailyDelta` in
    T-88, so the bound doesn't strike invisibly.
- **Side finding, fixed along with it:** the dialog for creating a *manual* alarm
  (`screen_alarms.dart`) pre-filled `gentlewake`, `volume`, and `tone` from AppState, but not the
  ramp duration — a manual alarm would therefore have stubbornly used the default minute.
  `test/manual_alarm_inherits_settings_test.dart` drives through the real dialog for this and was
  red against the unmodified code (`0:01:00` instead of `0:09:00`).
- **A reading I made:** "how long the quiet alarm should play" is implemented as **ramp length** —
  the volume rises over this duration from 0 to the set value, so the alarm stays quiet for
  exactly that long. The plugin could alternatively run a staircase (`VolumeSettings.staircaseFade`),
  e.g. "10 minutes constantly quiet, then a sudden jump to loud". If that was what was meant, it's
  a different call at the same spot.

### T-95 · Sleep-habits screen: the order was misleading — RESOLVED (2026-09-10)

- [x] Group entries by cause and name the groups.
- **Why:** the order wasn't just a matter of taste, it misattributed effects. "Sleep Goal" was in
  **first** place, but doesn't affect the alarm time at all — it only shifts the bedtime reminder
  (`nextWakeUpTime - sleepGoal - reminderDuration`, `lib/utils/sleep_reminder.dart`). Someone who
  sees it at the top and adjusts it expects an earlier alarm and gets nothing. At the same time it
  was separated from "Enable Reminder" — the other half of the same calculation — by three
  unrelated entries. And "Preferred wake-up time", the anchor of the entire FR-4 drift and the
  only setting a user needs **without** calendar appointments, sat at position 4, below two
  durations that only apply on days **with** an appointment.
- **Status:** three causal groups with headings:
  1. *Wake-up time* — Preferred wake-up time, Max. daily shift, Duration to wake up, Duration to
     get ready. First the goal, then the bound on how fast the wake time may approach it (FR-6),
     then the two lead times in the order `hardFloor` subtracts them.
  2. *Bedtime reminder* — Sleep Goal, then Enable Reminder: the lead time is measured from the
     bedtime, which the sleep goal sets.
  3. *When the alarm rings* — Gentle WakeUp.
  The headings are part of the fix, not decoration: without them the grouping would be invisible
  to the user, and the new order just a different one, not an explained one.
  `test/sleep_habits_order_test.dart` checks the order via the labels' **y-positions** (i.e. what
  the user sees, not the source order), that each group has a heading above its first entry, and
  that the T-88 hint about the 15-minute minimum stays with its control. All three were red
  against the old order.

### T-94 · The dev VM can no longer run the suite or the release build to completion — RESOLVED (2026-09-10)

- [x] Reboot the VM (clears the hanging kernel threads) and then run both once to completion:
      `flutter test` and `flutter build apk --release`.
- [x] If the build still hangs afterward: isolate the one line from T-90
      (`isCoreLibraryDesugaringEnabled` in `android/app/build.gradle.kts`) and build without it.
      That is the only change in this pass that touches the build.
      **Turned out not to be necessary** — see status.
- **Why:** on 2026-09-10, from midday onward the VM finished neither the unit suite nor a release
  build. Symptoms and evidence:
  - `flutter test` (whole suite): aborts after 150-190 tests with rotating "did not complete" /
    "Bad state: Cannot add event while adding stream" failures. This is a `flutter_tools` harness
    error that occurs when a test **device** dies mid-stream — not an assertion failure. The
    affected file changes on every run.
  - The same files pass **individually** and in two large blocks (62 + 88 tests) green in 4
    seconds each. So it's a resource question, not a code question.
  - Every aborted run leaves behind a `frontend_server` process at ~490 MB. On 8 GB, the pressure
    builds back up after a few runs.
  - `flutter build apk --release` hangs: four or three JVMs in `futex_do_wait`, **zero** file
    changes under `build/` for minutes. Even with `-Dorg.gradle.daemon=false` and after
    `rm -rf ~/.gradle/daemon`. The same build had run in 36 seconds earlier the same day.
  - An independent pass saw the same hang **before** any Gradle change made that day
    (`flutter build apk --debug`, unchanged for 45 minutes at `Running Gradle task
    'assembleDebug'`, daemon in `futex_do_wait`), and traced it to lock/resource contention. So the
    cause is not the desugaring line.
  - The trigger was most likely the emulator work: two emulators started in parallel on 8 cores /
    8 GB, after which `kworker/u32:1+netns` and `kworker/u38:*+events_unbound` stayed permanently
    in D-state (load average has stood at ~6 ever since, even though `procs_running 1` and
    `procs_blocked 0` are reported). Such kernel threads usually only disappear with a reboot.
- **Practical handling until then** (also noted in `CLAUDE.md`): `pkill -f "frontend_serve[r]"` —
  the character class matters, without it `pkill` matches its own command line and kills the shell
  — and running the suite in two to three file groups instead of one invocation.
- **Status:** after `pacman -Syu` (20 packages, kernel 7.2.3 -> 7.2.4) and a reboot, both have been
  run to completion and the diagnosis confirmed — it was exclusively resource exhaustion, not a
  code problem:
  - `flutter test` in **one** invocation: **199/199 green in 2 seconds**. Previously the same
    invocation reproducibly aborted after 150-190 tests.
  - `flutter build apk --release`: **succeeded in 100 seconds**, 84.2 MB, signed (`CN=Dam0k1es`),
    `apksigner verify` OK, minSdk 24 / targetSdk 36. Previously the same build hung for over 20
    minutes with JVMs in `futex_do_wait`.
  - Measurements before/after: D-state processes 5 -> **0**, load average ~6 -> **0.65**, available
    memory 1-2 GB -> **6.9 GB**.
  - The `vboxsf` mount survived the kernel update unscathed (reading and writing) — as expected,
    because the module belongs to the kernel package and isn't built via DKMS.
- **The desugaring line from T-90 was not the cause** — it's still in unchanged and the build runs.
  So the suspicion in the second point above has been settled.
- **Lesson for the next suspected case:** "no file changes under `build/`" is **not** evidence of a
  hang — Gradle works in the meantime in `~/.gradle` and in temp paths. Only
  `find <project> ~/.gradle -newermt "-5 minutes"` with **zero** hits is evidence. In this pass, a
  running build was once wrongly aborted because of this (`exit code -9` came from the `kill`
  itself, not from Gradle).

- **Addendum (2026-09-11):** the point still open at the time, "the new E2E scenarios need a
  device", is done — run 34532845207 ran them on the CI emulator (`🎉 7 tests passed`). See T-91.

### T-89 · PII-free developer log, and the leaks it replaces — RESOLVED (2026-09-10)

- [x] Build an event logger that structurally cannot record personal data.
- [x] Close the leaks that were found.
- **Why:** an installed release build returned **nothing** — every diagnostic went through
  `debugPrint`, and `main.dart:29-31` replaces that with an empty function in release. So a device
  test could only show THAT something went wrong, never why. At the same time, an independent
  audit found five **critical** leaks and a whole bug class:
  - `qr_scanner.dart:139` and `:176`, plus `page_deactivation_code.dart:48`, logged the
    **QR deactivation code in plain text** — the secret that lets the "guaranteed" alarm be
    defeated. The validation line fired reliably every morning.
  - `calendar.dart:25` logged the calendar name, on Android regularly the **account email
    address**; `:72` the **appointment title**.
  - `catch (e) { debugPrint("... $e") }` in ~60 places: `FormatException.toString()` contains a
    slice of the **source string**, so `$e` let payload data into the log that never appeared in
    the format string itself — with corrupted SharedPreferences, alarm titles, planned wake times,
    or the deactivation code.
  - `replan.dart:317` is the **only** debugPrint that bypasses the release guard: it sits in
    `runTimezoneCheckpoint2`, which runs via `@pragma('vm:entry-point')` in its own isolate, where
    `main()` never ran.
  - `handler.dart:110-125` created two real **notifications** with alarm type, wake time, and id —
    guarded only by `kDebugMode`, not by the debugPrint shutoff. They landed in the notification
    shade and thus on the **lock screen** of every tester with a debug APK (which `ci.yml` uploads
    for `dev` as an artifact). A history of these is a sleep profile.
  - `scanned_barcode_label.dart:27` showed the raw scanned value large on screen — in alarm mode,
    i.e. on a ringing device.
- **Status:** Resolved. New: `lib/utils/diag/diag_log.dart`.
  - **The load-bearing decision:** the recording API takes **not a single String**. There is
    therefore no channel through which an appointment title, a calendar name, an exception
    message, or the QR code could enter it — what cannot be represented cannot leak.
    `test/diag_log_api_test.dart` checks this against the source (no String parameters, no
    `debugPrint`/`print`, no clock reads, no int parameter with a clock-shaped name).
  - **Why this is still diagnostically sufficient:** every real finding in this project was a
    STRUCTURAL bug, not a VALUE bug — a wrong count (T-75, T-70), colliding day keys (T-74d/T-76),
    a value shifted by the device offset (T-61), unbounded growth (T-82), diverging sets
    (T-74e/T-88). None of them needs the user's actual wake time.
  - **Time:** no timestamps, no calendar data, no clock times. Days only relative (via
    `dayDistance`, so the logger doesn't rebuild T-76 inside itself), instants only as bucketed
    **differences** (steps chosen after the bug signatures: 0 = healthy, one hour = offset/DST =
    T-61, one day = off-by-one = T-74d/T-76). The absolute time zone offset is never recorded, only
    the *shape* of the change — it would immediately pin down the region. Ordering via `bootSeq` +
    `seq`, coarse timing via `Stopwatch`.
  - **Exceptions** go in as `runtimeType` through an identity table to an int, never as a message;
    `toString()` is never called on a `Type` (R8 obfuscation is then irrelevant).
  - **Sink:** a bounded ring buffer (512), batched to SharedPreferences. Deliberately no file via
    `path_provider`: FR-16's checkpoint 2 runs in a background isolate and already talks directly
    to SharedPreferences there today — a file logger would depend on plugin-channel availability,
    exactly the bug class T-79 was. The isolate has its **own** ring buffer (the same trap as
    T-69), hence two prefs keys and a merge on read.
  - **Export** via display + clipboard (`Settings > Diagnostics`), not via a share dialog: no
    network code, no new dependency requiring a license check — and more honest, because the user
    reads exactly what they're passing on. A switch to turn it off and a button to clear it sit
    alongside; `assets/text/Privacy.md` updated accordingly.
  - All leaks closed: 62 `$e` interpolations switched to `${e.runtimeType}`, the five concrete
    spots defused, the two debug notifications removed outright, the raw-value display replaced
    with "QR Code detected", the zone name removed from `main.dart`.
    `test/no_pii_in_logs_test.dart` forbids the **channel** (not a specific value) and was red with
    66 violations against the unmodified code.

### T-90 · minSdk 24 is claimed, but never proven — PARTIALLY RESOLVED (2026-09-10)

- [x] Enable core library desugaring (defuses the latent `java.time` mine).
- [ ] Have a real API-24 run that proves the claim.
- **Why:** `android/app/build.gradle.kts` pins minSdk 24, and `aapt2 dump badging` confirms that in
  the built release APK. But that only proves what's in the manifest, not that the app runs there:
  the E2E suite has so far run exclusively on API 34, and locally only an API-29 image is
  installed. On top of that, a concrete finding: `strings classes.dex | grep '^Ljava/time/'` finds
  `Ljava/time/Duration;` in the release dex, and `grep -c '^Lj\$/'` returns **0** — so the call went
  into the APK un-desugared, even though `java.time.*` only exists from API 26. The source is the
  `alarm` plugin (`AlarmSettings.kt:138`), which itself declares minSdk 19 and enables no
  desugaring.
- **Clarification:** the call sits in the backward-compatibility branch for old v4 alarm JSON, which
  the current app version normally never enters. So it's a **latent** API-26 mine under a
  minSdk-24 contract, not a confirmed crash.
- **Status:** `isCoreLibraryDesugaringEnabled = true` plus `desugar_jdk_libs:2.1.5` in
  `android/app/build.gradle.kts`. **Verified in the built artifact** (2026-09-10, release APK):
  `Ljava/time/` references in the dex **0** (previously 1: `Ljava/time/Duration;`), `Lj$/`
  replacement classes **124**, of which **122** under `j$/time`. So the mine is not just
  theoretically defused, but measurably gone. Proof that the app runs on API 24 is still missing —
  an API-24 leg in `e2e-tests.yml` would be the next step, but it would be an unverified leg, and
  one of those must not block a release.

### T-91 · The new engine had never run on any device — RESOLVED (2026-09-10)

- [x] E2E scenarios for scheduling-v2.
- **Why:** Phase 6 deleted the old engine and armed the new one, but
  `integration_test/app_test.dart` only covered manual alarms — the engine was represented there by
  **not a single** test. And that's not a small thing: **no** unit test mocks the `alarm` plugin's
  channel. In `flutter test`, `Alarm.set()`/`Alarm.getAlarms()` throws and is swallowed, so the unit
  suite only ever checks AppState lists. Everything between `appState.addAlarm` and an actually
  registered alarm was unproven.
- **Status:** four scenarios added, each tied to a real finding — T-63 (an appointment becomes
  registered alarms), T-61 (the registered alarm carries the *local* reading of the planned
  instant), T-84 (tone/volume/gentle-wake reach the plugin), T-64 (a dismiss leaves the planned
  week standing). Plus `integration_test/arm_alarm_test.dart` as a prelude for T-93. Fixture recipe:
  lead times zero, no preferred wake-up time, no history, trigger `manualSync` (FR-17's daily lock
  has already kicked in at app start, a second `appForeground` would be a no-op). Hard boundary
  condition: `AppState.addAlarm` rejects a `ScheduledAlarm` whose time is not after the **real**
  `DateTime.now()` — not after an injected "now".

### T-92 · The gate was blind to timezones, and the release path had no safety gate — RESOLVED (2026-09-10)

- [x] Timezone matrix for the unit suite.
- [x] Non-UTC timezone on the E2E emulator.
- [x] SCA/secret/SAST in the release path too.
- [x] Coverage as a signal.
- **Why (timezones):** the dominant bug class in this project is frame confusion, and three real
  bugs (T-61, T-74d, T-76) were **structurally invisible** at UTC+0 - which is exactly where the
  dev machine AND the GitHub runners sit, and the emulator too.
- **Why (release path):** `release.yml` only ran `flutter analyze`, `flutter test` and the E2E
  suite. A signed APK built from a tag and attached to a GitHub Release could therefore carry a
  vulnerable dependency or a committed secret, even though the same commit would have failed that
  check on `master`.
- **Status:**
  - `ci.yml`'s test job is a matrix over six zones (UTC, Europe/Berlin, Asia/Tokyo,
    America/St_Johns, Pacific/Chatham, Australia/Lord_Howe - the half- and three-quarter-hour zones
    are deliberate, since digit arithmetic fails there first), with `fail-fast: false`, because with
    a frame bug the *pattern* across zones is the diagnosis. Verified that the TZ variable actually
    reaches Dart's `DateTime` inside the test process - and that the suite is green in all six
    zones. It is therefore a regression net, not a bug-finder.
  - `.github/scripts/run_e2e_tests.sh` sets the emulator's timezone to `Europe/Berlin` before the
    app first runs. Injecting `deviceUtcOffset` is NOT sufficient for this - that value only
    travels through the domain layer, while `alarmPlatformTime` reads the real device zone.
  - New `.github/workflows/security-gate.yml` (reusable), called by both `ci.yml` **and**
    `release.yml`; `build-signed-release` has it as a `needs`.
  - Coverage runs only in the UTC leg and as an artifact, with **no** percentage gate: an arbitrary
    threshold would reward the wrong thing here - trivial getter tests raise it, while frame and
    structural errors are not captured by line coverage at all.

### T-93 · Alarm survival across a reboot is unverified (R3) — FIRST REAL MEASUREMENT TAKEN, force-stop result unexplained (2026-09-19)

- [x] A procedure that answers the question without a wait.
- [x] Actually run the procedure once for real (run 34566962847, 2026-09-11).
- [x] A route that can answer the question at all: `scripts/verify-alarm-survival.sh` measures
      against a **real phone over USB** - no GitHub Actions and no emulator. That removes T-131's
      structural blocker (the app stays installed) and this VM's emulator problem (T-94) in one
      go. The alarm is armed through the app's **own UI**, located via `uiautomator dump` in the
      accessibility tree rather than by fixed coordinates, so it does not depend on one phone's
      screen size. The counting moved to `.github/scripts/alarm_detection.sh` and is now shared by
      both scripts - a second copy would be a second chance at T-99/T-103. The tap locating proves
      itself against recorded accessibility trees too, and that self-test immediately caught a real
      bug: `tr '>' '>\n'` cannot map one character to two, so all three taps would have landed in
      the middle of the screen and the script would have reported "not measurable" while the app
      was fine.
- [x] Run the script once with a phone attached and record the result here.
- **Real-device result (2026-09-19, Fairphone 6, Android 16, 15198268):** `evidence/alarm-survival-20260919T211356Z/alarm_survival.log`
  (not tracked in this repo - gitignored, contains the device serial). 9 alarms registered before
  the intervention; **reboot: PASS** (8 registered afterwards - the -1 is plausibly a replan-driven
  alarm-id change around the same boundary the run itself created, not a loss, and the counting
  only distinguishes "≥1" from "0" in the first place). **force-stop: alarms still registered (8)**
  - this is the *opposite* of what this entry's own "What is already known from the code" section
    below predicted ("force-stop will come back red, by design"). Checked against the actual
    `alarm` plugin source
    (`~/.pub-cache/hosted/pub.dev/alarm-5.12.0/android/.../services/AlarmScheduler.kt:166,172`):
    it registers with `setExactAndAllowWhileIdle`/`setExact`, not `AlarmManager.setAlarmClock()`
    (the one documented exemption from force-stop's alarm cancellation) - so by the documented
    platform contract, these alarms should have been cleared, and were not.
  - The run's `--apk` argument printed as a literal, unsubstituted placeholder path in the log, so
    `adb install` itself failed - but the maintainer confirmed the phone already had the actual
    current build installed from earlier manual testing (2026-09-19), so the measurement did
    cover today's code, not a stale one. One of the three UI taps ("Manual") also could not be
    located - "Add A New Alarm" and "Save" both succeeded regardless, most likely because the app
    was already showing the Manual tab from a previous session (`AppState.currentPageIndex`
    persists), not a real UI regression.
  - **Not yet re-measured to rule out:** a timing artifact (the script waits only 5s after
    `force-stop` before counting) or a device/Android-16-specific platform behaviour change. Until
    a clean re-run (ideally with a longer post-force-stop wait) confirms it, treat "alarms survive
    force-stop on this app" as a promising real observation on one real device, not yet a verified
    property to build on or advertise more broadly.
  - **Flagged by the external-auditor persona review (2026-09-24, see T-161):** `docs/REQUIREMENTS.md`
    R3 had never been updated to reflect this contradiction - it still stated the 2026-09-18
    force-stop-loses-the-alarm observation as a settled, unfixable platform guarantee, one day
    after this entry's own measurement contradicted it. Fixed by rewriting R3's relevant paragraphs
    to state plainly that the force-stop question is unresolved (not "loses it" and not "survives
    it") until a clean re-measurement closes the disagreement - see R3 for the corrected text.
- **Root cause known since 2026-09-11, and structural (T-131):** `flutter test` uninstalls the app
  after the run, so Android drops its AlarmManager entries with it - there can be no alarm
  registered at the time of measurement at all. The procedure therefore needs a different way of
  arming the alarm before anything here becomes measurable in the first place. **The question
  remains unanswered, not failed.**
- **Status after the first real run:** unusable, and that is a measurement problem, not a
  substantive one. The counting pattern matched foreign alarms and reported a groundless FAIL - see
  T-103, where this is worked through and fixed. The question "does an alarm survive the reboot?"
  therefore remains **unanswered**; it has only become measurable now. Only arm it for real once a
  run actually sees its own alarm before the reboot.
- **Why:** R3 is the last open question in the "guaranteed wake-up" product promise and had never
  been measured. A ring test costs a minute of real time per run and does not fit the E2E time
  budget.
- **Status:** `.github/scripts/check_alarm_survival.sh` evaluates `dumpsys alarm` - which
  distinguishes "an alarm is registered" from "no alarm registered" without waiting.
  `integration_test/arm_alarm_test.dart` runs before it, because `app_test.dart` consistently calls
  `Alarm.stopAll()` in `tearDown`, so nothing would remain registered coming out of it. Deliberately
  **not gating**: this behaviour has never been measured on this image, and an unverified leg must
  not block a release - it collects evidence first.
- **What is already known from the code:** the app has **no** `BootReceiver` of its own; the
  `alarm` plugin registers one and re-arms the stored alarms after boot via
  `setExactAndAllowWhileIdle(RTC_WAKEUP, …)` (so reboot should come back green). On
  `am force-stop`, Android clears all of the package's alarms at the platform level, and a
  force-stopped process no longer receives `BOOT_COMPLETED` afterwards - so force-stop will come
  back red, **by design**. That belongs in R3 as a boundary, not as a defect.

### T-75 · `lastReplanDate` conflates two purposes -> FR-9/FR-12 skip whole days — RESOLVED (2026-09-10)

- [x] Split into two fields: `lastProcessedConcludedDay` (drives `firstUnprocessedDay`) and
      `lastReplanDate` (only FR-17's daily lock).
- **Why:** since T-71, `lastConcludedDay` is `today` or `today-1` depending on the trigger, but
  `lastReplanDate` is always set to `today` (`replan.dart:194`). A recovery replan (app resume or a
  settings change before the morning alarm - a perfectly normal occurrence) therefore consumes the
  marker without advancing it; the later, real ring then finds `needsDayAdvance == false` and the
  day is permanently lost. Empirically: ring on day 9 -> recovery on day 10 at 03:00 -> ring on day
  10 at 07:00 yields `gapDayCounter == 1` instead of 2. Consequence: FR-9's valve undercounts (and
  may never trip), and FR-12 never reports for such days. No test covered two replans on the same
  day.
- **Done when:** regression test "recovery on day D, ring on day D+1 -> both days counted" passes.
- **Status:** Resolved 2026-09-10: new `AppState.lastProcessedConcludedDay` (with a migration from the old key), `lastReplanDate` now carries only FR-17's daily lock. Regression tests in `test/replan_test.dart`, group "T-75" (recovery on day D then ring on day D counts both days; FR-12 stays reportable).

### T-76 · DST: `dayOffset` in `computeWeekPlan` is off by 1 after the spring-forward transition — RESOLVED (2026-03-29)

- [x] Calendar-day arithmetic fixed in `computeWeekPlan` too (`scheduling_v2.dart:578` and `:592`).
- **Why:** T-74d only replaced `add(Duration(days:))` in `replan.dart`. Here,
  `anchorDay = window[startIndex].subtract(const Duration(days: 1))` and
  `window[j].difference(anchorDay).inDays` still operate on locally-tagged markers. Verified
  independently (`TZ=Europe/Berlin`, transition 2026-03-29): on 28 March this produces offsets
  `[1, 1, 2, 3, 4, 5, 6]` instead of `[1..7]` - two window days collide. Consequence: `nRest`/`N`
  come out too small (the curve is too steep, the FR-6 overrun fires wrongly), `distribute` places
  `Day_i` wrongly, and `groupTarget`'s violation check compares the wrong day against `hardFloor` -
  a real appointment can be violated. Invisible to the tests, because they use UTC-tagged windows.
- **Status:** Resolved 2026-09-10: new `lib/models/scheduling/day_marker.dart` (`midnight`/`dayMarker`/`dayStamp`/`dayDistance`/`isoDate`); `computeWeekPlan` now uses `dayMarker(window[startIndex], -1)` and `dayDistance(...)`. `replan.dart`'s private copies are gone. Tests: `test/day_marker_test.dart` and `test/scheduling_v2_dst_test.dart` - the latter builds the window from `tz.TZDateTime` in `Europe/Berlin`, so it reproduces independently of the test machine's own timezone (exactly what the earlier partial fix T-74d ran past). The red test run produced exactly the hand-calculated wrong value, 04:36:40 instead of 04:40.

### T-77 · `replan()` is not serialized - concurrent checkpoints are possible — RESOLVED (2026-09-10)

- [x] A future-based mutex around the whole checkpoint; reserve the day marker **before** the
      calendar I/O, not only at the end.
- **Why:** four triggers, three of them `unawaited` (`handler.dart:68`, `main.dart:235`,
  `main.dart:207`, plus the UI). FR-17's lock doesn't protect against this, because it reads
  `lastReplanDate`, which is only written at the **end** of `replan()` (`replan.dart:194`). When an
  alarm rings, Android brings the app forward via a full-screen intent -> `resumed` -> a second
  checkpoint starts while the first is still stuck in calendar I/O: `gapDayCounter` gets
  incremented twice, and both compute `toAdd` against the same stale alarm list -> duplicate alarms
  on the same minute.
- **Status:** Resolved 2026-09-10: `runSchedulingCheckpoint()` serializes every trigger through a future chain, and FR-17's daily lock is read **inside** the lock. Verified effective: with the lock disabled, `test/checkpoint_test.dart`'s first case goes red (2 concurrent calendar accesses instead of 1).

### T-78 · FR-9's safety valve has no way back for a `wunschzeit` user — RESOLVED (2026-09-10)

- [x] Spec decision + implementation: either don't let the valve trip when `wunschzeit != null`, or
      also reset the counter on a day that actually got planned, or add a reset action in the UI.
- **Why:** only reachable once T-72 landed. `updateGapDayCounter` only resets on a day with a real
  `hardFloor`. A user with a preferred wake-up time set and no calendar appointments gets shut off
  by the valve after 7 days (every window value is `null`, `applyPlannedAlarms` removes every future
  alarm) - after that, nothing rings any more, so there is no ring checkpoint, and only a
  `hardFloor` day could reset the counter. The alarm clock switches itself off permanently.
- **Status:** Resolved 2026-09-10 - as a **spec change**, not a bug fix: FR-9 had no exception, so FR-9 was first extended with the section "Exception: `wunschzeit` set" (with rationale), then the existing valve test was switched to `wunschzeit: null` (the condition that made it valid in the first place), and a new exception case was added. The counter keeps running unchanged; the valve only trips when `wunschzeit == null`.

### T-79 · `Notifications().init()` is not awaited, but the post-frame replan needs the plugin — RESOLVED (2026-09-10)

- [x] `await Notifications().init()` before the first checkpoint (or in `main()` before `runApp`).
- **Why:** `main.dart:190` starts `init()` without `await` (it contains `Alarm.init()`,
  `AwesomeNotifications().initialize()`, `setListeners`), and the post-frame callback calls `replan`
  a frame later -> `applyPlannedAlarms` -> `Alarm.getAlarms()`/`Alarm.set()`. If that falls inside
  the init window, the `catch` branches kick in: the T-74e platform reconciliation silently
  disables itself and `Alarm.set` failures are swallowed per alarm - so the FR-18 sync can be
  rendered inert on cold start, exactly on FR-17's reboot-recovery path. Likewise, a silent
  notification created before `setListeners` does not trigger Checkpoint 2.
- **Status:** Resolved 2026-09-10: `Notifications().init()` is now **awaited** in the post-frame callback, before the first checkpoint (and therefore before any `Alarm.set`/`getAlarms` call and before the first notification is created).

### T-80 · The bedtime hook is not re-scheduled after a replan — RESOLVED (2026-09-10)

- [x] Fold `scheduleSleepReminder` into the checkpoint (the same rationale as for
      `applyPlannedAlarms`: no path should be able to compute and then forget).
- **Why:** called from `initState`, the reminder toggle, `onSchedulingSettingsChanged` and
  `onAlarmHandled` - **not** from `runForegroundCheckpointSafely`/`runAlarmRingCheckpoint`. So on
  the resume path (T-68) a replan happens, but the bedtime notification keeps its old time;
  Checkpoint 2 then fires at a moment with no relation to the plan. Same for a native swipe-dismiss
  (without `onAlarmHandled`).
- **Status:** Resolved 2026-09-10: structurally through T-87 - `scheduleSleepReminder()` is now the last step in `runSchedulingCheckpoint()`'s fixed sequence and runs in a `finally`, so a calendar error cannot take FR-16's hook down with it.

### T-81 · FR-9's valve notification repeats on every replan — RESOLVED (2026-09-10)

- [x] Throttle it analogously to T-74a (its own field, or a shared "once per episode" helper).
- **Why:** `replan_notifications.dart:53-63` has no lock, but `safetyValveTriggered` is re-derived
  on every replan. Since nothing rings any more once the valve has tripped (T-78), the notification
  arrives again every time the app is opened on a new day and on every settings change.
- **Status:** Resolved 2026-09-10: new `AppState.safetyValveNotificationSent`; `reportReplanNotifications` now routes FR-6 and FR-9 through a shared `oncePerEpisode` helper. FR-12 is deliberately left unthrottled (a one-off observation, not a standing condition).

### T-82 · `pendingDayValues`/`pendingDayInstantAnchored` grow without bound — RESOLVED (2026-09-10)

- [x] Discard everything older than `lastConcludedDay - 1` on merge.
- **Why:** merging without pruning carries real weight for *today* (comment in
  `replan.dart:137-144`), but nothing is ever removed: after a year, roughly 365 entries sit in a
  JSON string that every replan decodes, copies and re-encodes; `planAlarmSync` and
  `nextWakeUpTime` iterate all of it. Functionally harmless, but monotonically growing - and
  `pendingDayInstantAnchored` behaved
  asymmetrically (there, entries were deleted via `remove`).
- **Status:** Resolved 2026-09-10: the merge now discards entries older than `lastConcludedDay - 1` (the same bound applies to `pendingDayInstantAnchored`, which was previously asymmetric). Yesterday is kept as a safety margin, because a recovery checkpoint reads yesterday as `lastConcludedDay`. Tests additionally confirm that today's not-yet-rung value is preserved.

### T-83 · Inconsistent `isUtc` tagging when reading the same map — RESOLVED (2026-09-10)

- [x] Two named converters (`instantFromStored` -> UTC-tagged for the domain layer,
      `localFromStored` -> `.toLocal()` for plugin/UI) plus `assert(anchor.isUtc)` in
      `computeWeekPlan`/`distribute`.
- **Why:** the same `Map<String,int?>` is read in five places, three times with `isUtc: true`
  (`replan.dart`), twice without (`apply_alarms.dart:86`, `next_wake_up.dart:47`). Today both are
  **correct** - the domain layer requires UTC tagging, while the UI and `ScheduledAlarm.title`
  (`formatDateTime`) require local. That is exactly why it is dangerous: unifying "for consistency"
  would silently shift the display and the alarm title by the device offset.
- **Status:** Resolved 2026-09-10: new `lib/models/scheduling/stored_values.dart` with `instantFromStored` (domain, UTC-tagged), `localFromStored` (platform/display) and `toStored`. All five read sites now use the matching name; there are no raw `DateTime.fromMillisecondsSinceEpoch` calls left outside this module.

### T-84 · T-74e is only half-fixed: tone/volume/gentle-wake do not propagate — RESOLVED (2026-09-10)

- [x] Hook `selectedTone`/`selectedVolume`/`gentleWakeUpEnabled` into `onSchedulingSettingsChanged`
      and extend `planAlarmSync` with a property comparison; add `volume` to `ScheduledAlarm`.
- **Why:** `planAlarmSync` compares only `_toMinute`, and none of the three setters triggers a
  replan - a tone or gentle-wake change only takes effect once a day is replanned for some other
  reason anyway. On top of that, `ScheduledAlarm` has no `volume` field, so every alarm set by
  FR-18 rings at `MyAlarm`'s default of 0.6 and ignores `appState.selectedVolume` (which does have
  a UI).
- **Status:** Resolved 2026-09-10: `ScheduledAlarm` now carries `volume` through (including JSON and `==`; old stored alarms fall back to the default), `applyPlannedAlarms` sets tone/volume/gentle-wake from the AppState, `planAlarmSync` compares them too and replaces alarms that differ, and tone, volume and gentle-wake changes now trigger a checkpoint (volume via `onChangeEnd`, not on every slider step).

### T-85 · Documentation contradicts the code in several places — RESOLVED (2026-09-10)

- [x] (a) `docs/scheduling-v2-spec.md`'s header called T-61 "reopened", carried the UTC+0 caveat and
      said "Phase 6 should only begin after that" - all superseded.
- [x] (b) The architecture block named `timezone_checkpoint.dart` (does not exist), `setSleepReminder()`
      (actually called `scheduleSleepReminder`, in a different file), "four new AppState fields"
      (there are eight), and left `onSchedulingSettingsChanged`, `apply_alarms.dart` (FR-18!),
      `replan_notifications.dart` and `next_wake_up.dart` out of the diagram. FR-3's table listed
      `lastEffectiveWakeTime` as a field (it is derived) and none of the new fields.
- [x] (c) `CLAUDE.md`/`README.md`/`docs/REQUIREMENTS.md` mention scheduling-v2 **nowhere**; the
      testing status lists 4 test files where there are 16, and describes `test/scheduling_test.dart`
      as the scheduling engine's core coverage - that is the file being replaced. The pinned process
      note points at `docs/scheduling-v2-pseudocode.md`, which does not exist.
- [x] (d) FR-16 says Checkpoint 2 hooks off the bedtime moment; in fact the listener fires for
      **every** notification created (including FR-6/9/12 warnings and debug notifications),
      shifting the comparison baseline uncontrollably. Either sharpen FR-16's wording or filter on
      the reminder ID.
- [x] (e) FR-16's DST test suggests the case is fully handled; on the transition day itself, a
      wall-clock-anchored alarm still rings an hour wrong, because the value was computed the day
      before with the old offset and Checkpoint 2 runs at bedtime, still before the transition.
      Document this as a deliberate boundary.
- **Status:** (a), (b), (d), (e) done 2026-09-10 - the header was rewritten (a consolidation section
  instead of a contradictory chronicle), the architecture block and Mermaid diagram brought in line
  with the actual structure, FR-3's table completed (nine fields, `lastEffectiveWakeTime` explained
  as derived), FR-16 extended with the listener clarification and the transition-day boundary. (c)
  remains open until Phase 6, because Phase 6 changes exactly these statements again.
- **Status (c):** done 2026-09-10, after Phase 6. `CLAUDE.md` has a new "Scheduling engine" section
  (layering as a table, plus the two load-bearing rules: no second entry point, and the frame
  convention); the testing status names 176 tests across 19 files and notes that timezone tests must
  build their fixtures as `tz.TZDateTime` (with `DateTime.utc` on a UTC+0 machine, the frame and DST
  bug classes are structurally unreproducible - exactly what the first attempts at T-61 and T-74d ran
  past). `README.md` has an "Alarm scheduling" section in user-facing language; three points were
  struck from the blocker list. `docs/REQUIREMENTS.md` R2 was rewritten from "not met - and more
  fundamentally than unverified" to "met in substance", with the one honest caveat left in place
  (the chain only sustains itself while it keeps ringing - the reboot case is R3) - the summary of
  open gaps no longer lists R2. The reference to the non-existent
  `docs/scheduling-v2-pseudocode.md` only appears in a pinned note outside the repository and is not
  addressable here.

### T-86 · Dead code and orphaned state (inventory for Phase 6) — RESOLVED (2026-09-10)

- [x] `test/scheduling_test.dart` (337 lines, tests only the functions being deleted);
      `Scheduler.nextAlarmTime` and `Scheduler.setScheduledAlarmToNow` (no callers left);
      `AppState._getAlarmTime`'s `ScheduledAlarm` branch (unreachable **and** a latent T-61 trap:
      builds `DateTime(alarm.time.year, ...)`, which would reinterpret UTC digits as local - delete
      it, don't repair it); `wakeUpSteps` (only reader: the old scheduler);
      `rescheduleOnAlarm` (only reader: `onAlarmHandled`, no UI);
      `doNotDisturbEnabled`/`turnOffNotifications`/`turnOffCalls` (**zero** readers, no UI);
      `_MyHomePageState.notifications` (never read); `ScheduledAlarm`'s `title` parameter (always
      overwritten by the constructor).
- **Status:** Done 2026-09-10 (Phase 6). Removed: `test/scheduling_test.dart`,
  `Scheduler.nextAlarmTime`/`setScheduledAlarmToNow` (with the whole file), the unreachable
  `ScheduledAlarm` branch in `AppState._getAlarmTime` (the function now takes a `ManualAlarm` - the
  latent T-61 trap inside it is gone rather than needing repair), `wakeUpSteps`,
  `rescheduleOnAlarm`, `doNotDisturbEnabled`, `turnOffNotifications`, `turnOffCalls` (field, getter,
  setter and load path each), and `ScheduledAlarm`'s inert `title` parameter.
  `_MyHomePageState.notifications` was **not** removed - through T-79 it gained a real reader
  (`await notifications.init()`).

### T-87 · Structural simplification: one checkpoint entry point instead of five — RESOLVED (2026-09-10)

- [x] Merge `replan`, `runAlarmRingCheckpoint`, `onAppForegroundCheckpoint`,
      `runForegroundCheckpointSafely` and `onSchedulingSettingsChanged` into one
      `runSchedulingCheckpoint({required trigger})` with a fixed, complete sequence (lock -> state
      reload -> offset -> replan -> applyPlannedAlarms -> reportReplanNotifications ->
      scheduleSleepReminder).
- **Why:** the five entry points differed along four orthogonal dimensions (write the offset?
  `todayAlreadyRang`? report? re-schedule the reminder? swallow errors?). That exact matrix is what
  produced T-67, T-71 and T-80 - the same bug three times in the same structure. This also resolves
  T-77 (the lock) and T-80 structurally. In addition: bundle the day/date arithmetic into one
  `DayMarker` module (`_midnight`/`_dayMarker`/`_isoDate`/`_dateTimeLike` plus the ad-hoc spots from
  T-76), and put the storage representation behind the converters from T-83.
- **Status:** Implemented 2026-09-10: new `lib/models/scheduling/checkpoint.dart` with `runSchedulingCheckpoint({trigger})` and `runCheckpointSafely(...)`. `runAlarmRingCheckpoint`, `onAppForegroundCheckpoint`, `runForegroundCheckpointSafely` and `onSchedulingSettingsChanged` (along with its file) are gone; their guarantees were ported into `test/checkpoint_test.dart`, where the T-67 reporting path now runs through the real wiring instead of injected seams. Also done: the shared day-marker module (T-76) and the named converters (T-83).

### T-88 · Smaller, confirmed findings — RESOLVED (2026-09-10)

- [x] `platformAlarmTimes` also included `ManualAlarm` times - a `ScheduledAlarm` on the same
      minute was wrongly considered "present on the platform" (one-line fix: only consider known
      `ScheduledAlarm` IDs).
- [x] The "Preferred wake-up time" picker labelled a clock time as a duration (" h", a shared
      `_buildTimePicker`).
- [x] `maxDailyDelta` clamping (15-minute minimum) is invisible to the user; there is no upper
      bound (23:59 effectively disables smoothing).
- [x] `overrunNotificationSent` is set before the `await` - if sending the notification fails, it
      is never retried for the episode.
- **Status:** Resolved 2026-09-10: `planAlarmSync` now compares the platform by **IDs** rather than by times (`platformAlarmIds`) - so a foreign alarm on the same minute no longer covers anything, and the T-61 frame trap disappears entirely at this boundary. The `wunschzeit` picker is labelled as a clock time ("o'clock" instead of " h"), the `maxDailyDelta` minimum is shown as a hint in the UI, and the episode markers are only set after the notification is sent successfully.

### T-63 · scheduling-v2 computes wake times but nothing ever turns them into real alarms — RESOLVED (2026-09-10)

- [x] **Done** (`lib/models/scheduling/apply_alarms.dart`): `planAlarmSync()` (pure) +
      `applyPlannedAlarms()` convert `pendingDayValues` into real `ScheduledAlarm`s, called from
      `replan()` itself so no path can compute a plan without applying it. Tests in
      `test/apply_alarms_test.dart`. Spec gap closed too (new FR-18). Follow-up: T-64.
- **Why:** found while verifying end-to-end functionality after Phase 5. `replan()`
  (`lib/models/scheduling/replan.dart`) computes the whole week correctly and persists it to
  `AppState.pendingDayValues`, but **no code anywhere reads `pendingDayValues`** to create an alarm -
  a repo-wide grep finds only `replan.dart` itself (write + anchor read) and doc comments. Every alarm
  the app actually rings still comes exclusively from the old `Scheduler.scheduleAlarms()`
  (`lib/models/scheduling/scheduling.dart:146`, via `appState.addAlarm()` -> `Alarm.set()`), which
  computes its own times with the old `getStartTimeForDate`/`getEarliestEvent`/`adjustAlarmTimes`
  algorithm and knows nothing about scheduling-v2. Consequences: (1) on a real device today,
  scheduling-v2 is **functionally inert** - it writes a `SharedPreferences` entry nobody consumes, and
  alarm behavior is unchanged from before the whole effort; (2) Phase 6 ("remove the old `Scheduler`")
  would delete the *only* code that sets calendar-derived alarms, so doing it before this item lands
  would leave the app with no calendar-derived alarms at all. `docs/scheduling-v2-spec.md`'s own
  implementation order (Phases 0-7) never contains this step - it is a genuine gap in the plan,
  not just in the code.
- **Evidence:** `grep -rn pendingDayValues lib/` (only `replan.dart` + comments);
  `grep -rn "addAlarm(\|Alarm.set(" lib/` (only `app_state.dart` and the old `scheduling.dart`);
  `docs/scheduling-v2-spec.md` (no FR and no phase step covers applying the computed values).
- **Done when:** a tested step exists that turns each planned day's value into exactly one
  `ScheduledAlarm` (respecting FR-15: never touching `ManualAlarm`s, and FR-11: only for days that
  haven't rung yet), the spec records it as its own FR/phase step, and Phase 6 can remove the old
  `Scheduler` without losing alarm functionality. Note T-61 (UTC+0 assumption) becomes
  **user-visible** the moment this lands - it should be fixed first or at the same time.

### T-62 · Unverified: does a silent background notification actually trigger `onNotificationCreatedMethod`? — TEST WRITTEN, awaiting a real E2E run (2026-09-19)

- [x] Write a device test that can answer the question at all.
- [ ] Confirm on a real/emulated Android device that scheduling a
      `NotificationContent` with neither `title` nor `body` (Phase 5 step 21,
      `sleepReminderContent(reminderEnabled: false)`) actually fires
      `onNotificationCreatedMethod` (`lib/utils/notifications.dart`) at the
      scheduled time, including after the app has been backgrounded.
- **Why:** docs/scheduling-v2-spec.md's own FR-16 "Precondition" section calls this "verified from
  the package source, high confidence" but explicitly recommends (without treating it as a
  TDD blocker) a device confirmation before relying on it - this environment has no Android
  emulator/device, so that confirmation has not happened yet. Everything testable without one
  (`runTimezoneCheckpoint2`'s own logic, `setListeners` being wired with the right callback) is unit
  tested (`test/replan_test.dart`), but the actual OS/plugin behavior triggering the callback for a
  title/body-less notification is unverified.
- **Test written (2026-09-19):** `integration_test/silent_notification_test.dart` schedules a real
  title/body-less notification 15 seconds out through the app's own `Notifications.scheduleNotification`
  (the same production call `scheduleSleepReminder` eventually makes), having first written an
  unreachable sentinel value (`999999`, not a real UTC offset in minutes) into
  `lastCheckedUtcOffsetMinutes` - a key `runTimezoneCheckpoint2` unconditionally rewrites on every
  invocation, regardless of whether a timezone change is found. If that key changes away from the
  sentinel within the wait window, `onNotificationCreatedMethod` demonstrably ran.
  Wired into `.github/scripts/run_e2e_tests.sh`, deliberately **not gating** on its first runs (same
  reasoning as T-93's alarm-survival leg): this exact mechanism has never been measured on the CI
  emulator image before, and an unverified leg must not block a release.
  Honest limit: this proves the callback fires for a real scheduled notification on a real device -
  it does **not** prove FR-16's "including after the app has been backgrounded" clause, since
  simulating a full OS-level background/kill from inside a widget test isn't practical here. That
  remains genuinely unverified.
- **Evidence:** `lib/utils/notifications.dart` (`onNotificationCreatedMethod`, `Notifications.init()`'s
  `setListeners` call); `docs/scheduling-v2-spec.md` FR-16 "Precondition, still to be built";
  `integration_test/silent_notification_test.dart`.
- **Done when:** confirmed on a real/emulated device (the test now exists; its first real run's
  result is still needed), or downgraded from "recommended" if a more direct source confirms the
  behavior without needing a live test.

