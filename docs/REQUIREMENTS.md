# Requirements

Essential requirements for WakeyWakey. These must be guaranteed - or their current
verification status honestly stated - before any push to `master` (production track). This
document formalizes and supersedes an earlier informal `tasks.txt` planning note.

Each requirement lists how it's checked today and flags where that check is missing, not just
what "should" be true.

## R1 - No high-or-above SAST/SCA/secret findings

No SAST, SCA, or secret-scan finding at severity "high" or above may be outstanding.
Medium/informational findings don't block a release but must be recorded and revisited.

- **Checked by:** `flutter analyze`, `osv-scanner`, `trufflehog`, `mobsfscan`, full MobSF - all run
  in CI on every `master` push/PR (see `.github/workflows/ci.yml`).
- **Status:** met as of the last full pipeline run. `mobsfscan`'s one HIGH finding (StrandHogg
  task-hijacking) is a documented tool-limitation false positive - see
  `docs/quality-baseline-2026-09.md`.

## R2 - Reliable calendar-derived alarm scheduling

The scheduling algorithm must always produce a new alarm in the background when fewer than 7
days ahead are currently scheduled, without requiring the app to be open or the user to interact
with the calendar screen.

- **Checked by:** code review of `lib/models/scheduling/scheduling.dart` and
  `lib/utils/utils.dart` (this round's code-review pass fixed a real bug here - a scoping error
  that could throw `LateInitializationError` before the Schedule screen was ever opened - see
  `docs/release-readiness-2026-09.md`, finding #1).
- **Status: not verified end-to-end.** No test exercises the actual background rescheduling path
  against a real calendar over multiple days. See the E2E test plan in
  `docs/quality-baseline-2026-09.md` (tier 2, item 5).

## R3 - The app is always ready to trigger an alarm

The app must remain able to fire a scheduled alarm after a device restart, after the app's UI is
closed, and after long periods without being opened (e.g. a month-long vacation with no alarms
set).

- **Checked by:** nothing automated today.
- **Status: not verified.** This is the single highest-value gap - a missed alarm is a total
  failure of the app's core purpose. Needs a real-device test: schedule an alarm, force-stop the
  app, reboot the device, and confirm it still fires.

## R4 - All alarm-ringing prerequisites are met before an alarm fires

Before an alarm rings, the app must have: working volume control, the ability to play the
selected tone, and every permission the ringing path needs (exact-alarm scheduling, notifications,
camera for QR deactivation).

- **Checked by:** manual security/code review of `lib/models/alarms/handler.dart`,
  `lib/utils/permissions.dart`, and the `alarm`/`awesome_notifications` plugin integration.
- **Status: not verified on a real device.** Build-time permission declarations are correct
  (`AndroidManifest.xml`), but no test has confirmed the actual ringing experience on hardware.

## R5 - Quality/stability checks don't degrade the runtime user experience

Static analysis, SCA, and other CI/quality checks must never affect what ships to users - they
run in CI, not on-device, and don't add runtime overhead.

- **Checked by:** by construction - all checks in R1 run only in CI against source/build
  artifacts, never inside the shipped app.
- **Status:** met.

## R6 - No changes to the device or other apps' data

The app must not modify the device or other applications' data beyond its own sandboxed storage
and the calendar entries the user explicitly grants access to.

- **Checked by:** manual security review (`docs/quality-baseline-2026-09.md`) - confirmed no
  network calls, no filesystem access outside the app's own sandbox and (for QR-from-gallery)
  `READ_EXTERNAL_STORAGE`, and `android:allowBackup="false"` to prevent local-secret extraction via
  `adb backup`.
- **Status:** met, per static analysis. Not independently verified via dynamic/runtime testing
  (see "Live-testing limitations" in `docs/release-readiness-2026-09.md`).

## R7 - No data extraction; GDPR-compliant, privacy-friendly

No user data leaves the device. The app must be GDPR-compliant.

- **Checked by:** the app makes zero network calls anywhere in `lib/` (verified by manual review -
  there is no HTTP client, no analytics SDK, no telemetry). `assets/text/Privacy.md` documents data
  handling.
- **Status:** met. GDPR compliance follows straightforwardly from "no data ever leaves the
  device," but this hasn't been reviewed by anyone with actual legal expertise - treat "met" here
  as a technical assessment, not legal sign-off.

## R8 - All dependencies are open-source and trustworthy

Every dependency should be open-source; a full source audit of each isn't in scope, but a
reasonable trust assessment is.

- **Checked by:** `pubspec.yaml`/`pubspec.lock` review - all direct dependencies are open-source
  packages from pub.dev with visible source repositories. `osv-scanner` additionally checks for
  known vulnerabilities in the resolved dependency tree.
- **Status:** met, at the level of assessment this requirement calls for.

## R9 - License compatibility

All dependency licenses must be compatible with this project's GNU GPLv3 license, and all legal
licensing obligations must be met.

- **Checked by:** not currently automated.
- **Status: not verified.** No license-compatibility scan has been run against the dependency
  tree. Worth adding (e.g. a `license_checker`/`flutter pub deps`-based check) before a real public
  release.

## R10 - All bundled assets are properly licensed for use

Images, audio, and other bundled assets (`assets/`) must be used with proper rights/licensing.

- **Checked by:** not currently automated or documented.
- **Status: not verified.** No record exists of where `assets/sounds/*.mp3` or the icon assets
  came from or under what license. Needs tracking down before public release.

## R11 - The privacy policy is accurate and complete

`assets/text/Privacy.md` must accurately describe the app's actual data handling and provide a
working contact method.

- **Checked by:** manual review during the PII sweep (`docs/quality-baseline-2026-09.md`) -
  confirmed the contact address is a maintained alias, not a placeholder.
- **Status:** met, as of the last review. Re-check whenever data handling changes.

## R12 - The project is human-readable and quickly understandable

The codebase and its high-level structure should be understandable without deep archaeology, and
manual intervention/override should always remain possible (no fully opaque automation).

- **Checked by:** `CLAUDE.md` documents build/toolchain/architecture decisions for exactly this
  reason. This requirement is inherently subjective - re-assess it whenever the project structure
  changes significantly.
- **Status:** met, by current maintainer judgment.

---

**Summary of open gaps (R2, R3, R4, R9, R10):** everything Android-specific comes back to the same
root cause - no build of this app has ever been installed and run on a real or emulated Android
device (see `docs/release-readiness-2026-09.md`). R9/R10 are separate, still-open documentation
gaps unrelated to device testing.
