# TODOs

The single task list for WakeyWakey, sorted by priority. Two sources feed it:

- **Device feedback** from the maintainer trying the app on real hardware (intake happens in the
  untracked `tasks.txt`; items are moved here once they are formulated as TODOs).
- **The audit** of project description, documentation, requirements, tests and CI against the
  actual code.

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

### T-06 · The signed release APK is built and published with no quality gate

- [ ] Gate the release build on the checks that are supposed to protect it.
- **Why:** in `ci.yml` the release-build job declares no `needs:`, so it runs regardless of whether
  analyze, tests, SCA, secret scanning or SAST failed; `release.yml` runs no SCA/secret/SAST job at
  all. A red run still produces a downloadable, signed, signature-verified APK that the README
  presents as the production artifact.
- **Evidence:** `.github/workflows/ci.yml:123` (no `needs:`), `:183` (the only `needs:` in the
  file); a real run concluded Analyze **failure**, SCA **failure**, mobsfscan **failure**, MobSF
  **failure** and still uploaded three artifacts.
- **Done when:** the release build depends on analyze/test/SCA/secret/SAST, and a deliberately
  failing check demonstrably prevents an APK from being published.
- **Requirement:** R1

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

### T-08 · The QR deactivation gate has no negative test

- [ ] Test the failing direction, and the two null-code bypasses.
- **Why:** this is the app's differentiating security property, and only the *correct* payload is
  ever injected — deleting the payload comparison entirely would keep CI green. Untested too:
  validation returns `true` when no code is stored, and the first scanned code is silently adopted
  as the deactivation code.
- **Evidence:** `integration_test/app_test.dart:141,165-167` (correct payload only), `:179-180`
  (assertions); `lib/screens/scan_code/qr_scanner.dart:146-148` (the comparison), `:137-141` and
  `:112-119` (the bypasses).
- **Done when:** a wrong payload leaves the scanner mounted and the alarm ringing; the null-code
  branches have unit tests (extract the predicate so it is testable without a device).
- **Requirement:** R4

### T-09 · The dismissal tests assert navigation, not that the alarm stopped

- [ ] Assert alarm state, not screen state — and stop swallowing stop failures in production.
- **Why:** both tests only check that a screen disappeared, and both production paths navigate away
  even when stopping the alarm throws. No test queries the alarm plugin at all, so an alarm that
  keeps ringing behind a dismissed overlay passes.
- **Evidence:** `integration_test/app_test.dart:132-133`, `:179-180`;
  `lib/screens/alarms/screen_active_alarm.dart:125-135` (pop outside the `try`);
  `lib/screens/scan_code/qr_scanner.dart:152-166` (catch → `return true`);
  `grep -rn "Alarm\." integration_test/` finds no plugin query.
- **Done when:** each dismissal asserts the alarm is absent from `Alarm.getAlarms()` / no longer
  ringing, and a stop failure surfaces instead of silently popping.

### T-10 · The scheduling engine has no real tests

- [ ] Make the production scheduling functions testable and port the existing cases onto them;
      retire the forked scripts.
- **Why:** `flutter test` discovers only `test/**/*_test.dart`, so `test/adjustTime/` and
  `test/getEarliestAlarm/` never run. They also do not import the app — and `test/adjustTime/`
  implements helpers (`isBeforeTime`, `isAfterTime`, `isAtSameMomentAsTime`) and a two-pass
  algorithm that exist nowhere in `lib/`. Converting them as-is would test a fork, not the shipped
  scheduler. The 17 `getEarliestAlarm` cases are worth keeping; their harness prints results and
  exits 0 either way.
- **Evidence:** `grep -rn "isBeforeTime" lib/` → 0 hits; neither script imports
  `package:wakeywakey`; `test/getEarliestAlarm/main.dart:15-19` sets no exit code.
- **Done when:** `_getEarliestEvent` / `_adjustAlarmTimes` / `_getStartTimeForDate` are reachable
  from tests, the ported cases run under `flutter test`, and `test/adjustTime/` is deleted or
  clearly quarantined as a historical experiment.
- **Requirement:** R2

### T-11 · Two of R1's five security tools cannot fail a run

- [ ] Make the claim match the pipeline, or the pipeline match the claim — and record accepted
      findings in a tracked file.
- **Why:** R1 asserts "no high-or-above finding — met", but `mobsfscan` runs with `--no-fail` and
  the MobSF step only prints counts with no threshold. The current MobSF report on master carries
  one HIGH (installable on Android 7.0 / `minSdk=24`) and a security score of 51 while the job
  concludes success. The task-hijacking finding R1 cites as a known false positive has its
  rationale written down nowhere.
- **Evidence:** `.github/workflows/ci.yml:115` (`--no-fail`), `scripts/mobsf_summary.py` (prints
  only); MobSF report from the newest master run: `HIGH: 1`, `WARNING: 14`, `security_score: 51`;
  `grep -rniE "strandhogg|task.?hijack"` finds only the two places that *cite* the rationale
  (`docs/REQUIREMENTS.md:17-18`, `ci.yml:112`).
- **Done when:** un-excepted HIGH findings fail the run, accepted exceptions live in a tracked
  file with a reason and a date, and R1's wording matches what actually gates.
- **Requirement:** R1

### T-12 · The evidence several requirements cite is not in the repository

- [ ] Track the security/quality evidence, or stop citing it as the basis for a "met" status.
- **Why:** `docs/quality-baseline-2026-09.md` and `docs/release-readiness-2026-09.md` are excluded
  by `.gitignore`, so anyone cloning this repo gets a requirements register whose "checked by" and
  "met" justifications point at files that do not exist. They are referenced from tracked files in
  about a dozen places, including test-file headers and workflow comments.
- **Evidence:** `.gitignore:438-439`; `git ls-files docs/` lists six files, neither snapshot among
  them; citations in `docs/REQUIREMENTS.md:19,30,33,71,76,122,140`, `CLAUDE.md:117,119,126`,
  `integration_test/app_test.dart:12,18`, `test/handler_stale_alarm_test.dart:1`,
  `.github/workflows/ci.yml:111`, `.github/workflows/release.yml:61`.
- **Done when:** the substance those documents carry is either committed (PII-reviewed first) or
  summarised inline where it is cited, and no tracked file points at an untracked path.
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

### T-15 · The gentle-wake ramp has no evidence of any kind

- [ ] Exercise the fade path, or state plainly that it is unverified.
- **Why:** a headline feature and half of R4. Gentle wake defaults to off, so no test enables it and
  the `VolumeSettings.fade` branch is never executed; the CI emulator also runs without audio. The
  audio-focus log does show the app taking alarm-usage audio focus, which is genuine but says
  nothing about a gradual ramp.
- **Evidence:** `lib/app_state.dart:44` (`_gentleWakeUpEnabled = false`), `:485-489` (fade vs.
  fixed), `lib/screens/alarms/screen_alarms.dart:263` (dialog default);
  `grep -niE "gentle|fade|volume" integration_test/app_test.dart` → nothing; emulator started with
  `-noaudio`; 3 of 249 audio-focus polls show `usage=USAGE_ALARM`.
- **Done when:** either an E2E scenario enables gentle wake and samples stream volume across the
  60-second window asserting a rising trajectory, or R4 and the evidence README say the ramp is
  unverified and only the fixed-volume path is exercised.
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

### T-17 · The privacy policy does not match the app

- [ ] Rewrite `assets/text/Privacy.md` against what the app actually does.
- **Why:** R11 reads "met", but that check only covered the contact address. The policy describes
  data the app cannot collect (location, NFC) while omitting camera, gallery access,
  calendar *writes* and the locally stored deactivation code.
- **Evidence:** `assets/text/Privacy.md` against the permissions in
  `android/app/src/main/AndroidManifest.xml` and the QR/calendar code paths.
- **Done when:** every declared permission and every stored data item is either described or
  removed, and R11's status states what was actually reviewed.
- **Requirement:** R11

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

### T-22 · Rework the README for a reader who is not a developer

- [ ] Remove the note about removed Windows/macOS/web scaffolding; remove the launcher-icon
      regeneration step (the icons are static); remove the VirtualBox/`vboxsf` note; rewrite
      "Quality Checks" so it does not address the reader as a contributor who will push tags; and
      replace the "Testing status" section with something shorter in a different form.
- **Why:** requested. Most of that material belongs in `CLAUDE.md`, not in the project's front page.
- **Done when:** the README reads as a description of the app for someone evaluating or using it,
  with contributor-only detail moved or dropped.

### T-23 · Remove the known flake mechanisms from the E2E harness

- [ ] Fail fast on a mis-scheduled alarm, add teardown, and stop asserting on transient states.
- **Why:** three mechanisms produce red runs that misdescribe their own cause: state is sampled once
  per 500 ms so short-lived screens can be missed; the "now + 1 minute" default is minute-truncated,
  so a save crossing a minute boundary schedules the alarm 24 hours out and the test reports "alarm
  never rang"; and no teardown stops leftover alarms, so one failure cascades into the next
  scenario.
- **Evidence:** `integration_test/app_test.dart:38-52,56-70` (sampling), `:104` (save after
  `pumpAndSettle`); `lib/screens/alarms/screen_alarms.dart:266-268` (truncation),
  `lib/app_state.dart:455-459` (`isBefore(now)` → `+1 day`);
  `integration_test/app_test.dart:113-115` (teardown nulls the override only).
- **Done when:** the helper reads back the created alarm and fails immediately with a clear message
  if it is more than ~2 minutes out; `setUp`/`tearDown` stop all alarms; assertions target durable
  state rather than a widget present at a sampling instant.

### T-24 · Stop evidence collection from degrading silently, and keep failure evidence

- [ ] Report what was actually collected, and retain the newest failure as well as the newest
      success.
- **Why:** the evidence artifact is the only human-inspectable proof of on-device behaviour, and it
  is both incomplete-by-silence and unread. In the last green run 7 of 12 recording segments were
  lost to "Operation not permitted" without affecting the job result, because both `screenrecord`
  and `adb pull` are followed by `|| true`; an entirely empty directory would only warn. The
  retention script keeps only the newest run and the newest *successful* run, so it deleted the
  evidence of both earlier failed runs — the project's own "2 passed, 1 failed" claims can no
  longer be re-derived from artifacts.
- **Evidence:** `.github/scripts/run_e2e_tests.sh:48-49` (`|| true`),
  `.github/workflows/release.yml:93` (`if-no-files-found: warn`),
  `.github/scripts/cleanup_old_artifacts.sh:22-25` (success-only keep); artifact listings for the
  two earlier E2E runs now return `total_count: 0`.
- **Done when:** a missing segment is visible in the job summary, the script prints a manifest of
  collected files, and the retention rule also keeps the most recent failed run.

### T-25 · Investigate the system ANR during E2E runs

- [ ] Find out why `system_server` is not responding on the CI emulator, and reduce it.
- **Why:** the evidence video of the green run shows an Android "Process system isn't responding"
  dialog in every sampled frame, across the whole test window. The tests pass anyway because
  `integration_test` drives the widget tree rather than the visible screen — which means the suite
  is insensitive to a system-level dialog that a real user would face, and it weakens how much
  weight "it works on a device" carries.
- **Evidence:** `e2e-evidence` recordings from the newest release run (dialog present in 22 of 22
  sampled frames, alongside the app's genuine "Your alarm is ringing" notification).
- **Done when:** the cause is known (emulator resources, boot timing, or the app's own startup
  work), and either the ANR is gone or the run records it explicitly instead of hiding it in a
  video nobody opens.

### T-26 · `scripts/security-scan.sh` can report a false all-clear

- [ ] Add trufflehog's `--fail` flag and describe the script's real coverage.
- **Why:** it is the only pre-commit gate contributors are told to run, and its header promises a
  non-zero exit on findings — but the trufflehog step omits the `--fail` that CI uses, so the script
  can print "All checks completed cleanly" while findings exist. It also covers two of R1's five
  tools and excludes paths CI scans.
- **Evidence:** `scripts/security-scan.sh:44` vs `.github/workflows/ci.yml:98`.
- **Done when:** the local script fails on the same findings CI fails on, and its header states
  which of R1's tools it does and does not cover.
- **Requirement:** R1

### T-27 · The global volume setting never reaches calendar-derived alarms

- [ ] Thread the configured volume through to scheduled alarms.
- **Why:** `ScheduledAlarm` takes no volume, so calendar-derived alarms always ring at the hardcoded
  default regardless of the user's setting — while manual alarms honour it.
- **Evidence:** `lib/models/alarms/scheduled_alarm.dart` (no volume field) vs
  `lib/models/alarms/manual_alarm.dart` and the volume default in `lib/app_state.dart`.
- **Done when:** a calendar-derived alarm rings at the configured volume, asserted by a test.

### T-28 · Correct the stale claims in `CLAUDE.md` and `REQUIREMENTS.md`

- [ ] Bring both in line with what is now verified.
- **Why:** both still state that no build has ever been installed or run on a real or emulated
  Android device, and `CLAUDE.md` additionally states that no integration/E2E tests exist. The
  release workflow runs E2E tests on an API-34 emulator and gates the signed build on them.
  `REQUIREMENTS.md` uses the falsified claim as the single root cause of R2/R3/R4, so its register
  mis-attributes which gaps actually remain. Neither document mentions the E2E gate, the evidence
  artifact, or how to run the suite.
- **Evidence:** `CLAUDE.md:116-121`, `docs/REQUIREMENTS.md:138-141`; the newest release run passed
  all three E2E scenarios on the emulator.
- **Done when:** both documents state what is verified on-device and narrow the open gaps to
  reboot/force-stop survival, audio and the gentle-wake ramp, real camera decoding, and
  calendar-derived scheduling — and the E2E suite is documented well enough to run.

---

## P3 — housekeeping

### T-29 · Record the provenance and licence of bundled assets

- [ ] Track down where `assets/sounds/*.mp3` and the icon assets came from, and under what licence.
- **Why:** R10 is unverified and no record exists. Needed before public distribution, and it
  interacts with T-05.
- **Done when:** every bundled asset has a documented source and licence, or is replaced.
- **Requirement:** R10

### T-30 · Annotate or retire the planning artifacts

- [ ] Mark what the personas, use cases, UML diagram and risk graphic describe but never shipped.
- **Why:** the descriptive documents miss the app in both directions: the README's three headline
  features understate the shipped surface, while `personas.md`, the UML diagram and `risk.png`
  still model features and classes that were never built and carry no annotation saying so.
  `use-cases.md` states that everything unmarked shipped, which is not the case.
- **Done when:** each planning document either matches the code or says plainly where it does not.

### T-31 · Triage the `main.dart` TODO backlog

- [ ] Decide which of the numbered TODOs at the top of `lib/main.dart` are real commitments and
      move those here.
- **Why:** the block mixes cosmetic wishes with items that mean an advertised setting does not
  exist. Several overlap with T-01, T-02, T-14 and T-27.
- **Evidence:** `lib/main.dart:21-63`.
- **Done when:** the block is reduced to genuine in-code markers, and anything user-visible lives
  in this file with a priority.
