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
- **Der Status steht in der Überschrift**, nicht nur im Rumpf — `BEHOBEN`, `WIDERLEGT`,
  `BEANTWORTET`, `TEILWEISE`/`GROSSTEILS`, oder `OFFENE SPEC-ENTSCHEIDUNG`. Eine Überschrift ohne
  solchen Zusatz bedeutet: offen. Wer ein Item schliesst, zieht die Überschrift mit; sonst ist die
  Liste nicht mehr überfliegbar, und genau das ist ihr ganzer Wert. (Am 2026-09-11 trugen 24 längst
  erledigte Items ihren Status nur im Rumpf.)
- **P0** blocks any push to `master` / production. **P1** must be resolved or consciously accepted
  before a public release. **P2** is real work that does not block a release. **P3** is
  housekeeping.
- `R1`–`R12` refer to [`REQUIREMENTS.md`](REQUIREMENTS.md).
- *Evidence* cites where the problem is visible, so nobody has to re-derive it.
- *Done when* is the acceptance criterion — if it cannot be checked, the TODO is not finished.

---

## Wartet auf eine Entscheidung, nicht auf Arbeit

Sieben Punkte sind untersucht, reproduziert und **nicht** umgesetzt, weil in allen der Code der
Spec folgt und die *Anforderung* die Lücke hat. Sie brauchen eine Entscheidung des
Projektverantwortlichen, keine weitere Analyse — jedes Item nennt die Frage, die Lesarten und was
jede kostet:

| | Frage in einem Satz |
|---|---|
| **T-112** | Was gilt, wenn eine Kurve über Mitternacht rutscht — darf ein Kalendertag zwei Weckzeiten tragen und ein anderer keine? |
| **T-113** | Soll FR-16s Checkpoint 2 die bereits scharf gestellten Alarme nachziehen? (Sonst klingelt der erste Wecker nach einem Flug um die volle Versatzdifferenz falsch.) |
| **T-115** | Welche Richtung gewinnt bei einem Abstand von exakt 12 Stunden? |
| **T-119** | Muss die Tageszuordnung den Versatz des jeweiligen Fenstertages verwenden? (Sonst wird zweimal im Jahr ein echter Morgentermin verschluckt.) |
| **T-120** | Welchem Tag gehört ein Weckwert, den die Vorlaufzeiten über Mitternacht zurückschieben? |
| **T-121** | Setzt ein Termin im Fenster FR-9s Ventil auch für die Tage **nach** ihm ausser Kraft? |
| **T-122** | Entscheidet über die Verankerung die Herkunft eines Wertes oder seine Bedeutung? |

Der jeweils **entschiedene** Teil dieser Fälle ist bereits durch Tests festgehalten (T-118,
T-123 … T-128) — das ist die Grundlage, gegen die eine Entscheidung formuliert werden kann.

---

## P0 — blocks a production push

### T-01 · Sleep-Habits durations are not subtracted from the alarm time — BEHOBEN (2026-09-10, Phase 6)

- [x] Apply "duration to wake up" and "duration to get ready" when deriving an alarm from a
      calendar entry.
- **Why:** the app's central promise. Confirmed on a real device: a calendar entry at 07:00 with
  both durations set to 15 minutes produced an alarm at 07:00 instead of 06:30.
- **Evidence (damals):** device test by the maintainer; scheduling path in the since-deleted
  `lib/models/scheduling/scheduling.dart` and `lib/screens/sleep_habits/screen_sleephabits.dart`.
- **Resolution:** die Subtraktion ist jetzt FR-2s Definition von `hardFloor` (frühester
  nicht-ganztägiger Termin − `durationToWakeUp` − `durationToGetReady`), umgesetzt in
  `lib/models/scheduling/scheduling_v2.dart`s `hardFloor()`. Alle drei durchgerechneten
  FR-2-Testfälle liegen mit denselben Zahlen in `test/scheduling_v2_test.dart:151-196` — der
  erste davon ist genau das gemeldete Gerätebeispiel: Termine um 09:00 und 07:00, beide Dauern
  15 min, erwartet **06:30** (der frühere Termin zählt, minus 15 + 15).
  Auf einem echten Emulator belegt hat das der E2E-Fall "injizierter Termin wird zu registrierten
  Plattformalarmen" (T-63/T-91, Lauf 34532845207). Die verbleibende Prüfung auf einem **echten**
  Gerät steht als B2/B4 in `docs/device-trial-checklist.md`.
- **Requirement:** R2

### T-02 · Calendar-derived alarm times are discarded for most days — BEHOBEN (2026-09-10, Phase 6)

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
- **Resolution (2026-09-10, Phase 6):** `_adjustAlarmTimes` existiert nicht mehr — die Datei ist
  mit dem alten Motor gelöscht (T-64/T-86). Die drei gemeldeten Symptome haben in scheduling-v2
  je eine benannte Anforderung, die das Gegenteil zusichert: jeder Tag behält seinen eigenen Wert
  (FR-6 "jeder `Tag_i` bekommt sein eigenes, echtes Kalenderdatum"), ein Tag ohne Termin driftet
  zur Wunschzeit statt verworfen zu werden (FR-4), und es gibt keinen Abbruch ab sieben
  geschätzten Alarmen — FR-9s Ventil ist die eine bewusste Ausnahme und meldet sich beim Nutzer.
  Der 23:59-Platzhalter ist ersatzlos weg; FR-18 legt nur Alarme für tatsächlich geplante Werte
  an. Abgedeckt von der ganzen scheduling-v2-Suite, für den Mehrtagesfall namentlich
  `test/scheduling_v2_test.dart`s `computeWeekPlan`-Gruppe und `test/replan_test.dart`.
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
  `needs: [analyze-and-test, security-gate, e2e-tests]` (bis zum Gate-Refactoring T-92 hiess die
  Liste `[analyze-and-test, sca-and-secrets, mobsfscan, e2e-tests]`; `security-gate` fasst die
  beiden mittleren jetzt als aufrufbaren Workflow zusammen, den auch `release.yml` benutzt) - a
  failure in any of those
  now prevents the job from running at all, per GitHub Actions' own `needs:` semantics (not
  demonstrated live with a deliberately-failing check, to avoid sabotaging a real pipeline run for
  the sake of a test; confirmed instead by a real green run where `build-android-release` correctly
  waited for, and only ran after, all four `needs:` had passed - see T-37's verification note).
  MobSF itself (needs the built APK, so it structurally cannot gate the build that produces it) now
  actively revokes the artifact after the fact instead of just marking the run red - see T-11.
- **Still open:** the "deliberately failing check" demonstration itself.
- **Requirement:** R1

### T-32 · The background rescheduling R2 requires does not exist — BEHOBEN (2026-09-10, formal verworfen und ersetzt)

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
- **Resolution:** die zweite Hälfte wurde gewählt, bewusst und begründet. Ein periodischer
  Hintergrund-Worker ist ausdrücklich **nicht** gebaut (Akku, herstellereigene
  Hintergrundgrenzen — `docs/choice-of-technologies.md` und FR-16 argumentieren beide dagegen).
  Stattdessen hängt jeder Checkpoint an einem Ereignis, das ohnehin stattfindet: beim Klingeln
  (FR-8, im Prozess, den der Alarm selbst gestartet hat), an der Bettzeit-Notification (FR-16
  Checkpoint 2) und beim App-Vordergrund als Erholung nach Reboot/Force-Quit (FR-17). Da jeder
  Checkpoint das **volle** 7-Tage-Fenster neu plant und anwendet (FR-8 + FR-18), kann "weniger als
  7 Tage armiert" keinen Checkpoint überdauern. R2 ist entsprechend umgeschrieben und führt die
  eine verbleibende Einschränkung ehrlich: die Kette trägt sich selbst nur, solange sie klingelt —
  reisst sie ganz und wird die App nie geöffnet, planst nichts neu. Das ist R3/T-04, nicht T-32.
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

### T-42 · Six persisted settings are unreachable or unused — GROSSTEILS BEHOBEN (2026-09-10)

- [x] Fuenf der sechs entfernt: `doNotDisturbEnabled`, `turnOffNotifications`, `turnOffCalls`
      (Feature nie gebaut), `wakeUpSteps` und `rescheduleOnAlarm` (beide gehoerten zum alten
      Motor und sind mit ihm verschwunden - Phase 6, T-86). `grep -rn` findet sie in `lib/` nicht
      mehr; der einzige verbliebene Treffer fuer `rescheduleOnAlarm` ist ein historischer
      Kommentar in `handler.dart`, der erklaert, was dort frueher stand.
- [ ] **Verbleibt: `startOfWeekDay`.** Und der Fall ist schlimmer als "keine UI": sein einziger
      Leser `getStartOfWeek` (`lib/utils/utils.dart:112-118`) benutzt den Wert nur als
      *Bedingung*, nicht als Ziel - trifft der Wochentag nicht zu, rechnet er mit
      `subtract(weekday - 1)` **immer auf Montag** zurueck. Die Einstellung entscheidet also
      lediglich, OB korrigiert wird, nie WORAUF. Betroffen ist die Kalender-Vorladung des
      Schedule-Schirms, nicht scheduling-v2. Entweder den Helfer auf den eingestellten Tag rechnen
      lassen und eine UI ergaenzen, oder die Einstellung ersatzlos streichen.
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

### T-46 · The scheduling window is hardcoded — BEANTWORTET (2026-09-10, durch scheduling-v2)

- [x] **Begruendet statt konfigurierbar gemacht.** FR-8 legt das Fenster ausdruecklich fest: "Nur
      das sichtbare 7-Tage-Fenster, kein groesserer Horizont", mit Begruendung im Spec-Text. Der
      Abbruch ab sieben geschaetzten Alarmen existiert nicht mehr (er gehoerte zum alten Motor);
      an seine Stelle tritt FR-9s Ventil mit einer benannten Schwelle (`gapDayValveThreshold`)
      und einer Benachrichtigung an den Nutzer. Bleibt als urspruengliche Aufgabe:
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

### T-57 · No fallback scheduling target when there are no calendar entries at all — BEHOBEN (2026-09-10, durch scheduling-v2)

- [x] **Entschieden und gebaut.** Ein Tag ohne Termin ist kein Sonderfall mehr, sondern FR-4s
      Lueckentag: der Wert driftet zur `wunschzeit`, begrenzt durch `maxDailyDelta`, und haelt
      ohne `wunschzeit` bei der zuletzt geklingelten Uhrzeit. Existiert gar kein Anker, greift
      FR-10s Kaltstart (es wird nichts erfunden); reisst die Terminlage dauerhaft ab, greift
      FR-9s Ventil und **meldet sich beim Nutzer**, statt stillschweigend nichts zu planen. Die
      urspruengliche Formulierung bezog sich auf `scheduleAlarms`, das es nicht mehr gibt.
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

### T-61 · scheduling-v2's wall-clock arithmetic assumes `deviceUtcOffset == 0` — BEHOBEN

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

### T-67 · FR-6/FR-9/FR-12: die Warn-Flags werden auf zwei von drei Pfaden verworfen — BEHOBEN

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

### T-68 · FR-17 greift nie bei einem echten Vordergrund-Wechsel — BEHOBEN

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

### T-69 · Checkpoint 2s Reinterpretation wird vom veralteten AppState zurückgedreht — BEHOBEN

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

### T-70 · Das Kalenderfenster liefert nur 6 statt 7 Tage Termindaten — BEHOBEN

- [x] **Behoben** (`lib/screens/schedule/calendar.dart`): `endDate` zieht nur noch 1 ms statt einen
      ganzen Tag ab - das Fenster deckt jetzt wirklich 7 Tage Termindaten ab.
- **Why:** `replan` holt `[fetchStart, windowStart + 7 Tage)` (`replan.dart:77`),
  `fetchMeetingsUncached` rechnet daraus `endDate: end.subtract(const Duration(days: 1))`
  (`calendar.dart:116`) = Mitternacht des letzten Fenstertages. Ein Termin um 09:00 an diesem Tag
  liegt damit außerhalb. `hardFloor(window[6])` ist folglich immer `null`, der Vorlauf für FR-7 ist
  einen Tag kürzer als spezifiziert. Der Doc-Kommentar behauptet `[start, end)`, der Code setzt die
  inklusive Tageskonvention von `getCalendarEntries` um. Für alle Tests unsichtbar, weil sie
  `fetchEvents` injizieren.

### T-71 · replan()s Tagesmodell gilt nur für den Klingel-Auslöser — BEHOBEN

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

### T-72 · Keine UI für `wunschzeit`/`maxDailyDelta` - halbe FR-4/FR-7 unerreichbar — BEHOBEN

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

### T-73 · Ein klingelnder ManualAlarm treibt die ScheduledAlarm-Kette (FR-8/FR-15-Grenze) — BEHOBEN

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

### T-74 · Kleinere, bestätigte Abweichungen (gesammelt) - **alle behoben** — BEHOBEN

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

### T-66 · Phase 6 would delete `Scheduler.nextAlarmTime()`, which scheduling-v2 itself depends on — BEHOBEN

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

### T-65 · Changing sleep-habit settings never triggers a scheduling-v2 replan — BEHOBEN (2026-09-10)

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

### T-64 · Both scheduling systems now set alarms - and the old one can leave ZERO alarms — BEHOBEN (2026-09-10, Phase 6)

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

### T-106 · Ein bereits geklingelter Tageswert wurde vom naechsten Nicht-Ring-Checkpoint ueberschrieben — BEHOBEN (2026-09-11)

- [x] Abgeschlossene Fenstertage behalten ihren aufgezeichneten Wert.
- **Why:** FR-11 sagt "Erst der tatsaechlich ausgeloeste Wert ist **fuer immer** fix" - und "fuer
  immer" schliesst den Rest desselben Tages ein. Nur der Ring setzt `todayAlreadyRang`; fuer
  `settingsChanged` und `manualSync` beginnt das Fenster deshalb wieder bei HEUTE, und der Merge
  in `replan()` schrieb den bereits ausgeloesten Wert neu.
- **Zwei Folgen, die zweite ist die schwerere:**
  1. Ein **zweiter Alarm am selben Morgen**. FR-18 plant jeden noch zukuenftigen Planwert ein; der
     revidierte heutige Wert ist einer. Ablauf: 06:00 klingelt, der Nutzer dismisst, aendert um
     06:05 eine Einstellung - und um 06:30 klingelt es erneut.
  2. Unter dem Klingeltag steht danach ein Wert, der **nie geklingelt hat**. Genau diesen Eintrag
     liest der naechste Checkpoint als `lastEffectiveWakeTime` (FR-3: "immer der Eintrag in
     `pendingDayValues` fuer den zuletzt abgeschlossenen Tag"). Der Vordergrund-Checkpoint am
     Folgemorgen - vor dem Klingeln, Tagessperre greift dort nicht mehr - glaettet die ganze Woche
     dann von einem erfundenen Anker aus.
- **Erreichbarkeit (vom Gegenpruefer einzeln nachgegangen):** `manualSync` ist der Sync-Knopf in
  der Alarmliste; `settingsChanged` haengt an sechs Ein-Tipp-Pfaden (Ton, Lautstaerke, die vier
  Dauer-Picker, wunschzeit-Schalter, Gentle-Wake-Schalter). Beide unterliegen der Tagessperre
  bewusst nicht. **`appForeground` traegt den Fall nicht** - dort faengt FR-17s Tagessperre ab,
  weil der Ring `lastReplanDate` schon auf heute gesetzt hat; dieser Teil der urspruenglichen
  Meldung ist widerlegt. Ausserdem braucht der Schaden eine *geaenderte* Lage: bleibt der Termin
  im Kalender, ist die Revision ein No-op. "Besprechung abgesagt, ich schaue in die App und
  synchronisiere" ist aber der naheliegendste Vormittagsablauf ueberhaupt.
- **Fix:** Fenstertage, die nicht nach dem Fortschrittsmarker liegen, werden beim Merge
  uebersprungen - Werte **und** `pendingDayInstantAnchored`. Das Fenster wird ausdruecklich
  **nicht** verkuerzt: der Tag traegt weiter die Kurve, nur seine Aufzeichnung bleibt stehen.
- **Test:** `test/replan_audit_test.dart` - der Fall selbst plus zwei Gegenproben (der Folgetag
  bleibt revisionierbar; der Ring-Checkpoint schreibt weiterhin).
- **Requirement:** R2

### T-107 · FR-9s Ventil vergass sich selbst, sobald es gewirkt hatte — BEHOBEN (2026-09-11)

- [x] Den Ventilzustand auch im Kaltstart-Zweig melden.
- **Why:** sobald das Ventil alle Fensterwerte auf `null` gesetzt hat, ist beim naechsten
  Checkpoint `lastEffectiveWakeTime == null`. `computeWeekPlan` nimmt dann FR-10s Kaltstart-Zweig,
  und der gab hart `safetyValveTriggered: false` zurueck - obwohl der Zaehler weiterlaeuft (8, 9,
  …), keine `wunschzeit` gesetzt ist und nach wie vor nichts geplant wird. Der Zustand behauptete
  "keine Episode", waehrend die Episode andauerte.
- **Warum das gefaehrlich ist, nicht nur unsauber:** `reportReplanNotifications` liest
  `needed == false` bei `alreadySent == true` als "Episode vorbei" und setzt
  `safetyValveNotificationSent` zurueck. Scheitert die Benachrichtigung am Tag des Ausloesens
  (Merker bleibt absichtlich `false`, damit wiederholt wird), kommt der Wiederholungsversuch
  **nie** - ab dem Folgetag ist `needed` dauerhaft `false`. Ergebnis: ein dauerhaft stummer Wecker
  ohne jede Meldung. FR-9s eigene Begruendung nennt genau das "der falsche Ausgang".
- **Zweite Auspraegung, vom selben Zweig getragen:** erreicht der Zaehler die Schwelle, **ohne**
  dass je ein Anker existierte - frische Installation, Kalenderfreigabe ohne Termine, keine
  `wunschzeit`, App taeglich geoeffnet -, war `safetyValveTriggered` **nie** `true`. Der Nutzer
  erfuhr nie, dass nichts geplant wird. Der erste Pruefer hielt das fuer aus der Spec nicht
  entscheidbar; der Gegenpruefer hat es entschieden, und die Begruendung traegt: FR-9 nennt
  **genau eine** Ausnahme zu "Zaehler >= 7 -> gestoppt und benachrichtigt", naemlich eine gesetzte
  `wunschzeit`. FR-10 regelt in diesem Zweig ausschliesslich die *Werte* ("Ohne: kein Alarm
  geplant"), nie die Meldung. "Kein Anker" ist keine Ausnahme, die dort steht.
- **Evidence:** ausgefuehrte Probe ueber elf Tage - Zaehler 11, kein geplanter Wert, null
  Ventil-Benachrichtigungen.
- **Fix:** `safetyValveTriggered: gapDayCounter >= gapDayValveThreshold && wunschzeit == null`.
  Die Schwelle ist dabei aus zwei Literalen zu einer benannten Konstante geworden - sie wird jetzt
  an zwei Stellen geprueft (mit und ohne Anker) und darf nicht auseinanderlaufen.
- **Test:** `test/scheduling_v2_audit_test.dart`, Gruppe "FR-9" - vier Faelle, darunter FR-9s
  eigener Schwellen-Testfall mit **6**. Der fehlte: die Suite rief `computeWeekPlan` nur mit 0, 7
  und 42 auf, ein Wechsel auf `>= 6` waere gruen durchgegangen und haette den Wecker einen Tag zu
  frueh abgeschaltet.
- **Requirement:** R2, R3

### T-109 · FR-17s Tagessperre legte nach einem Datumsruecksprung bis zu 48 Stunden alles still — BEHOBEN (2026-09-11)

- [x] Die Sperre auf Gleichheit umstellen ("!= heute"), statt "nicht vor heute".
- **Why:** FR-17 sagt woertlich "Ist `lastReplanDate` **!=** heutiges Kalenderdatum
  (Geraete-Zeitzone): sofort, vor jeder UI-Interaktion, derselbe Ablauf wie FR-8s Ring-Checkpoint
  […] Sonst: kein zusaetzlicher Checkpoint." Der Code las `!midnight(last).isBefore(midnight(now))`
  - also ">=". Fuer einen Marker in der **Zukunft** wurde damit uebersprungen.
- **Wie der Marker in die Zukunft geraet - ohne jedes Zutun der App:** er ist ein geraetelokales
  Ziffern-Datum ohne Klammerung. Ein Zonenwechsel ueber die Datumsgrenze oder eine
  Rueckwaertskorrektur der Systemuhr laesst das lokale Datum zurueckspringen. Kein Code-Pfad
  klammert ihn gegen "nicht in der Zukunft".
- **Evidence:** tz-basierte Probe (echte IANA-Zonen, nicht `DateTime.utc` - auf einer UTC+0-VM
  kann ein UTC-Fixture einen Datumsruecksprung gar nicht darstellen). Apia (+13) 10.03. →
  Pago Pago (−11), derselbe Instant traegt dort den **09.03.**: von fuenf App-Oeffnungen liefen
  **zwei** statt der vier, die FR-17 wortwoertlich verlangt, und `fetchCount == 2` belegt, dass in
  diesen zwei lokalen Tagen kein einziger ungecachter Kalender-Neuread stattfand. Dauer: der
  gesamte lokale 09.03. **und** der gesamte 10.03., also bis zu ~48 lokale Stunden.
- **Warum das gerade dort weh tut:** ein `alarmRing`-Checkpoint unterliegt der Sperre nicht und
  repariert den Marker nebenbei - das begrenzt den Schaden real. Es begrenzt ihn aber genau dort
  **nicht**, wofuer FR-17 ueberhaupt gebaut ist: Reboot, Force-Quit und ein ausgefallenes
  taegliches Klingeln sind FR-17s drei namentliche Luecken, und in allen dreien gibt es keinen
  Ring, der reparieren koennte. Nach einem West-Flug faellt also genau der Mechanismus aus, der
  einen veralteten Plan und veraltete Plattformalarme noch heilen wuerde.
- **Fix:** verglichen wird ueber `dayDistance(...) == 0`, **nicht** ueber `==` auf zwei
  `DateTime`. Der Marker kommt lokal getaggt aus den Preferences, `currentTime` kann ein
  `tz.TZDateTime` sein, und Darts `==` verlangt denselben `isUtc`-Frame - das waere genau die
  Fehlerklasse dieses Moduls (T-61/T-76/T-83) an einer neuen Stelle.
- **Test:** `test/checkpoint_audit_test.dart` - Marker morgen/heute/gestern plus der echte
  Datumsruecksprung mit Fixture-Kontrollen (das lokale Datum springt wirklich zurueck; der zweite
  Moment liegt real spaeter).
- **Requirement:** R2, R3

### T-110 · Eine vergangene Bettzeit nahm FR-16s Checkpoint 2 seinen Einsprungpunkt — BEHOBEN (2026-09-11)

- [x] Nie fuer einen vergangenen Zeitpunkt planen; den Aufhaenger stattdessen nachholen.
- **Why:** `scheduleSleepReminder` stornierte die vorhandene Notification **bedingungslos** und
  plante dann neu - ohne zu pruefen, ob der berechnete Zeitpunkt noch in der Zukunft liegt. Ist
  `sleepGoal + reminderDuration` groesser als der Abstand bis zum naechsten Weckzeitpunkt, ist die
  Bettzeit vergangen. Beispiel: 22:00 eine Einstellung geaendert, naechster Weckzeitpunkt 05:00,
  Schlafziel 9h → Bettzeit 20:00. `settingsChanged` unterliegt keiner Tagessperre, laeuft also.
- **Was Android damit macht - nachgelesen, nicht vermutet:** der Pruefer hat
  `AndroidAwnCore-0.12.1.aar` aus dem Gradle-Cache entpackt und mit `javap -c` gelesen.
  `CronUtils.getNextCalendar` liefert fuer jedes Ergebnis vor "jetzt" `null`;
  `NotificationScheduler.doInBackground` ruft daraufhin `cancelSchedule`, loggt
  "Date is not more valid." und bricht ab; `onPostExecute` sendet das Created-Ereignis nur im
  Nicht-null-Zweig. Die alte Notification ist zu dem Zeitpunkt bereits storniert.
- **Folge:** fuer diese Nacht laeuft FR-16s Checkpoint 2 gar nicht. Ein untertags eingetretener
  Zeitzonenwechsel faellt dann erst beim Klingeln auf - exakt das Szenario, gegen das der zweite
  Checkpoint eingefuehrt wurde. Zusaetzlich bleibt die sichtbare Erinnerung aus.
- **Fix und die Entscheidung darin:** liegt die Bettzeit nicht mehr in der Zukunft, wird der
  Aufhaenger auf "in zwei Minuten" gelegt (zwei, nicht eine: `alarmPlatformTime` schneidet auf
  ganze Minuten ab) - und zwar **still**, auch bei aktivierter Erinnerung. **Die Spec entscheidet
  diesen Fall nicht**: FR-16 sagt, wann der Checkpoint laufen soll, nicht was gilt, wenn dieser
  Zeitpunkt vorbei ist. Gewaehlt ist die Lesart, die FR-16s Zweck am naechsten kommt (Aufhaenger
  so frueh wie moeglich nachholen), ohne eine irrefuehrende "Zeit zu schlafen"-Meldung Stunden
  nach dem gemeinten Zeitpunkt - FR-16 trennt Sichtbarkeit ausdruecklich vom Aufhaenger. **Wenn
  das anders gewollt ist, gehoert es in FR-16 und dann hierher.**
- **Kein Schleifenrisiko:** der Isolate-Einstiegspunkt (`onNotificationCreatedMethod`) ruft nur
  `runTimezoneCheckpoint2()` und plant die Erinnerung nicht neu. Geprueft.
- **Test:** `test/sleep_reminder_always_scheduled_test.dart`, Gruppe T-110 - in die Zukunft
  gelegt, still, und eine Gegenprobe, dass eine zukuenftige Bettzeit unveraendert sichtbar und
  puenktlich bleibt.
- **Requirement:** R2, R3

### T-137 · "Scheduled" ist der erste Reiter, "Manual" der zweite — UMGESETZT (2026-09-12)

- [x] Reiter, Inhalte und Indexkonstanten getauscht.
- **Warum:** auf Wunsch des Maintainers, und es passt zum Produkt: die kalenderabgeleiteten Wecker
  sind der eigentliche Zweck der App, manuelle Alarme die Ausnahme. Der Schirm oeffnet jetzt auf
  dem, was man taeglich sieht.
- **Folge, die man kennen muss:** der Knopf unten rechts haengt am Reiter. Auf "Scheduled" ist es
  der **Sync**-Knopf, auf "Manual" der **Add**-Knopf. Einen neuen manuellen Alarm anzulegen kostet
  damit einen Tipp mehr - das ist die beabsichtigte Gewichtung, aber es ist eine Aenderung am
  gewohnten Ablauf.
- **Die eigentliche Gefahr beim Tauschen** ist nicht die Reihenfolge, sondern ein Auseinanderlaufen:
  wer die `tabs:`-Liste tauscht und die `TabBarView.children` vergisst (oder die
  Indexkonstanten), bekommt einen Schirm, der die eine Liste zeigt, waehrend der Knopf zur anderen
  gehoert - und beide Reiter sehen weiterhin plausibel aus. Genau diese **Kopplung** sichert
  `test/screen_alarms_tab_order_test.dart`: er legt einen manuellen Alarm an und prueft, dass er
  auf Reiter 1 **nicht** und auf Reiter 2 **doch** erscheint. Beide Mutationen (nur die Inhalte
  zurueckgetauscht; nur die Indizes zurueckgetauscht) gehen rot.
- **Nebenbei:** `manualTabIndex`/`scheduledTabIndex` waren `static int`, also von ueberall
  veraenderbar, obwohl sie eine feste Reihenfolge beschreiben. Jetzt `static const`.
- **Ein bestehender Test musste seinen Weg anpassen** (nicht seine Zusicherung):
  `manual_alarm_inherits_settings_test` tippte direkt nach dem Oeffnen auf den Add-Knopf. Der sitzt
  jetzt einen Reiter weiter; der Test wechselt vorher dorthin. Was er prueft - dass ein neuer
  manueller Alarm Rampendauer, Lautstaerke und Ton erbt - ist unveraendert.
- **Requirement:** R12

### T-136 · Meldungen blieben stehen, obwohl seit dem ersten Commit 5 Sekunden eingestellt waren — BEHOBEN (2026-09-12)

- [x] `persist: false` an `displayToast`s SnackBar.
- **Gemeldet vom Maintainer:** Meldungen wie "Can not edit scheduled alarms!" verschwinden nicht
  von selbst.
- **Der verwirrende Teil:** `displayToast` setzt `duration: const Duration(seconds: 5)`, und zwar
  seit dem allerersten Commit (`git log -S` bestaetigt es) - die Zeile steht in **jedem**
  ausgelieferten APK. Die Einstellung war also nie das Problem.
- **Ursache im Framework, nicht im Aufruf:** `SnackBar` belegt sein Feld `persist` mit
  `persist ?? action != null` vor, und `ScaffoldMessengerState.build` bricht den Ausblend-Timer mit
  `if (snackBar.persist) return;` ab. Ein SnackBar **mit Aktion** ignoriert damit seine eigene
  `duration`. Die Framework-Dokumentation sagt es woertlich: *"If not provided, but the snackbar
  action is not null, the snackbar will persist as well."* Und `displayToast` gibt einen
  "Dismiss"-Knopf mit - genau der hat die Zeitabschaltung abgeschaltet.
- **Fix:** `persist: false` ausdruecklich. Der Knopf bleibt (wer gelesen hat, tippt sofort weg),
  und nach 5 Sekunden verschwindet die Meldung ohne Zutun.
- **Nur diese eine Stelle betroffen:** die uebrigen drei SnackBars im Projekt (Barcode-Ergebnis,
  "Diagnostics copied", Alarm-Bildschirm) haben keine Aktion, fuer sie ist `persist` also ohnehin
  `false`. `displayToast` ist die einzige Stelle mit `SnackBarAction`.
- **Test:** `test/display_toast_test.dart` - verschwindet nach Ablauf von selbst (und steht kurz
  davor noch), und der Dismiss-Knopf funktioniert weiterhin. Mutationsprobe (`persist: false`
  entfernt) geht rot.
- **Eine Testfalle, die dabei fast in die Irre gefuehrt haette:** `ScaffoldMessenger` legt seinen
  Timer erst an, wenn die **Einblend-Animation** durch ist (`_snackBarController!.isCompleted` in
  dessen `build`). Ein Test, der zu knapp pumpt, misst den Timer gar nicht und sieht die Meldung
  faelschlich als "bleibt stehen" - genau so sah der erste Lauf nach dem Fix aus. Deshalb pumpt der
  Test die Animation ausdruecklich ab, bevor er die Zeit misst.
- **Requirement:** R12 (Benutzbarkeit)

### T-135 · Das Log protokolliert Weckzeiten und fruehe Terminzeiten — auf Wunsch (2026-09-12)

- [x] `Diag.dayPlanned`: pro Fenstertag die geplante Weckzeit und der fruehste Termin des Tages.
- [x] Eigener Schalter, Standard **aus**, getrennt vom allgemeinen Diagnoseschalter.
- **Angefragt vom Maintainer**, und der Bedarf ist belegt: T-132 (der Termin, der die Weckzeit nach
  spaet zog) liess sich aus dem Log **nicht** diagnostizieren. Es enthielt Zaehlungen und Buckets,
  aber nicht die eine Information, die die Frage beantwortet: *warum* steht an diesem Tag diese
  Weckzeit - liegt es am Termin, an der Kurve oder an der Wunschzeit? Gefunden wurde der Fehler
  ueber Bildschirmfotos und Handrechnung.
- **Was das kostet, und warum es einen eigenen Schalter hat:** die tragende Eigenschaft dieses Logs
  war bisher, dass ein Uhrwert konstruktiv nicht hineinpasst - *"eine Historie von Weckzeiten plus
  Versaetzen ist ein Schlafmuster und eine Reisespur, identifizierend ohne jeden Namen"*. Genau die
  wird hier gelockert. Deshalb:
  - **nicht** am allgemeinen Diagnoseschalter mitgehaengt (der steht auf **an**), sondern ein
    zweiter, der auf **aus** steht;
  - `Diag.dayPlanned` ist ohne ihn ein No-op, und der Hauptschalter bleibt uebergeordnet (beides
    getestet);
  - die Kopfzeile des Exports **sagt selbst**, in welchem der beiden Modi er entstanden ist - wer
    ihn an einen Fehlerbericht haengt, sieht es ihm an;
  - `-1` bedeutet "kein Wert"/"kein Termin". Nicht `0` - das waere Mitternacht und damit eine
    gueltige Uhrzeit.
  - Datum bleibt draussen: protokolliert wird die Minute des lokalen Tages plus ein **relativer**
    Tagesversatz. Ein Kalendertag ist daraus nicht zu gewinnen.
- **Zwei Fehler, die beim Bauen aufgefallen sind:**
  - Der Quelltext-Waechter in `test/diag_log_api_test.dart` haette die neuen Parameter
    **durchgelassen** - sein Muster prueft Endungen wie `...Minutes`/`...Time`, und
    `plannedMinuteOfDay` endet auf `Day`. Eine Namenslücke, keine Erlaubnis. Das Muster kennt jetzt
    auch `...MinuteOfDay`/`...HourOfDay`, und die beiden Ausnahmen stehen **namentlich** im Test,
    mit Begruendung. Probe: ein neu hinzugefuegter `wakeMinuteOfDay` wird gefangen.
  - `Diag.resetForTest()` setzte den neuen Schalter nicht zurueck, er leckte also zwischen Tests
    durch. Dieselbe Falle mit globalem Zustand wie bei `Diag.init` (T-89). Gefunden vom eigenen
    Test; behoben.
- **Nebenbei gelernt:** die `Actual`-Anzeige des Dart-Matchers bricht bei einem mehrzeiligen String
  an der ersten Zeile ab. Das sah aus, als liefere `render()` nur eine Zeile, und hat die Suche
  kurz in die falsche Richtung geschickt - erst eine Ausgabe im Test selbst zeigte den wahren
  Zustand.
- **Test:** `diag_log_test.dart` (Gruppe T-135: Voreinstellung schreibt nichts, eingeschaltet
  beide Zahlen, `-1`-Bedeutung, Kopfzeile, Hauptschalter bleibt uebergeordnet),
  `diag_log_api_test.dart` (verschaerfter Waechter), `app_state_scheduling_v2_test.dart`
  (Persistenz-Rundreise, Unabhaengigkeit der beiden Schalter).
- **Requirement:** R7 (Datensparsamkeit), R2 (Diagnosefaehigkeit)

### T-133 · Ein Deckelungs-Sprung an einem Termin blieb stumm — BEHOBEN (2026-09-12)

- [x] FR-6s Meldepflicht auch auf dem Kappungs-Pfad.
- **Why:** FR-6 sagt "bei **jeder** Ueberschreitung von `maxDailyDelta` (`N=1` oder verteilt) wird
  der Nutzer einmalig benachrichtigt". T-105 hat das fuer den Zweig ohne Folgepunkte nachgetragen;
  der zweite Weg, auf dem ein Tageswert an einem Termin gedeckelt wird - die Kappung eines
  laufenden Kurvenwerts am eigenen `hardFloor` -, meldete weiterhin nichts.
- **Wie er aufgefallen ist:** beim Durchrechnen eines Alltagsfalls (siehe T-134). Die Weckzeit war
  ueber terminlose Tage bis zur `wunschzeit` 07:00 gedriftet, danach wurde die Arbeit im Kalender
  nachgetragen. Der erste Arbeitstag wurde auf seinen `hardFloor` 06:15 gedeckelt - ein Schritt von
  **45 Minuten** bei erlaubten 30, und der Nutzer erfuhr **nichts** davon.
- **Warum ihn die erste Pruefung nur streifte:** sie hatte ihn als "Nebenbefund (schwaecher)" zu
  B-2 notiert, weil die Meldung in ihrer eigenen Probe zufaellig trotzdem anfiel - ein Folgetag
  startete dort einen neuen Run und meldete ueber `distribute`. Der Fall ohne diesen Zufall blieb
  ungeprueft.
- **Fix:** dieselbe division-freie Formel wie im Nachbarzweig und in `distribute`, damit die drei
  nicht auseinanderlaufen koennen.
- **Test:** `test/scheduling_v2_audit_test.dart`, Gruppe T-133 - der Sprung ueber der Grenze meldet,
  eine Kappung innerhalb der Grenze (25 min) nicht. Mutationsprobe (Meldung wieder entfernt) geht
  gezielt rot.
- **Requirement:** R2

### T-134 · VERWORFEN: ein Wochenend-/Wochentagsbegriff in der Scheduling-Schicht (2026-09-12)

- **Angefragt war:** Wochenenden sollen den Rhythmus nur beeinflussen, wenn ein Termin frueher
  liegt als unter der Woche; sonst sollen sie keinen Drift erzeugen bzw. nur Richtung
  `wunschzeit`. Dazu eine konfigurierbare Menge freier Wochentage mit eigener UI, aus der auch
  `startOfWeekDay` abgeleitet wird.
- **Verworfen auf Entscheidung des Maintainers,** und es ist die bessere Abstraktion: *"eigentlich
  ist die Logik 'Wochentag' egal, man hat ja Termine oder nicht."* Die Engine trennt bereits Tage
  mit realem `hardFloor` von Lueckentagen, und das ist die Unterscheidung, die etwas bedeutet - ein
  freier Dienstag und ein freier Sonntag sind dasselbe. Fuer eine App, die ausdruecklich fuer
  unregelmaessige Schlafzeiten und Schichtdienst gebaut ist, liegt "das Wochenende" ohnehin nicht
  dort, wo der Kalender es vermutet.
- **Was das Aufschreiben vorher gebracht hat** (die Spec stand fertig als FR-19 da, bevor eine
  Zeile Code entstand): gegen die laufende Engine durchgerechnet war die Anforderung **groesstenteils
  schon erfuellt**. FR-7s Rueckwaerts-Pruefung kappt den `wunschzeit`-Drift bereits so weit, dass
  der naechste bindende `hardFloor` erreichbar bleibt - ein terminloses Wochenende schiesst also gar
  nicht erst ueber, solange der Termin des Arbeitstages im 7-Tage-Fenster sichtbar ist. Gerechnet
  (`wunschzeit` 07:00, `maxDailyDelta` 30 min, Freitag 06:15, spaeter Samstagstermin, Montag 06:15):
  **Sa 06:45, So 06:45, Mo 06:15**, kein Sprung, keine Meldung. Mein von Hand geschriebener
  Erwartungswert ("So 07:00") war falsch; die Engine hatte recht.
- **Was daraus wirklich folgte:** genau ein Fall traegt - wenn die Anforderung des Arbeitstages beim
  Planen noch nicht sichtbar ist (Termin noch nicht eingetragen oder hinter dem Fensterrand). Dann
  faellt die Korrektur in einen Schritt, und der war zusaetzlich **stumm**. Das ist T-133, und es
  braucht keinen Wochentagsbegriff.
- **Fuer kuenftige Entwuerfe:** keine Regeln auf `DateTime.weekday` in `lib/models/scheduling/`.
  Wenn eine Regel "Wochenende" zu brauchen scheint, in An- oder Abwesenheit eines `hardFloor`
  formulieren - das ist fast immer das Gemeinte und kommt ohne Einstellung und ohne UI aus.

### T-132 · Ein Termin zog die Weckzeit nach SPAET — BEHOBEN (2026-09-11)

- [x] Ein `hardFloor` kann nur noch Ziel sein, wenn er frueher liegt als der heutige Wert.
- **Woher:** Geraeterueckmeldung des Maintainers, erster Lauf gegen einen **echten** Kalender. Die
  Weckzeit lief von **06:45 ueber 08:00 auf 11:00** - "deutlich mehr als drift und als noetig, auch
  nicht nahe an der praeferierten zeit. die 11 uhr scheinen komplett grundlos".
- **Reproduziert** (Anker 06:45, `wunschzeit` 07:00, `maxDailyDelta` 30min, Termine 08:00 und
  11:00 an den Folgetagen): exakt `08:00`, dann `11:00`. Und der zweite Teil der Meldung
  ("reagiert extrem auf freie tage") ebenso: ein **einzelner** Termin um 11:00 in vier Tagen, sonst
  alles frei, ergab `07:48 / 08:52 / 09:56 / 11:00` - die freien Tage wurden als Rampe benutzt, um
  auf einen spaeten Termin hinaufzuklettern.
- **Ursache:** `hardFloor` ist ein **Termin-Deckel**, die Engine hat ihn aber als **Kurvenziel**
  behandelt - in beide Richtungen. Ein Punkt, der spaeter liegt als die bisherige Weckzeit, wurde
  damit zum Ziel eines Runs, und der Run zog die Weckzeit zu ihm hinauf; `maxDailyDelta` war dabei
  ausgehebelt, weil FR-6 fuer `N=1` den vollen Sprung erlaubt.
- **Die Spec sagt zweimal das Gegenteil,** nur nicht als Verfahrensregel:
  - FR-2: "`hardFloor` ist eine **Obergrenze** ('nicht spaeter als'). Der geplante Wert darf
    frueher liegen (**immer erlaubt**), aber niemals spaeter."
  - FR-5, Schritt 1: "`hardFloor` ist ausschliesslich eine Obergrenze (FR-2), **nie eine
    Richtungsvorgabe**."
  Deshalb ist das **keine** der offenen Entscheidungsfragen, sondern ein Fehler mit eindeutiger
  Grundlage: wer um 06:45 aufsteht, erfuellt einen Termin um 11:00 laengst. Nach spaet bewegt die
  Weckzeit ausschliesslich FR-4s Drift zur `wunschzeit`.
- **Fix an zwei Stellen:** `planGapOrRunStartDay` startet keinen Run, wenn das gruppierte Ziel
  nicht frueher liegt als der Anker; und `computeWeekPlan`s Zweig ohne Folgepunkte driftet jetzt
  und **deckelt** danach, statt den eigenen `hardFloor` unbesehen zuzuweisen. FR-5s Warnung vor
  einem "Richtungsfilter" bleibt gewahrt: die Punkte werden nicht aus der Liste entfernt und nehmen
  weiter an der Verletzungspruefung teil - sie kommen nur als *Ziel* nicht mehr in Frage.
- **Ergebnis nach dem Fix,** dieselben Eingaben: jeder Tag **07:00**, keine Overrun-Meldung. Ein
  **frueher** Termin (05:00 in vier Tagen) wird weiterhin geglaettet herangefuehrt
  (`06:18 / 05:52 / 05:26 / 05:00`) und danach zur `wunschzeit` zurueckgefuehrt - der eigentliche
  Zweck von FR-5/FR-6 bleibt also unberuehrt.
- **Spec nachgezogen:** FR-5 hat die Vorbedingung jetzt als eigenen Absatz samt zwei
  durchgerechneten Testfaellen. Ohne sie baut das jemand zurueck.
- **Ein bestehender Test musste neu hergeleitet werden:** `T-118c`s Nebenzusicherung stand auf
  `08:00` und hat damit genau den Fehler festgeschrieben. Richtig sind `07:00` (ohne `wunschzeit`
  haelt FR-4 beim Anker, und FR-2 erlaubt jeden frueheren Wert ausdruecklich). Die tragende
  Zusicherung dieses Tests - dass FR-9s Ventil einen Termintag nicht auf `null` setzt - ist
  unveraendert.
- **Was das ueber die Testlage sagt:** 267 Tests, zwei unabhaengige Pruefrunden und eine
  Zeitzonen-Matrix haben das nicht gefunden - der erste Lauf gegen einen echten Kalender schon.
  Alle Suite-Fixtures bewegten die Weckzeit entweder nach frueh oder liessen sie halten; der Fall
  "Termin liegt spaeter als die bisherige Weckzeit" kam in keinem einzigen vor, obwohl er der
  Alltagsfall ist.
- **Requirement:** R2

### T-131 · Das Reboot-Verfahren kann strukturell nichts messen: `flutter test` deinstalliert die App

- [x] Die Ursache benennen, statt sie ein drittes Mal als Musterfrage zu verbuchen.
- [ ] **Entscheidung noetig:** auf welchem Weg soll der Alarm fuer die Messung scharf gestellt
      werden?
- **Der Befund, aus Lauf 34627328009:** die drei Aufloesungswege melden uebereinstimmend
  - `pm list packages -U` → keine Zeile enthaelt den Paketnamen
  - `dumpsys package` → `Unable to find package: com.wakeywakey.wakeywakey`
  - `stat /data/data/<paket>` → `No such file or directory`
  Die App ist zum Messzeitpunkt **nicht installiert**. Ein Debug-Suffix scheidet als Erklaerung aus
  (`applicationId` traegt keinen, `android/app/build.gradle.kts:44`), und `arm_alarm.log` desselben
  Laufs zeigt eine erfolgreiche Installation plus `🎉 1 test passed`.
- **Warum das alles erklaert:** `flutter test integration_test/...` installiert die App fuer den
  Lauf und raeumt sie danach wieder ab. Android verwirft mit dem Paket auch dessen
  AlarmManager-Eintraege. Das Verfahren "Alarm in einem Test scharf stellen, danach `dumpsys`
  befragen" kann deshalb **grundsaetzlich** nichts messen - unabhaengig von jedem Suchmuster.
- **Und damit war T-99s urspruengliche Deutung falsch.** Dort wurde die Null als "Muster falsch
  geraten" gelesen und mit **mehr** Mustern beantwortet; daraus entstand T-103s Falschbefund. Die
  eigentliche Ursache lag eine Ebene tiefer und war die ganze Zeit dieselbe. Lehre: wenn ein
  Beweismittel nichts findet, ist die erste Frage nicht "suche ich falsch?", sondern "ist das
  Gesuchte ueberhaupt da?".
- **Was jetzt passiert:** das Skript prueft `pm path` und meldet
  `RESULT: not measurable - die App ist zum Messzeitpunkt NICHT INSTALLIERT`, statt eine
  Messluecke zu verbuchen. Kein Lauf kann daraus mehr eine Aussage ueber das Produkt machen.
- **Zu entscheiden, bevor hier weitergebaut wird:** *soll CI den Alarm ueber eine installierte App
  plus UI-Automatisierung scharf stellen (`adb install` + `am start` + `input tap`), oder bleibt
  Reboot-Ueberleben eine Sache des manuellen Geraetetests?* Ersteres ist echte Arbeit und macht
  den E2E-Job von der UI-Beschriftung abhaengig; Letzteres steht bereits als Abschnitt C in
  `docs/device-trial-checklist.md` und braucht nur ein Geraet und fuenf Minuten. Solange das nicht
  entschieden ist, bleibt **T-93 offen** - und zwar als *unbeantwortet*, nicht als *fehlgeschlagen*.
- **Requirement:** R3

### T-130 · Die uid-Aufloesung scheiterte stumm — BEHOBEN (2026-09-11)

- [x] Jeder Aufloesungsversuch protokolliert seine Rohausgabe in die Beweisdatei.
- **Stand nach dem ersten Lauf mit der reparierten Messung (34622086175):** das Skript verhaelt
  sich jetzt richtig - der Selbsttest ist bestanden, es gibt **keinen** Falschbefund mehr, und
  statt eines erfundenen `FAIL` steht ehrlich `RESULT: inconclusive - this app has no alarm
  registered even BEFORE the reboot` da. Genau so soll ein Beweismittel scheitern.
- **Was es dabei selbst benannt hat:** `app uid: <nicht aufloesbar>`. Ohne uid-Token traegt allein
  der Paketname, und der taucht in `dumpsys alarm` auf diesem Image offenbar nicht auf - deshalb
  die Null. Im Rohauszug ist eine uid mit genau einem anstehenden Alarm zu sehen (`u0a160:1`), die
  sehr wahrscheinlich die App ist; belegen laesst sich das ohne Aufloesung aber nicht.
- **Warum das eine eigene Behebung braucht:** beide Aufloesungswege leiteten ihre Fehler nach
  `/dev/null`. Aus dem Beweismaterial war deshalb nicht zu erkennen, **warum** sie scheiterten -
  obwohl `arm_alarm_test.dart` im selben Lauf nachweislich einen Alarm gesetzt hatte ("1 test
  passed") und die App installiert war (kein Uninstall in `arm_alarm.log`). Das Format zu raten
  hat dieses Skript schon zweimal in die Irre gefuehrt (T-99, T-103); ein drittes Mal wird es
  aufgezeichnet statt geraten.
- **Fix:** drei Wege, jeder mit Rohausgabe in der Beweisdatei - `pm list packages -U` (zusaetzlich
  mit einer weniger strengen Zweitauswertung), `dumpsys package` auf `userId=`/`appId=`, und
  `stat -c %u /data/data/<paket>`. Der naechste Lauf zeigt damit, welcher greift und woran die
  anderen scheitern.
- **T-93 bleibt offen** - die Frage "ueberlebt ein Alarm den Reboot?" ist weiterhin unbeantwortet.
  Sie ist jetzt aber ehrlich als unbeantwortet ausgewiesen und einen Schritt naeher an einer
  Messung.
- **Requirement:** R3

### T-129 · Ein kranker Emulator gab sich als Produktfehler aus — BEHOBEN (2026-09-11)

- [x] Vor der Messung pruefen, ob der Emulator ueberhaupt benutzbar ist.
- **Was passierte:** Lauf 34622327599 meldete `❌ a created alarm survives being reloaded from
  on-device storage` mit der Begruendung "Alarm … was created in AppState but never reached the
  native alarm plugin". Das liest sich wie ein schwerer Produktfehler. Es war keiner: derselbe Lauf
  hatte zuvor `Unable to connect to adb daemon on port: 5037` und
  `adb: device 'emulator-5554' not found` protokolliert - der Emulator war nie richtig
  hochgekommen.
- **Wie sich das zeigen liess:** der Commit dieses Laufs (`6aa2325`) aenderte ausschliesslich
  Testdateien und Dokumentation; `git diff b0d6662 6aa2325 -- lib/` ist **leer**. Der
  unmittelbar vorige Lauf auf byteweise identischem `lib/` hatte die E2E-Suite gruen. Damit war
  eine Code-Regression ausgeschlossen, ohne auch nur einen Test lesen zu muessen.
- **Warum das ein eigener Punkt ist:** `adb wait-for-device` kehrt schon zurueck, wenn der
  Geraeteeintrag existiert - nicht erst, wenn das System benutzbar ist. Der Lauf lief also weiter
  und produzierte am Ende eine Aussage ueber das Produkt, wo eine ueber die Umgebung faellig
  gewesen waere. Das ist dieselbe Fehlerklasse wie T-99 und T-103, nur eine Ebene hoeher: **ein
  Beweismittel, das eine Umgebungsstoerung als Produktfehler ausgibt, ist schlimmer als eines, das
  nichts findet** - man glaubt ihm.
- **Fix:** `run_e2e_tests.sh` wartet jetzt auf `sys.boot_completed=1` (bis zu fuenf Minuten) und
  bricht sonst mit `::error::EMULATOR NICHT BENUTZBAR … Das ist eine Umgebungsstoerung, KEIN
  Testergebnis` ab, samt `adb devices -l` fuer die Diagnose. Im Erfolgsfall protokolliert es den
  API-Level des Geraets - bisher stand nirgends im Beweismaterial, auf welcher Android-Version
  gemessen wurde.
- **Requirement:** R3

### T-123 bis T-128 · Sechs weitere ungedeckte Eigenschaften — BEHOBEN (2026-09-11)

Zweite Absicherungs-Charge aus der Testfall-Pruefung. Jede hat eine belegte Mutation, die sie rot
macht und die heute in der uebrigen Suite unsichtbar bleibt.

- **T-123 · FR-18s Gleichheitsgrenze zu jetzt.** Die gefaehrlichste Minute des Moduls, und sie war
  ungedeckt. FR-18 verbietet ausdruecklich, einen Alarm der laufenden Minute zu entfernen - "die
  Anwendung laeuft auch aus FR-8s Ring-Checkpoint heraus, also *waehrend* ein Alarm klingelt […]
  ihn zu entfernen wuerde ihn per `Alarm.stop()` mitten im Klingeln verstummen lassen". Der
  vorhandene Test arbeitet mit **fuenf Minuten** Abstand; der Fehler tritt aber nur in den
  60 Sekunden auf, in denen er zaehlt. Belegt: eine Umformulierung der Vergangenheitspruefung
  (`isAfter` -> `isBefore`) laesst apply_alarms, replan, replan_audit, checkpoint, app_state und
  next_wake_up vollstaendig gruen und faellt nur an den zwei neuen Zeilen auf.
  Als Grenzwerttabelle ueber vier Faelle geschrieben. Der fuenfte (geplanter Wert **genau** in der
  laufenden Minute) bleibt bewusst ohne Zusicherung: er hat keine beobachtbare Wirkung, weil
  `AppState.addAlarm` einen Wert vor `DateTime.now()` ohnehin ablehnt - beide Lesarten enden im
  selben sichtbaren Ergebnis, die Frage ist kosmetisch und darf keine sicherheitskritische
  Absicherung blockieren.
- **T-124 · Schalttag.** Die klassische selbstgeschriebene Tag-im-Jahr-Rechnung (Monatstabelle plus
  `(a.year - b.year) * 365`) liegt ueber den 29.02.2028 um einen Tag daneben - und blieb in
  **allen** sechzehn Testdateien unsichtbar, `day_marker_test` eingeschlossen, also gerade in der
  Datei, die fuer diese Arithmetik zustaendig ist. Der Jahreswechsel faengt sie **nicht** (die
  Tabelle stimmt fuer 2026/2027); nur der Schalttag tut es.
- **T-125 · Versaetze mit halben und dreiviertel Stunden.** Saemtliche Versaetze der Suite waren
  ganze Stunden. Die Fehlerklasse "jemand rechnet mit `offset.inHours` statt mit `offset`" war
  dadurch in **keinem** Test sichtbar. Wichtig: die CI-Zeitzonen-Matrix faengt sie ebenfalls nicht,
  obwohl sie St. John's, Chatham und Lord Howe enthaelt - die Matrix setzt die Zone der
  **Testmaschine**, waehrend die Domaenenschicht den Versatz als expliziten Parameter bekommt
  (FR-2 "Testbarkeit"). Matrix und Unit-Test erfassen Verschiedenes und ersetzen einander nicht;
  das war bisher nirgends festgehalten.
- **T-126 · FR-2 als Invariante ueber eine volle Terminwoche.** FR-2 ist eine Allaussage ("der
  geplante Wert darf frueher liegen, aber **niemals spaeter**"), also ist sie als Invariante
  geprueft und nicht als Liste handgerechneter Einzelwerte - eine solche Liste wird bei jeder
  legitimen Kurvenaenderung ohnehin angepasst, die Invariante nicht. Belegt: FR-2s Kappung liess
  sich ersatzlos streichen, ohne dass ein einziger bestehender Test rot wurde.
- **T-127 · Ein Plattform-Alarm, den die App nicht kennt.** Ungedeckt war die Kombination "eigene
  ID **und** eine fremde": der vorhandene T-88-Fall uebergibt eine fremde ID *ohne* die eigene.
- **T-128 · Idempotenz zweier Ring-Checkpoints.** Fuer diese Fehlerklasse - ein Lauf fasst den
  Zustand ein zweites Mal an, obwohl er ihn schon verarbeitet hat - gab es auf Checkpoint-Ebene
  kein Netz, und sie hat in diesem Projekt bereits sechsmal zugeschlagen (T-67, T-71, T-77, T-80,
  T-106, T-114).
- **Requirement:** R2, R3

### T-119 · OFFENE SPEC-ENTSCHEIDUNG: eine Sommerzeit-Umstellung INNERHALB des 7-Tage-Fensters

- [ ] Entscheiden, ob die Tageszuordnung den Versatz des jeweiligen Fenstertages verwenden muss.
- **Lage:** der Geraete-Versatz wird als **eine Zahl** zum Checkpoint-Zeitpunkt gelesen und fuer
  alle sieben Fenstertage benutzt. Liegt eine Umstellung im Fenster, ist diese Zahl fuer die Tage
  danach um die Umstellungsdifferenz falsch, und Termine, deren Ortszeit naeher als diese Differenz
  an Mitternacht liegt, landen auf dem **Nachbartag**.
- **Reproduziert:** Herbstumstellung Europe/Berlin, ein Termin am 27.10. um 23:30 Ortszeit und
  einer am 28.10. um 08:00. Der erste rutscht auf den 28.10., verdraengt dort als *fruehester*
  Termin (FR-13) den echten Morgentermin - und am Morgen des 28.10. klingelt **gar nichts**. Der
  Wochenplan kippt zusaetzlich auf Abendwerte. In der Fruehjahrsrichtung zeigt der Fehler
  spiegelbildlich einen Tag zu frueh, ist also kein blosses "immer eine Stunde daneben".
- **Warum es keine reine Fehlerbehebung ist:** FR-2 sagt woertlich "die Geraete-Zeitzone **zum
  Auswertungszeitpunkt**" - der Status quo ist damit spec-konform. Der Spec-Text kennt nur *einen*
  Versatz und hat nicht bedacht, dass das Fenster in die Zukunft reicht und eine Umstellung
  ueberspringen kann.
- **Der eigentliche Befund ist ein anderer:** FR-16s ausdruecklich akzeptierte Grenze am
  Umstellungstag behauptet, echte Termine seien nicht betroffen. Das stimmt nicht - genau ein
  solcher wird hier verschluckt. Diese Passage ist in jedem Fall zu korrigieren, unabhaengig davon,
  wie die Frage unten entschieden wird.
- **Zu entscheiden:** *Muss die Tageszuordnung eines Fenstertages den Versatz verwenden, der an
  DIESEM Tag gilt?* Dann braucht FR-2 eine Zonenregel-Vorausschau, die FR-16 bewusst nicht kennt.
  Die Alternative waere, die Zuordnung ueber die lokalen Kalenderfelder des `tz.TZDateTime` zu
  machen, das `device_calendar` ohnehin liefert - das braucht keine Vorausschau, aendert aber die
  Herkunft der Zone, und genau die legt FR-2 fest.
- **Bereits abgesichert (T-118a):** die Tageszuordnung nahe Mitternacht bei **konstantem** Versatz.
- **Requirement:** R2

### T-120 · OFFENE SPEC-ENTSCHEIDUNG: welchem Tag gehoert ein Weckwert, der ueber Mitternacht zurueckfaellt?

- [ ] Entscheiden, DANN testgetrieben umsetzen.
- **Lage:** ein Termin kurz nach Mitternacht schiebt `hardFloor` durch die Vorlaufzeiten auf den
  **Vortag**. Der Wert eines Tages liegt dann auf einem anderen Kalendertag als sein Schluessel -
  und wird anschliessend zum Anker der Fortschreibung.
- **Reproduziert:** ein einziger Termin am 12.03. um 00:30 (Vorlaeufe je 30min) ergibt zwei
  Weckzeiten am 11.03. (03:15 und 23:30) und **keine** am 12.03.; danach haelt FR-4 die Weckzeit
  dauerhaft bei 23:30 - der Nutzer wird ab da jeden Abend geweckt, und die Kette findet ohne
  `wunschzeit` nicht mehr heraus. Dazu eine FR-6-Warnung, die den Effekt als "Anpassung wegen
  eines Termins" erklaert.
- **Zusatzfund, der die Tragweite erhoeht:** in dieser Lage greift FR-11s "fuer immer fix" **nicht**.
  Die Absicherung (T-106/T-114: das Fenster beginnt hinter `lastConcludedDay`) traegt genau so
  lange, wie der Wert eines Tages auf dem eigenen Kalendertag liegt. Probe: der 23:30-Wert klingelt,
  der Termin war abends abgesagt worden - der soeben ausgeloeste Wert wird ueberschrieben und fuer
  03:15 **derselben Nacht** ein neuer Alarm gesetzt, 3:45 Stunden nach dem Wecker, der eben lief.
- **Warum keine Umsetzung ohne Entscheidung:** kein einzelner FR-Satz wird verletzt. Verletzt wird
  eine Grundannahme, die die Spec nirgends ausspricht - dass Wert-Datum und Tagesschluessel
  zusammenfallen.
- **Zu entscheiden:** *Was ist der Tagesschluessel eines Weckwertes, wenn `hardFloor` ueber
  Mitternacht zurueckfaellt?*
  - **"Wert bleibt beim Termin-Tag" (Status quo):** FR-2 woertlich, der Termin wird zuverlaessig
    nicht verpasst. Preis: zwei Weckzeiten an einem Tag, keine am Termintag, FR-4 macht den
    23:30-Wert zum Dauer-Anker, und FR-11 ist fuer diesen Wert nicht durchsetzbar. Dann muessten
    FR-3, FR-4 und FR-11 den Fall ausdruecklich aufnehmen.
  - **"`hardFloor` ist ein einmaliger Deckel, kein Anker":** die Kette schreibt danach am vorherigen
    Anker weiter. Preis: FR-4 braucht einen zweiten Ankerbegriff ("letzter *regulaerer* Wert"), den
    die Spec heute bewusst nicht hat.
  - **"Wert wird auf seinen eigenen Tag geklammert":** einfach, aber sie verletzt FR-2s Kernaussage
    und der 00:30-Termin wuerde garantiert verpasst. Aus Pruefersicht ausgeschlossen.
- **Bereits abgesichert (T-118b):** dass `hardFloor` vor Mitternacht des eigenen Tages liegen darf -
  die Voraussetzung jeder dieser Lesarten.
- **Requirement:** R2

### T-121 · OFFENE SPEC-ENTSCHEIDUNG: die Asymmetrie von FR-9s Ventil

- [ ] Entscheiden, ob ein Termin im Fenster das Ventil auch fuer die Tage NACH ihm aufhebt.
- **Lage:** das Ventil nimmt Tage **vor** einem realen Termin im Fenster aus (`remaining.isEmpty`),
  Tage **nach** ihm aber nicht. Nach dem ersten wieder auftauchenden Termin verliert der Nutzer
  also saemtliche Alarme fuer die Tage danach - und bekommt die Meldung "automatische
  Fortschreibung gestoppt", waehrend fuer morgen frueh ein terminabgeleiteter Wecker auf dem
  Bildschirm steht.
- **Der Zustand heilt** beim Klingeln dieses Alarms (dann ist der Tag abgeschlossen und der Zaehler
  geht auf 0) - aber nur, wenn er klingelt.
- **Zu entscheiden:** *Setzt ein im Fenster sichtbarer realer `hardFloor` das Ventil auch fuer die
  Tage nach ihm ausser Kraft?*
  - **"nein" (Status quo):** woertlich FR-9-konform, aber die Asymmetrie gehoert dann ausdruecklich
    in FR-9 - sonst liest sie sich wie ein Versehen.
  - **"ja":** die Bedingung waere "kein realer `hardFloor` irgendwo im Fenster", und das ist
    zugleich genau die Formulierung, die FR-9s **eigene drei Testfaelle** beschreiben ("kein
    `hardFloor` im Fenster") - insofern die kleinere Aenderung am Spec-Text.
- **Bereits abgesichert (T-118c):** beide heute vorhandenen Einschraenkungen.
- **Requirement:** R2, R3

### T-122 · OFFENE SPEC-ENTSCHEIDUNG: Verankerung nach Herkunft oder nach Bedeutung?

- [ ] Entscheiden; die vollstaendige Loesung ist eine Erweiterung von FR-3, kein Bugfix.
- **Lage:** ein Kurvenwert, der *exakt* auf dem eigenen `hardFloor` landet, gilt als
  **ziffern**-verankert (weil die Kurve ihn berechnet hat) und wandert bei einem Zeitzonenwechsel
  mit - ausgerechnet am Termintag. Der Wert ist aber zugleich der Termin-Deckel.
- **Groesser als der Gleichheitsfall:** FR-16s Checkpoint 2 kann FR-2s Obergrenze **grundsaetzlich**
  nicht einhalten, weil er den Kalender nicht lesen darf. Probe: nach einem Versatzwechsel landet
  ein Wert 8 Stunden **nach** dem Termin, fuer den er geplant war.
- **Zu entscheiden:** *Entscheidet ueber `pendingDayInstantAnchored` die Herkunft (die Kurve hat den
  Wert berechnet) oder die Bedeutung (der Wert ist zugleich der Termin-Deckel)? Und darf Checkpoint
  2 einen ziffern-verankerten Wert ueber einen `hardFloor` hinausschieben?*
  - **"Herkunft" (Status quo):** kein Codeaenderungsbedarf, aber FR-2s Obergrenze gilt dann
    ausdruecklich nur **bis zum naechsten Zeitzonenwechsel**, und das gehoert in FR-2 und FR-16
    hineingeschrieben. Die Folge ist real: ein echter Termin kann nach einer Reise nach Westen
    verpasst werden, obwohl der Alarm fuer ihn geplant war.
  - **"Bedeutung":** eine Ein-Zeilen-Aenderung (`ownHardFloor != null &&
    !candidate.value.isBefore(ownHardFloor)`), loest aber nur den Gleichheitsfall.
  - **Vollstaendig:** Checkpoint 2 duerfte einen Wert nur bis zum jeweiligen `hardFloor`
    verschieben - dafuer muesste dieser mitpersistiert werden (eine dritte Karte neben Werten und
    Ankern), weil Checkpoint 2 den Kalender nicht lesen darf. Erweiterung von FR-3.
- **Bereits abgesichert (T-118d):** der Kappungsfall.
- **Requirement:** R2, R3

### T-118 · Vier entschiedene Eigenschaften waren ungedeckt — BEHOBEN (2026-09-11)

- [x] Absicherungen fuer die Teile, die keine Spec-Entscheidung brauchen.
- **Why:** vier der neuen Testfaelle haben als *Kern* eine offene Spec-Entscheidung (T-119 bis
  T-122). Jeder enthaelt aber einen Teil, den die Spec sehr wohl entscheidet, der heute richtig
  umgesetzt ist - und der von keinem Test gedeckt war. Diese Teile sind jetzt festgenagelt; sie
  sind zugleich die Grundlage, gegen die eine spaetere Entscheidung ueberhaupt formuliert werden
  kann.
- **(a) FR-2, Tageszuordnung an der Mitternachtsgrenze** (bei konstantem Versatz eindeutig): lokal
  23:30 gehoert zum laufenden Tag, lokal 00:30 zum Folgetag. Mutation `add(deviceUtcOffset)` ->
  `subtract(...)` in `eventsForDay` wird rot; sie war in `scheduling_v2_test`, `_dst_test` und
  `_tz_test` unsichtbar, weil der vorhandene FR-2-Zeitzonentest die *Herkunft* des Versatzes
  prueft, nie dessen Vorzeichen und nie eine Tagesgrenze (sein Termin liegt um 18:00 UTC).
- **(b) FR-2, `hardFloor` darf vor Mitternacht des eigenen Tages liegen.** Die Formel kennt keine
  Klammerung; eine solche waere genau der von FR-2 benannte Schadensfall. Mutation "Ergebnis auf
  Mitternacht klammern" wird rot - sie war in vier Testdateien unsichtbar und ist genau die Art
  "Aufraeumen", die jemand fuer eine Selbstverstaendlichkeit halten koennte.
- **(c) FR-9, das Ventil loescht nie einen Tag, der etwas zu tun hat** - weder einen mit eigenem
  realem `hardFloor` (ein `null` dort hiesse, den Termin garantiert zu verpassen, und FR-18
  entfernte den Alarm) noch einen, vor dem noch ein realer Punkt im Fenster liegt (FR-5/FR-7:
  darauf ist ein Run zu planen). Beide Teilbedingungen waren ungedeckt, weil **jeder** vorhandene
  Ventiltest mit leerem Kalender faehrt - dort sind sie nie falsch. Schuetzt gegen die
  Vereinfachung auf "Zaehler >= 7 -> alles null", die woertlichste Lesart von FR-9 und damit die
  wahrscheinlichste Aufraeum-Aenderung; ihr Wegfall waere ein stummer Wecker an einem Tag mit
  echtem Termin.
- **(d) FR-3, ein am eigenen `hardFloor` gekappter Tag ist instant-verankert** - er darf bei einem
  Zeitzonenwechsel nicht ziffernweise mitwandern. Der Kappungszweig war in `test/` nie ausgefuehrt:
  die einzige positive Zusicherung zu `instantAnchoredDays` betrifft einen Tag aus dem
  `remaining.isEmpty`-Zweig, und der einzige Nachbartest prueft ausdruecklich den Gegenfall.
- **Methodischer Hinweis, der Zeit spart:** zwei meiner ersten fuenf Mutationen griffen gar nicht
  (Zeichenkette traf nicht), was wie "der Test faengt sie nicht" aussah. Eine Mutation, deren
  Einbau nicht belegt ist, beweist nichts - der Einbau gehoert mitgeprueft, bevor man aus einem
  gruenen Lauf etwas schliesst.
- **Requirement:** R2, R3

### T-117 · Die Naht zwischen "Plan berechnet" und "Alarm registriert" war ungedeckt — BEHOBEN (2026-09-11)

- [x] Zusichern, dass `replan()` den berechneten Plan tatsaechlich anwendet.
- **Why:** kein Verhaltensfehler, sondern eine Abdeckungsluecke - und die gefaehrlichste, die diese
  Pruefung gefunden hat. `test/apply_alarms_test.dart` prueft `planAlarmSync` rein und
  `applyPlannedAlarms` direkt; **nichts** prueft, dass `replan()` sie ueberhaupt aufruft. Die
  Bindung existierte nur als Kommentar an der Aufrufstelle.
- **Evidence:** entfernt man `await applyPlannedAlarms(appState, now: nowFn);` aus `replan()`,
  bleiben **neun** Testdateien vollstaendig gruen: `replan_test` (21/21), `apply_alarms_test`
  (32/32), `checkpoint_test` (20/20), `replan_audit_test` (die uebrigen 6/6),
  `checkpoint_audit_test` (4/4), `handler_replan_wiring_test` (4/4),
  `handler_on_alarm_handled_test` (3/3), `next_wake_up_test` (8/8),
  `app_state_scheduling_v2_test` (12/12). Vom Pruefer gemeldet und von mir nachgestellt.
- **Warum das keine hypothetische Regression ist:** genau so war scheduling-v2 schon einmal
  **vollstaendig wirkungslos** - die Woche wurde korrekt berechnet und nie zu einem Alarm (T-63).
  Der Kommentar an der Aufrufstelle nennt die Gefahr beim Namen ("that way no code path can
  compute a plan and forget to apply it, which is exactly how the whole engine ended up
  functionally inert before"); ab jetzt nennt sie ein Test.
- **Zwei Zusicherungen:** die Alarmmenge nach `replan()` entspricht genau den geplanten Werten
  **nach jetzt** (FR-18s Wortlaut), und ein *geaenderter* Plan zieht die bereits registrierten
  Alarme im naechsten Lauf nach. Letzteres ist zugleich FR-16s entscheidbare Haelfte ("keine
  vollstaendige Neuberechnung … die folgt erst beim naechsten regulaeren Planungslauf") - die
  andere Haelfte ist T-113.
- **Bewusst mit echten Zukunftszeiten:** `AppState.addAlarm` vergleicht gegen `DateTime.now()` und
  nimmt einen vergangenen Zeitpunkt gar nicht erst auf; ein injizierter Vergangenheits-"now"
  wuerde hier nichts beweisen. Der heutige Fenstertag faellt je nach Laufzeit heraus - korrekt,
  und der Test rechnet das aus FR-18s "nach jetzt" heraus, statt es hinzunehmen.
- **Requirement:** R2, R3

### T-116 · Zwei Alarme auf derselben Minute waren ein stabiler Fixpunkt — BEHOBEN (2026-09-11)

- [x] Pro geplantem Wert darf hoechstens ein Alarm ueberleben.
- **Why:** `planAlarmSync` entschied ueber `desiredMinutes.contains(...)` - eine blosse
  **Mengenzugehoerigkeit**, keine Zuordnung. Liegen zwei `ScheduledAlarm`s auf derselben Minute,
  galten damit **beide** als behaltenswert und keiner als ueberzaehlig; weil `keptMinutes`
  anschliessend die Minute enthielt, blieb auch `toAdd` leer. Der Zustand war damit ein **stabiler
  Fixpunkt**: jede weitere Neuplanung bestaetigte das Duplikat. Der Nutzer wird dauerhaft zweimal
  geweckt, und nichts in der Engine raeumt das je wieder auf.
- **Warum das kein Auslegungsstreit ist:** FR-18s Kopfsatz ist eine Nachbedingung ueber die MENGE
  ("angeglichen, dass sie **genau den geplanten Werten entspricht**"), und FR-18s eigener Testfall
  nennt dasselbe Ziel ("passender Alarm existiert bereits -> **kein Duplikat**, keine Entfernung
  (idempotent)"). Die zweite Spiegelstrich-Regel ist dagegen eine Bedingung *pro Alarm* und trifft
  auf ein Duplikat bei keinem der beiden zu - massgeblich ist der Kopfsatz: er nennt das Ziel, die
  Spiegelstriche die Mittel. Unabhaengig von jeder Spec-Auslegung verfehlt die Funktion ausserdem
  ihren **eigenen** dokumentierten Vertrag: "computes what has to change so the set of
  `ScheduledAlarm`s matches [pendingDayValues] **exactly**".
- **Evidence:** `planAlarmSync` mit einem geplanten Wert und zwei identischen Alarmen auf dessen
  Minute liefert `toRemove=[] toAdd=[]` - in beiden Betriebsarten, mit und ohne Plattformwissen.
- **Fix:** der erste passende Alarm belegt den Wert, jeder weitere faellt weg. Bewusst
  reihenfolge-abhaengig, und der Ueberlebende steht gerade **nicht** in `toRemove` - entfernt wird
  ueber die Alarm-ID, ein Entfernen derselben ID wuerde ihn auf der Plattform mitstoppen. Das war
  der Hinweis des Gegenpruefers, nicht des urspruenglichen Vorschlags.
- **Unberuehrt bleibt FR-18s sicherheitskritische Regel:** ein Alarm in der Vergangenheit wird nie
  entfernt (er koennte gerade klingeln). Eigener Testfall mit zwei Duplikaten in der
  Vergangenheit.
- **Test:** `test/apply_alarms_test.dart`, Gruppe T-116 - zwei und drei Alarme auf derselben
  Minute, der Fixpunkt danach, das Vergangenheits-Duplikat und zwei Alarme auf verschiedenen
  Minuten als Gegenprobe gegen eine Ueberkorrektur.
- **Requirement:** R2, R3

### T-115 · OFFENE SPEC-ENTSCHEIDUNG: was gilt bei einem Abstand von exakt 12 Stunden?

- [x] Die beiden Werte NEBEN der Schwelle absichern (das geht ohne Entscheidung).
- [ ] Entscheiden, welche Lesart bei genau 12:00 gewinnt, und es in FR-6 schreiben.
- **Lage:** FR-6s Klarstellung loest die Richtungs-Mehrdeutigkeit so auf, dass "die Variante mit
  `|Δ| <= 12h` gewinnt". Bei einem Abstand von **exakt** 12:00 erfuellen aber **beide** Lesarten
  `|Δ| <= 12h` - die Regel waehlt nicht. FR-1 hilft nicht weiter: FR-1 rechnet ueber echte
  Instants, wo die Mehrdeutigkeit gar nicht erst entsteht; das `|Δ| <= 12h`-Kriterium existiert
  ausschliesslich fuer FR-6s reinen Uhrzeit-Vergleich.
- **Heute** wird "spaeter" gewaehlt - aber nur als Nebenwirkung der Operatorwahl in
  `scheduling_v2.dart:61-68` (`> halfDay` im ersten, `<= -halfDay` im zweiten Zweig), nicht als
  bewusste Festlegung.
- **Zu entscheiden:** *Welche Lesart gewinnt bei genau 12:00, und soll das im Spec-Text stehen?*
  - **"spaeter"** (heutiges Verhalten): der Weg von 07:00 ueber 13:00 nach 19:00 fuehrt durch den
    Tag. Dann gehoert in FR-6 ein Zusatz "bei Gleichstand gewinnt die positive Variante", und
    `_wallClockDelta`s zweiter Zweig muss sein `<=` behalten.
  - **"frueher"**: der Zwischentag laege bei 01:00, der Nutzer wuerde mitten durch die Nacht
    geschleift. Fuer eine Wecker-App die schlechtere Wahl, vom heutigen Text aber gleichermassen
    gedeckt.
- **Was bereits erledigt ist:** die beiden Werte unmittelbar neben der Schwelle (11:59 und 12:01)
  sind jetzt getestet - dort entscheidet die Spec eindeutig, und die beiden Faelle klammern die
  Schwelle beidseitig auf 12:00 +/- eine Minute ein. Damit ist die eigentliche Gefahr abgedeckt:
  jede Verschiebung oder versehentliche Entfernung der Wraparound-Aufloesung. Mutationsprobe
  (Schwelle 12h -> 11h) geht rot. Vorher deckte die Suite gar nichts davon ab - der groesste
  geprüfte Abstand lag bei zwei Stunden, und diese Schwelle traegt die gesamte
  Mitternachtsbehandlung des Moduls.
- **Ein Hinweis aus der Pruefung, der Arbeit spart:** die naheliegende Mutation `>` -> `>=` im
  **ersten** Zweig ist ein *aequivalenter* Mutant und durch keinen Test fangbar - die beiden `if`
  sind nicht `else if`, bei genau +12h zieht der erste Zweig 24h ab und der zweite addiert sie
  sofort wieder. Der Grenzfall haengt allein am zweiten Zweig.
- **Requirement:** R2

### T-114 · Der Anker der Folgewoche hing am Ausloeser statt am Zustand — BEHOBEN (2026-09-11)

- [x] `lastConcludedDay` aus dem Fortschrittsmarker ableiten, gegen die Zukunft geklammert.
- [x] Die zu schwache Zusicherung aus T-106 schaerfen.
- [x] Die dadurch tot gewordene Schreibsperre entfernen, statt sie als Schein-Sicherung
      stehenzulassen.
- **Why:** FR-3 sagt "`lastEffectiveWakeTime` ist bewusst **kein** eigenes Feld: es ist **immer
  der Eintrag in `pendingDayValues` fuer den zuletzt abgeschlossenen Tag** und wuerde als zweite
  Quelle nur auseinanderlaufen koennen". `replan()` las den Anker aber aus einem vom **Ausloeser**
  abgeleiteten Tag: fuer alles ausser dem Ring aus "gestern". Hat heute schon geklingelt, ist der
  zuletzt abgeschlossene Tag aber **heute** - und der steht in `lastProcessedConcludedDay`, genau
  dem Feld, das T-75 dafuer von `lastReplanDate` getrennt hat.
- **Wirkung, gemessen:** `maxDailyDelta` ist die eine Zusicherung, die diese App ihren Nutzern
  ueber ihren Schlaf gibt - "verschiebe meine Weckzeit nie um mehr als X pro Tag". Sie wurde durch
  eine beliebige Einstellungsaenderung am Vormittag gebrochen:
  - *Anker vorhanden, aber der falsche:* Tagesschritt **2 Stunden** bei erlaubter einer.
  - *Kein Eintrag fuer gestern* (der Normalzustand nach dem T-82-Prune oder nach einer Luecke):
    der Anker ist `null`, `computeWeekPlan` nimmt FR-10s Kaltstart - und der springt **direkt auf
    die `wunschzeit`**, ohne jede Begrenzung. Gemessen: **3 Stunden** bei erlaubter halben. FR-10
    ist hier gar nicht anwendbar; ein `lastEffectiveWakeTime` existiert sehr wohl, es steht unter
    heute.
  Betroffen ist jede planungsrelevante Einstellung und der Sync-Knopf, also ein alltaeglicher
  Handgriff - und der Nutzer erfaehrt nichts davon: FR-6s Overrun-Warnung greift nur in Runs,
  nicht im Lueckentag-Drift.
- **T-71 widerspricht dem nicht,** obwohl es so aussieht. T-71 sagt, ein Checkpoint darf nicht
  *annehmen*, heute sei abgeschlossen - daher `todayAlreadyRang`. Ob heute abgeschlossen **ist**,
  ist eine Frage des Zustands. Vom Gegenpruefer eigens gesucht: keine FR und kein bestehender Test
  widerspricht (21 Fundstellen von `todayAlreadyRang` in `test/` einzeln durchgesehen).
- **Ein Fehler, den ich selbst am selben Tag eingebaut hatte, faellt damit auch:** T-106s
  Schreibsperre las den Fortschrittsmarker **ungeklammert**. Stand der in der Zukunft (Uhrzeit
  zurueckgestellt, Zonenwechsel ueber die Datumsgrenze - dieselbe Ursache wie T-109), galt das
  **ganze Fenster** als abgeschlossen und es wurde ueberhaupt nichts mehr geplant. Regressionstest
  vorhanden; `dayDistance(markerDay, today) <= 0` klammert jetzt.
- **Und eine Sicherung, die nichts mehr sicherte:** seit `windowStart = lastConcludedDay + 1` dem
  Zustand folgt, kann kein Fenstertag mehr als abgeschlossen gelten - die Sperre war beweisbar
  toter Code. Die Mutationsprobe bestaetigte es (entfernt: alle Tests bleiben gruen). Entfernt
  statt stehengelassen: eine Sicherung, die Schutz vortaeuscht, ist schlimmer als keine. FR-11
  entsteht jetzt an genau einer Stelle - der Fensterbildung -, und das steht dort im Kommentar.
- **Meine eigene Luecke, vom Pruefer gefunden:** der T-106-Test "der Folgetag bleibt revisionierbar"
  pruefte `isNot(06:00)` - "irgendetwas anderes". Der spec-richtige Wert 06:30 erfuellt das, der
  falsche 09:00 aber genauso. Der Test lag exakt auf diesem Fall und blieb gruen, waehrend
  `maxDailyDelta` um das Sechsfache ueberschritten wurde. Jetzt prueft er den Betrag.
- **Verglichen wird durchgehend ueber `dayDistance`,** nicht ueber `isAfter`: der Marker kommt
  lokal getaggt aus den Preferences, `currentTime` kann ein `tz.TZDateTime` sein - ein
  Instant-Vergleich zweier Mitternachten aus verschiedenen Frames waere die Fehlerklasse dieses
  Moduls an einer neuen Stelle.
- **Test:** `test/replan_audit_test.dart`, Gruppe T-114 - drei Faelle; beide Mutationen (zurueck
  auf die Ausloeser-Ableitung; Klammerung entfernt) gehen gezielt rot.
- **Requirement:** R2

### T-112 · OFFENE SPEC-ENTSCHEIDUNG: was gilt beim Mitternachtsuebertritt einer Kurve?

- [ ] FR-6 um eine Mitternachtsregel ergaenzen, DANN testgetrieben umsetzen.
- **Lage:** rutscht eine interpolierte Weckzeit ueber Mitternacht, kann ein Kalendertag **zwei**
  Alarme bekommen (in der Probe 00:30 und 01:00) und ein anderer **keinen**. Kein FR verbietet das
  woertlich: FR-18 fordert einen Alarm *pro geplantem Wert*, sieben Werte ergeben sieben Alarme,
  und eine Regel "genau ein Alarm pro Kalendertag" existiert nirgends.
- **Warum es nicht einfach ein Bug ist:** FR-6 verlangt gleichzeitig zwei Dinge, die beim
  Uebertritt **nicht gleichzeitig erfuellbar** sind - "jeder `Tag_i` bekommt sein eigenes, echtes
  Kalenderdatum `A`s Datum + i" und die Schrittformel `Tag_i = A ± (ΔT/N)·i`. Ein Beispiel: Anker
  lokal 23:30, Schritt +30min. Die strenge Datumslesart ergaebe fuer `Tag_1` den Folgetag um
  00:00 - das liegt **23,5 Stunden vor** dem Anker und ist gerade kein "+30min"-Schritt. Der Code
  hat sich fuer die Formel entschieden (Instant-Monotonie, Schritt <= `maxDailyDelta`) und das
  Datum folgen lassen. Das ist eine zulaessige Lesart, nicht nachweisbar die verlangte.
- **Dazu kommt:** der Uebertritt ist eine direkte Folge einer anderen Spec-Regel. FR-1s
  Richtungsaufloesung "`|Δ| <= 12h` gewinnt" erzwingt ihn. Und "Schluesseldatum != Instant-Datum"
  ist per Spec kein Fehlerindiz - FR-2 erzeugt es selbst (ein Termin lokal 01:00 ergibt einen
  `hardFloor`-Instant am Vortag, der per FR-2 der Wert des Termintags ist).
- **Geprueft und widerlegt wurden beide urspruenglich unterstellten Folgen:** ein rueckwaerts
  gerutschter Wert wird auf dem Ring-Pfad **nie** stillschweigend verworfen (der Wert fuer
  `window[0]` liegt strukturell >= Anker + 12h); auf dem FR-17-Erholungspfad faellt einer weg, aber
  es ist einer, der zum Planungszeitpunkt schon vergangen war - genau das schreibt FR-18 vor. Keine
  Nacht bleibt ohne Alarm.
- **Zu entscheiden:** entweder FR-6 ergaenzen um "der Instant bleibt monoton, das Schluesseldatum
  bleibt der Fenstertag; ein Fenstertag darf dadurch ohne eigenen Alarm bleiben" - das ist das
  heutige Verhalten, die Aenderung waere rein redaktionell - **oder** um "der Wert wird auf seinen
  Fenstertag zurueckgeholt", dann ist es eine echte Verhaltensaenderung mit Folgen fuer FR-5s
  Verletzungspruefung (die vergliche sonst Kurvenwerte mit `hardFloor`s eines anderen Tages).
- **Vor einer Entscheidung nicht implementieren:** ohne sie gibt es keinen Test, der den Fall rot
  machen koennte, ohne das Soll vorher selbst zu erfinden.
- **Requirement:** R2

### T-113 · OFFENE SPEC-ENTSCHEIDUNG: soll FR-16s Checkpoint 2 die scharf gestellten Alarme nachziehen?

- [ ] FR-16/FR-18 entscheiden, DANN testgetrieben umsetzen.
- **Lage:** Checkpoint 2 deutet bei erkanntem Versatzwechsel den gespeicherten Plan um, ruehrt den
  bereits registrierten Plattformalarm aber nicht an. Der **erste** Wecker nach einem Flug klingelt
  deshalb um die volle Versatzdifferenz falsch - im durchgerechneten Beispiel 17:00 statt 09:00
  Ortszeit - und wird erst durch den Ring dieses falsch stehenden Alarms korrigiert. Fuer einen
  Wecker ist das der schwerste Schadensfall ueberhaupt.
- **Warum das (heute) kein Implementierungsfehler ist:** vier unabhaengige Festlegungen sprechen
  fuer den Code. FR-18s Praeambel sagt, FR-1 bis FR-17 beschreiben **ausschliesslich Berechnung und
  Ausloeser** - FR-16s Testfall kann ueber scharf gestellte Alarme also gar nichts aussagen. FR-18
  bindet den Abgleich an "nach **jeder Neuplanung**", und CP2 ist per FR-16 explizit **keine**.
  FR-16 verschiebt die Wirkung selbst ("die folgt erst beim naechsten regulaeren Planungslauf").
  Und FR-16s Abschnitt "Bekannte Grenze am Umstellungstag" akzeptiert woertlich denselben
  Nutzereffekt.
- **Wogegen das steht:** FR-16s eigener durchgerechneter Testfall "Ortswechsel" behauptet
  "**Ohne den zweiten Checkpoint waere das erst beim naechsten Klingeln (>12h spaeter) korrigiert
  worden**" - also eine sofortige Wirkung. In seiner schwachen Lesart ist er erfuellt (der
  gespeicherte Planwert traegt danach die richtigen Ziffern), in der starken nicht.
- **Zu entscheiden:** bleibt es bei der schwachen Lesart (dann gehoert FR-16s Testfall
  praezisiert, damit er nicht laenger mehr verspricht als die Anforderung), oder kommt eine
  Anforderung "nach einer Umdeutung durch CP2 ist FR-18 erneut anzuwenden"?
- **Was die zweite Variante technisch bedeutet:** `planAlarmSync` ist rein und aus dem Isolate
  aufrufbar, `Alarm.set` aus dem Hintergrund-Isolate ist dagegen eine eigene, in FR-16 nicht
  behandelte Frage - Plugin-Kanal im Isolate, dieselbe Fehlerklasse, der FR-16 mit dem direkten
  SharedPreferences-Zugriff schon einmal ausgewichen ist (T-79). Das ist der eigentliche Aufwand,
  nicht die Rechnung.
- **Requirement:** R2, R3

### T-111 · Geprueft und WIDERLEGT: Migrationspfad `lastProcessedConcludedDay` → `lastReplanDate` (2026-09-11)

- **Behauptung war:** faellt der neue Schluessel, wird `lastReplanDate` als Fortschrittsmarker
  uebernommen; da der alte Schluessel vor T-75 bei *jedem* Replan auf heute gesetzt wurde,
  importiere die Migration den T-75-Fehler noch einmal - der erste Ring nach einem Update zaehle
  einen Tag nicht mit und pruefe ihn nicht auf FR-12.
- **Ergebnis: widerlegt.** Der Mechanismus ist reproduzierbar (Sonde rot: `gapDayCounter` 0 statt
  1), aber der ausloesende Preferences-Zustand ist **unerreichbar**: der heutige Code schreibt
  beide Schluessel immer gemeinsam, FR-16s Checkpoint 2 fasst sie nicht an, und `git log -S`
  zeigt, dass `lastReplanDate` erst mit demselben Commit existiert wie
  `lastProcessedConcludedDay`. Es gibt **null** Tags und kein veroeffentlichtes Artefakt, in dem
  der alte Schluessel je allein geschrieben worden waere. Die Spec regelt Migration nicht, und die
  unterstellte Wirkung faellt zusaetzlich in FR-9s ausdruecklich akzeptiertes Restrisiko.
- **Warum das hier steht, obwohl nichts zu tun ist:** damit derselbe Verdacht nicht ein drittes
  Mal untersucht wird. Der Fallback bleibt bewusst stehen - er kostet nichts und ist die
  konservativere der beiden Lesarten (die Alternative, `null`, wuerde denselben Tag doppelt
  zaehlen).
- **Was aus der Pruefung wirklich folgte:** der fehlende Persistenz-Rundreise-Test fuer
  `lastProcessedConcludedDay` - das ist T-108, und der ist erledigt.

### T-108 · Drei FR-3-Felder ohne Persistenz-Rundreise — BEHOBEN (2026-09-11)

- [x] Rundreise-Tests fuer `lastProcessedConcludedDay`, `overrunNotificationSent` und
      `safetyValveNotificationSent`.
- **Why:** von den zehn FR-3-Feldern hatten sieben einen Rundreise-Test, diese drei nicht. Benutzt
  werden sie funktional in `replan_test`, `checkpoint_test` und `replan_notifications_test` - aber
  keiner davon baut `AppState` neu auf, prueft also nie, ob der Wert einen App-Neustart
  ueberdauert. Beide bool-Merker tragen FR-6s bzw. FR-9s "einmalig"-Zusage ueber genau diese
  Grenze; ohne Persistenz wuerde nach jedem Neustart erneut gemeldet.
- **Ergebnis:** das Verhalten war korrekt, nur ungedeckt - alle vier Tests waren sofort gruen.
  Gegen einen Scheingruen-Test abgesichert: mit entfernter `setBool`-Zeile geht der Test rot
  (ausprobiert), der Rundgang laeuft also wirklich ueber die Preferences und nicht ueber eine
  gemeinsame Instanz.
- **Zusaetzlich:** ein Test pflockt fest, dass `lastProcessedConcludedDay` und `lastReplanDate`
  getrennt bleiben - das war der ganze Punkt von T-75 und war nur implizit abgesichert.
- **Requirement:** R2

### T-105 · FR-6s Meldepflicht fiel genau im haeufigsten Overrun-Fall aus — BEHOBEN (2026-09-11)

- [x] Die Overrun-Meldung auch auf dem Pfad setzen, der einem Tag seinen eigenen `hardFloor`
      direkt zuweist.
- **Why:** FR-6 sagt "bei **jeder** Ueberschreitung von `maxDailyDelta` (`N=1` **oder** verteilt)
  wird der Nutzer einmalig benachrichtigt", und rechnet den `N=1`-Fall sogar als eigenen Testfall
  durch (`A=08:00, F=02:00, N=1, maxDailyDelta=60min` -> voller 6h-Sprung **plus** Meldung). Die
  Ausnahme, die FR-6 fuer `N=1` gewaehrt, betrifft die Sprunghoehe ("nicht verteilbar"), nicht das
  Schweigen. `computeWeekPlan`s Zweig `remaining.isEmpty` wies den `hardFloor` aber direkt zu,
  ohne `distribute()` - und `distribute()` ist die einzige Stelle, die die Flagge je gesetzt hat.
- **Tragweite:** betroffen ist genau `window[0]`, also der Alltagsfall "morgen einmal frueh raus,
  danach eine termin-lose Woche". Fuer jeden spaeteren Fenstertag laeuft der Vortag noch durch
  FR-7s Pruefung, die den Rest-Sprung entweder klein haelt oder dort einen Run startet (dann
  meldet `distribute`). `window[0]`s Anker ist der gestern geklingelte Wert - fuer den findet
  keine solche Pruefung mehr statt. Der Nutzer bekam also fuer einen mehrstuendigen
  Weckzeit-Sprung keine Warnung.
- **Evidence:** unabhaengig gefunden und anschliessend unabhaengig gegengeprueft (beide Male mit
  ausgefuehrter Probe). Anker 31.12. 07:00Z, ein einziger Termin am 01.01. 01:00Z,
  `maxDailyDelta = 30min` -> Wert 01:00Z (FR-konform), `overrunNotificationNeeded: false`
  (spec-widrig). Der Gegenpruefer hat die urspruengliche Formulierung ausserdem **eingeschraenkt**:
  ein "beliebig grosser Sprung ohne Meldung" entsteht nicht bei jedem letzten Fensterpunkt,
  sondern nur auf `window[0]`.
- **Fix:** derselbe Ausdruck wie in `distribute` (`ΔT/N > maxDailyDelta`, division-frei
  geschrieben), damit die beiden Pfade nicht auseinanderlaufen koennen.
- **Test:** `test/scheduling_v2_audit_test.dart`, Gruppe "FR-6: die Overrun-Meldung darf auch bei
  N=1 nicht ausfallen" - drei Faelle: Sprung ueber der Grenze meldet, Sprung darunter meldet
  nicht, Sprung **genau auf** der Grenze meldet nicht (FR-6s Bedingung ist `>`, nicht `>=`).
  Schliesst zugleich eine zweite Luecke: `overrunNotificationNeeded` wurde auf
  `computeWeekPlan`-Ebene in der ganzen Suite **nie** als `true` geprueft - nur an `distribute`
  direkt und an handgebauten `WeekPlanResult`s in `replan_notifications_test.dart`. Genau deshalb
  konnte der Befund unentdeckt bleiben: Unit-Ebene und Meldeebene waren je einzeln gruen, die
  Verbindung dazwischen ungetestet.
- **Requirement:** R2

### T-104 · FR-5s ΔT=0-Regel galt nur fuer den ersten Punkt — BEHOBEN (2026-09-11)

- [x] Den Run an jedem ΔT=0-Punkt begrenzen, nicht nur an `points.first`.
- **Why:** FR-5 Schritt 2 lautet "Ein Punkt mit `ΔT=0` relativ zu `A` beendet den Run sofort bei
  sich selbst - zaehlt fuer keine Richtung als kompatibel, **wird nie mit einem Folgepunkt
  zusammengefasst**". Kein Positionsvorbehalt. `groupTarget` pruefte aber nur `points.first`; die
  anschliessende Schrumpfungsschleife sieht fuer Zwischenpunkte ausschliesslich die *Verletzung*
  (`interpolated.isAfter(intermediate.value)`), nie deren ΔT=0-Eigenschaft.
- **Warum das so lange unentdeckt blieb:** der spec-eigene Test-Bullet stellt den ΔT=0-Punkt an
  Position 1 (`A=07:00, t1(Di)=07:00, t2(Fr)=09:00`) - also genau dorthin, wo eine Pruefung von
  `points.first` allein schon ausreicht. Der vorhandene Test bildet diesen Bullet ab und war
  gruen.
- **Evidence:** unabhaengig gefunden und gegengeprueft. Anker 07:00, `t1(+1)=08:00`,
  `t2(+2)=07:00` (ΔT=0), `t3(+3)=05:00`, `maxDailyDelta=60min` -> geliefert wurde `t3`, verlangt
  ist `t2`.
- **Tragweite:** gering, aber eindeutig. Der Run wird ueber einen Tag hinweg zusammengefasst,
  dessen Weckzeit ohnehin schon exakt der aktuellen entspricht; die Kurve wird flacher als
  vorgesehen und verschiebt genau den Tag, an dem gar nichts zu glaetten war. Setzt eine auf die
  Minute gleiche Uhrzeit-Ablesung voraus.
- **Fix:** die Kandidatenliste wird am ersten ΔT=0-Punkt abgeschnitten (einschliesslich), statt
  bei ihm sofort zurueckzukehren - so bleibt Schritt 1s Schrumpfung darunter wirksam. Eine flache
  Kurve kann einen strengeren Zwischenpunkt sehr wohl verletzen; dann muss `t_m` weiter
  schrumpfen wie bei jedem anderen Ziel auch.
- **Test:** `test/scheduling_v2_audit_test.dart`, Gruppe "FR-5 Schritt 2" - vier Faelle,
  darunter zwei Gegenproben gegen eine Ueberkorrektur (ohne ΔT=0-Punkt wird weiterhin bis zum
  letzten Punkt gruppiert; ein ΔT=0-Punkt schrumpft weiter, wenn er einen Zwischenpunkt verletzt).
- **Requirement:** R2

### T-103 · Die Alarm-Ueberlebensmessung meldete ein FAIL, das sie nicht belegen konnte — BEHOBEN (2026-09-11)

- [x] Das Zaehlmuster auf vollstaendig qualifizierte Bezeichner umstellen.
- [x] Einen Selbsttest gegen aufgezeichnete `dumpsys`-Ausgabe, der ohne Emulator laeuft.
- **Why:** `check_alarm_survival.sh` faellt ein Urteil ueber die zentrale Produktzusage
  ("garantiertes Aufwachen"). Im ersten Lauf mit dem Skript (T-99) fand das Muster **nichts**,
  obwohl `arm_alarm_test.dart` nachweislich einen Alarm gesetzt hatte. Die Reaktion darauf war,
  **mehr** Muster zu ergaenzen - darunter die blosse Teilzeichenkette `AlarmReceiver`. Im zweiten
  Lauf (34566962847) traf genau die Googles
  `com.android.wallpaper.module.DailyLoggingAlarmReceiver`, zweimal. Der Zaehler stand damit auf
  2 statt 0, das Skript lief an seinem eigenen `BEFORE == 0`-Waechter vorbei und schrieb
  `RESULT reboot: FAIL - no alarm survived the reboot` in die Beweisdatei. Diese Zeile belegt
  nichts: der eigene Alarm war in **keiner** der beiden Messungen je gefunden worden.
- **Evidence:** `alarm_survival.log` aus Lauf 34566962847 — `registered alarm lines before
  reboot: 2`, waehrend der Rohauszug darunter ausschliesslich fremde Eintraege zeigt
  (`android`, `com.android.settings`, `com.google.android.gms`, `…apps.wallpaper`) und der
  Abschnitt `app-uid alarms` leer bleibt. Die Datei liegt woertlich als
  `.github/scripts/fixtures/dumpsys_alarm_foreign.txt` im Repo und ist die Negativ-Fixture des
  Selbsttests. Nachgestellt: `grep -cE "com.wakeywakey.wakeywakey|AlarmReceiver|…"` liefert
  darauf **2**, korrekt waeren **0**.
- **Resolution:** die Zaehlung liest jetzt die Summenzeile
  `Pending alarms per uid: [… u0a161:2 …]` — den kernel-eigenen Zaehler pro uid, ganz ohne
  Textmustersuche —, und faellt nur ersatzweise auf Eintragszeilen mit dem **Paketnamen** zurueck.
  Die uid wird ueber `pm list packages -U` aufgeloest, mit `userId=`/`appId=` als Rueckfallweg
  (`userId=` allein blieb im echten Lauf leer). Generische Wortteile sind verboten, und das uid-
  Token ist ziffernbegrenzt, damit `u0a16` nicht `u0a161` trifft.
  Vor allem aber: **das Instrument beweist sich jetzt selbst, bevor es misst.**
  `check_alarm_survival.sh --self-test` prueft die Erkennung gegen zwei Fixtures (die echte
  Fremd-Aufzeichnung muss 0 ergeben, ein eigener Alarm muss gefunden werden — sonst waere der
  Negativtest trivial durch ein Muster zu erfuellen, das gar nichts trifft), laeuft ohne Emulator
  in CIs UTC-Bein und bricht die Messung ab, wenn er fehlschlaegt. Beide Mutationen (generisches
  `AlarmReceiver` zurueck; uid-Token ohne Ziffernbegrenzung) wurden ausprobiert und gehen rot.
- **Was weiterhin offen ist:** wie ein eigener Alarm in `dumpsys alarm` **wirklich** aussieht, ist
  nach wie vor nie beobachtet worden. `dumpsys_alarm_own.txt` ist deshalb ausdruecklich
  **konstruiert** und als solche gekennzeichnet (`fixtures/README.md`). Der naechste Lauf muss
  zeigen, ob die Erkennung in der Realitaet greift; findet sie wieder nichts, meldet das Skript
  jetzt **inconclusive** statt FAIL und nennt die drei Stellen, an denen zu suchen ist.
- **Lehre, allgemein:** ein blindes Beweismittel, das "nichts gefunden" meldet, ist harmlos - man
  merkt es. Eines, das etwas Falsches findet, ist gefaehrlich: es sieht aus wie ein Ergebnis. Wer
  ein Muster erweitert, weil es nichts trifft, muss im selben Zug pruefen, was es **zusaetzlich**
  trifft.
- **Requirement:** R3

### T-102 · Der Gradle-Cache hat den Release-Build erschlagen — BEHOBEN (2026-09-11)

- [x] Cache auf das verschmaelern, was sich lohnt.
- [x] Die aufgelaufenen Caches loeschen.
- [ ] Im naechsten Lauf bestaetigen, dass der Build-Job durchlaeuft (danach ist T-06s Restaufgabe
      - ein Live-Beweis, dass das Gate wirklich stoppt - separat noch offen).
- **Why:** im Lauf 34535358135 stand `Build Android (production)` auf `failure`, und die
  naheliegende Deutung waere gewesen: "die Desugaring- oder Override-Aenderung hat den Build
  zerbrochen". Das war **falsch**. Die Schrittliste des Jobs zeigt, dass er in **Schritt 6**
  (`actions/cache`, Gradle) nach 2m49s starb und `flutter build apk --release` (Schritt 9)
  **nie ausgefuehrt** wurde. Die Logs waren zu diesem Zeitpunkt schon nicht mehr abrufbar
  (`BlobNotFound`), die Schrittliste aber schon.
- **Ursache:** der Cache-Block legte `~/.gradle/caches` **komplett** ab. Das waechst unbegrenzt -
  darin liegen neben den geladenen Abhaengigkeiten auch jede transformierte AAR und jeder
  Build-Cache-Eintrag. Messung: **6436 MB** Actions-Cache, davon zwei Gradle-Eintraege mit
  **3746 MB** und **2397 MB**. Zwei, weil die Aenderungen an `android/**/*.gradle*` den
  Cache-Schluessel aendern - der alte Multi-GB-Eintrag bleibt daneben liegen. Ein Restore dieser
  Groesse dauert laenger als der Build spart und faellt gelegentlich einfach um.
- **Status:** gecacht wird jetzt nur `~/.gradle/caches/modules-2` (die geladenen Module) und
  `~/.gradle/wrapper`, mit `restore-keys` fuer Teiltreffer - in allen vier Workflows. Alle
  aufgelaufenen Caches geloescht (Liste ist leer; die Nutzungsanzeige von GitHub laeuft nach).
- **Lehre, die ueber diesen Fall hinausgeht:** bei einem roten Job zuerst die **Schrittliste**
  ansehen, nicht die eigene naheliegendste Hypothese. Hier haette die falsche Deutung dazu
  gefuehrt, eine korrekte und nachweislich verifizierte Aenderung (T-90/T-97) zurueckzunehmen.

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

- **Nachtrag (2026-09-11):** der damals noch offene Punkt "die neuen E2E-Szenarien brauchen ein
  Geraet" ist erledigt - Lauf 34532845207 hat sie auf dem CI-Emulator gefahren (`🎉 7 tests
  passed`). Siehe T-91.

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
- [x] Das Verfahren einmal wirklich laufen lassen (Lauf 34566962847, 2026-09-11).
- [ ] Ein **verwertbares** Ergebnis eintragen und das Bein dann scharf stellen.
- **Ursache seit 2026-09-11 bekannt und strukturell (T-131):** `flutter test` deinstalliert die
  App nach dem Lauf, Android verwirft damit ihre AlarmManager-Eintraege - es kann zum Messzeitpunkt
  gar kein Alarm registriert sein. Das Verfahren braucht also einen anderen Weg, den Alarm scharf
  zu stellen, bevor hier ueberhaupt etwas messbar wird. **Die Frage bleibt unbeantwortet, nicht
  fehlgeschlagen.**
- **Stand nach dem ersten echten Lauf:** unbrauchbar, und zwar messtechnisch, nicht inhaltlich.
  Das Zaehlmuster traf fremde Alarme und meldete ein unbegruendetes FAIL - siehe T-103, wo das
  aufgearbeitet und behoben ist. Die Frage "ueberlebt ein Alarm den Reboot?" ist damit weiterhin
  **unbeantwortet**; sie ist jetzt nur messbar geworden. Scharf stellen erst, wenn ein Lauf den
  eigenen Alarm vor dem Reboot ueberhaupt sieht.
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

### T-75 · `lastReplanDate` vermischt zwei Zwecke -> FR-9/FR-12 überspringen ganze Tage — BEHOBEN (2026-09-10)

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

### T-76 · Sommerzeit: `dayOffset` in `computeWeekPlan` ist nach der Frühjahrsumstellung um 1 zu klein — BEHOBEN (2026-03-29)

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

### T-77 · `replan()` ist nicht serialisiert - nebenläufige Checkpoints möglich — BEHOBEN (2026-09-10)

- [x] Einen Future-Mutex um den gesamten Checkpoint; den Tagesmarker **vor** dem Kalender-I/O
      reservieren, nicht erst am Ende.
- **Why:** vier Auslöser, drei davon `unawaited` (`handler.dart:68`, `main.dart:235`, `main.dart:207`,
  plus die UI). FR-17s Sperre schützt nicht, weil sie `lastReplanDate` liest, das erst am **Ende** von
  `replan()` geschrieben wird (`replan.dart:194`). Klingelt ein Alarm, holt Android die App per
  Full-Screen-Intent nach vorn -> `resumed` -> zweiter Checkpoint startet, während der erste noch im
  Kalender-I/O hängt: `gapDayCounter` wird doppelt inkrementiert und beide berechnen `toAdd` gegen
  dieselbe alte Alarmliste -> Doppelalarme auf derselben Minute.
- **Status:** Behoben 2026-09-10: `runSchedulingCheckpoint()` serialisiert alle Auslöser über eine Future-Kette, und FR-17s Tagessperre wird **innerhalb** der Sperre gelesen. Nachgewiesen wirksam: mit ausgeschaltetem Lock wird `test/checkpoint_test.dart`s erster Fall rot (2 parallele Kalenderzugriffe statt 1).

### T-78 · FR-9s Sicherheitsventil hat für einen `wunschzeit`-Nutzer keinen Rückweg — BEHOBEN (2026-09-10)

- [x] Spec-Entscheidung + Umsetzung: Ventil bei `wunschzeit != null` nicht greifen lassen, oder den
      Zähler auch an einem tatsächlich geplanten Tag zurücksetzen, oder eine Reset-Aktion in der UI.
- **Why:** erst durch T-72 erreichbar geworden. `updateGapDayCounter` setzt nur an einem Tag mit
  echtem `hardFloor` zurück. Ein Nutzer mit `wunschzeit` und ohne Kalendertermine wird nach 7 Tagen
  vom Ventil abgeschaltet (alle Fensterwerte `null`, `applyPlannedAlarms` entfernt alle
  Zukunftsalarme) - danach klingelt nichts mehr, es gibt also keinen Ring-Checkpoint, und nur ein
  `hardFloor`-Tag könnte den Zähler zurücksetzen. Der Wecker schaltet sich dauerhaft ab.
- **Status:** Behoben 2026-09-10 - als **Spec-Änderung**, nicht als Bugfix: FR-9 hatte keine Ausnahme, also wurde zuerst FR-9 um den Abschnitt "Ausnahme: gesetzte `wunschzeit`" ergänzt (mit Begründung), dann der bestehende Ventil-Test auf `wunschzeit: null` umgestellt (das war die Bedingung, die ihn überhaupt gültig macht) und ein neuer Ausnahmefall ergänzt. Der Zähler läuft unverändert weiter, das Ventil greift nur bei `wunschzeit == null`.

### T-79 · `Notifications().init()` wird nicht abgewartet, der Post-Frame-Replan braucht das Plugin — BEHOBEN (2026-09-10)

- [x] `await Notifications().init()` vor dem ersten Checkpoint (oder in `main()` vor `runApp`).
- **Why:** `main.dart:190` startet `init()` ohne `await` (es enthält `Alarm.init()`,
  `AwesomeNotifications().initialize()`, `setListeners`), der Post-Frame-Callback ruft einen Frame
  später `replan` -> `applyPlannedAlarms` -> `Alarm.getAlarms()`/`Alarm.set()`. Fällt das ins
  Init-Fenster, greifen die `catch`-Zweige: der T-74e-Plattformabgleich wird still deaktiviert und
  `Alarm.set`-Fehler werden pro Alarm geschluckt - der FR-18-Sync kann beim Kaltstart wirkungslos
  bleiben, genau auf FR-17s Reboot-Erholungspfad. Ebenso löst eine vor `setListeners` erzeugte stille
  Notification Checkpoint 2 nicht aus.
- **Status:** Behoben 2026-09-10: `Notifications().init()` wird im Post-Frame-Callback **awaited**, vor dem ersten Checkpoint (und damit vor jedem `Alarm.set`/`getAlarms` und vor der ersten erzeugten Notification).

### T-80 · Der Schlafengeh-Aufhänger wird nach einem Replan nicht neu geplant — BEHOBEN (2026-09-10)

- [x] `scheduleSleepReminder` in den Checkpoint aufnehmen (dieselbe Begründung wie bei
      `applyPlannedAlarms`: kein Pfad soll rechnen und vergessen können).
- **Why:** gerufen aus `initState`, Reminder-Toggle, `onSchedulingSettingsChanged` und
  `onAlarmHandled` - **nicht** aus `runForegroundCheckpointSafely`/`runAlarmRingCheckpoint`. Auf dem
  Resume-Pfad (T-68) wird also neu geplant, die Bettzeit-Notification behält aber die alte Zeit;
  Checkpoint 2 feuert dann zu einem Zeitpunkt ohne Bezug zum Plan. Beim nativen Wisch-Dismiss (ohne
  `onAlarmHandled`) ebenso.
- **Status:** Behoben 2026-09-10: strukturell durch T-87 - `scheduleSleepReminder()` steht als letzter Schritt in `runSchedulingCheckpoint()`s fester Sequenz und läuft im `finally`, damit ein Kalenderfehler FR-16s Aufhänger nicht mitreißt.

### T-81 · FR-9s Ventil-Benachrichtigung wiederholt sich bei jedem Replan — BEHOBEN (2026-09-10)

- [x] Analog zu T-74a drosseln (eigenes Feld oder eine gemeinsame "einmal pro Episode"-Hilfe).
- **Why:** `replan_notifications.dart:53-63` hat keine Sperre, `safetyValveTriggered` wird aber bei
  jedem Replan neu abgeleitet. Da nach dem Ventil kein Alarm mehr klingelt (T-78), kommt die Meldung
  bei jedem App-Öffnen an einem neuen Tag und bei jeder Einstellungsänderung erneut.
- **Status:** Behoben 2026-09-10: neues `AppState.safetyValveNotificationSent`; `reportReplanNotifications` hat FR-6 und FR-9 in einen gemeinsamen `oncePerEpisode`-Helfer gezogen. FR-12 bleibt bewusst ungedrosselt (einmalige Beobachtung, keine stehende Bedingung).

### T-82 · `pendingDayValues`/`pendingDayInstantAnchored` wachsen unbegrenzt — BEHOBEN (2026-09-10)

- [x] Beim Merge alles älter als `lastConcludedDay - 1` verwerfen.
- **Why:** der Merge-ohne-Prune ist für *heute* lasttragend (Kommentar in `replan.dart:137-144`), es
  wird aber nie etwas entfernt: nach einem Jahr ~365 Einträge in einem JSON-String, den jeder Replan
  dekodiert, kopiert und wieder kodiert; `planAlarmSync` und `nextWakeUpTime` iterieren alles.
  Funktional harmlos, aber monoton wachsend - und `pendingDayInstantAnchored` verhält sich
  asymmetrisch (dort werden Einträge per `remove` gelöscht).
- **Status:** Behoben 2026-09-10: der Merge verwirft Einträge vor `lastConcludedDay - 1` (dieselbe Grenze für `pendingDayInstantAnchored`, das vorher asymmetrisch war). Gestern bleibt als Sicherheitsmarge, weil ein Erholungs-Checkpoint gestern als `lastConcludedDay` liest. Tests halten zusätzlich fest, dass der heutige, noch nicht geklingelte Wert erhalten bleibt.

### T-83 · Uneinheitliches `isUtc`-Tagging beim Lesen derselben Map — BEHOBEN (2026-09-10)

- [x] Zwei benannte Konverter (`instantFromStored` -> UTC-getaggt für die Domänenschicht,
      `localFromStored` -> `.toLocal()` für Plugin/UI) plus `assert(anchor.isUtc)` in
      `computeWeekPlan`/`distribute`.
- **Why:** dieselbe `Map<String,int?>` wird an fünf Stellen gelesen, dreimal mit `isUtc: true`
  (`replan.dart`), zweimal ohne (`apply_alarms.dart:86`, `next_wake_up.dart:47`). Heute ist beides
  **korrekt** - die Domänenschicht verlangt UTC-Tagging, UI und `ScheduledAlarm.title`
  (`formatDateTime`) verlangen lokales. Genau deshalb ist es gefährlich: ein Vereinheitlichen "für
  Konsistenz" würde Anzeige und Alarmtitel still um den Geräteversatz verschieben.
- **Status:** Behoben 2026-09-10: neues `lib/models/scheduling/stored_values.dart` mit `instantFromStored` (Domäne, UTC-getaggt), `localFromStored` (Plattform/Anzeige) und `toStored`. Alle fünf Lesestellen benutzen jetzt den passenden Namen; rohe `DateTime.fromMillisecondsSinceEpoch`-Aufrufe gibt es außerhalb dieses Moduls nicht mehr.

### T-84 · T-74e ist nur zur Hälfte behoben: Ton/Lautstärke/Gentle-Wake propagieren nicht — BEHOBEN (2026-09-10)

- [x] `selectedTone`/`selectedVolume`/`gentleWakeUpEnabled` an `onSchedulingSettingsChanged` hängen
      und `planAlarmSync` um einen Eigenschaftsvergleich erweitern; `ScheduledAlarm` um `volume`
      erweitern.
- **Why:** `planAlarmSync` vergleicht ausschließlich `_toMinute`, und keiner der drei Setter löst
  einen Replan aus - eine Ton- oder Gentle-Wake-Änderung wirkt erst, wenn ein Tag ohnehin neu geplant
  wird. Zusätzlich hat `ScheduledAlarm` kein `volume`-Feld, alle von FR-18 gesetzten Alarme klingeln
  also mit `MyAlarm`s Default 0.6 und ignorieren `appState.selectedVolume` (das eine UI hat).
- **Status:** Behoben 2026-09-10: `ScheduledAlarm` reicht `volume` durch (inkl. JSON und `==`; alte gespeicherte Alarme fallen auf den Default zurück), `applyPlannedAlarms` setzt Ton/Lautstärke/Gentle-Wake aus dem AppState, `planAlarmSync` vergleicht sie mit und ersetzt abweichende Alarme, und Ton-, Lautstärke- und Gentle-Wake-Änderungen lösen einen Checkpoint aus (Lautstärke per `onChangeEnd`, nicht bei jedem Rasterschritt).

### T-85 · Dokumentation widerspricht dem Code an mehreren Stellen — BEHOBEN (2026-09-10)

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

### T-86 · Toter Code und verwaister Zustand (Inventar für Phase 6) — BEHOBEN (2026-09-10)

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

### T-87 · Strukturelle Vereinfachung: ein Checkpoint-Einstiegspunkt statt fünf — BEHOBEN (2026-09-10)

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

### T-88 · Kleinere, bestätigte Punkte — BEHOBEN (2026-09-10)

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

### T-63 · scheduling-v2 computes wake times but nothing ever turns them into real alarms — BEHOBEN (2026-09-10)

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

