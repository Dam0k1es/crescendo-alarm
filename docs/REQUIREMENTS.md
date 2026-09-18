# Requirements

Essential requirements for WakeyWakey. These must be guaranteed - or their current
verification status honestly stated - before any push to `master` (production track). This
document formalizes and supersedes an earlier informal `tasks.txt` planning note.

Each requirement lists how it's checked today and flags where that check is missing, not just
what "should" be true.

## R1 - No high-or-above SAST/SCA/secret findings

No SAST, SCA, or secret-scan finding at severity "high" or above may be outstanding.
Medium/informational findings don't block a release but must be recorded and revisited.

- **Checked by:** `flutter analyze`, `osv-scanner` and `trufflehog` run in the reusable
  `.github/workflows/security-gate.yml`, which both `ci.yml` (on `master`) and `release.yml` (on a
  tag) call - so the tag path can no longer skip them (`docs/TODO.md` T-92). `mobsfscan` runs in
  the same gate and **is** gating since 2026-09: it runs with `--no-fail` only because its own exit
  code cannot tell an accepted finding from a new one, and `scripts/mobsfscan_check.py` then fails
  the job for anything not listed in `.github/security-exceptions.json`. The full MobSF scan of the
  built APK (`ci.yml`'s `mobsf-full-scan`) is gating too, with the same exceptions file as its
  threshold, and on an un-accepted HIGH it additionally **deletes the uploaded production APK
  artifact** so a red run leaves nothing downloadable (`docs/TODO.md` T-11).
- **Status: partially met.** All gating tools are currently green against the recorded exceptions.
  The two findings that are *accepted* rather than fixed, and therefore carry a dated rationale in
  `.github/security-exceptions.json`: `mobsfscan`'s one ERROR (`android_task_hijacking2`, a
  StrandHogg-style task-hijacking pattern), and MobSF's one HIGH ("app installable on unpatched
  Android 7.0", i.e. `minSdk=24`) alongside 14 WARNING-level findings. The rationale for
  both - the same text as in that file: the `mobsfscan` finding is a
  known tool limitation - it flags a task-affinity/launch-mode pattern generically, without the
  runtime context to distinguish it from this app's actual configuration. The MobSF HIGH restates
  the project's own deliberate `minSdk=24` choice (see `CLAUDE.md`'s toolchain table) and is
  accepted, not fixed, because lowering `minSdk` further is not currently planned. Update this
  paragraph if either acceptance is revisited.

## R2 - Reliable calendar-derived alarm scheduling

The scheduling algorithm must always produce a new alarm in the background when fewer than 7
days ahead are currently scheduled, without requiring the app to be open or the user to interact
with the calendar screen.

- **Checked by:** code review of `lib/models/scheduling/` (`checkpoint.dart`, `replan.dart`,
  `scheduling_v2.dart`, `apply_alarms.dart`) and every call site of `runSchedulingCheckpoint` /
  `runCheckpointSafely`; plus `test/checkpoint_test.dart`, `test/replan_test.dart`,
  `test/apply_alarms_test.dart` and `test/scheduling_v2_test.dart`. Since the independent review of
  2026-09-11 also `test/scheduling_v2_audit_test.dart`, `test/replan_audit_test.dart` and
  `test/checkpoint_audit_test.dart` - those carry the regressions and guards from it, each with a
  recorded mutation that turns it red (`docs/TODO.md` T-104 … T-129).
- **Status: met in substance since the scheduling-v2 rebuild (2026-09), with one caveat.** The
  requirement was written against the old engine, which really had no mechanism at all. What exists
  now (`docs/scheduling-v2-spec.md`, FR-1–FR-18):
  - Every checkpoint plans a **full 7-day window** from scratch and applies it to real alarms
    (FR-8 + FR-18), so "fewer than 7 days ahead are scheduled" cannot persist past one checkpoint.
    Days without a calendar appointment are no longer discarded: they are smoothed towards the
    user's preferred wake-up time (FR-4/FR-6), which is what replaced the old
    `_adjustAlarmTimes`' "discard most days and possibly schedule nothing" behaviour.
  - Checkpoints do **not** need the app to be open or the calendar screen visited: the primary one
    runs when an alarm actually rings (FR-8), in the process the alarm itself started. A second one
    hangs off the bedtime notification (FR-16 Checkpoint 2, timezone check only), and a third runs
    on app foreground as recovery after a reboot or force-quit (FR-17).
  - There is deliberately **no** periodic background worker - `docs/choice-of-technologies.md` and
    FR-16 both argue against one (battery, OEM-specific background limits); every checkpoint hangs
    off an event that is already scheduled anyway.
- **What the 2026-09-11 review changed here.** Six real deviations were found and fixed, three of
  which bore directly on this requirement: a value that had already rung was overwritten by any
  setting change the same morning, so the user could be woken twice and the next week was smoothed
  from an anchor that never existed (T-106/T-114); FR-9's valve reported itself as "over" after a
  single day, so a notification that failed once was never retried and the alarm clock stayed
  permanently silent (T-107); and two alarms on the same minute were a stable fixed point that
  nothing ever cleaned up (T-116). Separately, **nothing had ever checked that `replan()` applies
  its own plan** - deleting that one call left nine test files green, which is precisely how this
  engine was once completely inert (T-117). Seven further points are understood, reproduced and
  deliberately **not** implemented: in each the code follows the spec and the spec is what has the
  gap - see `docs/TODO.md`, "Waiting on a decision, not on work".
- **Remaining caveat (honest):** the chain is self-sustaining only while it keeps ringing. If the
  chain is ever fully broken *and* the app is never opened - the realistic case being a reboot that
  loses the platform alarms (that is R3, still unverified) - nothing re-plans until the next app
  start. FR-9's safety valve can no longer cause this (`docs/TODO.md` T-78).

## R3 - The app is always ready to trigger an alarm

The app must remain able to fire a scheduled alarm after a device restart, after the app's UI is
closed, and after long periods without being opened. "Long period" is not an arbitrary example
here: FR-9's rolling safety valve (`docs/scheduling-v2-spec.md`) is the one place scheduling-v2
actually gives this a number - a rolling counter of consecutive appointment-free days that stops
automatic advancement and notifies the user once it reaches **7**, precisely so a genuinely
unattended stretch (no calendar appointments, no app opened) does not drift into a permanently dead
alarm. Below that count, the app keeps scheduling on its own; at 7 it deliberately hands control
back to the user instead of guessing further - that hand-back is by design, not an R3 failure, and
only applies when no `preferredWakeUpTime` is set (with one set, FR-4 bounds the drift and the
valve never needs to fire at all).

- **Real-device evidence (2026-09-18):** the app's UI was swiped away from the recent-apps list
  (not force-stopped) while a manual alarm was armed, and the alarm rang correctly regardless -
  the process-death path that matters for most users day to day, distinct from the reboot and
  `am force-stop` scenarios below. `docs/device-trial-checklist.md` records this.

- **Checked by:** an automated E2E test now exercises alarm creation, firing and persistence on a
  real Android emulator (`integration_test/app_test.dart`, gating `.github/workflows/release.yml`).
  It does not reboot the emulator or force-stop the app, and its persistence check currently reads
  an in-process cache rather than a genuine storage round-trip (see `docs/TODO.md` T-04).
- **Real-device evidence (2026-09-18): a reboot, without opening the app afterward, still let a
  scheduled alarm ring.** This is the first actual observation of the reboot leg described below
  ("already derivable from the code") rather than a code-reading inference - the `alarm` plugin's
  own `BootReceiver` re-armed the alarm and it fired with no user interaction at all in between.
  Not yet captured with the scripted `dumpsys alarm` procedure (`check_alarm_survival.sh`) or
  logged with device/APK details in `docs/device-trial-checklist.md`'s table format - see the
  Findings entry there for now.
- **Status: partially met, real evidence still thin.** A missed alarm is a total failure of the
  app's core purpose, so this remains the single highest-value gap even with the reboot
  observation above - `am force-stop` survival (a different, harsher kill than a reboot: Android
  drops the package's AlarmManager entries entirely on force-stop, see the boundary noted below)
  is still unverified, and the E2E suite doesn't touch either path. Also unaddressed: the
  per-alarm enable/disable switch does not cancel the underlying OS alarm (`docs/TODO.md` T-03),
  and a `SharedPreferences` load failure can currently block app startup entirely rather than
  degrade to defaults (`docs/TODO.md` T-45).
- **A procedure is now in place (2026-09-10, `docs/TODO.md` T-93):**
  `.github/scripts/check_alarm_survival.sh` answers the question via `dumpsys alarm` instead of via
  an actual ring - that makes "alarm is registered" distinguishable from "no alarm registered",
  with no waiting time. It runs in the E2E job, **not yet gating**, because this behaviour on this
  emulator image has never been measured, and an unverified leg must not block a release.
  `docs/device-trial-checklist.md` section C runs the same check on a real device.
- **First real run (34566962847, 2026-09-11): unusable as a measurement.** The counting pattern
  matched a foreign app's alarms (Google's `DailyLoggingAlarmReceiver`, via the substring
  `AlarmReceiver`) and reported a FAIL that proved nothing - the app's own alarm had never been
  found. This has been fixed (`docs/TODO.md` T-103): the counting now reads `dumpsys`'s uid counter
  instead of guessing from text, and the script checks itself against recorded output before every
  measurement. **The question therefore remains unanswered** - it has only become measurable. Read
  this requirement's status as "still not measured", not "fails reboot".
- **Already derivable from the code:** the app has **no** `BootReceiver` of its own; the `alarm`
  plugin registers one and re-arms the stored alarms after boot via
  `setExactAndAllowWhileIdle(RTC_WAKEUP, …)`. Reboot survival is implemented there - only the
  evidence is missing.
- **Adjacent defect found and fixed (2026-09-18, `docs/TODO.md` T-147):** not a triggering failure,
  but the same "still ready after the app was left alone" theme on the tail end - an alarm stopped
  via its notification (swipe-dismiss, no app UI open) left the ring screen stuck showing on
  reopen, behind `PopScope(canPop: false)` with nothing left to stop. Fixed by having the ring
  screens themselves notice the alarm disappearing from `Alarm.ringing`.
- **An important boundary this requirement does not yet draw:** on `am force-stop`, Android removes
  all of the package's AlarmManager alarms at the platform level, and a force-stopped process no
  longer receives `BOOT_COMPLETED` afterwards until the user starts the app again. "Surviving a
  force-stop" is therefore not an achievable goal but a platform boundary - R3 should track it as
  that boundary, not as a deficiency. What the app can do, and per FR-17 does: re-arm everything the
  next time the app is opened.

## R4 - All alarm-ringing prerequisites are met before an alarm fires

Before an alarm rings, the app must have: working volume control, the ability to play the
selected tone, and every permission the ringing path needs (exact-alarm scheduling, notifications,
camera for QR deactivation).

- **Checked by:** manual security/code review of `lib/models/alarms/handler.dart`,
  `lib/utils/permissions.dart`, and the `alarm`/`awesome_notifications` plugin integration, plus an
  automated E2E test on a real Android emulator covering permission grants and both dismissal
  overlays (`integration_test/app_test.dart`).
- **Status: partially met.** Permissions and overlay display are now exercised on real hardware and
  pass. Not covered: the gentle wake-up volume ramp is never exercised (it defaults to off, and the
  CI emulator runs without audio - `docs/TODO.md` T-15), the QR gate is tested only with the
  correct code and only through a debug seam that does not isolate the real camera (`docs/TODO.md`
  T-08, T-16), and neither dismissal test confirms the alarm actually stopped rather than just
  navigating away (`docs/TODO.md` T-09). The app's declared `CAMERA` permission comes from the
  camera plugin behind the QR scanner via manifest merging, not from
  `android/app/src/main/AndroidManifest.xml` directly (`docs/TODO.md` T-49). Since the scanner swap
  (T-33) the merged manifest is checked against what the app actually does: `RECORD_AUDIO` and
  `WRITE_EXTERNAL_STORAGE`, merged in by that plugin's own dependencies and never exercised, are
  removed again with `tools:node="remove"`.

  The negative half of the QR gate is no longer E2E-only: `test/qr_scanner_gate_test.dart` asserts
  that a wrong code is not accepted, with `Diag.qrGate` as the oracle.

## R5 - Quality/stability checks don't degrade the runtime user experience

Static analysis, SCA, and other CI/quality checks must never affect what ships to users - they
run in CI, not on-device, and don't add runtime overhead.

- **Checked by:** by construction - all checks in R1 run only in CI against source/build
  artifacts, never inside the shipped app.
- **Status:** met.

## R6 - No changes to the device or other apps' data

The app must not modify the device or other applications' data beyond its own sandboxed storage
and the calendar entries the user explicitly grants access to.

- **Checked by:** manual security review, findings recorded here directly rather than in an
  untracked file:
  - No network SDKs are used from `lib/` (though see R7 on the app's declared `INTERNET`
    permission).
  - No filesystem access outside the app's own sandbox. The QR-from-gallery path that
    `READ_EXTERNAL_STORAGE` existed for is gone (`docs/TODO.md` T-44), and the replacement
    scanner's own gallery button is switched off; `WRITE_EXTERNAL_STORAGE`, which its transitive
    `image_picker` merged in, is removed from the manifest again.
  - `android:allowBackup` was found unset (defaults to `true`) during an earlier pass - the
    deactivation-code payload and other prefs, stored via `SharedPreferences`, would have been
    included in Android's auto-backup / `adb backup` by default, letting anyone with adb/backup
    access extract them without root. Fixed: `android:allowBackup="false"` is set in
    `AndroidManifest.xml`.
  - Deactivation-code generation uses `Random.secure()`. QR-code validation happens before any
    alarm-stopping side effect. AndroidManifest permissions all map to real, used features.
    ProGuard rules don't disable meaningful obfuscation. The on-screen deactivation QR code is
    intentionally unprotected against screenshots - the user is meant to photograph or print it for
    physical placement, by design, not a gap.
- **Status:** met, per static analysis. Not independently verified via dynamic/runtime testing.

## R7 - No data extraction; GDPR-compliant, privacy-friendly

No user data leaves the device. The app must be GDPR-compliant.

- **Checked by:** the app makes zero network calls anywhere in `lib/` (verified by manual review -
  there is no HTTP client, no analytics SDK, no telemetry). `assets/text/Privacy.md` documents data
  handling and has been corrected to match what the app actually collects (calendar reads, camera
  for QR scanning, locally stored alarms/settings/deactivation code) rather than the location/NFC
  data it does not.
- **Status: partially met, scope narrower than the requirement - but materially better since
  2026-09-17.** "No data leaves the device" had only been checked against `lib/` Dart source, while
  the built APK additionally declared `INTERNET` and `ACCESS_NETWORK_STATE`, merged in by a plugin
  rather than by this project's own code (`docs/TODO.md` T-49). **`INTERNET` is now gone**: it came
  with the proprietary ML Kit stack, and replacing that scanner for licence reasons (T-33) removed
  it as a side effect - verified by comparing `aapt2 dump permissions` on the APKs before and
  after. An app that claims to be fully offline and holds the INTERNET permission is a
  contradiction a reader can see; that one is resolved. `ACCESS_NETWORK_STATE` remains, and a
  network capture during an E2E run is still what would close this requirement properly. GDPR compliance otherwise follows straightforwardly from "no data ever
  leaves the device," but this hasn't been reviewed by anyone with actual legal expertise - treat
  "met" here as a technical assessment, not legal sign-off.

## R8 - All dependencies are open-source and trustworthy

Every dependency should be open-source; a full source audit of each isn't in scope, but a
reasonable trust assessment is.

- **Checked by:** `pubspec.yaml`/`pubspec.lock` review, plus
  `test/no_proprietary_dependencies_test.dart`, which fails the suite if either of the two
  offenders below is declared again or imported anywhere in `lib/`. `osv-scanner` additionally
  checks for known vulnerabilities in the resolved dependency tree.
- **Status: met** (2026-09-17). The two dependencies that were not open-source are gone:
  `syncfusion_flutter_calendar` (Syncfusion Essential Studio licence - a commercial licence or a
  revenue/team-size-limited community programme) was replaced by `calendar_view` (MIT), and
  `mobile_scanner`, whose Android build links Google's proprietary ML Kit barcode binaries, by
  `flutter_zxing` (MIT, wrapping zxing-cpp under Apache-2.0). The remaining direct dependencies are
  BSD-3, MIT or Apache-2.0. A full source audit of each is still explicitly out of scope, as this
  requirement says. See `docs/licence-position.md` for the reasoning, and `docs/TODO.md` T-05/T-33.

## R9 - License compatibility

All dependency licenses must be compatible with this project's GNU GPLv3 license, and all legal
licensing obligations must be met.

- **Checked by:** not automated; manually reviewed and written down in
  `docs/licence-position.md`, with the dependency half guarded by
  `test/no_proprietary_dependencies_test.dart`.
- **Status: largely met, one condition outstanding.** The concrete conflict is resolved: nothing in
  the shipped set carries a licence that conflicts with GPLv3 any more (see R8). The project's rule
  is recorded there too - a conflicting dependency is replaced, not covered by a GPLv3 §7 linking
  exception, although as sole copyright holder the maintainer could grant one.
  **Outstanding:** GPLv3's Corresponding Source obligation is discharged by making the repository
  public, and that has to actually happen **before the first release to anyone else**
  (`docs/TODO.md` T-34). Until then nothing is conveyed - builds go to the maintainer's own test
  devices, which is not distribution. Also still open, and real work rather than decisions: no
  in-app licence/notice surface for dependencies (T-36) and no per-file licence headers (T-48). An
  automated `license_checker`-style scan remains worth adding as a second line of defence.

## R10 - All bundled assets are properly licensed for use

Images, audio, and other bundled assets (`assets/`) must be used with proper rights/licensing.

- **Checked by:** not currently automated or documented.
- **Status: partially met (2026-09-17).** `assets/sounds/*.mp3`: all six bundled tones were traced
  by metadata (ID3 tags identified a YouTube-rip and a meme remix with no redistribution licence
  among them - see `docs/TODO.md` T-29) and replaced with Mixkit Sound Effects Free License tracks,
  recorded per-file in `assets/sounds/CREDITS.md`. **Still open:** the icon assets
  (`assets/icons/icon.png`, `icon_no_shadow.png`) have no recorded source or licence, and
  inspection found no embedded metadata to trace either way - needs tracking down (or replacing,
  as the sounds were) before public release. This is the only remaining item under T-29.

## R11 - The privacy policy is accurate and complete

`assets/text/Privacy.md` must accurately describe the app's actual data handling and provide a
working contact method.

- **Checked by:** manual review during the PII sweep confirmed the contact address is a maintained
  alias, not a placeholder - but that review checked only the contact method, not the data-handling
  content itself. A later pass found the policy described location/NFC data collection the app
  cannot perform while omitting camera use and the alarm/settings/deactivation-code data it
  actually stores; the policy has since been rewritten to match reality.
- **Status:** met, as of this correction. Re-check whenever data handling changes - this
  requirement was previously marked "met" on a check that never covered its actual content, which
  is itself worth remembering when reading any other "Checked by" line in this document: verify
  what a cited review actually covered before trusting its conclusion.

## R12 - The project is human-readable and quickly understandable

The codebase and its high-level structure should be understandable without deep archaeology, and
manual intervention/override should always remain possible (no fully opaque automation).

- **Checked by:** `CLAUDE.md` documents build/toolchain/architecture decisions for exactly this
  reason. This requirement is inherently subjective - re-assess it whenever the project structure
  changes significantly.
- **Status:** met, by current maintainer judgment.

---

**Summary of open gaps (R1 partial, R3, R4 partial, R7 partial, R9 one condition):** R2 is **no longer** among them - the
scheduling-v2 rebuild (2026-09) replaced the old engine wholesale and is covered by unit tests; see
R2 above for the one remaining caveat, which is really R3. R3 and part of R4 are no longer explained
by "no build has ever run on a device or emulator" - that build now happens on every release and has
surfaced what's actually still missing: no reboot/force-stop survival test (R3), and no coverage of
audio/the gentle-wake ramp or a camera-isolated QR test (R4). R1 is only partial now because two
findings are *accepted* rather than fixed, each with a dated rationale in
`.github/security-exceptions.json` - not because a check is missing or non-gating; every tool in
the gate can fail the run, on the branch path and the tag path alike. R8 and R9 were a separate licensing conflict (Syncfusion and Google/ML Kit
are not open-source, and GPLv3 obligations for the distributed APK were unaddressed). That is
resolved as of 2026-09-17: both dependencies were replaced rather than covered by a licence
exception, and `docs/licence-position.md` records the decision. One condition remains rather than a
task - the repository has to be public before the APK reaches anyone else. R10 remains a separate, still-open documentation gap (asset provenance). See
`docs/TODO.md` for the full, prioritised, evidence-backed list every one of these gaps is now
tracked under.
