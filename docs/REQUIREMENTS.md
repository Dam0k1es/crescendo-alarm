# Requirements

Essential requirements for WakeyWakey. These must be guaranteed - or their current
verification status honestly stated - before any push to `master` (production track). This
document formalizes and supersedes an earlier informal `tasks.txt` planning note.

Each requirement lists how it's checked today and flags where that check is missing, not just
what "should" be true.

## R1 - No high-or-above SAST/SCA/secret findings

No SAST, SCA, or secret-scan finding at severity "high" or above may be outstanding.
Medium/informational findings don't block a release but must be recorded and revisited.

- **Checked by:** `flutter analyze`, `osv-scanner` and `trufflehog` all run in CI and can fail the
  `master` pipeline (see `.github/workflows/ci.yml`). `mobsfscan` and a full MobSF scan also run on
  every `master` push/PR, but **neither can currently fail the run**: `mobsfscan` runs with
  `--no-fail`, and the MobSF step only prints a summary with no threshold. Treat their output as
  informational until that's closed (see `docs/TODO.md` T-11).
- **Status: partially met.** The three gating tools are currently clean. The two non-gating tools
  are not: `mobsfscan` reports one ERROR (`android_task_hijacking2`, a StrandHogg-style
  task-hijacking pattern), and the most recent MobSF scan reports one HIGH ("app installable on
  unpatched Android 7.0", i.e. `minSdk=24`) plus 14 WARNING-level findings. Accepted rationale for
  both, recorded here since neither previously had a citable write-up: the `mobsfscan` finding is a
  known tool limitation - it flags a task-affinity/launch-mode pattern generically, without the
  runtime context to distinguish it from this app's actual configuration. The MobSF HIGH restates
  the project's own deliberate `minSdk=24` choice (see `CLAUDE.md`'s toolchain table) and is
  accepted, not fixed, because lowering `minSdk` further is not currently planned. Update this
  paragraph if either acceptance is revisited.

## R2 - Reliable calendar-derived alarm scheduling

The scheduling algorithm must always produce a new alarm in the background when fewer than 7
days ahead are currently scheduled, without requiring the app to be open or the user to interact
with the calendar screen.

- **Checked by:** code review of `lib/models/scheduling/scheduling.dart`,
  `lib/utils/utils.dart` and every call site of `scheduleAlarms`/`preloadCalendarData`.
- **Status: not met - and more fundamentally than "unverified".** There is no background mechanism
  at all: `scheduleAlarms` is reachable only from UI call sites in
  `lib/screens/sleep_habits/screen_sleephabits.dart` and `lib/screens/alarms/screen_alarms.dart`,
  plus from `Handler` when an alarm actually fires; the calendar preload runs once, at app startup.
  There is no periodic worker and no "fewer than 7 days scheduled" trigger anywhere. Separately,
  `_adjustAlarmTimes` discards most days' real calendar-derived times once a schedule spans more
  than one day, and can silently schedule nothing at all after seven adjustments. See
  `docs/TODO.md` T-01, T-02 and T-32 for the concrete, code-level work this requirement is
  currently blocked on.

## R3 - The app is always ready to trigger an alarm

The app must remain able to fire a scheduled alarm after a device restart, after the app's UI is
closed, and after long periods without being opened (e.g. a month-long vacation with no alarms
set).

- **Checked by:** an automated E2E test now exercises alarm creation, firing and persistence on a
  real Android emulator (`integration_test/app_test.dart`, gating `.github/workflows/release.yml`).
  It does not reboot the emulator or force-stop the app, and its persistence check currently reads
  an in-process cache rather than a genuine storage round-trip (see `docs/TODO.md` T-04).
- **Status: not met.** This remains the single highest-value gap - a missed alarm is a total
  failure of the app's core purpose - and it is not touched by the new E2E suite. Also
  unaddressed: the per-alarm enable/disable switch does not cancel the underlying OS alarm
  (`docs/TODO.md` T-03), and a `SharedPreferences` load failure can currently block app startup
  entirely rather than degrade to defaults (`docs/TODO.md` T-45). Needs a real-device test:
  schedule an alarm, force-stop the app, reboot the device, and confirm it still fires.

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
  navigating away (`docs/TODO.md` T-09). The app's declared `CAMERA` permission also comes from the
  `mobile_scanner` plugin via manifest merging, not from `android/app/src/main/AndroidManifest.xml`
  directly (`docs/TODO.md` T-49).

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
  - No filesystem access outside the app's own sandbox and (for QR-from-gallery, currently
    unreachable code - `docs/TODO.md` T-44) `READ_EXTERNAL_STORAGE`.
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
- **Status: partially met, scope narrower than the requirement.** "No data leaves the device" has
  only been checked against `lib/` Dart source - the built APK additionally declares `INTERNET` and
  `ACCESS_NETWORK_STATE`, pulled in by a plugin's manifest merge rather than by this project's own
  code (`docs/TODO.md` T-49). Nothing found so far suggests these permissions are exercised, but
  that is an absence of evidence, not evidence of absence - a network capture during an E2E run
  would close this properly. GDPR compliance otherwise follows straightforwardly from "no data ever
  leaves the device," but this hasn't been reviewed by anyone with actual legal expertise - treat
  "met" here as a technical assessment, not legal sign-off.

## R8 - All dependencies are open-source and trustworthy

Every dependency should be open-source; a full source audit of each isn't in scope, but a
reasonable trust assessment is.

- **Checked by:** `pubspec.yaml`/`pubspec.lock` review. `osv-scanner` additionally checks for known
  vulnerabilities in the resolved dependency tree.
- **Status: not met.** `syncfusion_flutter_calendar`, `_core` and `_datepicker` are direct
  dependencies published under the Syncfusion Essential Studio licence - a commercial licence or a
  revenue/team-size-limited community programme, not an open-source licence. The QR-scanning stack
  (`mobile_scanner`) additionally pulls in proprietary Google/ML Kit Android dependencies
  (`play-services-mlkit-barcode-scanning`, `com.google.mlkit:barcode-scanning`). See
  `docs/TODO.md` T-05 and T-33 for what resolving this requires.

## R9 - License compatibility

All dependency licenses must be compatible with this project's GNU GPLv3 license, and all legal
licensing obligations must be met.

- **Checked by:** not automated; manually reviewed following R8's finding.
- **Status: not met - a concrete conflict, not just an unrun scan.** Distributing a GPLv3 work that
  links the proprietary Syncfusion and Google/ML Kit components named under R8 is a real
  incompatibility, already visible without a scan. Separately, GPLv3's source-offer obligation for
  the signed APK attached to GitHub Releases is unaddressed (`docs/TODO.md` T-34), and the app
  ships no in-app licence/notice surface for its dependencies (`docs/TODO.md` T-36). A
  `license_checker`/`flutter pub deps`-based automated scan is still worth adding, but would not by
  itself resolve the Syncfusion/ML Kit conflict.

## R10 - All bundled assets are properly licensed for use

Images, audio, and other bundled assets (`assets/`) must be used with proper rights/licensing.

- **Checked by:** not currently automated or documented.
- **Status: not verified.** No record exists of where `assets/sounds/*.mp3` or the icon assets
  came from or under what license. Needs tracking down before public release (`docs/TODO.md` T-29).

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

**Summary of open gaps (R1 partial, R2, R3, R4 partial, R8, R9):** R2, R3 and part of R4 are no
longer explained by "no build has ever run on a device or emulator" - that build now happens on
every release and has surfaced what's actually still missing: no background rescheduling
mechanism (R2), no reboot/force-stop survival test (R3), and no coverage of audio/the gentle-wake
ramp or a camera-isolated QR test (R4). R1's remaining gap is about two non-gating security tools,
not about whether checks run at all. R8 and R9 are a separate, newly-identified licensing conflict
(Syncfusion and Google/ML Kit are not open-source, and GPLv3 obligations for the distributed APK
are unaddressed) - unrelated to device testing and requiring a licensing decision, not more
testing. R10 remains a separate, still-open documentation gap (asset provenance). See
`docs/TODO.md` for the full, prioritised, evidence-backed list every one of these gaps is now
tracked under.
