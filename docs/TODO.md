# TODOs

The single task list for WakeyWakey, sorted by priority. Two sources feed it:

- **Device feedback** from the maintainer trying the app on real hardware (intake happens in the
  untracked `tasks.txt`; items are moved here once they are formulated as TODOs).
- **The audit** of project description, documentation, requirements, tests and CI against the
  actual code — both its ranked findings and the underlying per-area survey, so that items the
  ranking cut off (most of the licensing ones) are represented here too.

Every item below was checked against the current code before being written down; where a claim
could not be confirmed from the repository it says so instead of asserting it.

Conventions:

- IDs (`T-01` …) are stable. Reference them in commit messages; never renumber an existing one.
- **P0** blocks any push to `master` / production. **P1** must be resolved or consciously accepted
  before a public release. **P2** is real work that does not block a release. **P3** is
  housekeeping.
- `R1`–`R12` refer to [`REQUIREMENTS.md`](REQUIREMENTS.md).
- *Evidence* cites where the problem is visible, so nobody has to re-derive it.
- *Done when* is the acceptance criterion — if it cannot be checked, the TODO is not finished.

---

## P0 — blocks a production push

### T-01 · Sleep-Habits durations are not subtracted from the alarm time

- [ ] Apply "duration to wake up" and "duration to get ready" when deriving an alarm from a
      calendar entry.
- **Why:** the app's central promise. Confirmed on a real device: a calendar entry at 07:00 with
  both durations set to 15 minutes produced an alarm at 07:00 instead of 06:30.
- **Evidence:** device test by the maintainer; scheduling path in
  `lib/models/scheduling/scheduling.dart` and `lib/screens/sleep_habits/screen_sleephabits.dart`.
- **Done when:** a test pins the arithmetic (entry time minus both durations) and the same manual
  scenario produces 06:30 on a device.
- **Requirement:** R2

### T-02 · Calendar-derived alarm times are discarded for most days

- [ ] Fix `_adjustAlarmTimes` so each day keeps its own calendar-derived time, and stop arming the
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
- **Requirement:** R2

### T-03 · The per-alarm enable switch does not stop an alarm

- [ ] Make the `enabled` flag actually cancel/arm the OS alarm, and persist the change.
- **Why:** a user switches an alarm off and it rings anyway. The flag is stored, serialized and
  compared, but never consulted when arming or cancelling.
- **Evidence:** `lib/models/alarms/myalarm.dart:6`; the only reads are constructor pass-throughs
  (`lib/app_state.dart:319`, `:343`), the UI switch (`lib/screens/alarms/screen_alarms.dart:152-155`)
  and `==`. No call site cancels a scheduled alarm.
- **Done when:** toggling an alarm off cancels it in `Alarm.getAlarms()`, survives an app restart,
  and a test asserts both.
- **Requirement:** R3

### T-04 · Alarm survival across reboot and force-stop is unverified

- [ ] Add a real restart scenario to the E2E run, and fix the test that currently claims to cover
      persistence.
- **Why:** for an alarm clock this is the only durability question that matters, and nothing tests
  it. The test named *"a created alarm survives being reloaded from on-device storage"* does not
  touch storage: `SharedPreferences.getInstance()` memoises its instance behind a static
  `Completer`, so rebuilding `AppState` re-reads the same in-process cache. Nothing anywhere
  reboots or force-stops.
- **Evidence:** `integration_test/app_test.dart:186-198`;
  `shared_preferences-2.5.5/lib/src/shared_preferences_legacy.dart:28,79-96` (memoised),
  `:107,129` (in-memory cache), `:223` (`reload()`, never called anywhere in this repo);
  `grep -rniE "reboot|force-stop" .github/` returns nothing.
- **Done when:** the test calls `reload()` (or `resetStatic()`) before re-reading and asserts the
  alarm's time and id plus its presence in `Alarm.getAlarms()`; and a separate scenario
  force-stops (ideally reboots) the device and confirms the alarm still fires with the app not in
  the foreground.
- **Requirement:** R3

### T-05 · A direct dependency is not open source — GPLv3 conflict

- [ ] Decide and document: replace the Syncfusion calendar packages, or change the project's
      licensing/distribution position.
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

### T-06 · The signed release APK is built and published with no quality gate — PARTIALLY RESOLVED (2026-09-09)

- [ ] Demonstrate, with a real deliberately-failing check, that the release build actually stops.
- **Why:** in `ci.yml` the release-build job declared no `needs:`, so it ran regardless of whether
  analyze, tests, SCA, secret scanning or SAST failed; `release.yml` ran no SCA/secret/SAST job at
  all. A red run still produced a downloadable, signed, signature-verified APK that the README
  presented as the production artifact.
- **Evidence (before this fix):** `.github/workflows/ci.yml:123` (no `needs:`), `:183` (the only
  `needs:` in the file); a real run concluded Analyze **failure**, SCA **failure**, mobsfscan
  **failure**, MobSF **failure** and still uploaded three artifacts.
- **Resolution so far:** `build-android-release` in `ci.yml` now declares
  `needs: [analyze-and-test, sca-and-secrets, mobsfscan, e2e-tests]` - a failure in any of those
  now prevents the job from running at all, per GitHub Actions' own `needs:` semantics (not
  demonstrated live with a deliberately-failing check, to avoid sabotaging a real pipeline run for
  the sake of a test; confirmed instead by a real green run where `build-android-release` correctly
  waited for, and only ran after, all four `needs:` had passed - see T-37's verification note).
  MobSF itself (needs the built APK, so it structurally cannot gate the build that produces it) now
  actively revokes the artifact after the fact instead of just marking the run red - see T-11.
- **Still open:** the "deliberately failing check" demonstration itself.
- **Requirement:** R1

### T-32 · The background rescheduling R2 requires does not exist

- [ ] Implement (or formally drop) app-independent rescheduling when fewer than 7 days are armed.
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
- **Requirement:** R2

---

## P1 — resolve or consciously accept before a public release

### T-07 · Swiping the alarm notification away leaves the alarm screen up

- [ ] Dismiss the full-screen alarm UI when the alarm ends through the notification.
- **Why:** confirmed on a real device: pressing *Stop* on the screen clears notification, screen and
  alarm correctly, but swiping the notification away ends the alarm while the screen stays on
  display, leaving the user on a dead overlay.
- **Evidence:** device test by the maintainer; `lib/screens/alarms/screen_active_alarm.dart`,
  `lib/utils/notifications.dart`, and the ringing subscription in `lib/main.dart:215-225`.
- **Done when:** the overlay closes on any path that stops the alarm, and the ringing-stream
  handler covers the notification-dismissal case.

### T-08 · The QR deactivation gate has no negative test — PARTIALLY RESOLVED (2026-09-09)

- [ ] Cover the remaining bypass: the first scanned code being silently adopted as the deactivation
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
- **Still open:** the *other* null-code bypass - `_handleBarcode`'s "import this code if none is
  set" branch (`qr_scanner.dart:126-133`) - is stateful (mutates `_appState` directly inside
  `setState`) and was not extracted or tested in this pass.
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

### T-14 · Per-weekday repeat is inert

- [ ] Consult `repeatOnDays` when scheduling, or remove the control.
- **Why:** the selector is editable and persisted but never read when deciding when to fire, so
  manual alarms are effectively one-shot (today or tomorrow) while the UI promises a weekly
  pattern.
- **Evidence:** `lib/models/alarms/manual_alarm.dart:7,17-19,25,39,53-54,74` and
  `lib/app_state.dart:323` are construction, serialization and comparison only — no scheduling
  decision reads it.
- **Done when:** an alarm set to repeat on specific weekdays fires on exactly those days, covered
  by a test over the production scheduling function.

### T-15 · The gentle-wake ramp has no evidence of any kind — RESOLVED for the doc route (2026-09-08)

- [x] State plainly that it is unverified (the alternative to actually exercising the fade path).
- **Why:** a headline feature and half of R4. Gentle wake defaults to off, so no test enables it and
  the `VolumeSettings.fade` branch is never executed; the CI emulator also runs without audio. The
  audio-focus log does show the app taking alarm-usage audio focus, which is genuine but says
  nothing about a gradual ramp.
- **Evidence:** `lib/app_state.dart:44` (`_gentleWakeUpEnabled = false`), `:485-489` (fade vs.
  fixed), `lib/screens/alarms/screen_alarms.dart:263` (dialog default);
  `grep -niE "gentle|fade|volume" integration_test/app_test.dart` → nothing; emulator started with
  `-noaudio`; 3 of 249 audio-focus polls show `usage=USAGE_ALARM`.
- **Resolution:** `docs/REQUIREMENTS.md` R4 now states plainly that the ramp is never exercised and
  only the fixed-volume path is covered. Adding an actual E2E scenario for the fade path (the other
  half of this TODO's "done when") remains open and is a code change, out of scope for this pass.
- **Requirement:** R4

### T-16 · The QR test seam does not isolate the camera, and ships in release builds

- [ ] Make the override actually bypass the camera, and keep it out of the release binary.
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
  `lib/screens/schedule/calendar.dart:91`) - the app currently only *reads* the calendar, and
  `READ_EXTERNAL_STORAGE` is declared but never actually requested at runtime
  (`lib/utils/permissions.dart` requests only exact-alarm, notification, camera and calendar) -
  consistent with T-44's dead gallery-import button.
- **Resolution:** `assets/text/Privacy.md` rewritten to describe calendar reads, camera use for QR
  scanning, and locally stored alarms/settings/deactivation code; the location/NFC claim removed; a
  line added disclosing the plugin-derived `INTERNET` permission and that it sends nothing. R11 in
  `docs/REQUIREMENTS.md` corrected to state what the original review actually covered.
- **Requirement:** R11

### T-33 · Proprietary Google/ML Kit binaries are a second GPLv3 exposure

- [ ] Assess the licence position of the barcode-scanning stack alongside T-05.
- **Why:** T-05 covers Syncfusion, but the QR feature itself links proprietary Google binaries:
  `mobile_scanner` pulls `play-services-mlkit-barcode-scanning` and `com.google.mlkit:barcode-scanning`,
  which ship under Google's terms rather than an open-source licence. For a GPLv3 work these raise
  the same "no further restrictions" question, and this one sits directly under the app's headline
  feature — so it cannot be resolved by swapping a calendar widget.
- **Evidence:** `mobile_scanner-7.4.0/android/build.gradle:66,69`.
- **Done when:** a tracked decision records the licence basis for the whole shipped dependency set,
  not just Syncfusion.
- **Requirement:** R8, R9

### T-34 · GPLv3 source-offer obligations are unaddressed for the distributed APK

- [ ] Decide how Corresponding Source is provided to anyone who receives the APK.
- **Why:** the release workflow attaches a signed APK to a GitHub Release while the repository is
  private, and nothing publishes or offers the corresponding source. Conveying a GPLv3 binary
  carries that obligation; right now there is no mechanism and no written position.
- **Done when:** either the repository is public at release time, or the release carries a written
  source offer that someone could actually act on.
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
- **Still open:** whether GitHub now detects `GPL-3.0` needs confirming after this change is pushed
  (detection re-runs on push, not retroactively); and the app itself still has no in-app licence/
  notices screen to carry the copyright to an end user - that's T-36, unchanged by this fix.
- **Requirement:** R9

### T-36 · The app has no third-party licence or notice surface

- [ ] Add a licences screen (e.g. `showLicensePage`) reachable from the About page.
- **Why:** Flutter embeds the dependency notices in the binary, but nothing in the app displays
  them, so the notice-retention obligations of the BSD/MIT/Apache dependencies — and GPLv3's own
  requirement to make the licence available to the user — are not met in the shipped product.
- **Evidence:** `grep -rn "showLicensePage\|LicensePage\|NOTICES" lib/` → 0 hits.
- **Done when:** a user can read the licence and third-party notices from inside the app.
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

### T-38 · The QR gate has unconditional bypasses

- [ ] Decide, document and test the fail-safe paths that dismiss an alarm without a scan.
- **Why:** the "guaranteed wake-up" promise has escape hatches: if no overlay can be shown, the
  handler waits three seconds and calls `Alarm.stopAll()`; the scanner also offers an emergency-stop
  button when the camera fails. These are defensible as fail-safes — being locked out by a broken
  camera is worse — but they are undocumented, untested, and not mentioned where the feature is
  advertised.
- **Evidence:** `lib/models/alarms/handler.dart:169-176`;
  `lib/screens/scan_code/qr_scanner.dart:277-285,310-317`.
- **Done when:** each bypass has a test, a written rationale, and an honest sentence in the feature
  description.
- **Requirement:** R4

### T-39 · The QR gate is enforced only in the Flutter UI layer

- [ ] Make alarm dismissal depend on validation somewhere the UI cannot bypass.
- **Why:** the whole gate hangs off one `Alarm.ringing` subscription in the home widget plus a
  `context.mounted` check. If that widget is not alive when an alarm fires, nothing enforces the
  scan requirement — the strength of the app's differentiating feature depends on widget lifecycle.
- **Evidence:** `lib/main.dart:215-225`; `lib/models/alarms/handler.dart:140,154`.
- **Done when:** the requirement is enforced independently of which widget happens to be mounted,
  or the limitation is documented as accepted.
- **Requirement:** R4

### T-40 · No CI check is actually enforceable — BLOCKED ON A MAINTAINER DECISION (2026-09-09)

- [ ] Decide how the "must pass before master" rule is enforced, given the repository's plan.
- **Why:** the requirements register says its checks must be guaranteed "before any push to
  `master`", but branch protection and rulesets are unavailable on this private repository's plan,
  every commit so far went straight to `master` with zero pull requests, and CI runs after the push
  anyway. A red run cannot stop anything. This undercuts T-06 and T-11: gating the release build is
  necessary but not sufficient while nothing can block a push.
- **Evidence:** `gh api …/branches/master/protection` and `…/rulesets` both return 403
  ("Upgrade to GitHub Pro or make this repository public"); `gh pr list --state all` is empty.
- **Not actioned tonight, deliberately:** both routes to "done" here - making the repository public,
  or upgrading its GitHub plan - are account/visibility decisions with real consequences (a private
  repo becoming publicly readable, or a billing change) that only the maintainer should make. This
  item is intentionally left for a maintainer decision rather than resolved unilaterally.
- **Done when:** either the repository is public/upgraded and protection is on, or the register says
  plainly that enforcement is by maintainer discipline.
- **Requirement:** R1

### T-41 · Permissions are requested before the privacy policy is reachable

- [ ] Present the data-handling information before or alongside the first permission prompt.
- **Why:** calendar, camera, exact-alarm and notification permissions are all requested from the
  splash screen at first launch, while the privacy policy is only reachable later through Settings.
  For a project claiming GDPR alignment, the transparency step comes after the consent step.
- **Evidence:** `lib/main.dart:136-153` (splash-screen permission flow);
  `assets/text/Privacy.md` reachable only via the About page.
- **Done when:** a first-run user can read what is collected before granting anything.
- **Requirement:** R7, R11

### T-49 · Requirement claims about permissions do not match the built APK — PARTIALLY RESOLVED (2026-09-08)

- [ ] Name every permission the shipped app actually holds, and capture traffic during an E2E run.
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

### T-18 · Add a snooze button with configurable limits

- [ ] Implement snooze, plus Sleep-Habits settings for maximum snooze count and interval.
- **Why:** requested feature; the ringing UI currently offers only stop.
- **Done when:** snoozing re-arms the alarm after the configured interval, stops after the
  configured maximum, and both settings persist.

### T-19 · Merge "duration to wake up" and "duration to get ready" into one field

- [ ] Collapse the two durations into a single value.
- **Why:** requested; distinguishing them adds no value to the user. Coordinate with T-01, which
  fixes how they are applied.
- **Done when:** one field drives the calculation, and existing stored values migrate without
  producing a wrong alarm time.

### T-20 · Add explanatory help buttons to every Sleep-Habits option

- [ ] Put a "?" button in the top-right of each Sleep-Habits element showing a short explanation.
- **Why:** requested; the options are not self-explanatory.
- **Done when:** every option has one, the text is concise enough to read on a phone, and the
  styling follows the existing elements.

### T-21 · Write a user manual

- [ ] A complete version under `docs/`, and a minimal one in the README.
- **Why:** requested; there is no usage documentation beyond four bullet points.
- **Done when:** the manual covers every screen and control that the GUI exposes.

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

### T-27 · The global volume setting never reaches calendar-derived alarms

- [ ] Thread the configured volume through to scheduled alarms.
- **Why:** `ScheduledAlarm` takes no volume, so calendar-derived alarms always ring at the hardcoded
  default regardless of the user's setting — while manual alarms honour it.
- **Evidence:** `lib/models/alarms/scheduled_alarm.dart` (no volume field) vs
  `lib/models/alarms/manual_alarm.dart` and the volume default in `lib/app_state.dart`.
- **Done when:** a calendar-derived alarm rings at the configured volume, asserted by a test.

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

### T-42 · Six persisted settings are unreachable or unused

- [ ] Wire them up or remove them.
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

### T-43 · The gentle-wake ramp duration is hardcoded

- [ ] Make the fade duration configurable, or state that it is fixed.
- **Why:** the whole tuning surface of a headline feature is `const Duration(seconds: 60)`. The one
  user-facing duration that sounds related ("duration to wake up") feeds scheduling, not the ramp —
  so a user adjusting it changes something else entirely.
- **Evidence:** `lib/app_state.dart:487`.
- **Done when:** the ramp length is either a setting or documented as fixed at 60 seconds.

### T-44 · A dead gallery-scan button would bypass the camera gate if wired in

- [ ] Remove `AnalyzeImageFromGalleryButton`, or gate it so it cannot dismiss an alarm.
- **Why:** the widget picks an image from the gallery and runs it through the scanner. It is
  currently never instantiated, but it sits in the scanner's own button file — wiring it into the
  alarm-dismissal scanner would let a screenshot of the QR code dismiss the alarm, defeating the
  "physical code in another room" premise. It is also the reason the app requests gallery access.
- **Evidence:** `lib/screens/scan_code/scanner_button_widgets.dart:5-49`; no instantiation anywhere
  in `lib/`.
- **Done when:** the code is gone, or it exists only on the import screen and cannot reach the
  dismissal path.
- **Requirement:** R4

### T-45 · A failure loading preferences can still prevent the app from starting

- [ ] Bring the `SharedPreferences.getInstance()` call inside the guard its own comment promises.
- **Why:** `_loadFromPreferences` carries a comment stating that a failure must never throw out of
  the method, because `main()` awaits initialisation before `runApp` — but the `getInstance()` call
  itself sits outside the `try`. If it throws, the app does not start at all, which for an alarm
  clock means every armed alarm is silently unreachable.
- **Evidence:** `lib/app_state.dart:660` (call), `:661-665` (the comment), `:666` (`try` starts
  after).
- **Done when:** a preferences failure degrades to defaults instead of blocking launch, covered by a
  test.
- **Requirement:** R3

### T-46 · The scheduling window is hardcoded

- [ ] Make the forward window, preload range, and estimate-abort threshold configurable, or justify
      the constants.
- **Why:** scheduling covers a fixed 7-day forward window, the preload is a hardcoded two past / one
  future week, and `_adjustAlarmTimes` aborts scheduling entirely once 7 alarms needed estimating -
  none of the three is user-changeable. `lib/main.dart`'s old TODO backlog named exactly these three
  as unfinished (`0x49`, `0x392`, `0x395` - see T-31); they were not separately re-tracked because
  they are this same gap.
- **Evidence:** `lib/models/scheduling/scheduling.dart:54` (window), `:169` (`>= 7` threshold);
  `lib/main.dart:242` (preload).
- **Done when:** the ranges/threshold are either settings or documented as deliberate constants with
  a reason.

---

### T-50 · Manual alarms don't respect two global settings

- [ ] Make manual alarms honor the vibration switch, and clarify/implement "respect time of day
      change".
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31). Two distinct gaps: (a)
  there is a global vibration setting that manual alarms don't apply (no `vibration` field is
  threaded through `ManualAlarm`/`MyAlarm`) - `lib/screens/alarms/screen_alarms.dart`'s alarm editor
  has no vibration control at all, so this needs a settings-model change too, not just a scheduling
  fix; (b) "respect time of day change" is not specified precisely enough in the original note to
  know what behavior is wanted - possibly reacting to a live system clock/DST change while an alarm
  is already scheduled. Clarify the intent before implementing (b).
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, item `0x502`/`0x503` (see T-31).
- **Done when:** (a) a vibration switch exists and manual alarms honor it, covered by a test; (b) is
  either implemented with a test, or dropped with a written reason.

### T-51 · Theme does not follow the system light/dark setting

- [ ] Add a "follow system" option alongside the existing manual dark-mode toggle.
- **Why:** `MyApp.build` sets `themeMode` from `appState.darkMode` (a manual boolean), never
  `ThemeMode.system` - so the app cannot automatically match the OS theme, only be switched by hand.
- **Evidence:** `lib/main.dart:106-108`; `lib/app_state.dart`'s `darkMode` getter/setter.
- **Done when:** a "system" option exists in Settings > Appearance and actually drives `themeMode`,
  covered by a widget test.

### T-52 · Several scheduling/sleep-habit options are hardcoded, not user-configurable

- [ ] Add settings for: scheduling (or not) on days without calendar entries, 24h-vs-AM/PM display,
      and a per-weekday "duration to get ready".
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31), the parts of it not
  already covered by T-42/T-43/T-46. Today: a day with no calendar entries always gets the 23:59
  placeholder-or-estimate treatment (see T-02) with no way to opt out per day; times are always
  displayed in one fixed format; and "duration to get ready" is a single global value with no
  per-weekday override, unlike `repeatOnDays` which is at least per-weekday (T-14).
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, items `0x393`, `0x398`, `0x399` (see T-31).
- **Done when:** each option is either implemented (with a test) or explicitly dropped with a
  written reason.

### T-53 · No way to choose which calendar counts as "the work calendar"

- [ ] Let the user select which calendar(s) feed the scheduling algorithm.
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31). `use-cases.md` describes
  "Select Calendar for interconnection" as a use case, but no per-calendar selection UI exists -
  `grep -rn "workCalendar\|selectedCalendar" lib/` finds nothing, and `calendar.dart`'s
  `retrieveCalendars()` result is used without a filtering step.
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, item `0x48` (see T-31);
  `lib/screens/schedule/calendar.dart`.
- **Done when:** a calendar-selection UI exists and `scheduleAlarms` only considers entries from the
  selected calendar(s), covered by a test.

### T-55 · Possible stale-data race when opening the Schedule screen before preload finishes

- [ ] Verify whether this is still reproducible, then fix or close it.
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31): "wrong scheduled alarm
  infos if opening scheduled alarm page before preloading finished" and "duplicate calendar entries
  for preloaded weeks (on first load only?)". `screen_schedule.dart` does guard on
  `appState.calendarsInitialized`/`firstUpdateOfCalendar`, which may already mitigate this - it was
  not re-verified against a live race during this triage pass, only read statically.
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, items `0x461`/`0x462` (see T-31);
  `lib/app_state.dart`'s `calendarsInitialized`/`firstUpdateOfCalendar`;
  `lib/screens/schedule/screen_schedule.dart:234,291`.
- **Done when:** a test reproduces the race (or confirms it no longer occurs) by opening the
  Schedule screen concurrently with `preloadCalendarData`.

### T-57 · No fallback scheduling target when there are no calendar entries at all

- [ ] Decide and implement what should happen when `scheduleAlarms` finds zero calendar entries.
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

### T-29 · Record the provenance and licence of bundled assets

- [ ] Track down where `assets/sounds/*.mp3` and the icon assets came from, and under what licence.
- **Why:** R10 is unverified and no record exists. Needed before public distribution, and it
  interacts with T-05.
- **Done when:** every bundled asset has a documented source and licence, or is replaced.
- **Requirement:** R10

### T-30 · Annotate or retire the planning artifacts — PARTIALLY RESOLVED (2026-09-08)

- [x] ~~Annotate the risk graphic~~ - **ersetzt** statt annotiert: `docs/risk.png` ist seit
      2026-09-10 ein echtes Threat Model, erzeugt aus `docs/threat-model.svg` (siehe T-101).
- [ ] Annotate the UML diagram (or retire it) - das steht noch aus.
- **Why:** the descriptive documents miss the app in both directions: the README's three headline
  features understate the shipped surface, while `personas.md`, the UML diagram and `risk.png`
  still model features and classes that were never built and carry no annotation saying so.
  `use-cases.md` stated that everything unmarked shipped, which was not the case.
- **Resolution so far:** `use-cases.md` annotated inline (the "Disable alarm" switch is a no-op;
  "Manage/Disable Deactivation Codes" only has Generate/Remove for a single code, no separate
  disable; "Print as QR Code" is only partially implemented - the code renders on-screen, but
  share/print is an explicit "future feature" stub) and its blanket top-note corrected to
  acknowledge shipped-but-broken items as a third category, tracked in `docs/TODO.md` rather than
  as planning gaps. `personas.md` given its own annotation note plus a specific correction to Tom's
  jetlag/timezone claim (the app only reads the device's current timezone; there is no dedicated
  jetlag-adjustment feature). `choice-of-technologies.md` annotated on its iOS cross-platform claim
  (unverified - iOS has never been built or run).
- **Still open:** `risk.png` (a diagram modelling a since-abandoned NFC deactivation component) and
  `UML_WakeyWakey.drawio` are images/diagrams and were not annotated in place; `CLAUDE.md`'s
  "Project documentation" section now points at this TODO instead, but that is a pointer, not an
  annotation on the artifacts themselves.
- **Done when:** each planning document either matches the code or says plainly where it does not.

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

### T-48 · No source file carries a licence header

- [ ] Decide whether to add per-file GPLv3 notices.
- **Why:** none of the Dart sources carry a copyright or licence header, so a file copied out of the
  repository loses any licence trace. This is recommended GPLv3 practice rather than a strict
  requirement — the point is to make it a recorded decision instead of an oversight.
- **Done when:** either headers exist, or a tracked note says they were deliberately omitted.
- **Requirement:** R9

### T-54 · No custom Android notification icon

- [ ] Set a proper small icon for the alarm/reminder notifications instead of the default.
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31). `Notifications`'s channel
  setup passes `null` for the icon, so Android falls back to the app's launcher icon (or a generic
  system icon, depending on OS version) rather than a purpose-made small monochrome notification
  icon.
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, item `0x511` (see T-31);
  `lib/utils/notifications.dart:11`.
- **Done when:** a proper notification icon asset exists and is wired up.

### T-56 · Alarm tones are a static bundled list

- [ ] Source available tones dynamically (e.g. from device storage or a user-added set) instead of
      a fixed list.
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31) - a nice-to-have, not a
  bug; the current static list works, it's just inflexible.
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, item `0x55` (see T-31);
  `lib/screens/settings/page_alarmtones.dart`.
- **Done when:** either implemented, or explicitly deprioritised with a reason.

### T-58 · Consider a toast instead of a notification for some feedback

- [ ] Decide where (if anywhere) a toast would be more appropriate than the current notification.
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31) - a UX design question,
  not a defect, and under-specified (which notification(s) it refers to was never recorded).
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, item `0x52` (see T-31).
- **Done when:** either a specific notification is identified and changed, or this is closed as "no
  change wanted" with a reason.

### T-59 · `AppState`'s calendar meetings are not modeled as a proper 1:n map

- [ ] Refactor the internal meetings data structure.
- **Why:** carried forward from `lib/main.dart`'s old TODO backlog (T-31) - an internal data-model
  cleanup with no user-visible effect, lowest priority of the carried-forward items.
- **Evidence:** `lib/main.dart`'s pre-triage TODO block, item `0x45` (see T-31); `AppState`'s
  meetings-related fields.
- **Done when:** the refactor is done and existing tests (once T-10 exists) still pass, or this is
  closed as not worth the churn.

### T-60 · Calendar data is cached forever per week, never re-fetched for the app's lifetime

- [ ] Fix `_fetchedCalendarWeeks` (`lib/app_state.dart:28`) to actually reflect whether a week's
      events were fetched, and/or add a way to force a fresh re-read.
- **Why:** found while checking scheduling-v2's feasibility (`docs/scheduling-v2-spec.md` FR-11/
  FR-12). `preloadCalendarData` (`lib/utils/utils.dart:82-109`) marks 2 past + 1 future week as
  "fetched" in `_fetchedCalendarWeeks` at startup, but only ever actually calls `retrieveEvents` for
  the single week containing "now" - the other weeks are marked fetched without ever having been
  fetched. Once a week-start-date is in `_fetchedCalendarWeeks`, `updateCalendarData`
  (`screen_schedule.dart:257-`) skips fetching it again for as long as the process lives, since
  nothing anywhere ever clears or reassigns that list. A calendar edit for a day already in this set
  is silently invisible to the app until the next process restart - this affects the *current*
  Syncfusion-based schedule display today, and would silently break scheduling-v2's FR-11
  revisability and FR-8's daily replanning if they reused this same path.
- **Evidence:** `lib/app_state.dart:28` (`_fetchedCalendarWeeks` field, never cleared/reassigned
  anywhere else in `lib/`); `lib/utils/utils.dart:82-109` (`preloadCalendarData`, marks weeks fetched
  without fetching them); `lib/screens/schedule/screen_schedule.dart:257-` (`updateCalendarData`,
  gates every fetch behind `appState.isCalendarWeekFetched`, `app_state.dart:635-656`).
- **Done when:** either `_fetchedCalendarWeeks` is correctly invalidated (e.g. time-boxed, or
  cleared on app foreground/a manual refresh), or - for scheduling-v2 specifically - the new
  scheduling engine is confirmed to bypass this cache entirely and call `retrieveEvents` directly
  on every replan, never through `updateCalendarData`.

### T-61 · scheduling-v2's wall-clock arithmetic assumes `deviceUtcOffset == 0`

- [x] **Behoben (2026-09, zweiter Anlauf).** Der erste Anlauf hatte nur die halbe Ursache erfasst:
      `applyGapDayDrift`/`coldStart` offset-bewusst zu machen war richtig, aber die Einschätzung
      "`distribute`/`groupTarget` sind frame-invariant" war falsch - `_wallClockDelta` vergleicht
      **Ziffernfelder**, und `hardFloor` gab `Meeting.from` als `TZDateTime` in der **Termin-Zone**
      weiter, während jeder andere Wert UTC-getaggt war. Empirisch nachgewiesen (Probe mit echtem
      `TZDateTime`): Termin 09:00 Europe/Berlin ergab eine Weckzeit zwei Stunden zu spät.
      Jetzt behoben an **vier** Frame-Grenzen, alle mit `TZDateTime`-Fixtures abgesichert
      (`test/scheduling_v2_tz_test.dart`, inkl. `tz.initializeTimeZones()` - die Infrastruktur, die
      der Teststruktur-Plan verlangte und die vorher fehlte):
  1. `hardFloor` normalisiert seinen Rückgabewert per `.toUtc()` - gleicher realer Moment
     (FR-1/FR-16: der Termin verschiebt sich nicht), aber im gemeinsamen Frame der Schicht.
  2. `AppState._setAlarm` nutzt das neue `alarmPlatformTime()` (`lib/utils/utils.dart`): erst
     `.toLocal()`, dann minutengenau - vorher wurden UTC-Ziffern als lokale Uhrzeit interpretiert und
     der Alarm klingelte um den Versatz zu früh (FR-18s Grenze zum Plugin, geplante Testebene 4).
  3. `scheduleSleepReminder` übergibt den Schlafenszeit-Zeitpunkt ebenfalls über
     `alarmPlatformTime()` - `NotificationCalendar.fromDate` liest lokale Ziffern, sonst hätte FR-16s
     Checkpoint 2 zur falschen lokalen Zeit gefeuert.
  4. `planAlarmSync`s `_toMinute` normalisiert beide Seiten nach UTC und die Funktion normalisiert
     die übergebene Plattform-Menge selbst - der Vergleich lief sonst zwischen UTC-Planwerten und
     lokalen `AlarmSettings.dateTime`, hätte also auf jedem Gerät außerhalb UTC+0 jeden korrekt
     gesetzten Alarm für "fehlt auf der Plattform" gehalten und bei jedem Replan neu gesetzt.
- **Hinweis für künftige Arbeit:** die letzten zwei Grenzen (3 und 4) wurden erst durch Fix 1 und 2
  sichtbar - wer hier etwas ändert, sollte prüfen, ob ein Wert die Domänenschicht verlässt und dabei
  von einem Plugin als *lokale Wall-Clock* gelesen wird. Genau dort liegt diese Fehlerklasse.
- [x] **Ebene 5 (FR-16-Reinterpretation) ebenfalls erledigt** - damit ist Phase 5 vollständig:
      `computeWeekPlan` liefert jetzt `instantAnchoredDays` (Tage, deren Wert direkt aus einem echten
      `hardFloor` stammt), `replan()` persistiert das als `AppState.pendingDayInstantAnchored`
      (gleiches direkt-über-SharedPreferences-lesbares Format wie `pendingDayValues`, weil
      Checkpoint 2 im Hintergrund-Isolate läuft), und `runTimezoneCheckpoint2` reagiert auf einen
      erkannten Versatzwechsel: ziffern-verankerte, noch nicht geklingelte Werte behalten per
      `reinterpretForNewOffset` ihre lokalen Ziffern, instant-verankerte ihren Instant, bereits
      vergangene bleiben unangetastet (FR-11). Checkpoint 1 braucht das bewusst nicht - der direkt
      folgende Replan rechnet alles neu und wendet es per FR-18 an. Tests: `test/replan_test.dart`
      (Checkpoint-2-Gruppe), `test/scheduling_v2_test.dart` (`instantAnchoredDays`),
      `test/app_state_scheduling_v2_test.dart` (Persistenz).
- **Verbleibende, bewusst akzeptierte Grenze:** Checkpoint 2 korrigiert den gespeicherten Plan, nicht
  die bereits an die Plattform übergebenen Alarme - FR-16 verschiebt die vollständige Neuberechnung
  ausdrücklich auf den nächsten regulären Planungslauf. Ein Alarm, der zwischen Versatzwechsel und
  nächstem Replan feuert, nutzt also noch den alten Zeitpunkt.
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
  semantics (`hardFloor` values must stay a genuine, unconverted instant per FR-16 - "nur die lokale
  Anzeige ändert sich"; `wunschzeit`/drift-derived values are digit-snapshots that need active
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
- **Geplante Teststruktur** (entworfen 2026-09, noch nicht umgesetzt):
  - **Erst die Semantik entscheiden, dann testen** - ein Test kodiert die Antwort, also muss sie
    vorher stehen: Empfehlung ist "die gesamte Domänenschicht rechnet in geräte-lokaler Wall-Clock",
    d. h. `hardFloor()` rechnet den Termin-Instant per `deviceUtcOffset` in die Gerätezone um, *bevor*
    die Dauern abgezogen werden. FR-2 braucht dazu einen Satz, und FR-16s Instant-vs-Wall-Clock-
    Aufteilung muss gegen diese Entscheidung neu geprüft werden (was persistiert, was reinterpretiert
    wird).
  - **Neue Test-Infrastruktur:** bisher initialisiert *kein* Test Zeitzonendaten. Nötig:
    `tz.initializeTimeZones()` (via `package:timezone/data/latest.dart`) in `setUpAll`, plus ein
    Fixture-Helper `_meetingInZone('Asia/Tokyo', …)`, der - wie `device_calendar` in Produktion -
    ein `tz.TZDateTime` in der **termin-eigenen** Zone liefert (`TZDateTime implements DateTime`, ist
    also direkt als `Meeting.from` verwendbar). `deviceUtcOffset` bleibt immer explizit, die
    Systemzeitzone der Testmaschine darf nie einfließen (FR-2 "Testbarkeit").
  - **Ebene 1 - `eventsForDay`/`hardFloor` mit `deviceUtcOffset != 0`** (die fehlende Dimension):
    gleiche Zone wie Gerät; termin-fremde Zone (Toms Tokyo-Termin bei Gerät in Berlin - geprüft wird
    diesmal der *Rückgabewert*, nicht nur die Tageszuordnung); Sommerzeit-Grenztag.
  - **Ebene 2 - Frame-Mischung in der Arithmetik** (der eigentliche Bug, hier zuerst rot):
    `groupTarget`/`distribute` mit Anker aus einem `wunschzeit`-Wert und Ziel aus einem
    termin-fremden `hardFloor` → ΔT muss die geräte-lokale Differenz sein; analog
    `applyGapDayDrift`.
  - **Ebene 3 - `computeWeekPlan` integriert:** (a) Invarianz-Eigenschaft: sind alle Termine in der
    Gerätezone, müssen die geplanten Wall-Clock-Ziffern **unabhängig** von `deviceUtcOffset` sein -
    dieselben Zahlen wie die heutigen UTC+0-Tests; (b) Toms Szenario mit gemischten Zonen.
  - **Ebene 4 - FR-18/echte Alarme:** nach einer Planung unter `deviceUtcOffset != 0` muss der
    gesetzte Alarm auf dem *richtigen realen Instant* liegen (nicht nur die richtigen Ziffern haben) -
    fängt einen falschen Frame an der Grenze zu `Alarm.set()`.
  - **Ebene 5 - FR-16-Wechselwirkung:** nach einem Versatzwechsel muss ein `wunschzeit`-abgeleiteter
    Wert seine **Ziffern** behalten (hier bekommt `reinterpretForNewOffset` endlich eine echte
    Aufgabe), ein `hardFloor`-abgeleiteter dagegen seinen **realen Instant** (der Termin verschiebt
    sich nicht). Diese beiden Zusicherungen dürfen nicht verwechselt werden - sie sind der eigentliche
    Prüfstein für FR-16s zwei Kategorien.
  - **Reihenfolge:** Ebene 2 zuerst (schlägt gegen den heutigen Code fehl und beweist den Bug), dann
    Ebene 1 (Fix in `hardFloor`), dann Ebene 3a als Invarianz-Wächter, dann Ebene 4 und 5.
  - **Bewusst nicht unit-testbar:** ein echter Zeitzonenwechsel des Geräts (Flugmodus/Reise) - das
    bleibt `integration_test` bzw. eine manuelle Geräteprüfung, wie bei T-62.
- **Second thing to fix together with this:** `runTimezoneCheckpoint2` writes
  `lastCheckedUtcOffsetMinutes` straight to `SharedPreferences` from the background isolate, but a
  *live* `AppState` in the main isolate keeps its own in-memory copy and never re-reads it - so that
  write is invisible to (and gets overwritten by) the running app. Harmless today, because nothing
  yet branches on the comparison's outcome and both checkpoints write "the offset as of now"; it
  becomes a real missed-detection path the moment a reinterpretation step depends on the previously
  stored value.

### T-67 · FR-6/FR-9/FR-12: die Warn-Flags werden auf zwei von drei Pfaden verworfen

- [x] **Behoben** (`lib/models/scheduling/replan_notifications.dart`): `reportReplanNotifications()`
      wird jetzt von allen drei Pfaden gerufen (Ring, FR-17-Erholung, Einstellungsänderung), jede
      Meldung hat ihr eigenes try/catch (T-74b), und FR-6 meldet nur einmal pro Overrun-Episode
      (T-74a, neues Feld `AppState.overrunNotificationSent`). Tests:
      `test/replan_notifications_test.dart`.
- **Why:** nur `Handler._runReplanCheckpointSafely` (`handler.dart:81-89`) übersetzt die Flags in
  Benachrichtigungen. `runForegroundCheckpointSafely` (`replan.dart:245`) und
  `onSchedulingSettingsChanged` (`settings_changed.dart:37`) verwerfen den Rückgabewert. Für FR-12 ist
  der Verlust **dauerhaft**, nicht nur verzögert: das Flag entsteht nur innerhalb von
  `if (needsDayAdvance)`, und `replan` setzt danach `lastReplanDate = ringDay` - der abendliche
  echte Ring findet also `needsDayAdvance == false` und meldet nie mehr. FR-12 nennt FR-8 **oder**
  FR-17 ausdrücklich als Auslöser.
- **Done when:** alle drei Flags werden auf jedem Pfad gemeldet, mit Test.

### T-68 · FR-17 greift nie bei einem echten Vordergrund-Wechsel

- [x] **Behoben** (`lib/main.dart`): `didChangeAppLifecycleState` löst bei
      `AppLifecycleState.resumed` `runForegroundCheckpointSafely` aus - der zuvor tote
      `addObserver`-Aufruf hat damit eine Wirkung. Idempotent durch FR-17s eigene Sperre.
- **Why:** `_MyHomePageState` deklariert `with WidgetsBindingObserver` (`main.dart:155`) und ruft
  `addObserver(this)` (`main.dart:164`), überschreibt aber `didChangeAppLifecycleState` nicht - der
  Observer ist toter Code. Der einzige Aufruf steht im `addPostFrameCallback` von `initState`
  (`main.dart:207`), greift also nur beim erstmaligen Mounten (Kaltstart). Das deckt FR-17s
  Reboot/Force-Quit ab, aber nicht den dritten dort genannten Fall ("ein App-Öffnen zwischendurch
  ist ein zusätzlicher, günstiger Gelegenheits-Neuread"). Besonders relevant, weil nach Auslösen des
  FR-9-Sicherheitsventils kein Alarm mehr klingelt - der Ring-Checkpoint als Erholungspfad fällt
  damit weg. Nebenbefund: "sofort, vor jeder UI-Interaktion" ist durch den Post-Frame-Callback
  ebenfalls nicht erfüllt.

### T-69 · Checkpoint 2s Reinterpretation wird vom veralteten AppState zurückgedreht

- [x] **Behoben**: neues `AppState.reloadSchedulingStateFromPreferences()` (mit `prefs.reload()`)
      wird als erste Anweisung jedes `replan()` aufgerufen - ein Schreibzugriff aus dem
      Hintergrund-Isolate wird damit nicht mehr von einer veralteten In-Memory-Kopie überschrieben.
- **Why:** `runTimezoneCheckpoint2` schreibt `pendingDayValues` direkt in die Prefs
  (`replan.dart:324`), `AppState` hält aber eine eigene In-Memory-Kopie (`app_state.dart:54`) und
  liest sie nie neu. Der nächste `replan` merged auf `Map.from(appState.pendingDayValues)`
  (`replan.dart:145`) - also auf dem alten Stand - und schreibt ihn zurück. Der heutige Tag liegt
  nicht im neuen Fenster (das beginnt morgen), sein reinterpretierter Wert fällt also zurück, und
  `applyPlannedAlarms` stellt den Alarm entsprechend falsch. Solange der Prozess lebt (der Normalfall
  von FR-16s eigenem Beispiel: Tom landet um 14:00, App läuft), hat Checkpoint 2 damit **keine
  Wirkung** außer dem Persistieren des Versatzes.

### T-70 · Das Kalenderfenster liefert nur 6 statt 7 Tage Termindaten

- [x] **Behoben** (`lib/screens/schedule/calendar.dart`): `endDate` zieht nur noch 1 ms statt einen
      ganzen Tag ab - das Fenster deckt jetzt wirklich 7 Tage Termindaten ab.
- **Why:** `replan` holt `[fetchStart, windowStart + 7 Tage)` (`replan.dart:77`),
  `fetchMeetingsUncached` rechnet daraus `endDate: end.subtract(const Duration(days: 1))`
  (`calendar.dart:116`) = Mitternacht des letzten Fenstertages. Ein Termin um 09:00 an diesem Tag
  liegt damit außerhalb. `hardFloor(window[6])` ist folglich immer `null`, der Vorlauf für FR-7 ist
  einen Tag kürzer als spezifiziert. Der Doc-Kommentar behauptet `[start, end)`, der Code setzt die
  inklusive Tageskonvention von `getCalendarEntries` um. Für alle Tests unsichtbar, weil sie
  `fetchEvents` injizieren.

### T-71 · replan()s Tagesmodell gilt nur für den Klingel-Auslöser

- [x] **Behoben**: `replan()` hat jetzt `todayAlreadyRang` (Default `false`). Nur
      `runAlarmRingCheckpoint` setzt es auf `true`; FR-17s Erholung und eine Einstellungsänderung
      behandeln heute als noch nicht abgeschlossen - der Tag bleibt im Fenster (FR-11) und wird von
      FR-9 nicht gezählt. Tests: `test/replan_test.dart` (Ring- vs. Erholungs-Semantik).
- **Why:** `replan` setzt fest "der Tag von `now` hat gerade geklingelt": `ringDay = _midnight(now)`,
  Fenster ab `ringDay + 1`, FR-9-Schleife bis einschließlich `ringDay`. Für den Ring ist das richtig,
  aber `replan` wird auch aus `onAppForegroundCheckpoint` und `onSchedulingSettingsChanged` zu
  beliebiger Tageszeit erreicht. Kaltstart um 06:00 nach einem Nacht-Reboot (FR-17s Kernszenario):
  der heutige 07:30-Wert wird nicht neu abgeleitet (FR-11 verletzt, genau für den Tag, auf den es
  ankommt) und `gapDayCounter` zählt heute mit, obwohl FR-9 sagt "Heutiger Tag zählt nicht mit".

### T-72 · Keine UI für `wunschzeit`/`maxDailyDelta` - halbe FR-4/FR-7 unerreichbar

- [x] **Behoben** (`lib/screens/sleep_habits/screen_sleephabits.dart`): neue Kacheln "Preferred
      wake-up time" (Schalter + Zeitwähler, `null`-fähig) und "Max. daily shift"; beide rufen
      `onSchedulingSettingsChanged` auf. FR-4s Drift, FR-7s Teil-Kappung und FR-10s
      wunschzeit-Zweig sind damit erreichbar.
- **Why:** `grep -rn "wunschzeit\|maxDailyDelta" lib/screens/` findet nichts - kein Screen setzt sie.
  `wunschzeit` ist real immer `null`, `maxDailyDelta` immer das 15-Minuten-Minimum. Damit sind FR-4s
  Drift-Zweig, FR-7s Teil-Drift-Kappung (binäre Suche) und FR-10s "Mit `wunschzeit`: diese Tage
  nutzen sie" toter Code. Praktische Folge auf einem frischen Gerät mit leerem Kalender: es wird
  **nichts** geplant, also klingelt nichts, also gibt es keinen Ring-Checkpoint - und nach 7
  gezählten Tagen schlägt FR-9s Ventil zu.

### T-73 · Ein klingelnder ManualAlarm treibt die ScheduledAlarm-Kette (FR-8/FR-15-Grenze)

- [x] **Behoben** (`lib/models/alarms/handler.dart`): `_fireReplanCheckpoint` prüft jetzt
      `_appState.getAlarm(event.id) is ScheduledAlarm` und kehrt sonst zurück. Regressionstest in
      `test/handler_replan_wiring_test.dart` ("ein klingelnder ManualAlarm löst KEINEN
      Replan-Checkpoint aus").
- **Why:** `_fireReplanCheckpoint()` ist die erste Anweisung von `handleAlarm`
  (`handler.dart:95-96`), ohne Typprüfung - `Alarm.ringing` feuert aber für jeden Alarm
  (`main.dart:181`). Manueller Alarm um 00:30: `ringDay` = heute, FR-9 zählt heute als abgeschlossen,
  FR-12 wird für heute bewertet, `lastReplanDate = heute` (unterdrückt FR-17 für den Rest des Tages),
  und `pendingDayValues[heute]` - der noch nicht geklingelte Wert - wird zum `lastEffectiveWakeTime`.
  Die *Wert*-Isolation aus FR-15 ist intakt (kein ManualAlarm wird je `hardFloor` oder Anker), die
  *Auslöser*-Isolation nicht.

### T-74 · Kleinere, bestätigte Abweichungen (gesammelt) - **alle behoben**

- [x] (a) **FR-6 "einmalig"**: das Overrun-Flag wird bei jedem Replan neu gesetzt, nichts persistiert
      "schon gemeldet" - bei einem mehrtägigen Overrun-Run kommt die Meldung täglich
      (`handler.dart:63-71`, `scheduling_v2.dart:131-132`).
- [x] (b) **Ein gemeinsames try für alle drei Meldungen** (`handler.dart:61-90`): schlägt die erste
      fehl, werden die anderen zwei übersprungen; `Notifications()` wird inline erzeugt, also nicht
      testbar.
- [x] (c) **FR-12-Falschmeldung beim allerersten Replan**: `lastReplanDate == null` ⇒
      `needsDayAdvance == true`, und der `storedValue == null`-Zweig meldet für jeden heutigen Termin
      (`replan.dart:111-115`).
- [x] (d) **Sommerzeit-Fenster**: `windowStart.add(Duration(days: i))` addiert absolute Zeit auf einen
      lokalen Marker (`replan.dart:68-69`) - über die Herbst-Umstellung kollidieren zwei
      `_isoDate`-Schlüssel, ein Tag wird doppelt, einer nie geplant.
- [x] (e) **behoben:** `QrScanner` bekommt jetzt die `alarmId` und stoppt nur den klingelnden Alarm
      statt aller gespeicherten; `planAlarmSync` nimmt zusätzlich `platformAlarmMinutes`
      (`Alarm.getAlarms()`) und setzt einen geplanten Tag neu, dessen Alarm auf der Plattform fehlt.
      Ursprünglicher Befund: **FR-18 modellierte "bestehende Alarme" aus `AppState`**, nicht aus `Alarm.getAlarms()`
      (`apply_alarms.dart:98-102`); der QR-Dismiss stoppt per `Alarm.stop` alle gespeicherten Alarme
      (`qr_scanner.dart:171-177`), ohne die AppState-Listen zu aktualisieren - nach Phase 6 repariert
      das niemand mehr. Zudem vergleicht `planAlarmSync` nur Minuten, Tonänderungen propagieren nicht.

### T-66 · Phase 6 would delete `Scheduler.nextAlarmTime()`, which scheduling-v2 itself depends on

- [x] **Done** (`lib/models/scheduling/next_wake_up.dart`): `nextWakeUpTime()` derives the next
      wake-up from scheduling-v2's `pendingDayValues` **and** the user's `ManualAlarm`s (resolving a
      manual alarm's `TimeOfDay` to today-or-tomorrow, matching `AppState._getAlarmTime`).
      `scheduleSleepReminder()` uses it instead of `Scheduler.nextAlarmTime()`, so nothing outside
      the old `scheduling.dart` references that class's alarm-time helper any more. Tests:
      `test/next_wake_up_test.dart` (incl. "ManualAlarm ist früher -> ManualAlarm gewinnt").
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

### T-65 · Changing sleep-habit settings never triggers a scheduling-v2 replan

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

### T-64 · Both scheduling systems now set alarms - and the old one can leave ZERO alarms

- **Schwere nach oben korrigiert (2026-09):** die frühere Beschreibung ("die Zeiten kippen zwischen
  beiden Algorithmen") war zu milde. `Scheduler.scheduleAlarms()` löscht **zuerst** alle
  `ScheduledAlarm`s (`scheduling.dart:164-169`) und kehrt danach an zwei Stellen zurück, ohne etwas
  neu zu setzen: `existingTimes.isEmpty` (`:212-215`) und `adjustAlarmTimes() == null` (`:254-267`).
  Es liest dabei `appState.meetings` (`:190`), das in einem vom Alarm gestarteten Prozess
  typischerweise leer ist. Ablauf: v2 setzt die Wochenalarme -> Nutzer dismisst -> `onAlarmHandled`
  (`rescheduleOnAlarm` Default `true`, keine UI) -> alles gelöscht, Abbruch -> **kein einziger Alarm
  mehr**, und der nächste Replan käme erst beim nächsten Ring (den es nicht gibt) oder am Folgetag.
  Dasselbe löst ein Tippen auf den "Scheduled"-Tab aus (`screen_alarms.dart:188`). Für eine App mit
  "garantiertem Aufwachen" ist das der schlimmstmögliche Ausgang - damit ist Phase 6 kein Aufräumen,
  sondern der dringendste offene Punkt.


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
- **Status:** Behoben 2026-09-10 (Phase 6). `lib/models/scheduling/scheduling.dart` ist gelöscht,
  samt `Scheduler`, `getEarliestEvent`, `getStartTimeForDate`, `adjustAlarmTimes`, `nextAlarmTime`
  und `setScheduledAlarmToNow`; `test/scheduling_test.dart` ist mit ihr gegangen. Die drei
  Aufrufstellen sind aufgelöst: `Handler.onAlarmHandled` plant nur noch die Bettzeit-Erinnerung
  (der Ring hat über `_fireReplanCheckpoint` ohnehin schon voll neu geplant), der Tab-Wechsel in
  der Alarmliste plant **nichts** mehr (FR-11: Kalenderänderungen haben bewusst keinen eigenen
  Auslöser), und der Sync-Knopf ruft `runCheckpointSafely(trigger: manualSync)`.
  `test/handler_on_alarm_handled_test.dart` hält den Befund fest und war gegen den alten Code rot -
  belegt mit dem realen Fall: nach einem Dismiss war der Alarm für morgen weg (0 statt 1).
  Damit sind auch T-02 und T-32 gegenstandslos.

### T-101 · risk.png war ein Planungsbild, jetzt ein Threat Model — BEHOBEN (2026-09-10)

- [x] `docs/risk.png` durch ein echtes Threat Model ersetzen.
- [x] Aus einer wartbaren Quelle erzeugen, nicht als blosses Binaerbild ablegen.
- **Why:** `risk.png` stammte aus der Planungsphase, modellierte teils nie gebaute Funktionen und
  trug keinen Hinweis darauf (T-30). Ein Risikobild, das man nicht gegen den Code halten kann, ist
  schlimmer als keines - es suggeriert Pruefung, wo keine stattfand.
- **Status:** neu als Datenfluss-Diagramm mit Vertrauensgrenzen und STRIDE-Bewertung. Quelle ist
  `docs/threat-model.svg` (Text, diffbar); `docs/risk.png` wird daraus gerendert mit
  `rsvg-convert -w 1400 -b white docs/threat-model.svg -o docs/risk.png`. Bewusst **keine**
  zusaetzliche `threat-model.md`: die Analyse steht vollstaendig im Diagramm, und zwei Quellen
  driften auseinander - genau das Problem, das dieser Durchgang mehrfach reparieren musste.
- **Der inhaltliche Kern, der es von einer Standard-Checkliste unterscheidet:** das
  schuetzenswerte Gut ist hier zuerst die **Verfuegbarkeit**. Bei einer Weckerapp heisst
  "Ausfall" Verschlafen, Denial of Service ist damit die schwerste Kategorie und nicht die
  laestigste - und die zwei gravierendsten Befunde des Projekts (T-64, T-78) waren genau das:
  selbstverschuldete Wecker-Abschaltungen. Zweitens ist der Angreifer im
  "garantierten Aufwachen" teils der **Nutzer selbst**, der sein eigenes Gate aushebeln will; das
  kehrt die ueblichen Annahmen um. Drittens ist "kein Netzzugriff in lib/" eine tragende
  Gegenmassnahme und keine Fussnote - sie streicht eine ganze Bedrohungsklasse.
- **Was das Modell als offen benennt:** R8/R9 (nicht-freie Abhaengigkeiten - Lizenz- UND
  Kontrollproblem), R3 (Reboot-Ueberleben unbelegt), Ueberberechtigung im Manifest
  (`WRITE_CALENDAR`, `READ_EXTERNAL_STORAGE` ohne Codepfad), keine dynamische Analyse, und das
  Restrisiko, dass der QR-Code per Design kopierbar ist.

### T-100 · Artefaktspeicher lief auf das 2,75-fache des Kontingents — BEHOBEN (2026-09-10)

- [x] Alte Artefakte entfernen.
- [x] Ursache abstellen.
- **Why:** **1375 MB** nicht abgelaufene Actions-Artefakte bei einem 500-MB-Kontingent (privates
  Repo, Free-Plan). Ursache: `ci.yml` laedt bei jedem `master`-Push ein Release-APK (~39 MB) und
  ein Debug-APK (~94 MB) hoch, und **keiner** der Uploads hatte `retention-days` - es griff also
  GitHubs Standard von 90 Tagen. `cleanup_old_artifacts.sh` existiert, prunt aber ausschliesslich
  `release.yml`-Laeufe; die CI-Laeufe hat nie etwas aufgeraeumt. Aufschluesselung:
  `app-production-apk` 19x/748 MB, `app-debug-apk` 3x/281 MB, `app-development-apk` 2x/188 MB,
  `app-release-apk` 2x/79 MB, `mobsf-report` 22x/51 MB, `e2e-evidence` 7x/29 MB.
- **Status:** 70 Artefakte aus alten Laeufen geloescht, **1282 MB** frei - Rest 11 Artefakte / 93 MB.
  Behalten wurden die beiden neuesten CI-Laeufe und der neueste Release-Lauf; Artefakte sind aus
  dem Commit reproduzierbar, die Beweise des Laufs 34532845207 ("7 tests passed") liegen zusaetzlich
  dauerhaft ausserhalb von `/tmp`. Jeder Upload hat jetzt ein ausdrueckliches `retention-days`
  (Entwicklungs-APK 5 Tage, Release-APK und Berichte 30) - damit kann es nicht wieder anlaufen,
  ohne dass jemand ein Aufraeumskript pflegt.

### T-98 · E2E-Zeitlimit war auf den Stand vor den Engine-Szenarien zugeschnitten — BEHOBEN (2026-09-10)

- [x] Limit anheben.
- [ ] Nach ein paar gemessenen Laeufen wieder eng setzen (dann mit Zahlen statt Schaetzung).
- **Why:** `e2e-tests.yml` hatte `timeout-minutes: 25`, passend zu den 19m53s, die der Job vor den
  neuen Szenarien brauchte. Dazu kamen vier Engine-Szenarien (eines wartet auf ein echtes
  Klingeln), ein zweiter `flutter test`-Aufruf fuer `arm_alarm_test.dart` und der Reboot-Nachweis
  mit bis zu 240s Bootwartezeit. Der erste Lauf danach (34532845207) lief prompt in den Timeout und
  wurde **cancelled**, wodurch Release-Build und MobSF-Scan uebersprungen wurden - obwohl inhaltlich
  alles in Ordnung war. Ein Zeitlimit soll einen haengenden Job abschneiden, nicht einen langsamen.
- **Status:** provisorisch 60 Minuten. Wichtig fuer die naechste Diagnose: `timeout-minutes` wird
  beim **Start** eines Laufs gelesen - eine Aenderung waehrend eines laufenden Jobs wirkt nicht mehr.

### T-99 · Zwei Beweismittel im E2E-Job waren blind — TEILWEISE BEHOBEN (2026-09-10)

- [x] Beide Stellen diagnosefaehig machen.
- [ ] Aus dem naechsten Lauf die echten `dumpsys alarm`-Muster ablesen und die Zaehlung darauf
      festziehen; danach das Survival-Bein scharf stellen (T-93).
- [ ] Bestaetigen, dass `adb root` die Zeitzone auf dem CI-Image wirklich setzt.
- **Why:** der Lauf 34532845207 hat beides zutage gebracht - beides Dinge, die ich vorher nur
  **angenommen** hatte, und der Aufklaerungsdurchgang hatte sie ausdruecklich als unverifiziert
  markiert:
  1. **Der Reboot-Nachweis fand nichts.** `arm_alarm_test.dart` hat im selben Lauf nachweislich
     einen Alarm gesetzt ("🎉 1 test passed", `TimeOfDay(23:55)`), aber
     `dumpsys alarm | grep -c com.wakeywakey.wakeywakey` lieferte **0**. Die erwartete
     dumpsys-Signatur war falsch geraten. "inconclusive" ist damit nicht "kein Alarm gesetzt",
     sondern "mein Muster passt nicht".
  2. **Die Emulator-Zeitzone hat nicht gegriffen.** `manifest.log` sagt `Etc/UTC` -
     `adb shell setprop persist.sys.timezone` wirkt als normaler Shell-Nutzer nicht. Folge: das
     T-61-Szenario lief **trivial wahr** durch. Es stand gruen im Bericht, hat aber nichts bewiesen -
     genau der Vorbehalt, der in seinem eigenen Testkommentar steht.
- **Status:**
  - `check_alarm_survival.sh` prueft jetzt mehrere Muster (Paketname, `AlarmReceiver`,
    `com.gdelataillade.alarm`) und schreibt bei jedem Lauf einen **Rohauszug** aus `dumpsys alarm`
    plus die App-UID in die Beweisdatei. Damit lassen sich die Muster beim naechsten Mal aus
    Belegen festziehen, statt sie erneut zu raten. Die "inconclusive"-Meldung sagt jetzt
    ausdruecklich, dass sie nicht "kein Alarm" bedeutet.
  - `run_e2e_tests.sh` versucht `adb root` vor dem `setprop`, liest den Wert zurueck und gibt bei
    Abweichung eine sichtbare `::warning::` aus - inklusive des Hinweises, dass das T-61-Szenario
    in diesem Lauf dann nichts beweist. Bewusst **kein** Abbruch: die Suite bleibt auf UTC gueltig,
    nur eben in diesem Punkt aussagelos. Das gehoert in den Beweis, nicht ins Verschweigen.
- **Was der Lauf dagegen wirklich belegt hat (T-91 ist eingeloest):** `🎉 7 tests passed` auf einem
  echten Emulator, inklusive aller vier Engine-Szenarien. Im Log sichtbar:
  `applyPlannedAlarms: removed 0, added 7` - aus einem injizierten Termin entstehen genau die
  sieben Alarme, die das Fixture vorhersagt, und ein Dismiss laesst sie stehen (T-64). Das ist die
  erste Bestaetigung von FR-18 bis zum Alarm-Plugin auf einem Geraet.

### T-97 · Projekthygiene: Altlasten in pubspec, Build und Doku — BEHOBEN (2026-09-10)

- [x] Nicht genutzte direkte Abhaengigkeiten entfernen.
- [x] Toten Zustand in `AppState` entfernen.
- [x] Ueberholte Doku-Aussagen richtigstellen.
- **Vorgehen:** nichts geloescht, was nicht begruendet ist. Planungsartefakte
  (`risk.png`, `UML_WakeyWakey.drawio`, `personas.md`, `use-cases.md`,
  `choice-of-technologies.md`) sind unangetastet - sie sind vom Maintainer erstellt. Die
  gitignorierten Momentaufnahmen (`quality-baseline-*`, `release-readiness-*`) ebenso.
- **Abhaengigkeiten (`pubspec.yaml`), alle vor dem Entfernen geprueft:**
  - `cupertino_icons`, `flutter_spinkit` - in `lib/` nirgends importiert, nach dem Entfernen auch
    nicht mehr in `pubspec.lock`. Waren also wirklich ungenutzt.
  - `syncfusion_flutter_core`, `syncfusion_flutter_datepicker` - nicht importiert, aber
    `syncfusion_flutter_calendar` fordert beide selbst (`^34.2.6` in dessen pubspec). Die direkten
    Eintraege waren Redundanz; sie stehen jetzt als `transitive` im Lock. **Korrektur einer
    naheliegenden Annahme:** das reduziert die Lizenzflaeche aus R8/R9 NICHT - die Pakete kommen
    ohnehin mit.
  - `awesome_notifications_core` - **der interessante Fund.** `awesome_notifications` 0.12.1
    fordert es gar nicht; der Eintrag war Altlast aus der 0.9.x/0.10.x-Zeit. Nach dem Entfernen ist
    es komplett aus der Auflösung verschwunden.
  - `awesome_notifications: any` -> `^0.12.1`. Ein `any`-Constraint ist eine offene Flanke: eine
    bruchhafte Version haette still hereinkommen koennen.
  - `flutter_lints` von `dependencies` nach `dev_dependencies` verschoben. Es liefert nur
    Analyse-Regeln und wird zur Laufzeit nie importiert - unter `dependencies` war es eine
    Laufzeit-Abhaengigkeit.
- **Build:** der compileSdk-Override in `android/build.gradle.kts` ist damit **entfallen**. Sein
  einziger Grund war `awesome_notifications_core`s hartkodiertes `compileSdkVersion 33`; ohne die
  Abhaengigkeit ist die stoerende AAR aus dem Build. `CLAUDE.md` hatte genau dafuer die Einladung
  ("If a future dependency bump makes this override redundant, it's safe to remove - but check
  `flutter build apk` still succeeds first"). Verifiziert mit einem **`flutter clean`**-Release-Build
  (33,9 s, 83,8 MB), nicht nur inkrementell - ein inkrementeller Lauf haette die
  AAR-Metadatenpruefung als UP-TO-DATE ueberspringen koennen.
- **Assets:** `assets/icons/icon.png` ist nicht mehr im Asset-Bundle. Es ist ausschliesslich die
  Quelle fuer `dart run flutter_launcher_icons` (das den Pfad aus seiner eigenen Konfiguration von
  der Platte liest); zur Laufzeit laedt es niemand. Die Datei bleibt im Repo. Alle sechs
  Klangdateien sind dagegen real in Benutzung (Tonauswahl) und bleiben gebuendelt.
- **Toter Zustand:** `AppState.isPreloadingCalendarMutex` entfernt - Feld, Getter und Setter hatten
  ausserhalb von `app_state.dart` **null** Leser und **null** Schreiber. Dieselbe Klasse wie die
  Funde in T-86. Ein Durchlauf ueber alle AppState-Getter fand sonst keinen weiteren.
- **Testkorrektur:** das E2E-Szenario zu T-84 setzte `assets/sounds/mozart.mp3` - eine Datei, die
  es nicht gibt. Der Test lief trotzdem gruen, weil er nur den zurueckgelesenen Pfad vergleicht,
  aber auf dem Geraet haette das Plugin ein fehlendes Asset referenziert. Jetzt
  `annoying_alarm.mp3`, das real existiert und sich vom Default unterscheidet.
- **Doku:** `CLAUDE.md`s Teststand (199/22 -> 209/24), die E2E-Beschreibung (drei -> sieben
  Szenarien, mit dem ausdruecklichen Hinweis, dass die vier neuen **noch nie gelaufen** sind) und
  der Abschnitt zum compileSdk-Override.
- **Bewusst NICHT angefasst:** `docs/TODO.md`s erledigte Eintraege. Sie sind das Beweismittel
  dafuer, dass ein Befund behoben ist - die Konvention dieses Projekts ist, dass ein gefixter
  Befund dokumentiert bleibt. "Nicht mehr aktuell" ist hier nicht gleich "wegwerfen".

### T-96 · Gentle Wake hatte keinen Regler fuer die Rampendauer — BEHOBEN (2026-09-10)

- [x] Dauer einstellbar machen und bis zum Alarm-Plugin durchreichen.
- **Why:** die Rampe war in `lib/app_state.dart` als `Duration(seconds: 60)` festverdrahtet -
  ein Nutzer konnte Gentle Wake ein- und ausschalten, aber nicht bestimmen, wie lange der Alarm
  leise bleibt. Das Plugin nimmt den Wert als Parameter (`VolumeSettings.fade`), die Einstellung
  fehlte also nur an der Oberflaeche.
- **Status:**
  - Neues `AppState.gentleWakeUpDuration`, persistiert als `gentleWakeUpSeconds`. Standard eine
    Minute - genau der bisher festverdrahtete Wert, damit bestehende Installationen unveraendert
    klingen. Nach unten geklammert auf eine Minute, weil das Plugin
    `assert(fadeDuration > Duration.zero)` verlangt, der hh:mm-Picker aber 00:00 zulaesst und
    Assertions im Release-Build aus sind.
  - **Die Dauer haengt am ALARM, nicht nur am AppState** (`MyAlarm.gentleWakeDuration`, durch
    `ScheduledAlarm` und `ManualAlarm` samt JSON und `==` gefuehrt). Das ist die Lehre aus T-84:
    `planAlarmSync` entscheidet anhand der Alarm-Eigenschaften, ob ein bereits gesetzter Alarm
    ersetzt werden muss - laege der Wert nur im AppState, koennte eine Aenderung nie als
    Abweichung erkannt werden und die Einstellung haette eine UI ohne Wirkung auf bestehende
    Alarme. `planAlarmSync` vergleicht sie jetzt mit, aber nur bei eingeschaltetem Gentle Wake
    (sonst benutzt `_setAlarm` die Rampe gar nicht, ein Unterschied waere also kein Grund zum
    Neusetzen).
  - Alte gespeicherte Alarme ohne das Feld fallen auf den Default zurueck.
  - UI: Regler "Ramp duration" unter dem Gentle-Wake-Schalter, nur sichtbar wenn eingeschaltet
    (Muster des Reminder-Schalters), mit sichtbarem Hinweis auf das Minimum - wie bei
    `maxDailyDelta` in T-88, damit die Klammer nicht unsichtbar zuschlaegt.
- **Nebenbefund, gleich mitbehoben:** der Dialog zum Anlegen eines *manuellen* Alarms
  (`screen_alarms.dart`) belegte `gentlewake`, `volume` und `tone` aus dem AppState vor, die
  Rampendauer aber nicht - ein manueller Alarm haette also stur die Default-Minute benutzt.
  `test/manual_alarm_inherits_settings_test.dart` faehrt dafuer durch den echten Dialog und war
  gegen den unveraenderten Code rot (`0:01:00` statt `0:09:00`).
- **Auslegung, die ich getroffen habe:** "wie lange der leise Alarm lauten soll" ist als
  **Rampenlaenge** umgesetzt - die Lautstaerke steigt ueber diese Dauer von 0 auf den
  eingestellten Wert, der Alarm bleibt also genau so lange leise. Das Plugin koennte alternativ
  eine Treppe fahren (`VolumeSettings.staircaseFade`), also z. B. "10 Minuten konstant leise, dann
  sprunghaft laut". Falls das gemeint war, ist es ein anderer Aufruf an derselben Stelle.

### T-95 · Sleep-Habits-Schirm: Reihenfolge fuehrte in die Irre — BEHOBEN (2026-09-10)

- [x] Eintraege nach Ursache gruppieren und die Gruppen benennen.
- **Why:** die Reihenfolge war nicht bloss Geschmackssache, sie ordnete Wirkungen falsch zu.
  "Sleep Goal" stand an **erster** Stelle, beeinflusst aber die Alarmzeit ueberhaupt nicht - es
  verschiebt ausschliesslich die Bettgeh-Erinnerung
  (`nextWakeUpTime - sleepGoal - reminderDuration`, `lib/utils/sleep_reminder.dart`). Wer es oben
  sieht und daran dreht, erwartet einen frueheren Wecker und bekommt nichts. Gleichzeitig war es
  von "Enable Reminder" - der anderen Haelfte derselben Rechnung - durch drei fremde Eintraege
  getrennt. Und "Preferred wake-up time", der Anker der ganzen FR-4-Drift und die einzige
  Einstellung, die ein Nutzer **ohne** Kalendertermine braucht, lag auf Position 4 unter zwei
  Dauern, die nur an Tagen **mit** Termin wirken.
- **Status:** drei ursaechliche Gruppen mit Ueberschriften:
  1. *Wake-up time* - Preferred wake-up time, Max. daily shift, Duration to wake up, Duration to
     get ready. Zuerst das Ziel, dann die Schranke, wie schnell die Weckzeit sich ihm naehern darf
     (FR-6), dann die zwei Vorlaufzeiten in der Reihenfolge, in der `hardFloor` sie abzieht.
  2. *Bedtime reminder* - Sleep Goal, dann Enable Reminder: der Vorlauf misst sich von der
     Bettzeit aus, die das Schlafziel festlegt.
  3. *When the alarm rings* - Gentle WakeUp.
  Die Ueberschriften sind Teil der Loesung, nicht Zierde: ohne sie waere die Gruppierung fuer den
  Nutzer unsichtbar und die neue Reihenfolge nur eine andere, keine erklaerte.
  `test/sleep_habits_order_test.dart` prueft die Reihenfolge ueber die **y-Positionen** der
  Beschriftungen (also was der Nutzer sieht, nicht die Quelltextfolge), dass jede Gruppe eine
  Ueberschrift ueber ihrem ersten Eintrag hat, und dass der T-88-Hinweis zum 15-Minuten-Minimum
  bei seinem Regler bleibt. Alle drei waren gegen die alte Reihenfolge rot.

### T-94 · Die Entwicklungs-VM kann Suite und Release-Build nicht mehr zu Ende fahren — BEHOBEN (2026-09-10)

- [x] VM neu starten (raeumt die haengenden Kernel-Threads ab) und danach beides einmal
      vollstaendig durchlaufen lassen: `flutter test` und `flutter build apk --release`.
- [x] Wenn der Build danach immer noch haengt: die eine Zeile aus T-90 isolieren
      (`isCoreLibraryDesugaringEnabled` in `android/app/build.gradle.kts`) und ohne sie bauen.
      Das ist die einzige Aenderung dieses Durchgangs, die den Build beruehrt.
      **Nicht noetig geworden** - siehe Status.
- **Why:** am 2026-09-10 hat die VM ab der Haelfte des Tages weder die Unit-Suite noch einen
  Release-Build zu Ende gebracht. Symptome und Belege:
  - `flutter test` (ganze Suite): bricht nach 150-190 Tests mit wandernden
    "did not complete" / "Bad state: Cannot add event while adding stream" ab. Das ist ein
    `flutter_tools`-Harness-Fehler, der auftritt, wenn ein Test-**Geraet** waehrend des Streamens
    stirbt - kein Zusicherungsfehler. Die betroffene Datei wechselt bei jedem Lauf.
  - Dieselben Dateien laufen **einzeln** und in zwei grossen Bloecken (62 + 88 Tests) in je
    4 Sekunden gruen durch. Es ist also eine Ressourcen-, keine Codefrage.
  - Jeder abgebrochene Lauf hinterlaesst einen `frontend_server`-Prozess mit ~490 MB. Auf 8 GB
    baut sich der Druck nach wenigen Laeufen wieder auf.
  - `flutter build apk --release` haengt: vier bzw. drei JVMs in `futex_do_wait`, **null**
    Dateiaenderungen unter `build/` ueber Minuten. Auch mit `-Dorg.gradle.daemon=false` und nach
    `rm -rf ~/.gradle/daemon`. Vorher am selben Tag lief derselbe Build in 36 Sekunden.
  - Ein unabhaengiger Durchgang hat denselben Hang **vor** jeder Gradle-Aenderung dieses Tages
    gesehen (`flutter build apk --debug`, 45 Minuten unveraendert auf
    `Running Gradle task 'assembleDebug'`, Daemon in `futex_do_wait`) und auf Lock-/Ressourcen-
    Konkurrenz zurueckgefuehrt. Die Ursache ist also nicht die Desugaring-Zeile.
  - Auslöser war mit hoher Wahrscheinlichkeit die Emulator-Arbeit: zwei parallel gestartete
    Emulatoren auf 8 Kernen / 8 GB, danach blieben `kworker/u32:1+netns` und
    `kworker/u38:*+events_unbound` dauerhaft im D-State stehen (Load-Average steht seither bei
    ~6, obwohl `procs_running 1` und `procs_blocked 0` melden). Solche Kernel-Threads verschwinden
    in der Regel erst mit einem Neustart.
- **Praktischer Umgang bis dahin** (auch in `CLAUDE.md` notiert):
  `pkill -f "frontend_serve[r]"` - die Zeichenklasse ist wichtig, ohne sie trifft `pkill` seine
  eigene Kommandozeile und erschlaegt die Shell - und die Suite in zwei bis drei Dateigruppen
  fahren statt in einem Aufruf.
- **Status:** Nach `pacman -Syu` (20 Pakete, Kernel 7.2.3 -> 7.2.4) und Reboot ist beides
  nachgeholt und die Diagnose bestaetigt - es war ausschliesslich Ressourcenerschoepfung, kein
  Codeproblem:
  - `flutter test` in **einem** Aufruf: **199/199 gruen in 2 Sekunden**. Vorher brach derselbe
    Aufruf reproduzierbar nach 150-190 Tests ab.
  - `flutter build apk --release`: **erfolgreich in 100 Sekunden**, 84,2 MB, signiert
    (`CN=Dam0k1es`), `apksigner verify` OK, minSdk 24 / targetSdk 36. Vorher hing derselbe Build
    ueber 20 Minuten mit JVMs in `futex_do_wait`.
  - Messwerte davor/danach: D-State-Prozesse 5 -> **0**, Load-Average ~6 -> **0.65**, verfuegbarer
    Speicher 1-2 GB -> **6,9 GB**.
  - Der `vboxsf`-Mount hat das Kernel-Update unbeschadet ueberstanden (lesen und schreiben) - wie
    erwartet, weil das Modul zum Kernel-Paket gehoert und nicht per DKMS gebaut wird.
- **Die Desugaring-Zeile aus T-90 war nicht die Ursache** - sie ist unveraendert drin und der Build
  laeuft. Die Vermutung im zweiten Punkt oben hat sich also erledigt.
- **Lehre fuer den naechsten Verdachtsfall:** "keine Dateiaenderungen unter `build/`" ist **kein**
  Beleg fuer einen Hänger - Gradle arbeitet zwischenzeitlich in `~/.gradle` und in Temp-Pfaden.
  Erst `find <projekt> ~/.gradle -newermt "-5 minutes"` mit **null** Treffern ist eines. In diesem
  Durchgang wurde ein laufender Build dadurch einmal faelschlich abgebrochen (`exit code -9` kam
  vom eigenen `kill`, nicht von Gradle).

- **Was weiterhin unbelegt bleibt:** die neuen E2E-Szenarien aus T-91 - die brauchen ein Geraet
  oder einen Emulator, nicht nur eine gesunde VM.

### T-89 · PII-freies Entwickler-Log, und die Lecks, die es ersetzt — BEHOBEN (2026-09-10)

- [x] Ereignis-Logger anlegen, der konstruktiv keine personenbezogenen Daten aufnehmen kann.
- [x] Die gefundenen Lecks schliessen.
- **Why:** aus einem installierten Release-Build kam **nichts** zurueck - alle Diagnosen liefen
  ueber `debugPrint`, und `main.dart:29-31` ersetzt das im Release durch eine leere Funktion. Ein
  Geraetetest konnte also nur zeigen, DASS etwas schiefging, nie warum. Gleichzeitig fand ein
  unabhaengiger Audit fuenf **kritische** Lecks und eine ganze Fehlerklasse:
  - `qr_scanner.dart:139` und `:176` sowie `page_deactivation_code.dart:48` loggten den
    **QR-Deaktivierungscode im Klartext** - das Geheimnis, mit dem sich der "garantierte" Wecker
    aushebeln laesst. Die Validierungszeile feuerte zuverlaessig jeden Morgen.
  - `calendar.dart:25` loggte den Kalendernamen, auf Android regelmaessig die
    **Konto-Mailadresse**; `:72` den **Termintitel**.
  - `catch (e) { debugPrint("... $e") }` an ~60 Stellen: `FormatException.toString()` enthaelt
    einen Ausschnitt der **Quellzeichenkette**, ueber `$e` gelangten also Nutzdaten ins Log, die im
    Format-String gar nicht vorkamen - bei beschaedigten SharedPreferences Alarmtitel, geplante
    Weckzeiten oder der Deaktivierungscode.
  - `replan.dart:317` ist der **einzige** debugPrint, der den Release-Guard umgeht: er sitzt in
    `runTimezoneCheckpoint2`, das per `@pragma('vm:entry-point')` in einem eigenen Isolate laeuft,
    in dem `main()` nie lief.
  - `handler.dart:110-125` erzeugte zwei echte **Notifications** mit Alarmtyp, Weckzeit und ID -
    nur durch `kDebugMode` geschuetzt, nicht durch die debugPrint-Abschaltung. Sie landeten im
    Notification-Shade und damit auf dem **Lockscreen** jedes Testers mit einem Debug-APK (das
    `ci.yml` fuer `dev` als Artefakt hochlaedt). Eine Historie daraus ist ein Schlafprofil.
  - `scanned_barcode_label.dart:27` zeigte den gescannten Rohwert gross auf dem Bildschirm - im
    Alarm-Modus, also auf einem klingelnden Geraet.
- **Status:** Behoben. Neu: `lib/utils/diag/diag_log.dart`.
  - **Die tragende Entscheidung:** die Aufzeichnungs-API nimmt **keinen einzigen String**. Es gibt
    damit keinen Kanal, durch den ein Termintitel, ein Kalendername, eine Exception-Nachricht oder
    der QR-Code hineingeraten koennte - was nicht darstellbar ist, kann nicht austreten.
    `test/diag_log_api_test.dart` prueft das am Quelltext (keine String-Parameter, kein
    `debugPrint`/`print`, keine Uhrablesung, kein int-Parameter mit Uhr-Namen).
  - **Warum das trotzdem diagnostisch reicht:** jeder echte Befund dieses Projekts war ein
    STRUKTURfehler, kein WERTfehler - falsche Anzahl (T-75, T-70), kollidierende Tagesschluessel
    (T-74d/T-76), ein um den Geraeteversatz verschobener Wert (T-61), unbegrenztes Wachstum (T-82),
    auseinanderlaufende Mengen (T-74e/T-88). Keiner braucht die tatsaechliche Weckzeit des Nutzers.
  - **Zeit:** keine Zeitstempel, keine Kalenderdaten, keine Uhrzeiten. Tage nur relativ (mit
    `dayDistance`, damit der Logger nicht T-76 in sich selbst nachbaut), Zeitpunkte nur als
    gebucketete **Differenzen** (Stufen nach den Fehlersignaturen: 0 = gesund, eine Stunde =
    Versatz/Sommerzeit = T-61, ein Tag = Off-by-one = T-74d/T-76). Der absolute Zeitzonen-Versatz
    wird nie aufgenommen, nur die *Gestalt* der Aenderung - er wuerde die Region sofort festnageln.
    Reihenfolge ueber `bootSeq` + `seq`, Grobzeit ueber `Stopwatch`.
  - **Ausnahmen** gehen als `runtimeType` ueber eine Identitaetstabelle auf einen int, nie als
    Nachricht; `toString()` wird auf einem `Type` nie gerufen (R8-Obfuskierung damit gleichgueltig).
  - **Senke:** begrenzter Ringpuffer (512), gebuendelt nach SharedPreferences. Bewusst keine Datei
    ueber `path_provider`: FR-16s Checkpoint 2 laeuft in einem Hintergrund-Isolate und redet dort
    schon heute direkt mit SharedPreferences - ein Datei-Logger haenge von der Verfuegbarkeit des
    Plugin-Channels ab, also genau der Fehlerklasse, die T-79 war. Das Isolate hat seinen **eigenen**
    Ringpuffer (dieselbe Falle wie T-69), deshalb zwei Prefs-Schluessel und ein Merge beim Lesen.
  - **Export** ueber Anzeigen + Zwischenablage (`Settings > Diagnostics`), nicht ueber einen
    Teilen-Dialog: kein Netzcode, keine neue lizenzpruefungspflichtige Abhaengigkeit - und
    ehrlicher, weil der Nutzer genau das liest, was er weitergibt. Schalter zum Abschalten und
    Knopf zum Loeschen daneben; `assets/text/Privacy.md` entsprechend ergaenzt.
  - Alle Lecks geschlossen: 62 `$e`-Interpolationen auf `${e.runtimeType}` umgestellt, die fuenf
    konkreten Stellen entschaerft, die zwei Debug-Notifications ersatzlos entfernt, die
    Rohwertanzeige durch "QR Code detected" ersetzt, der Zonenname aus `main.dart` entfernt.
    `test/no_pii_in_logs_test.dart` verbietet den **Kanal** (nicht einen konkreten Wert) und war
    gegen den unveraenderten Code mit 66 Verstoessen rot.

### T-90 · minSdk 24 ist behauptet, aber nie belegt — TEILWEISE BEHOBEN (2026-09-10)

- [x] Core-Library-Desugaring aktivieren (entschaerft die latente `java.time`-Mine).
- [ ] Einen echten API-24-Lauf haben, der die Behauptung belegt.
- **Why:** `android/app/build.gradle.kts` pinnt minSdk 24, und `aapt2 dump badging` bestaetigt das
  im gebauten Release-APK. Belegt ist damit aber nur, was im Manifest steht, nicht dass die App
  dort laeuft: die E2E-Suite fuhr bisher ausschliesslich API 34, lokal ist nur ein API-29-Image
  installiert. Dazu ein konkreter Fund: `strings classes.dex | grep '^Ljava/time/'` findet im
  Release-Dex `Ljava/time/Duration;` und `grep -c '^Lj\$/'` liefert **0** - der Aufruf ging also
  un-desugart ins APK, obwohl `java.time.*` erst ab API 26 existiert. Quelle ist das
  `alarm`-Plugin (`AlarmSettings.kt:138`), das selbst minSdk 19 deklariert und kein Desugaring
  aktiviert.
- **Praezisierung:** der Aufruf sitzt im Rueckwaertskompatibilitaets-Zweig fuer altes
  v4-Alarm-JSON, den die aktuelle App-Version normalerweise nicht betritt. Es ist also eine
  **latente** API-26-Mine unter einem minSdk-24-Vertrag, kein bestaetigter Absturz.
- **Status:** `isCoreLibraryDesugaringEnabled = true` plus `desugar_jdk_libs:2.1.5` in
  `android/app/build.gradle.kts`. **Im gebauten Artefakt verifiziert** (2026-09-10, Release-APK):
  `Ljava/time/`-Referenzen im Dex **0** (vorher 1: `Ljava/time/Duration;`), `Lj$/`-Ersatzklassen
  **124**, davon **122** unter `j$/time`. Die Mine ist damit nicht nur theoretisch entschaerft,
  sondern messbar weg. Der
  Beleg, dass die App auf API 24 laeuft, fehlt weiter - ein API-24-Bein in `e2e-tests.yml` waere
  der naechste Schritt, aber es waere ein unverifiziertes Bein, und ein solches darf kein
  Release blockieren.

### T-91 · Die neue Engine war auf keinem Geraet je gelaufen — BEHOBEN (2026-09-10)

- [x] E2E-Szenarien fuer scheduling-v2.
- **Why:** Phase 6 hat den alten Motor geloescht und den neuen scharf geschaltet, aber
  `integration_test/app_test.dart` deckte nur manuelle Alarme ab - die Engine war dort mit **keinem
  einzigen** Test vertreten. Und das ist keine Kleinigkeit: **kein** Unit-Test mockt den Kanal des
  `alarm`-Plugins. In `flutter test` wirft `Alarm.set()`/`Alarm.getAlarms()` und wird geschluckt,
  die Unit-Suite prueft also ausschliesslich AppState-Listen. Alles zwischen `appState.addAlarm`
  und einem wirklich registrierten Alarm war unbelegt.
- **Status:** vier Szenarien ergaenzt, jedes an einen realen Befund gebunden - T-63 (Termin wird zu
  registrierten Alarmen), T-61 (der registrierte Alarm traegt die *lokale* Lesart des geplanten
  Instants), T-84 (Ton/Lautstaerke/Gentle-Wake erreichen das Plugin), T-64 (ein Dismiss laesst die
  geplante Woche stehen). Dazu `integration_test/arm_alarm_test.dart` als Vorlauf fuer T-93.
  Fixture-Rezept: Vorlaufzeiten null, keine `wunschzeit`, keine Vorgeschichte, Auslöser
  `manualSync` (FR-17s Tagessperre hat beim App-Start schon zugeschlagen, ein zweiter
  `appForeground` waere ein No-op). Harte Randbedingung: `AppState.addAlarm` verwirft einen
  ScheduledAlarm, dessen Zeit nicht nach dem **echten** `DateTime.now()` liegt - nicht nach einem
  injizierten "now".

### T-92 · Das Gate war blind fuer Zeitzonen, und der Tag-Pfad hatte kein Sicherheitstor — BEHOBEN (2026-09-10)

- [x] Zeitzonen-Matrix fuer die Unit-Suite.
- [x] Nicht-UTC-Zeitzone auf dem E2E-Emulator.
- [x] SCA/Secret/SAST auch im Release-Pfad.
- [x] Coverage als Signal.
- **Why (Zeitzonen):** die dominante Fehlerklasse dieses Projekts ist Frame-Verwirrung, und drei
  echte Bugs (T-61, T-74d, T-76) waren auf UTC+0 **prinzipiell unsichtbar** - genau dort laufen
  aber Entwicklungsmaschine UND GitHub-Runner, und der Emulator ebenso.
- **Why (Release-Pfad):** `release.yml` fuhr nur `flutter analyze`, `flutter test` und die
  E2E-Suite. Ein per Tag gebautes, signiertes und an ein GitHub-Release angehaengtes APK konnte
  also eine verwundbare Abhaengigkeit oder ein eingechecktes Geheimnis enthalten, obwohl derselbe
  Commit auf `master` daran gescheitert waere.
- **Status:**
  - `ci.yml`s Test-Job ist eine Matrix ueber sechs Zonen (UTC, Europe/Berlin, Asia/Tokyo,
    America/St_Johns, Pacific/Chatham, Australia/Lord_Howe - die Halb- und Dreiviertelstunden sind
    Absicht, an ihnen faellt Ziffernarithmetik am ehesten auf), mit `fail-fast: false`, weil bei
    einem Frame-Fehler das *Muster* ueber die Zonen die Diagnose ist. Verifiziert, dass die
    TZ-Variable Darts `DateTime` im Testprozess wirklich erreicht - und dass die Suite in allen
    sechs Zonen gruen ist. Sie ist damit ein Regressionsnetz, kein Bug-Finder.
  - `.github/scripts/run_e2e_tests.sh` setzt die Emulator-Zeitzone auf `Europe/Berlin`, bevor die
    App das erste Mal laeuft. `deviceUtcOffset` zu injizieren reicht dafuer NICHT - der Wert
    wandert nur durch die Domaenenschicht, `alarmPlatformTime` liest die echte Geraetezone.
  - Neu `.github/workflows/security-gate.yml` (wiederverwendbar), aufgerufen von `ci.yml` **und**
    `release.yml`; `build-signed-release` hat es als `needs`.
  - Coverage laeuft nur im UTC-Bein und als Artefakt, **ohne** Prozent-Gate: eine willkuerliche
    Schwelle belohnt hier das Falsche - triviale Getter-Tests heben sie, waehrend Frame- und
    Strukturfehler von Zeilenabdeckung ueberhaupt nicht erfasst werden.

### T-93 · Alarm-Ueberleben nach Reboot ist unverifiziert (R3) — BEWEISSAMMLUNG EINGERICHTET (2026-09-10)

- [x] Ein Verfahren, das die Frage ohne Wartezeit beantwortet.
- [ ] Das Ergebnis eines echten Laufs eintragen und das Bein dann scharf stellen.
- **Why:** R3 ist die letzte offene Frage des Produktversprechens "garantiertes Aufwachen" und war
  nie gemessen. Ein Klingel-Test kostet pro Durchgang eine Minute Echtzeit und passt nicht ins
  E2E-Zeitbudget.
- **Status:** `.github/scripts/check_alarm_survival.sh` wertet `dumpsys alarm` aus - damit ist
  "Alarm ist registriert" von "kein Alarm registriert" unterscheidbar, ohne zu warten. Davor laeuft
  `integration_test/arm_alarm_test.dart`, weil `app_test.dart` in `tearDown` konsequent
  `Alarm.stopAll()` ruft und aus ihm heraus nichts registriert bliebe. Bewusst **nicht gatend**:
  das Verhalten ist auf diesem Image nie gemessen worden, und ein unverifiziertes Bein darf keinen
  Release blockieren - es sammelt zuerst Belege.
- **Was aus dem Code schon bekannt ist:** die App hat **keinen** eigenen `BootReceiver`; das
  `alarm`-Plugin registriert einen und armiert die gespeicherten Alarme nach dem Boot per
  `setExactAndAllowWhileIdle(RTC_WAKEUP, …)` neu (Reboot sollte also gruen sein). Bei
  `am force-stop` loescht Android plattformseitig alle Alarme des Pakets, und ein force-gestoppter
  Prozess empfaengt danach kein `BOOT_COMPLETED` mehr - Force-Stop wird also rot sein, und zwar
  **by design**. Das gehoert in R3 als Grenze, nicht als Fehler.

### T-75 · `lastReplanDate` vermischt zwei Zwecke -> FR-9/FR-12 überspringen ganze Tage

- [x] Zwei Felder trennen: `lastProcessedConcludedDay` (steuert `firstUnprocessedDay`) und
      `lastReplanDate` (nur FR-17s Tagessperre).
- **Why:** seit T-71 ist `lastConcludedDay` je nach Auslöser `today` oder `today-1`, `lastReplanDate`
  wird aber immer auf `today` gesetzt (`replan.dart:194`). Ein Erholungs-Replan (App-Resume oder
  Einstellungsänderung vor dem Morgenalarm - ein normaler Vorgang) verbraucht damit den Marker, ohne
  fortzuschreiben; der spätere echte Ring findet `needsDayAdvance == false` und der Tag ist dauerhaft
  verloren. Empirisch: Ring Tag9 -> Erholung Tag10 03:00 -> Ring Tag10 07:00 ergibt
  `gapDayCounter == 1` statt 2. Folge: FR-9s Ventil unterzählt (schlägt ggf. nie an), FR-12 meldet
  für solche Tage nie. Kein Test deckt zwei Replans an einem Tag ab.
- **Done when:** Regressionstest "Erholung an Tag D, Ring an Tag D+1 -> beide Tage gezählt" grün.
- **Status:** Behoben 2026-09-10: `AppState.lastProcessedConcludedDay` neu (mit Migration aus dem alten Schlüssel), `lastReplanDate` trägt nur noch FR-17s Tagessperre. Regressionstests in `test/replan_test.dart`, Gruppe "T-75" (Erholung an Tag D dann Ring an Tag D zählt beide Tage; FR-12 bleibt meldefähig).

### T-76 · Sommerzeit: `dayOffset` in `computeWeekPlan` ist nach der Frühjahrsumstellung um 1 zu klein

- [x] Kalenderarithmetik auch in `computeWeekPlan` (`scheduling_v2.dart:578` und `:592`).
- **Why:** T-74d hat `add(Duration(days:))` nur in `replan.dart` ersetzt. Hier stehen weiterhin
  `anchorDay = window[startIndex].subtract(const Duration(days: 1))` und
  `window[j].difference(anchorDay).inDays` auf lokal getaggten Markern. Unabhängig nachgerechnet
  (`TZ=Europe/Berlin`, Umstellung 2026-03-29): am 28.03. ergeben sich die Offsets
  `[1, 1, 2, 3, 4, 5, 6]` statt `[1..7]` - zwei Fenstertage kollidieren. Folge: `nRest`/`N` zu klein
  (Kurve zu steil, FR-6-Overrun feuert falsch), `distribute` platziert `Tag_i` falsch und
  `groupTarget`s Verletzungsprüfung vergleicht den falschen Tag gegen den `hardFloor` - ein echter
  Termin kann verletzt werden. Für die Tests unsichtbar, weil sie UTC-getaggte Fenster nutzen.
- **Status:** Behoben 2026-09-10: neues `lib/models/scheduling/day_marker.dart` (`midnight`/`dayMarker`/`dayStamp`/`dayDistance`/`isoDate`), `computeWeekPlan` nutzt `dayMarker(window[startIndex], -1)` und `dayDistance(...)`. `replan.dart`s private Kopien sind entfallen. Tests: `test/day_marker_test.dart` und `test/scheduling_v2_dst_test.dart` - letzterer baut das Fenster aus `tz.TZDateTime` in `Europe/Berlin`, reproduziert also unabhängig von der Zeitzone der Testmaschine (der vorherige Teilfix T-74d lief genau daran vorbei). Der rote Testlauf lieferte exakt den vorab handgerechneten Fehlwert 04:36:40 statt 04:40.

### T-77 · `replan()` ist nicht serialisiert - nebenläufige Checkpoints möglich

- [x] Einen Future-Mutex um den gesamten Checkpoint; den Tagesmarker **vor** dem Kalender-I/O
      reservieren, nicht erst am Ende.
- **Why:** vier Auslöser, drei davon `unawaited` (`handler.dart:68`, `main.dart:235`, `main.dart:207`,
  plus die UI). FR-17s Sperre schützt nicht, weil sie `lastReplanDate` liest, das erst am **Ende** von
  `replan()` geschrieben wird (`replan.dart:194`). Klingelt ein Alarm, holt Android die App per
  Full-Screen-Intent nach vorn -> `resumed` -> zweiter Checkpoint startet, während der erste noch im
  Kalender-I/O hängt: `gapDayCounter` wird doppelt inkrementiert und beide berechnen `toAdd` gegen
  dieselbe alte Alarmliste -> Doppelalarme auf derselben Minute.
- **Status:** Behoben 2026-09-10: `runSchedulingCheckpoint()` serialisiert alle Auslöser über eine Future-Kette, und FR-17s Tagessperre wird **innerhalb** der Sperre gelesen. Nachgewiesen wirksam: mit ausgeschaltetem Lock wird `test/checkpoint_test.dart`s erster Fall rot (2 parallele Kalenderzugriffe statt 1).

### T-78 · FR-9s Sicherheitsventil hat für einen `wunschzeit`-Nutzer keinen Rückweg

- [x] Spec-Entscheidung + Umsetzung: Ventil bei `wunschzeit != null` nicht greifen lassen, oder den
      Zähler auch an einem tatsächlich geplanten Tag zurücksetzen, oder eine Reset-Aktion in der UI.
- **Why:** erst durch T-72 erreichbar geworden. `updateGapDayCounter` setzt nur an einem Tag mit
  echtem `hardFloor` zurück. Ein Nutzer mit `wunschzeit` und ohne Kalendertermine wird nach 7 Tagen
  vom Ventil abgeschaltet (alle Fensterwerte `null`, `applyPlannedAlarms` entfernt alle
  Zukunftsalarme) - danach klingelt nichts mehr, es gibt also keinen Ring-Checkpoint, und nur ein
  `hardFloor`-Tag könnte den Zähler zurücksetzen. Der Wecker schaltet sich dauerhaft ab.
- **Status:** Behoben 2026-09-10 - als **Spec-Änderung**, nicht als Bugfix: FR-9 hatte keine Ausnahme, also wurde zuerst FR-9 um den Abschnitt "Ausnahme: gesetzte `wunschzeit`" ergänzt (mit Begründung), dann der bestehende Ventil-Test auf `wunschzeit: null` umgestellt (das war die Bedingung, die ihn überhaupt gültig macht) und ein neuer Ausnahmefall ergänzt. Der Zähler läuft unverändert weiter, das Ventil greift nur bei `wunschzeit == null`.

### T-79 · `Notifications().init()` wird nicht abgewartet, der Post-Frame-Replan braucht das Plugin

- [x] `await Notifications().init()` vor dem ersten Checkpoint (oder in `main()` vor `runApp`).
- **Why:** `main.dart:190` startet `init()` ohne `await` (es enthält `Alarm.init()`,
  `AwesomeNotifications().initialize()`, `setListeners`), der Post-Frame-Callback ruft einen Frame
  später `replan` -> `applyPlannedAlarms` -> `Alarm.getAlarms()`/`Alarm.set()`. Fällt das ins
  Init-Fenster, greifen die `catch`-Zweige: der T-74e-Plattformabgleich wird still deaktiviert und
  `Alarm.set`-Fehler werden pro Alarm geschluckt - der FR-18-Sync kann beim Kaltstart wirkungslos
  bleiben, genau auf FR-17s Reboot-Erholungspfad. Ebenso löst eine vor `setListeners` erzeugte stille
  Notification Checkpoint 2 nicht aus.
- **Status:** Behoben 2026-09-10: `Notifications().init()` wird im Post-Frame-Callback **awaited**, vor dem ersten Checkpoint (und damit vor jedem `Alarm.set`/`getAlarms` und vor der ersten erzeugten Notification).

### T-80 · Der Schlafengeh-Aufhänger wird nach einem Replan nicht neu geplant

- [x] `scheduleSleepReminder` in den Checkpoint aufnehmen (dieselbe Begründung wie bei
      `applyPlannedAlarms`: kein Pfad soll rechnen und vergessen können).
- **Why:** gerufen aus `initState`, Reminder-Toggle, `onSchedulingSettingsChanged` und
  `onAlarmHandled` - **nicht** aus `runForegroundCheckpointSafely`/`runAlarmRingCheckpoint`. Auf dem
  Resume-Pfad (T-68) wird also neu geplant, die Bettzeit-Notification behält aber die alte Zeit;
  Checkpoint 2 feuert dann zu einem Zeitpunkt ohne Bezug zum Plan. Beim nativen Wisch-Dismiss (ohne
  `onAlarmHandled`) ebenso.
- **Status:** Behoben 2026-09-10: strukturell durch T-87 - `scheduleSleepReminder()` steht als letzter Schritt in `runSchedulingCheckpoint()`s fester Sequenz und läuft im `finally`, damit ein Kalenderfehler FR-16s Aufhänger nicht mitreißt.

### T-81 · FR-9s Ventil-Benachrichtigung wiederholt sich bei jedem Replan

- [x] Analog zu T-74a drosseln (eigenes Feld oder eine gemeinsame "einmal pro Episode"-Hilfe).
- **Why:** `replan_notifications.dart:53-63` hat keine Sperre, `safetyValveTriggered` wird aber bei
  jedem Replan neu abgeleitet. Da nach dem Ventil kein Alarm mehr klingelt (T-78), kommt die Meldung
  bei jedem App-Öffnen an einem neuen Tag und bei jeder Einstellungsänderung erneut.
- **Status:** Behoben 2026-09-10: neues `AppState.safetyValveNotificationSent`; `reportReplanNotifications` hat FR-6 und FR-9 in einen gemeinsamen `oncePerEpisode`-Helfer gezogen. FR-12 bleibt bewusst ungedrosselt (einmalige Beobachtung, keine stehende Bedingung).

### T-82 · `pendingDayValues`/`pendingDayInstantAnchored` wachsen unbegrenzt

- [x] Beim Merge alles älter als `lastConcludedDay - 1` verwerfen.
- **Why:** der Merge-ohne-Prune ist für *heute* lasttragend (Kommentar in `replan.dart:137-144`), es
  wird aber nie etwas entfernt: nach einem Jahr ~365 Einträge in einem JSON-String, den jeder Replan
  dekodiert, kopiert und wieder kodiert; `planAlarmSync` und `nextWakeUpTime` iterieren alles.
  Funktional harmlos, aber monoton wachsend - und `pendingDayInstantAnchored` verhält sich
  asymmetrisch (dort werden Einträge per `remove` gelöscht).
- **Status:** Behoben 2026-09-10: der Merge verwirft Einträge vor `lastConcludedDay - 1` (dieselbe Grenze für `pendingDayInstantAnchored`, das vorher asymmetrisch war). Gestern bleibt als Sicherheitsmarge, weil ein Erholungs-Checkpoint gestern als `lastConcludedDay` liest. Tests halten zusätzlich fest, dass der heutige, noch nicht geklingelte Wert erhalten bleibt.

### T-83 · Uneinheitliches `isUtc`-Tagging beim Lesen derselben Map

- [x] Zwei benannte Konverter (`instantFromStored` -> UTC-getaggt für die Domänenschicht,
      `localFromStored` -> `.toLocal()` für Plugin/UI) plus `assert(anchor.isUtc)` in
      `computeWeekPlan`/`distribute`.
- **Why:** dieselbe `Map<String,int?>` wird an fünf Stellen gelesen, dreimal mit `isUtc: true`
  (`replan.dart`), zweimal ohne (`apply_alarms.dart:86`, `next_wake_up.dart:47`). Heute ist beides
  **korrekt** - die Domänenschicht verlangt UTC-Tagging, UI und `ScheduledAlarm.title`
  (`formatDateTime`) verlangen lokales. Genau deshalb ist es gefährlich: ein Vereinheitlichen "für
  Konsistenz" würde Anzeige und Alarmtitel still um den Geräteversatz verschieben.
- **Status:** Behoben 2026-09-10: neues `lib/models/scheduling/stored_values.dart` mit `instantFromStored` (Domäne, UTC-getaggt), `localFromStored` (Plattform/Anzeige) und `toStored`. Alle fünf Lesestellen benutzen jetzt den passenden Namen; rohe `DateTime.fromMillisecondsSinceEpoch`-Aufrufe gibt es außerhalb dieses Moduls nicht mehr.

### T-84 · T-74e ist nur zur Hälfte behoben: Ton/Lautstärke/Gentle-Wake propagieren nicht

- [x] `selectedTone`/`selectedVolume`/`gentleWakeUpEnabled` an `onSchedulingSettingsChanged` hängen
      und `planAlarmSync` um einen Eigenschaftsvergleich erweitern; `ScheduledAlarm` um `volume`
      erweitern.
- **Why:** `planAlarmSync` vergleicht ausschließlich `_toMinute`, und keiner der drei Setter löst
  einen Replan aus - eine Ton- oder Gentle-Wake-Änderung wirkt erst, wenn ein Tag ohnehin neu geplant
  wird. Zusätzlich hat `ScheduledAlarm` kein `volume`-Feld, alle von FR-18 gesetzten Alarme klingeln
  also mit `MyAlarm`s Default 0.6 und ignorieren `appState.selectedVolume` (das eine UI hat).
- **Status:** Behoben 2026-09-10: `ScheduledAlarm` reicht `volume` durch (inkl. JSON und `==`; alte gespeicherte Alarme fallen auf den Default zurück), `applyPlannedAlarms` setzt Ton/Lautstärke/Gentle-Wake aus dem AppState, `planAlarmSync` vergleicht sie mit und ersetzt abweichende Alarme, und Ton-, Lautstärke- und Gentle-Wake-Änderungen lösen einen Checkpoint aus (Lautstärke per `onChangeEnd`, nicht bei jedem Rasterschritt).

### T-85 · Dokumentation widerspricht dem Code an mehreren Stellen

- [x] (a) `docs/scheduling-v2-spec.md`s Kopf nennt T-61 "wieder geöffnet", den UTC+0-Vorbehalt und
      "Phase 6 sollte erst danach beginnen" - alles überholt.
- [x] (b) Der Architektur-Block nennt `timezone_checkpoint.dart` (existiert nicht), `setSleepReminder()`
      (heißt `scheduleSleepReminder`, andere Datei), "vier neue AppState-Felder" (es sind acht) und
      lässt `onSchedulingSettingsChanged`, `apply_alarms.dart` (FR-18!), `replan_notifications.dart`
      und `next_wake_up.dart` im Diagramm aus. FR-3s Tabelle listet `lastEffectiveWakeTime` als Feld
      (wird abgeleitet) und keines der neuen Felder.
- [x] (c) `CLAUDE.md`/`README.md`/`docs/REQUIREMENTS.md` erwähnen scheduling-v2 **nirgends**; der
      Testing-Status listet 4 Testdateien, es gibt 16, und beschreibt `test/scheduling_test.dart` als
      Kernabdeckung der Scheduling-Engine - das ist die abzulösende. Die gepinnte Prozess-Notiz
      verweist auf `docs/scheduling-v2-pseudocode.md`, das nicht existiert.
- [x] (d) FR-16 sagt, Checkpoint 2 hänge am Schlafengeh-Zeitpunkt; der Listener feuert faktisch für
      **jede** erzeugte Notification (auch FR-6/9/12-Warnungen und Debug-Notifications), verschiebt
      also die Vergleichs-Baseline unkontrolliert. Entweder FR-16 präzisieren oder auf die
      Reminder-ID filtern.
- [x] (e) FR-16s Sommerzeit-Test suggeriert, der Fall sei vollständig behandelt; am Umstellungstag
      klingelt ein wall-clock-verankerter Alarm dennoch eine Stunde falsch, weil der Wert am Vortag
      mit dem alten Versatz berechnet wird und Checkpoint 2 zur Bettzeit noch vor der Umstellung
      läuft. Als bewusste Grenze dokumentieren.
- **Status:** (a), (b), (d), (e) erledigt 2026-09-10 - Kopf neu geschrieben (Konsolidierungs-Abschnitt
  statt widersprüchlicher Chronik), Architektur-Block und Mermaid-Diagramm auf den tatsächlichen
  Aufbau gebracht, FR-3s Tabelle vollständig (neun Felder, `lastEffectiveWakeTime` als abgeleitet
  erklärt), FR-16 um die Listener-Präzisierung und die Umstellungstag-Grenze ergänzt. (c) bleibt
  offen bis Phase 6, weil Phase 6 genau diese Aussagen erneut ändert.
- **Status (c):** erledigt 2026-09-10 nach Phase 6. `CLAUDE.md` hat einen neuen Abschnitt
  "Scheduling engine" (Schichtung als Tabelle, plus die zwei lasttragenden Regeln: kein zweiter
  Einstiegspunkt, und die Frame-Konvention), der Testing-Status nennt 176 Tests in 19 Dateien und
  den Hinweis, dass Zeitzonen-Tests ihre Fixtures als `tz.TZDateTime` bauen müssen (mit
  `DateTime.utc` auf einer UTC+0-Maschine sind die Frame- und DST-Fehlerklassen prinzipiell nicht
  reproduzierbar - genau daran liefen die ersten Versuche zu T-61 und T-74d vorbei). `README.md`
  hat einen Abschnitt "Alarm scheduling" in Nutzersprache; drei Punkte sind aus der Blocker-Liste
  gestrichen. `docs/REQUIREMENTS.md` R2 ist von "not met - and more fundamentally than unverified"
  auf "met in substance" umgeschrieben, mit dem einen ehrlichen Vorbehalt (die Kette trägt sich
  selbst nur, solange sie klingelt - der Reboot-Fall ist R3) - die Zusammenfassung der offenen
  Lücken führt R2 nicht mehr. Der Verweis auf das nicht existierende
  `docs/scheduling-v2-pseudocode.md` steht nur in einer gepinnten Notiz außerhalb des Repos und
  ist hier nicht adressierbar.

### T-86 · Toter Code und verwaister Zustand (Inventar für Phase 6)

- [x] `test/scheduling_test.dart` (337 Zeilen, testet nur die zu löschenden Funktionen);
      `Scheduler.nextAlarmTime` und `Scheduler.setScheduledAlarmToNow` (keine Aufrufer mehr);
      `AppState._getAlarmTime`s `ScheduledAlarm`-Zweig (unerreichbar **und** eine latente T-61-Falle:
      baut `DateTime(alarm.time.year, ...)`, würde also UTC-Ziffern als lokal reinterpretieren -
      löschen, nicht reparieren); `wakeUpSteps` (einziger Leser: alter Scheduler);
      `rescheduleOnAlarm` (einziger Leser: `onAlarmHandled`, keine UI);
      `doNotDisturbEnabled`/`turnOffNotifications`/`turnOffCalls` (**null** Leser, keine UI);
      `_MyHomePageState.notifications` (nie gelesen); `ScheduledAlarm`s `title`-Parameter (wird vom
      Konstruktor immer überschrieben).
- **Status:** Erledigt 2026-09-10 (Phase 6). Entfernt: `test/scheduling_test.dart`,
  `Scheduler.nextAlarmTime`/`setScheduledAlarmToNow` (mit der ganzen Datei), der unerreichbare
  `ScheduledAlarm`-Zweig in `AppState._getAlarmTime` (die Funktion nimmt jetzt `ManualAlarm` - die
  latente T-61-Falle darin ist damit weg statt reparaturbedürftig), `wakeUpSteps`,
  `rescheduleOnAlarm`, `doNotDisturbEnabled`, `turnOffNotifications`, `turnOffCalls` (jeweils Feld,
  Getter, Setter und Ladepfad) sowie `ScheduledAlarm`s wirkungsloser `title`-Parameter.
  `_MyHomePageState.notifications` ist **nicht** entfallen - es hat durch T-79 einen echten Leser
  bekommen (`await notifications.init()`).

### T-87 · Strukturelle Vereinfachung: ein Checkpoint-Einstiegspunkt statt fünf

- [x] `replan`, `runAlarmRingCheckpoint`, `onAppForegroundCheckpoint`, `runForegroundCheckpointSafely`
      und `onSchedulingSettingsChanged` zu einem `runSchedulingCheckpoint({required trigger})` mit
      fester, vollständiger Sequenz zusammenlegen (Lock -> State-Reload -> Offset -> replan ->
      applyPlannedAlarms -> reportReplanNotifications -> scheduleSleepReminder).
- **Why:** die fünf Einstiegspunkte unterscheiden sich in vier orthogonalen Dimensionen (Offset
  schreiben? `todayAlreadyRang`? melden? Reminder neu planen? Fehler schlucken?). Genau diese Matrix
  hat T-67, T-71 und T-80 produziert - dreimal derselbe Fehler in derselben Struktur. Erledigt T-77
  (Lock) und T-80 strukturell mit. Ergänzend: die Tages-/Datumsarithmetik in ein `DayMarker`-Modul
  bündeln (`_midnight`/`_dayMarker`/`_isoDate`/`_dateTimeLike` plus die Ad-hoc-Stellen aus T-76) und
  die Speicherform hinter die Konverter aus T-83 legen.
- **Status:** Umgesetzt 2026-09-10: neues `lib/models/scheduling/checkpoint.dart` mit `runSchedulingCheckpoint({trigger})` und `runCheckpointSafely(...)`. `runAlarmRingCheckpoint`, `onAppForegroundCheckpoint`, `runForegroundCheckpointSafely` und `onSchedulingSettingsChanged` (samt Datei) sind entfallen; ihre Zusicherungen sind nach `test/checkpoint_test.dart` portiert, der T-67-Meldepfad läuft dort jetzt durch die echte Verdrahtung statt durch injizierte Nähte. Ebenfalls erledigt: das gemeinsame Tagesmarker-Modul (T-76) und die benannten Konverter (T-83).

### T-88 · Kleinere, bestätigte Punkte

- [x] `platformAlarmTimes` enthält auch `ManualAlarm`-Zeiten - ein `ScheduledAlarm` auf derselben
      Minute gilt fälschlich als "auf der Plattform vorhanden" (einzeiliger Fix: nur bekannte
      `ScheduledAlarm`-IDs betrachten).
- [x] Der "Preferred wake-up time"-Picker beschriftet eine Uhrzeit als Dauer (" h", geteilter
      `_buildTimePicker`).
- [x] `maxDailyDelta`-Clamping (Minimum 15 min) ist für den Nutzer unsichtbar; nach oben gibt es keine
      Grenze (23:59 deaktiviert die Glättung faktisch).
- [x] `overrunNotificationSent` wird vor dem `await` gesetzt - schlägt die Meldung fehl, wird sie für
      die Episode nie nachgeholt.
- **Status:** Behoben 2026-09-10: `planAlarmSync` vergleicht die Plattform über **IDs** statt über Zeiten (`platformAlarmIds`) - damit deckt ein fremder Alarm auf derselben Minute nichts mehr ab, und die T-61-Frame-Falle verschwindet an dieser Grenze ganz. Der `wunschzeit`-Picker ist als Uhrzeit beschriftet (" Uhr" statt " h"), das `maxDailyDelta`-Minimum steht als Hinweis in der UI, und die Episoden-Merker werden erst nach erfolgreichem Senden gesetzt.

### T-63 · scheduling-v2 computes wake times but nothing ever turns them into real alarms

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
  alarm behavior is unchanged from before the whole effort; (2) Phase 6 ("alten `Scheduler` entfernen")
  would delete the *only* code that sets calendar-derived alarms, so doing it before this item lands
  would leave the app with no calendar-derived alarms at all. `docs/scheduling-v2-spec.md`'s own
  Implementierungsreihenfolge (Phases 0-7) never contains this step - it is a genuine gap in the plan,
  not just in the code.
- **Evidence:** `grep -rn pendingDayValues lib/` (only `replan.dart` + comments);
  `grep -rn "addAlarm(\|Alarm.set(" lib/` (only `app_state.dart` and the old `scheduling.dart`);
  `docs/scheduling-v2-spec.md` (no FR and no phase step covers applying the computed values).
- **Done when:** a tested step exists that turns each planned day's value into exactly one
  `ScheduledAlarm` (respecting FR-15: never touching `ManualAlarm`s, and FR-11: only for days that
  haven't rung yet), the spec records it as its own FR/phase step, and Phase 6 can remove the old
  `Scheduler` without losing alarm functionality. Note T-61 (UTC+0 assumption) becomes
  **user-visible** the moment this lands - it should be fixed first or at the same time.

### T-62 · Unverified: does a silent background notification actually trigger `onNotificationCreatedMethod`?

- [ ] Confirm on a real/emulated Android device that scheduling a
      `NotificationContent` with neither `title` nor `body` (Phase 5 step 21,
      `sleepReminderContent(reminderEnabled: false)`) actually fires
      `onNotificationCreatedMethod` (`lib/utils/notifications.dart`) at the
      scheduled time, including after the app has been backgrounded.
- **Why:** docs/scheduling-v2-spec.md's own FR-16 "Voraussetzung" section calls this "per
  Paketquellcode verifiziert, hohe Konfidenz" but explicitly recommends (without treating it as a
  TDD blocker) a device confirmation before relying on it - this environment has no Android
  emulator/device, so that confirmation has not happened yet. Everything testable without one
  (`runTimezoneCheckpoint2`'s own logic, `setListeners` being wired with the right callback) is unit
  tested (`test/replan_test.dart`), but the actual OS/plugin behavior triggering the callback for a
  title/body-less notification is unverified.
- **Evidence:** `lib/utils/notifications.dart` (`onNotificationCreatedMethod`, `Notifications.init()`'s
  `setListeners` call); `docs/scheduling-v2-spec.md` FR-16 "Voraussetzung, noch zu bauen".
- **Done when:** confirmed on a real/emulated device (or via `integration_test/app_test.dart`, if a
  reliable way to simulate the scheduled notification firing is found), or downgraded from
  "recommended" if a more direct source confirms the behavior without needing a live test.

