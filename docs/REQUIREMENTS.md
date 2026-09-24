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
  **Since 2026-09-18 (`docs/TODO.md` T-148):** `trufflehog` scans the full git history
  (`trufflehog git`), not only the current checkout (`trufflehog filesystem`, the gap that would
  have missed a secret exactly the way T-29's unlicensed audio blobs sat undetected in history for
  ten days); and a second, independent `osv-scanner` pass in `ci.yml`/`release.yml`'s Android build
  jobs checks the native dependency tree (a CycloneDX SBOM of the `releaseRuntimeClasspath`
  configuration) that the original `--lockfile=pubspec.lock` pass never saw at all - it found and
  fixed one real HIGH (`gson:2.8.8`, forced to the patched `2.8.9`) the same day it was added.
  **Confirmed live, not just by construction (2026-09-20, `docs/TODO.md` T-06):** a throwaway branch
  with a deliberately broken `flutter analyze` was dispatched through `ci.yml` directly - every
  timezone leg failed as expected, and `security-gate`, `e2e-tests` and both Android build jobs all
  came back **skipped**, never run at all. The `needs:` chain holds transitively, not only at the
  one job (`build-android-release`) this was originally checked against.
- **Status: partially met.** All gating tools are currently green against the recorded exceptions.
  The two findings that are *accepted* rather than fixed, and therefore carry a dated rationale in
  `.github/security-exceptions.json`: `mobsfscan`'s one ERROR (`android_task_hijacking2`, a
  StrandHogg-style task-hijacking pattern), and MobSF's one HIGH ("app installable on unpatched
  Android 7.0", i.e. `minSdk=24`) alongside 15 WARNING-level findings (2026-09-20: one more than
  before - `DirectBootReceiver`'s exported-and-unprotected status, an expected consequence of
  `docs/TODO.md` T-158 not yet triaged one way or the other, see `docs/TODO.md` T-160). The
  rationale for the two accepted findings - the same text as in that file: the `mobsfscan` finding
  is a known tool limitation - it flags a task-affinity/launch-mode pattern generically, without the
  runtime context to distinguish it from this app's actual configuration. The MobSF HIGH restates
  the project's own deliberate `minSdk=24` choice (see `CLAUDE.md`'s toolchain table) and is
  accepted, not fixed, because lowering `minSdk` further is not currently planned. Update this
  paragraph if either acceptance is revisited, or once T-160 is triaged.

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
  It does not reboot the emulator or force-stop the app. Its persistence check used to only re-read
  an in-process cache rather than a genuine storage round-trip - fixed (`docs/TODO.md` T-04): it now
  calls `SharedPreferences.resetStatic()`/`reload()` first and asserts the alarm's id and time plus
  its presence in `Alarm.getAlarms()`.
- **Real-device evidence (2026-09-18): a reboot, without opening the app afterward, still let a
  scheduled alarm ring.** This is the first actual observation of the reboot leg described below
  ("already derivable from the code") rather than a code-reading inference - the `alarm` plugin's
  own `BootReceiver` re-armed the alarm and it fired with no user interaction at all in between.
  Not yet captured with the scripted `dumpsys alarm` procedure (`check_alarm_survival.sh`) or
  logged with device/APK details in `docs/device-trial-checklist.md`'s table format - see the
  Findings entry there for now.
- **Status: partially met - one gap remains open and unresolved (not merely undocumented), one is
  now resolved, as of 2026-09-24.** Every scenario where the app is reopened, or the device stays
  unlocked, has been observed working on a real device: a UI swipe-away, a reboot with no app
  interaction (device left unlocked), and a force-stop followed by reopening the app (FR-17's
  recovery). **`am force-stop` with the app never reopened again is the one scenario this
  requirement cannot currently make a claim about either way** - see the contradiction between the
  2026-09-18 and 2026-09-19 real-device evidence documented below; it is not the settled platform
  boundary earlier drafts of this section described. A **reboot followed by the device staying
  locked** (never unlocked, `docs/TODO.md` T-158) was not a platform boundary - it was this app's
  own missing Direct-Boot support, with a real ordinary-use trigger (an overnight OTA reboot) - and
  has since been **confirmed fixed on a real device**: a Direct-Boot-aware fallback (native,
  self-contained, does not touch the real ring pipeline or the user's actual tone/volume settings)
  vibrates and plays an audible, looping siren while the device stays locked, and is silenced the
  moment the device is unlocked. What's left: a clean, repeatable re-measurement of the force-stop
  question (a longer post-force-stop wait, ideally cross-checked against an actual ring, not only
  `dumpsys` registration) logged via `docs/device-trial-checklist.md`'s table template, and the E2E
  suite still doesn't exercise reboot or force-stop at all (structurally can't, for the reasons
  `docs/TODO.md` T-93/T-131 record). A missed alarm is a total failure of the app's core purpose, so
  closing this gap remains the single highest-priority open item in this document.
  **Fixed (2026-09-18):** a `SharedPreferences` load failure could block app startup entirely
  instead of degrading to defaults - see `docs/TODO.md` T-45. (The per-alarm enable/disable switch
  not cancelling the underlying OS alarm, `docs/TODO.md` T-03, was already resolved on 2026-09-16 -
  this line was stale.)
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
- **Real-device confirmation (2026-09-18): force-stopping the app during a scheduled alarm indeed
  loses it - no ring.** This is the boundary above actually observed, not just reasoned from the
  code, and was believed to be Android's own platform guarantee for what `am force-stop` does to a
  package (every AlarmManager entry it owns dropped, unconditionally, before the app gets any chance
  to react).
  **Contradicted the next day and currently unresolved (2026-09-19, `docs/TODO.md` T-93):** a
  second, independently-scripted real-device measurement (`dumpsys alarm`'s own uid counter, not a
  wait-and-see ring test) found the app's alarms **still registered after `am force-stop`** on the
  same physical device - the opposite of what this paragraph and T-93's own code-reading both
  predicted, and checked directly against the `alarm` plugin's source, which does not use the one
  documented exemption (`AlarmManager.setAlarmClock()`) that would explain it. Neither run has been
  repeated to rule out a timing artifact (T-93's script waits only 5s after force-stop) or an
  Android-16-specific behaviour change. **Read this requirement's force-stop half as genuinely
  unresolved, not as either "loses the alarm" or "survives it"** - the two most recent real-device
  data points disagree with each other, and closing that disagreement (a clean, longer-wait re-run
  of `check_alarm_survival.sh`, ideally cross-checked against an actual ring rather than only
  `dumpsys` registration) is the single most important open item for R3's core promise, because it
  is exactly the scenario ("the app or OS does something unexpected, will the alarm still fire")
  that this requirement exists to answer. Until it is closed, this app should not be recommended as
  a sole, unconditionally-reliable alarm for a shift or commitment someone cannot afford to miss.
- **Real-device confirmation, same session: FR-17's recovery works.** After the force-stop above,
  reopening the app re-armed the alarm and it rang. This is the actual, fixable half of C4/C5 that
  the force-stop boundary itself doesn't cover - "the alarm survives force-stop" is impossible by
  design, but "the app recovers as soon as it's opened again" is the real guarantee R3 depends on
  for that path, and it now has real-device evidence rather than only a code-reading inference.
- **Narrowed further (2026-09-19, `docs/TODO.md` T-04):** the maintainer confirmed on a real device
  that reboot, closing the app, and a force-stop all still let the alarm ring **provided the app
  gets reopened at some point before the alarm is due** (which is exactly the FR-17 recovery path
  above). The one scenario genuinely still unverified, across all three interruptions alike, is a
  long idle stretch with the app never reopened at all before the alarm's due time - not only the
  force-stop-specific platform boundary this section already documents.
- **That scenario is now confirmed to fail, with a known cause (2026-09-20, `docs/TODO.md`
  T-158):** a reboot followed by the device staying locked - never unlocked even once - does not
  ring the alarm at all until the device is unlocked. Root cause: neither this app nor the `alarm`
  plugin is `directBootAware`, and the plugin's `BootReceiver` (which re-registers the
  `AlarmManager` entries after a reboot) listens only for `BOOT_COMPLETED`, which Android withholds
  entirely from non-direct-boot-aware apps until the device's first unlock after that boot - not
  merely delays. This is a genuine, ordinary-use failure mode (an overnight OTA reboot with the
  phone left locked on a nightstand), unlike the `am force-stop` boundary below.
- **Fixed and confirmed on a real device (2026-09-20, `docs/TODO.md` T-158):** a Direct-Boot-aware
  fallback now arms itself while the device stays locked - a native, self-contained path that never
  touches the real ring pipeline (custom tone, gentle-wake ramp, QR gate) or any credential-encrypted
  storage, since none of that is reachable before the device's first unlock. It took five same-day
  revisions, each following a real-device test that found the previous one still insufficient (a
  single notification chime instead of a real loop; continuous vibration but no audible sound; the
  fallback not stopping once the real alarm took over; a first stop-attempt via `MainActivity`'s
  lifecycle that changed nothing) before the maintainer confirmed it fully working: continuous
  vibration and an audible, looping siren while locked, silenced immediately on unlock via
  `ACTION_USER_PRESENT`.

## R4 - All alarm-ringing prerequisites are met before an alarm fires

Before an alarm rings, the app must have: working volume control, the ability to play the
selected tone, and every permission the ringing path needs (exact-alarm scheduling, notifications,
camera for QR deactivation).

- **Checked by:** manual security/code review of `lib/models/alarms/handler.dart`,
  `lib/utils/permissions.dart`, and the `alarm`/`awesome_notifications` plugin integration, plus an
  automated E2E test on a real Android emulator covering permission grants and both dismissal
  overlays (`integration_test/app_test.dart`). **Since 2026-09-20 (`docs/TODO.md` T-157):**
  camera and calendar permissions are no longer requested upfront in a batch on first launch -
  camera is requested lazily from `QrScanner.initState` (both the initial-scan and
  deactivate-alarm paths) and calendar lazily on first Schedule-tab visit or a manual reload, via
  the same `requestCameraPermission`/`requestCalendarPermission` seams in `permissions.dart`. The
  requirement itself is unaffected - the permission is still obtained before the path that needs
  it runs, just closer to that point instead of at app start.
- **Status: partially met.** Permissions and overlay display are now exercised on real hardware and
  pass. **Resolved (2026-09-20, `docs/TODO.md` T-15):** the gentle wake-up volume ramp
  (`VolumeSettings.fade`) has been manually validated on a real device by the maintainer - the fade
  path runs and audibly ramps rather than jumping to full volume. This is real-device evidence, not
  an automated one: the CI emulator still runs without audio, so a regression here still would not
  be caught by CI - only by re-checking on a device. The QR gate's own gaps have moved on from
  how T-08/T-16 originally described them (both now "PARTIALLY"/"LARGELY RESOLVED" - a negative
  test exists, and the debug seam no longer ships a real camera preview in release). **Resolved
  (2026-09-19, `docs/TODO.md` T-143):** `ReaderWidget` itself (the real, native decode path,
  previously exercised only through the format/behaviour-agnostic debug seam) has now actually run
  on a real device across two tuning rounds (`cropPercent`/`tryHarder`/`tryInverted`/`codeFormat`,
  then `scanDelay`) and been confirmed working by the maintainer - this also covers R13's "any
  code, not only QR" requirement. The same real-device testing surfaced and fixed a gap in T-38's
  emergency-stop bypass (a hardware camera kill-switch could leave it permanently withheld - see
  T-38's own entry). The app's declared `CAMERA` permission comes from the
  camera plugin behind the QR scanner via manifest merging, not from
  `android/app/src/main/AndroidManifest.xml` directly (`docs/TODO.md` T-49). Since the scanner swap
  (T-33) the merged manifest is checked against what the app actually does: `RECORD_AUDIO` and
  `WRITE_EXTERNAL_STORAGE`, merged in by that plugin's own dependencies and never exercised, are
  removed again with `tools:node="remove"`.

  The negative half of the QR gate is no longer E2E-only: `test/qr_scanner_gate_test.dart` asserts
  that a wrong code is not accepted, with `Diag.qrGate` as the oracle.

- **Fail-safes, and why "guaranteed" isn't absolute (`docs/TODO.md` T-38):** the QR gate has two
  deliberate escape hatches, both weighed the same way - trapping someone behind a gate they have
  no physical way to satisfy is worse than the gate occasionally being bypassable.
  1. **A camera that produces frames but can never decode one.** A hardware camera kill-switch, a
     covered lens, or a broken sensor can leave `ReaderWidget` "running" forever while every decode
     attempt legitimately reports "no code found" - indistinguishable, from this screen's side, from
     a user who simply hasn't held the code up yet. `_maxScanDurationTimer`
     (`lib/screens/scan_code/qr_scanner.dart`, 30s) fires regardless of that proof-of-life signal,
     specifically because it doesn't tell the two cases apart, and offers an explicit
     "Camera not working - Stop alarm" button once it does. Found on a real device (a maintainer's
     hardware kill-switch produced exactly this state) after an earlier, narrower timer
     (`_proofOfLifeTimer`) had already shipped for the six other "camera never even starts" failure
     modes an earlier review had listed.
  2. **The app cannot show the ringing/QR overlay at all.** `Handler.handleAlarm`
     (`lib/models/alarms/handler.dart`) retries showing it `maxOverlayAttempts` (5) times,
     `overlayRetryDelay` (3s) apart - roughly 15 seconds of genuine retrying, since the likeliest
     cause (`context.mounted` being momentarily false, e.g. the app still finishing its own startup
     right as the alarm fires) can resolve itself a moment later - and only then calls
     `Alarm.stopAll()` rather than leaving an alarm ringing with literally no UI able to stop it.
  Both are logged (`Diag`) and tested (`test/qr_scanner_gate_test.dart`,
  `test/handler_overlay_retry_test.dart`) rather than being silent, undocumented escape hatches -
  the previous state of both this file and `docs/TODO.md` before 2026-09-19.

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
  contradiction a reader can see; that one is resolved. **`ACCESS_NETWORK_STATE` is now also
  removed (2026-09-20, `docs/TODO.md` T-49)** - traced to `media3-common` (the `alarm` plugin's
  audio stack) and `awesome_notifications`' transitive transport libraries, neither used by
  anything network-related in this app, and stripped with `tools:node="remove"` the same way
  `RECORD_AUDIO`/`WRITE_EXTERNAL_STORAGE`/`READ_EXTERNAL_STORAGE` already were. Confirmed absent
  from a real release build's manifest; **not yet confirmed that removing it leaves tone/gentle-wake/
  custom-tone playback unaffected on a real device** - `media3` uses `ConnectivityManager`
  internally, so this is a real, if small, risk rather than a formality. A network capture during
  an E2E run remains the other piece that would close this requirement fully. GDPR compliance
  otherwise follows straightforwardly from "no data ever leaves the device," but this hasn't been
  reviewed by anyone with actual legal expertise - treat "met" here as a technical assessment, not
  legal sign-off.

## R8 - All dependencies are open-source and trustworthy

Every dependency should be open-source; a full source audit of each isn't in scope, but a
reasonable trust assessment is.

- **Checked by:** `pubspec.yaml`/`pubspec.lock` review, plus
  `test/no_proprietary_dependencies_test.dart`, which fails the suite if either of the two
  offenders below is declared again, resolves back in transitively (`docs/TODO.md` T-144, since
  2026-09-24 - the earlier version only ever read `pubspec.yaml`, missing a transitive return with
  no direct line), or is imported anywhere in `lib/`. `scripts/check_proprietary_native_deps.py`
  (also T-144) covers the channel that guard still can't see - a proprietary Android artifact
  arriving through a plugin's own `build.gradle`, exactly how ML Kit arrived via `mobile_scanner`
  before this was fixed - by checking the CycloneDX SBOM `ci.yml`/`release.yml` already generate for
  the native `osv-scanner` pass. `osv-scanner` additionally checks for known vulnerabilities in the
  resolved dependency tree.
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
- **Status: met (2026-09-20).** The concrete conflict is resolved: nothing in
  the shipped set carries a licence that conflicts with GPLv3 any more (see R8). The project's rule
  is recorded there too - a conflicting dependency is replaced, not covered by a GPLv3 §7 linking
  exception, although the copyright holders could grant one.
  **Fixed (2026-09-20, `docs/TODO.md` T-34):** GPLv3's Corresponding Source obligation is discharged
  by making the repository public, and that has now actually happened - confirmed public, and
  `v1.0.0` published as a GitHub Release with a signed, `apksigner`-verified production APK the
  same day. **Fixed (2026-09-18):** the app previously had no in-app
  licence/notice surface at all - the About page now links both the project's own GPLv3 text and
  Flutter's collected third-party notices (`docs/TODO.md` T-36). **Fixed (2026-09-19):** the
  Apache-2.0/BSD-3 notices for `flutter_zxing`'s compiled-in native code (zxing-cpp/librscpp, zint)
  were also missing - invisible to Flutter's own licence collector, which only reads package-root
  `LICENSE` files, not CMake-compiled C/C++ - and are now shipped as a hand-assembled asset,
  reachable from the same About page (`docs/TODO.md` T-142). **Fixed (2026-09-19):** every `.dart`
  source under `lib/` now carries a GPLv3 copyright/licence header, guarded against regressing by
  `test/licence_header_test.dart` (`docs/TODO.md` T-48). An automated `license_checker`-style scan
  remains worth adding as a second line of defence for the dependency tree specifically.

## R10 - All bundled assets are properly licensed for use

Images, audio, and other bundled assets (`assets/`) must be used with proper rights/licensing.

- **Checked by:** not currently automated or documented.
- **Status: met (2026-09-18).** `assets/sounds/*.mp3`: all six bundled tones were traced by
  metadata (ID3 tags identified a YouTube-rip and a meme remix with no redistribution licence among
  them - see `docs/TODO.md` T-29) and replaced with Mixkit Sound Effects Free License tracks,
  recorded per-file in `assets/sounds/CREDITS.md`. The old, unlicensed blobs were also removed from
  git history itself (`git filter-repo`, T-29), not just from the current tree - a `git clone`
  would otherwise have handed them out just as readily. The icon assets
  (`assets/icons/icon.png`, `icon_no_shadow.png`) are confirmed AI-generated by the maintainer -
  own content, nothing to license from a third party.

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
- **Corrected again (2026-09-24, independent external-auditor review, `docs/TODO.md` T-161):** the
  policy still claimed "no wake-up times, no dates or times of day" without acknowledging the
  opt-in diagnostics clock-time switch added since (T-135), and separately still claimed the app
  "declares an internet-access permission" - stale since T-33/T-101 removed `INTERNET` and
  `ACCESS_NETWORK_STATE` from the manifest entirely. Both fixed in `assets/text/Privacy.md`. The
  `WRITE_CALENDAR` permission remains declared but unused (known since T-17); T-161 records why
  removing it is not a safe same-session fix.

## R12 - The project is human-readable and quickly understandable

The codebase and its high-level structure should be understandable without deep archaeology, and
manual intervention/override should always remain possible (no fully opaque automation).

- **Checked by:** `CLAUDE.md` documents build/toolchain/architecture decisions for exactly this
  reason. This requirement is inherently subjective - re-assess it whenever the project structure
  changes significantly.
- **Status:** met, by current maintainer judgment.

## R13 - Any pre-existing QR code or barcode can be adopted as the deactivation code

Without being told otherwise, a user's realistic expectation of the "guaranteed wake-up" feature is
that they can scan an arbitrary code they already have - a QR code or an ordinary barcode, printed
on a household object, a poster, anything with a scannable code already on it - and have the app
adopt it as their deactivation code, without that code needing to come from WakeyWakey itself or
match any particular format or symbology.

- **Why a formal requirement, not just an implementation detail:** the mechanism (`QrScanner`'s
  "no code stored yet -> import whatever was just scanned" branch, `lib/screens/scan_code/
  qr_scanner.dart`) already existed and already behaved this way for QR codes before this
  requirement was written down - found while confirming the maintainer's own expectation of the
  feature, then explicitly widened to every symbology at the maintainer's request. Writing it down
  turns "this happens to work" into "this must keep working": `DeactivationCode`'s payload is a
  plain string with no format of its own (`lib/models/scan_code/deactivation_code.dart`), and
  nothing in `qr_scanner.dart`'s import branch validates the scanned text against any expected
  shape - the only two hard requirements are that `ReaderWidget` could decode *something*
  (`codeFormat: Format.any` - every 1D barcode and 2D matrix symbology zxing-cpp supports: EAN/UPC/
  Code128/Codabar/ITF/GS1 DataBar, Aztec, Data Matrix, PDF417, MaxiCode, Micro/rectangular Micro QR,
  and ordinary QR) and that the decoded text is not empty (an empty decode must never become a code
  nobody can ever reproduce).
- **Checked by:** `test/qr_scanner_gate_test.dart`'s "with no code stored, the first scan is
  imported" (a simple token) and its "requirement: any pre-existing QR code can be adopted as the
  deactivation code" group - a real-world URL and a long string with unicode/whitespace/
  punctuation, proving the payload is adopted verbatim with no format assumption of its own, not
  just the shape of a WakeyWakey-generated code (`DeactivationCode.generateRandomHash`'s base64
  output). These exercise the app-logic layer through the debug scan-stream seam, which is
  necessarily format-agnostic (`ScanResult` carries only decoded text, never a symbology) - it
  cannot prove `ReaderWidget` itself actually decodes a barcode, since that seam bypasses
  `ReaderWidget` entirely. `test/qr_scanner_reader_config_test.dart` is a source-reading test
  guarding the lines that matter instead (`codeFormat: Format.any`, `scanDelay`), the same "forbid
  the channel, not the symptom" reasoning as `test/no_proprietary_dependencies_test.dart` -
  `docs/TODO.md` T-143 (now resolved) is where the actual real-device confirmation happened.
- **Status: met.** `docs/use-cases.md`'s "Scan QR Code" entry is annotated to describe this
  explicitly, since the bullet alone did not distinguish "scan to validate against a stored code"
  from "scan to adopt as a new one", nor that non-QR symbologies now work too.

---

**Summary of open gaps (R1 partial, R3, R4 partial, R7 partial):** R2 is **no longer** among them - the
scheduling-v2 rebuild (2026-09) replaced the old engine wholesale and is covered by unit tests; see
R2 above for the one remaining caveat, which is really R3. R3 and part of R4 are no longer explained
by "no build has ever run on a device or emulator" - that build now happens on every release and has
surfaced what's actually still missing: no reboot/force-stop survival test over a long, never-
reopened stretch (R3, `docs/TODO.md` T-04), and R4 is now only partial because of the QR gate's own
`debugScanStreamOverride` seam remaining a plain mutable static rather than an injected dependency
(`docs/TODO.md` T-16) - the gentle-wake ramp (T-15) and the real camera decode path (T-143) have
both since been confirmed on real hardware, so this isn't the "audio and camera both unverified"
gap it used to be. R1 is only partial now because two
findings are *accepted* rather than fixed, each with a dated rationale in
`.github/security-exceptions.json` - not because a check is missing or non-gating; every tool in
the gate can fail the run, on the branch path and the tag path alike. R8 and R9 were a separate licensing conflict (Syncfusion and Google/ML Kit
are not open-source, and GPLv3 obligations for the distributed APK were unaddressed). That is
resolved as of 2026-09-17: both dependencies were replaced rather than covered by a licence
exception, and `docs/licence-position.md` records the decision. R9's one remaining condition -
the repository has to be public before the APK reaches anyone else - is met as of 2026-09-20
(`docs/TODO.md` T-34): the repository is public and `v1.0.0` has been released. R10 remains a separate, still-open documentation gap (asset provenance). See
`docs/TODO.md` for the full, prioritised, evidence-backed list every one of these gaps is now
tracked under.
