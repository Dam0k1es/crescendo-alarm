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

### T-13 · The tag → GitHub Release path has never run and would fail

- [ ] Give the release-attach step the permission it needs and dry-run the tag path once.
- **Why:** the documented release ritual is untested. No tag and no release exist, the attach step
  is skipped in every run so far, and the repository's default workflow token is read-only while
  `release.yml` declares `permissions:` only on its cleanup job — so the first real `v*.*.*` tag
  would fail on permissions.
- **Evidence:** `gh api …/tags` and `…/releases` both empty; `default_workflow_permissions: read`;
  `.github/workflows/release.yml:153-158` (attach step) with no `contents: write` on its job.
- **Done when:** a throwaway pre-release tag produces a GitHub Release with the APK attached.

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

- [ ] Annotate the UML diagram and risk graphic themselves (or retire them).
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

