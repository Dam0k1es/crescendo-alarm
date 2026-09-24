# WakeyWakey

A Flutter alarm-clock app for people with irregular sleep schedules: calendar-derived alarm
scheduling, gentle wake-up (gradual volume ramp), and a "guaranteed wake-up" mode that requires
scanning a physical QR code to deactivate the alarm. Fully offline - no network calls anywhere in
`lib/`.

## Scheduling engine (`lib/models/scheduling/`)

Calendar-derived wake times come from **scheduling-v2**, specified in
`docs/scheduling-v2-spec.md` (FR-1 … FR-21) and implemented test-first against that spec. The old
engine (`scheduling.dart`'s `Scheduler`/`getEarliestEvent`/`adjustAlarmTimes`/`getStartTimeForDate`)
was **removed** in Phase 6 (2026-09, `docs/TODO.md` T-64/T-86) - don't reintroduce a second
scheduling path, and don't look for `Scheduler` in older docs' terms.

Layering, outermost first:

| File | Role |
|---|---|
| `checkpoint.dart` | **The** entry point: `runSchedulingCheckpoint({trigger})` / `runCheckpointSafely(...)`. Serialized against itself, and runs the full sequence (offset → replan → FR-6/9/12 notifications → bedtime reminder). Every platform trigger goes through here with a `CheckpointTrigger`; nothing else composes that sequence by hand. |
| `replan.dart` | `replan()` (reads the calendar uncached, walks the day-advance for FR-9/FR-12, calls the domain layer, applies FR-18) and `runTimezoneCheckpoint2()` (FR-16's second checkpoint, which runs in a background isolate and therefore talks to `SharedPreferences` directly). |
| `scheduling_v2.dart` | Pure domain logic - plain values only, no `AppState`, no plugins, no `BuildContext`. Directly unit-testable without mocks. |
| `apply_alarms.dart` | FR-18: turns the computed week into real `ScheduledAlarm`s (`planAlarmSync` pure, `applyPlannedAlarms` the applier). |
| `replan_notifications.dart`, `next_wake_up.dart` | FR-6/9/12 warnings (once per episode); the next expected wake-up across plan **and** manual alarms. |
| `day_marker.dart`, `stored_values.dart` | The two things that kept getting re-derived wrongly: calendar day arithmetic, and the two legitimate readings of a stored value. **Read both files' doc comments before touching any date/time handling here** - the recurring bug class in this engine is frame confusion (`docs/TODO.md` T-61, T-76, T-83). |

Two rules that are load-bearing and easy to break by "cleaning up":

- **Never add a second entry point.** The five that used to exist differed in four orthogonal
  dimensions and produced the same class of bug three times (T-67, T-71, T-80). Add a
  `CheckpointTrigger` value instead.
- **Every domain value is an absolute instant, UTC-tagged**, while `preferredWakeUpTime` is a bare
  device-local `TimeOfDay` and everything leaving the layer (alarm plugin, notifications, UI, alarm
  titles) is read as **local wall clock**. Use `instantFromStored`/`localFromStored` and
  `alarmPlatformTime` at those boundaries; don't "unify" them.

## Diagnostics log (`lib/utils/diag/diag_log.dart`)

A local, PII-free event log, readable under Settings > Diagnostics and exportable via the
clipboard. It exists because an installed **release** build returned nothing at all: every
diagnostic went through `debugPrint`, which `main.dart` replaces with an empty function in release.

The load-bearing property, and the one thing not to "clean up": **the recording API takes no
String parameter anywhere**. There is therefore no channel through which a calendar title, an
account name, an exception message or the QR deactivation code could enter it - what cannot be
represented cannot leak. `test/diag_log_api_test.dart` enforces this against the source (no String
parameters, no `debugPrint`/`print`, no clock reads, no int parameter with a clock-shaped name),
and `test/no_pii_in_logs_test.dart` forbids the *channel* in `lib/` generally - including bare
`$e`, because `FormatException.toString()` echoes a slice of its source string.

Consequences to respect when adding an event:

- **No clock values, by default.** Days are relative (via `dayDistance`, so the logger does not
  rebuild T-76 inside itself); moments appear only as *bucketed differences*; the absolute UTC
  offset is never recorded, only the shape of a change. A history of wake times plus offsets is a
  sleep pattern and a travel trace - identifying without any name.
  - **The two exceptions are `Diag.dayPlanned` and `Diag.dayEventTime`.** `dayPlanned`
    (`docs/TODO.md` T-135) records each window day's planned wake time and its earliest appointment
    as a minute-of-day. It exists because nothing else in the log answers *why* a given day got the
    wake time it did, and that question cost a real diagnosis: T-132 could only be tracked down from
    screenshots and hand arithmetic. `dayEventTime` (`docs/TODO.md` T-163, maintainer request) goes
    one step further: one record per real calendar event within the planning window, carrying only
    its start and end minute-of-day and which window day it falls on - **never** its title,
    description, attendees, location, or which of the device's calendars it came from. It exists
    because `dayPlanned` alone only shows what `hardFloor` picked as *the* earliest appointment, not
    what the day's other real candidates were - so a wrong pick (an all-day/ignored event miscounted,
    or the wrong one winning among several) could only be diagnosed by re-deriving the whole
    candidate set from a fresh calendar read, not from the log itself. One record per event (not per
    day), so a busy day produces several - accepted deliberately: the log is opt-in specifically so
    a user actively investigating a problem can afford a bit more detail than the log's own default,
    silent-by-construction posture.
  - Both are behind the **same, single** switch (`AppState.diagnosticsIncludeClockTimes`, Settings >
    Diagnostics), **off by default** and deliberately not folded into the general diagnostics
    toggle - because the log is meant to be pasted into a bug report, and a user doing that should
    not ship their sleep pattern without having said so. The export header says which of the two
    modes produced it. A calendar event's *timing* crossing this boundary is a deliberate, scoped
    exception to the log's own "structurally cannot represent PII" rule elsewhere - it is exactly the
    tradeoff opt-in exists to allow, and the boundary that must never move is what stays excluded:
    title, description, attendees, location, calendar identity. If you are ever tempted to add any
    of those "just for this one case", don't - replace the missing signal with another numeric shape
    instead (a count, a bucket, a flag), the same way every other event in this file already does.
  - When adding an event: the source-reading guard in `test/diag_log_api_test.dart` still rejects
    any `int` parameter whose name looks like a clock value, and the allowed names are listed there
    explicitly - eight as of T-163, not the original two (`plannedMinuteOfDay`,
    `earliestEventMinuteOfDay`): `preferredWakeUpMinuteOfDay`, `maxDailyDeltaMinutes`,
    `wakeUpMinutes` and `getReadyMinutes` were added for `Diag.planInputs`, which logs those four
    durations **unconditionally** (outside the `diagnosticsIncludeClockTimes` switch, unlike the
    others) because they are configuration values, not clock readings - a duration reveals
    nothing about when someone sleeps. `startMinuteOfDay`/`endMinuteOfDay` (T-163) were added for
    `Diag.dayEventTime`, gated behind the switch like `dayPlanned`'s own two. Do not widen the list
    further without the same kind of reason, and note that `...MinuteOfDay` had to be added to the
    pattern, because a `...OfDay` suffix slipped past the original rule unnoticed.
- **Exceptions go in as `runtimeType`** through an identity table to an int; `toString()` is never
  called on a `Type` (R8 obfuscation is then irrelevant).
- **The background isolate has its own ring buffer.** FR-16's Checkpoint 2 runs in a separate
  isolate, so there are two `SharedPreferences` keys and a merge on read - the same trap as T-69,
  one level down. `Diag.init` belongs at the isolate's *entry point*
  (`onNotificationCreatedMethod`), never inside the checkpoint: it mutates global state.
  **`onNotificationCreatedMethod` does not always run in a genuinely fresh isolate, though**
  (`docs/TODO.md` T-162): `awesome_notifications` only spins one up when the app process wasn't
  already running - a notification created while the app is alive (which `scheduleSleepReminder()`
  does on every single checkpoint) fires that same callback in-process, in the main isolate. `Diag
  .init()` is therefore idempotent per isolate (a no-op once `_boot != 0`), or a second, in-process
  call silently mislabels every later event `(bg)` and double-bumps the persisted boot counter -
  found by reading a real exported log, not by code review, and easy to reintroduce by "simplifying"
  that guard away.
- Persisted via `shared_preferences`, not a file via `path_provider`, precisely because that
  isolate already talks to it directly - a file logger would depend on plugin-channel availability
  there, which is the failure class T-79 was.

License: GNU GPLv3 (see `LICENSE`). Copyright holders named in tracked files: Dam0k1es, centron5961
- two of the three original developers of the project this repository grew from. All three have
now given explicit consent to GPLv3 (2026-09-20); the third's consent is to the licence only, not
to being named, so no third name is added anywhere - this is a deliberate choice by that developer,
not a pending item. Do not add any other personal names, emails, or locations to tracked files -
see "PII policy" below.

## Supported platforms

- **Android** is the actual target platform this app is built for.
- **Linux desktop** exists only as a fast local dev/debug loop (no emulator/device needed to smoke-test
  UI and core logic changes) - it is not a real deployment target. `device_calendar` has no Linux
  implementation, so `retrieveCalendars()` throws there; the generic `try/catch` around that call in
  `lib/screens/schedule/calendar.dart` swallows it like any other error (there is no
  `MissingPluginException`-specific handling), leaving `calendars` empty and the app simply
  proceeding with none, by design.
- **iOS** has project scaffolding but has never been built or run in this environment (no Mac/Xcode
  available here) - treat it as unverified, not "supported."

## Critical gotcha: build from a native filesystem, not a shared folder

If this checkout lives on a VirtualBox `vboxsf` (or similar network/shared) mount, **every**
`flutter` command that needs to create plugin symlinks (`pub get`, `analyze`, `test`, `run`,
`build`) fails with a `PathAccessException` - those filesystems don't support symlinks. Work from
a copy on a native filesystem (e.g. `rsync` the repo to `~/projects/wakeywakey` or similar) and
sync finished changes back. Do not "fix" this by chasing a symlink error inside Gradle - it's a
filesystem limitation, not a project bug.

## Development process

New features and changes are developed test-driven: write the test(s) that specify the desired
behavior first (they should fail against the current code), then implement to make them pass. For a
bug fix, that means a regression test that reproduces the bug before touching the fix.

## Build & run

```sh
flutter pub get
flutter analyze
flutter test
flutter build linux --debug     # dev/debug loop only, not a deployment target - see "Supported platforms"
flutter build apk --debug       # Android, needs the Android SDK components below
bash scripts/security-scan.sh   # analyze + osv-scanner (SCA) + trufflehog (secrets)
```

`flutter build apk` on a from-scratch environment will trigger the Android Gradle Plugin to
auto-download several SDK platforms/build-tools on first run (it resolves whatever `compileSdk`
values the app and its transitive plugins declare) - this is normal and can take a while.

Launcher icons for Android/iOS are already generated and checked into the repository - regenerating
them isn't needed on a fresh clone. Only run this if you change `assets/icons/icon.png`:

```sh
dart run flutter_launcher_icons
```

## Branches and where work happens

**Work goes on `dev`. `master` is fast-forwarded only when a state is worth the full gate** - a
signed release build, the E2E emulator run, MobSF. Both branches sit on one linear history; there
has never been a merge commit, and `master` is only ever a fast-forward of `dev`.

This is not bookkeeping, it is money and meaning. The pipeline is scaled by branch (see below): a
push to `dev` costs roughly 8 minutes of CI, a push to `master` roughly 45, because `master`
additionally runs the security gate, a **22-minute Android emulator E2E run**, the signed build and
MobSF. On a private repository those are billed minutes. In September 2026 this was gotten backwards
- thirteen commits went straight to `master`, nineteen full runs, and the account's Actions minutes
appear to have run out: every job began failing after seconds with no step executed. Committing to
`dev` is also what keeps `master` meaning "this passed the gate" rather than "this is the newest
thing somebody wrote".

**Worktree layout**, because a branch can live in only one worktree at a time:

| Directory | Branch | Role |
|---|---|---|
| `/mnt/wakeywakey` | `master` | the shared-folder checkout; no builds possible here (vboxsf, see the gotcha below), and `current.apk` lives here |
| `~/projects/wwmaster` | `dev` | the native-filesystem worktree where editing, `flutter test` and builds happen |

So `/mnt/wakeywakey` lags `dev` by exactly the work that has not been promoted yet - that is the
design, not a mistake. Promote with `git -C /mnt/wakeywakey merge --ff-only dev` and push.

## CI/CD pipeline

Four workflows under `.github/workflows/`:

- **`ci.yml`** runs on every push and PR, scaled by branch. `dev` gets fast feedback only
  (analyze + tests, plus a debug development APK as an artifact). `master` (and PRs into it)
  additionally runs the security gate and the E2E suite, and builds a signed production release
  APK - **gated**: `build-android-release` has
  `needs: [analyze-and-test, security-gate, e2e-tests]`.
- **`e2e-tests.yml`** (reusable, `workflow_call`) runs `integration_test/` against a real Android
  emulator with KVM acceleration, collecting video, an audio-focus timeline and ActivityManager
  logs as an evidence artifact. Called by both `ci.yml` and `release.yml`.
- **`security-gate.yml`** (reusable, `workflow_call`) is the SCA/secret/SAST gate: `osv-scanner`
  against `pubspec.lock`, `trufflehog git --fail` against the **full git history** (not just the
  checkout - `docs/TODO.md` T-148), and `mobsfscan` filtered through
  `.github/security-exceptions.json`. It lives in its own file because the **tag-triggered release
  path used to have no security gate at all** (`docs/TODO.md` T-92) - a signed APK could be
  attached to a GitHub Release with a vulnerable dependency that the same commit on `master` would
  have been rejected for. A second, independent `osv-scanner` pass lives in `ci.yml`'s
  `build-android-release` and `release.yml`'s `build-signed-release` instead of here - it needs a
  resolved `releaseRuntimeClasspath` (a CycloneDX SBOM via the `org.cyclonedx.bom` Gradle plugin,
  scoped to that one configuration so debug/androidTest-only dependencies don't produce noise), which
  this reusable workflow has no Android build to provide. That pass exists because the
  `pubspec.lock`-only scan can't see the native Android dependency tree at all (`docs/TODO.md`
  T-148) - AndroidX, media3, the camera plugin's own transitive deps. The same SBOM feeds a second
  check right after it, `scripts/check_proprietary_native_deps.py` (`docs/TODO.md` T-144): a
  proprietary Android artifact (Google ML Kit, Syncfusion) arriving through a plugin's own
  `build.gradle` rather than anything in the Dart dependency graph - the exact channel
  `test/no_proprietary_dependencies_test.dart` cannot see, and exactly how `mobile_scanner` brought
  in ML Kit before T-33 removed it.
- **`release.yml`** is triggered by a `v*.*.*` tag or `workflow_dispatch` and gates its signed
  build on **both** `e2e-tests` and `security-gate`.
- **`ci.yml`'s `mobsf-full-scan` job** (`needs: build-android-release`) runs a full MobSF Docker
  scan against the built signed APK - a second, independent scanner from `security-gate.yml`'s
  `mobsfscan` (a static source-pattern scanner; MobSF here scans the compiled binary). It is
  gating, filtered through the same `.github/security-exceptions.json`, and on an un-accepted HIGH
  it additionally **deletes the uploaded `app-production-apk` artifact** so a red run leaves
  nothing downloadable (`docs/TODO.md` T-11, `docs/REQUIREMENTS.md` R1) - release-revoking
  behaviour worth knowing about before assuming an artifact exists just because the run went green
  up to that point.
- **`.github/dependabot.yml`** (`docs/TODO.md` T-148) opens weekly update PRs for `pub`, `gradle`,
  and `github-actions` - all three against `dev`, never `master`, per "Work goes on `dev`" above.

Two things about the test job that are easy to undo by accident:

- It is a **matrix over six timezones** (`docs/TODO.md` T-92), not a single run. The dominant bug
  class in this project is frame confusion, and three real bugs (T-61, T-74d, T-76) were
  *structurally invisible* at UTC+0 - which is where both the dev machine and GitHub's runners sit.
  The half- and three-quarter-hour offsets (St. John's, Chatham, Lord Howe) are deliberate: digit
  arithmetic fails there first. `fail-fast: false`, because with a frame bug the *pattern* across
  zones is the diagnosis.
- Coverage runs in the UTC leg only, as an artifact, with **no percentage gate**. An arbitrary
  threshold would reward the wrong thing here: trivial getter tests raise it, while frame and
  structural errors are not captured by line coverage at all.

`.github/scripts/run_e2e_tests.sh` sets the emulator's timezone to `Europe/Berlin` before the app
first runs - injecting `deviceUtcOffset` in a test is **not** a substitute, because that value only
travels through the domain layer while `alarmPlatformTime` reads the real device zone. It also runs
`check_alarm_survival.sh` (reboot/force-stop evidence via `dumpsys alarm`, deliberately
non-gating until it has been green once - `docs/TODO.md` T-93).

`scripts/security-scan.sh` mirrors part of the pipeline locally (analyze + osv-scanner against
`pubspec.lock` + `trufflehog git` against the full history) but is narrower than CI - no
mobsfscan/MobSF, and no native-Android `osv-scanner` pass (needs a resolved Gradle build).

**Validate workflow changes locally before pushing: `actionlint` is installed on the dev VM** and
checks all four workflows (plus shellcheck over every `run:` block) in under a second. Invalid
workflow YAML does not fail loudly on GitHub - the run starts, executes *no step*, and concludes
as a failure in a few seconds, which reads like an infrastructure blip rather than a syntax error.
Three runs were burned that way on one commit (a duplicated `restore-keys:` inside one `with:`
mapping) before the cause was found.

**Alarm survival (R3) is measured against a real phone, not in CI.**
`scripts/verify-alarm-survival.sh` installs/uses the app on a USB-connected device, arms an alarm
**through the app's own UI** (located via `uiautomator dump` in the accessibility tree, not by
fixed coordinates), then reboots and force-stops, reading `dumpsys alarm` at each step. Two reasons
it is not a CI job: inside the E2E run the question is structurally unanswerable, because
`flutter test` uninstalls the app afterwards and Android drops a package's AlarmManager entries
with it (`docs/TODO.md` T-131); and the emulator is unreliable on this VM's nested virtualisation
(T-94). Run it with `scripts/verify-alarm-survival.sh --apk current.apk`; `--self-test` checks both
self-tests without any device. Its evidence lands in `evidence/` (gitignored - it contains the
device model and serial).

The counting itself lives in `.github/scripts/alarm_detection.sh`, shared by that script and the CI
leg. Keep it that way: a second copy is a second chance to repeat T-99/T-103, where a generic
substring counted another app's alarms and produced a confident, unfounded verdict.

`.github/scripts/check_alarm_survival.sh --self-test` is the other cheap local check: it runs the
alarm-detection logic against recorded `dumpsys alarm` output in `.github/scripts/fixtures/`, needs
no emulator, and runs in CI's UTC leg. It exists because that script produces a *verdict* ("the
alarm survived the reboot" / "it did not") and got it wrong twice - first matching nothing, then
matching a foreign app's `DailyLoggingAlarmReceiver` through a bare `AlarmReceiver` substring and
reporting a confident, unfounded FAIL (`docs/TODO.md` T-99, T-103). The counting now reads the
per-uid summary line `Pending alarms per uid: [... u0a161:2 ...]` rather than pattern-matching
entry text, and the self-test's negative fixture is the real recording from the run that got it
wrong. Never put a generic substring back into that pattern.

Run the E2E suite locally with a connected device or running emulator:
`flutter test integration_test/app_test.dart -d <device-id>`.

## Toolchain versions (as verified working, September 2026)

| Component | Version | Notes |
|---|---|---|
| Flutter | 3.47.2 (stable) | `fvm` used to pin this on the dev VM |
| Dart | 3.13.2 | bundled with the above Flutter |
| JDK | 17 (OpenJDK) | required by AGP 9.x / Gradle 9.x |
| Gradle | 9.3.1 | `android/gradle/wrapper/gradle-wrapper.properties` |
| Android Gradle Plugin (AGP) | 9.1.0 | `android/settings.gradle.kts` |
| Kotlin Gradle Plugin | 2.4.0 | `android/settings.gradle.kts` |
| compileSdk | 36 (Flutter default) | no override any more - see "compileSdk override ... (removed)" below |
| minSdk | 24 (pinned explicitly) | `android/app/build.gradle.kts` - was intended to stay below Flutter's own default (also 24, coincidentally, on current Flutter) for older-device support, but MobSF found the *compiled* APK's merged manifest already enforced minSdk=24 regardless, because several plugins (`image_picker_android`, `shared_preferences_android`, `flutter_plugin_android_lifecycle`) declare `minSdk=24` in their own Gradle modules, and manifest merging always takes the highest value across the app + all dependencies. Pinned explicitly to 24 to match the real enforced floor instead of leaving a misleadingly lower number. Also: this value has silently regressed to `flutter.minSdkVersion` (dropping any pin at all) more than once in this project's history - if you ever intend to actually push it lower than 24 again, you'd first need to downgrade those three plugins, not just change this line. |
| targetSdk | 36 (Flutter default, `flutter.targetSdkVersion`) | |
| NDK | intentionally left unset in `app/build.gradle.kts` (no `ndkVersion = flutter.ndkVersion` line) | AGP uses whichever NDK is installed (currently 28.2.13676358) instead of requiring an exact pin |

**Android SDK packages this build needs installed** (via `sdkmanager`): `platform-tools`,
`platforms;android-36`, `build-tools;36.0.0`, plus whatever additional `platforms;android-NN` /
`build-tools;NN.0.0` the currently-resolved plugin versions demand (Flutter's own doctor check has
asked for `build-tools;28.0.3` historically; AGP may also pull a newer one automatically). NDK
`28.2.13676358` under `Sdk/ndk/`.

### compileSdk override for plugin subprojects (removed)

`android/build.gradle.kts` used to force every Android library subproject to `compileSdk = 36` via an
`afterEvaluate` hook, registered **before** `evaluationDependsOn(":app")` (registering it after
throws `Cannot run Project.afterEvaluate(Action) when the project is already evaluated`). This
existed because `awesome_notifications_core` (last published Feb 2025, `compileSdkVersion 33`
hardcoded) failed AAR-metadata checks against its own newer AndroidX transitive dependencies.

**Removed in the 2026-09-10 hygiene pass** (`docs/TODO.md` T-97): `awesome_notifications` 0.12.1
does not depend on `awesome_notifications_core` at all - that entry in `pubspec.yaml` was leftover
cruft from the 0.9.x/0.10.x era, when the main package still required it. Dropping the dependency
removed the offending AAR from the build, so the workaround lost its reason. Verified by a
`flutter clean` release build, not just an incremental one.

### Pinned/overridden Dart dependencies (`pubspec.yaml` `dependency_overrides`)

- **`permission_handler_android: 13.0.1`** - versions 14.0.0 and 14.1.0 hardcode
  `compileSdk = 37` in their own Gradle module, but Android SDK 37 currently only exists as
  preview-numbered packages (`android-37.0`, `.1`, `.2`), not a plain `android-37` target AGP can
  resolve - any build fails with `Failed to find target with hash string 'android-37'`. Revisit
  once upstream publishes a fixed release.
- **`timezone: ^0.11.0`** - `device_calendar` (even its latest release) still pins
  `timezone: ^0.9.0`, while this app itself declares `^0.11.0` and relies on 0.11's refreshed IANA
  data for the frame handling in `lib/models/scheduling/`. (Until 2026-09-17 the other side of this
  conflict was `syncfusion_flutter_calendar`; that package is gone, this override is not.) Forcing 0.11.x is safe in practice: the
  public API (`TZDateTime`, `Location`, `getLocation`) is unchanged between 0.9.x and 0.11.x, only
  the bundled IANA timezone data was refreshed. Revisit once `device_calendar` allows `^0.11.0`.

Both overrides carry explanatory comments in `pubspec.yaml` itself - keep them in sync if you
change either.

## Licence position (GPLv3)

`docs/licence-position.md` is the tracked decision for requirements R8/R9, and two things in it are
standing rules rather than history:

- **A dependency whose licence conflicts with GPLv3 gets replaced, not excepted.** The copyright
  holders could grant a GPLv3 §7 linking exception in a few lines; that was considered and
  rejected. Syncfusion (calendar) and `mobile_scanner` (proprietary Google ML
  Kit binaries) were replaced by `calendar_view` and `flutter_zxing` accordingly
  (`docs/TODO.md` T-05, T-33). `test/no_proprietary_dependencies_test.dart` enforces this against
  `pubspec.yaml` and every import in `lib/` - adding a name to its list is a licence decision, and
  each entry says why.
- **Corresponding Source is provided by making the repository public at the first public release**
  (T-34), not by a written offer. Until that release nothing is conveyed: builds go to the
  maintainer's own test devices.

## PII policy

Don't add real personal names, emails, addresses, or other identifying info to any tracked file.
The privacy-policy contact (`assets/text/Privacy.md`) intentionally uses an alias contact address,
not the maintainer's real one. `android/key.properties` (gitignored) intentionally uses a
project-relative placeholder path, not a real machine username. `.idea/` is fully gitignored
(blanket rule) - JetBrains IDEs write more local/user-specific files than can be enumerated
individually, including AI-assistant chat history that can leak real usernames and local paths.

## Testing status (as of September 2026)

`flutter test` currently runs **501 tests across 80 files**, and CI runs them six times over -
once per timezone in the matrix described above.

A note on running them locally on the dev VM: the full suite in one invocation is memory-hungry
(each test file spawns its own `flutter_tester`, and an interrupted run leaves a ~500 MB
`frontend_server` behind). On an 8 GB box that shows up as *rotating* "did not complete" / "Bad
state: Cannot add event while adding stream" failures that look like flaky tests but are the
harness losing a device. If that happens: `pkill -f "frontend_serve[r]"` (note the character class -
without it `pkill` matches its own command line and kills the shell), then run the suite in a
couple of file groups. Every file passes on its own; a rotating failure is an environment signal,
not a test signal. The same resource exhaustion can deadlock Gradle (JVMs in `futex_do_wait`, no
file changes under `build/`) - see `docs/TODO.md` T-94, which also records that running two
emulators on this VM left kernel threads stuck in D-state until a reboot. The list below covers the
pre-scheduling-v2 files plus the shape of the new ones; `ls test/` is the authoritative list.

- The diagnostics suite (`diag_log_test.dart`, `diag_log_api_test.dart`,
  `no_pii_in_logs_test.dart`) guards the PII-free logger described above. Two of the three are
  *source-reading* tests on purpose - they forbid a channel, not a value, because a value-based
  test would only ever catch the leaks already known.

- `app_state_vibration_test.dart` covers the T-50 vibration setting on its own (default,
  persistence, notifies listeners); its reach into the scheduling engine and manual-alarm creation
  is covered by new cases added to `apply_alarms_test.dart`, `ringing_alarm_settings_test.dart` and
  `manual_alarm_inherits_settings_test.dart` instead of a separate file, following T-84/T-96's own
  precedent that a per-alarm property's tests belong alongside the reconciliation logic they
  exercise.

- `calendar_week_fetched_test.dart` pins down T-55: `AppState.isCalendarWeekFetched` must normalize
  the day it's asked about to its own start of week before comparing against
  `fetchedCalendarWeeks` (which is keyed by week start), or every non-start-of-week query wrongly
  reports an already-preloaded week as unfetched.

- `resync_calendar_data_test.dart` and `schedule_tab_spinner_test.dart` cover T-60: the calendar
  cache is now force-refreshed on every app open (`lib/utils/utils.dart`'s `resyncCalendarData`,
  called from `lib/main.dart` on cold start and every resume) instead of only once per process
  lifetime, and the Schedule tab's icon swaps for a spinner while that read is in flight
  (`AppState.isReadingCalendarMutex`).

- `licence_header_test.dart` covers T-48: every `.dart` file under `lib/` now carries a GPLv3
  copyright/licence header (recommended GPLv3 practice, and expected by F-Droid's inclusion
  review specifically) - a source-reading test in the same shape as
  `no_proprietary_dependencies_test.dart`, guarding against a new file being added without it.

- `screen_alarms_weekday_pills_test.dart` covers T-152: a manual alarm's `repeatOnDays` now shows
  as a row of small pills directly on the alarm list, not only inside the edit dialog. Fixing this
  also caught a German-language slip the T-151 hygiene pass had missed - `_getDayLabel` returned
  German day abbreviations shown directly in the UI, invisible to a grep-based audit because none
  of them are full German words.

- Repository hygiene pass (2026-09-19): `meeting_data_test.dart` gained cases pinning down a real
  bug the audit found - `Meeting.hashCode` called `jsonEncode(this).hashCode`, relying on a
  `toJson()` that had been commented out, so every call threw `JsonUnsupportedObjectError` instead
  of returning an int. Nothing currently puts a `Meeting` in a `Set` or uses one as a `Map` key, so
  it went unnoticed, but it violated the basic hashCode contract regardless. Replaced with
  `Object.hash` over the same fields `==` compares.

- T-150: `deactivation_code_description_test.dart` and `page_deactivation_code_description_test.dart`
  cover the user-entered description that now replaces the deactivation code screen's re-rendered
  (and therefore unrecognizable) QR image once one exists - a fresh code prompts for one
  automatically, tracked by payload so a genuinely new code is prompted for again but the same one
  is not re-prompted on every rebuild.

- `qr_scanner_reader_config_test.dart` is a source-reading test guarding `ReaderWidget`'s tuned
  config in `qr_scanner.dart` - `codeFormat: Format.any` (the scanner accepts any barcode/2D
  symbology zxing-cpp supports, not only QR) and `scanDelay: 150ms` (shortened well below the
  library's 1000ms default, from a real-device report that recognition was slow/inconsistent) -
  neither of which can be exercised through the widget-test seam any more than `cropPercent`/
  `tryHarder` can (see `docs/TODO.md` T-143), so the source is what's checked.

- T-38's emergency-stop bypass had its own gap: `_proofOfLifeTimer` was cancelled the moment ANY
  scan attempt ran, even a legitimate "no code in this frame" - so a hardware camera kill-switch
  (or a covered lens) producing a permanently black feed could satisfy it forever and withhold the
  escape hatch from someone whose camera is physically blocked. A second, independent
  `_maxScanDurationTimer` in `qr_scanner.dart` now fires regardless of that flag; the new
  `qr_scanner_gate_test.dart` case keeps proof-of-life continuously satisfied throughout and
  confirms the button still appears once it elapses. Both timers were later tightened at the
  maintainer's request: `_proofOfLifeTimeout` 20s→10s, `_maxTimeWithoutValidScan` 60s→30s.

- The handler-side 3-second fallback had a related gap the maintainer asked to fix directly: it
  gave up after a single failed attempt to show the ringing overlay, with no chance for
  `context.mounted` (the likeliest failure cause) to flip back to true a moment later.
  `Handler._showOverlayWithRetries` now tries up to `maxOverlayAttempts` (5) times,
  `overlayRetryDelay` (3s) apart - `handler_overlay_retry_test.dart` unmounts a context right after
  constructing the `Handler` (so every attempt fails like a real "no longer mounted" case) and
  asserts exactly 5 attempts happen, using an injectable `sleep` function so the test doesn't wait
  real wall-clock seconds.

- `page_deactivation_code_reactivity_test.dart` pins down a T-143 fix: `PageDeactivationCode` used
  to read `AppState` with `listen: false`, so it never rebuilt when the *separate* `QrScanner`
  route mutated `deactivationCode` on a successful import - the import had actually persisted, but
  the screen underneath kept showing "no code configured" until something unrelated rebuilt it.

- `docs/REQUIREMENTS.md` R13 ("any pre-existing QR code can be adopted as the deactivation code")
  is pinned down by two new cases in `qr_scanner_gate_test.dart` (a real-world URL, and a long
  string with unicode/whitespace/punctuation - not just the short token the existing "first scan
  is imported" case used) and by `page_deactivation_code_import_hint_test.dart` (the on-screen hint
  that makes the already-working capability discoverable).

- `app_state_calendar_selection_test.dart` and `screen_schedule_calendar_selection_test.dart` cover
  T-53: a checkable calendar list reachable from a corner button on the Schedule screen filters
  which `device_calendar` calendars feed both the display and scheduling, following the same
  `StatefulBuilder`-wrapped-`CheckboxListTile`-in-a-modal-sheet shape T-149's "ignore this event"
  sheet already established.

- `page_aboutpage_native_notices_test.dart` covers T-142: the About page's "Native Code Notices"
  button, added because Flutter's own licence collector (`showLicensePage`) cannot see the
  third-party C/C++ `flutter_zxing` compiles into the app - kept in its own file for the same
  isolate-pairing reason as the two other About-page licence tests.

- T-52's three previously-hardcoded options are covered across the files that already own their
  respective areas rather than one new file: `scheduling_v2_test.dart` gained cases for
  `durationToGetReadyForDay` (T-52.3, a per-window-day callback) and `scheduleOnGapDays` (T-52.1, a
  masking pass over `computeWeekPlan`'s output); `app_state_scheduling_v2_test.dart` covers both
  new `AppState` fields' persistence; `screen_schedule_test.dart` covers the hour axis following
  `MediaQuery.alwaysUse24HourFormat` (T-52.2) instead of a hardcoded format; and
  `sleep_habits_gap_day_and_per_weekday_test.dart` covers the two new Sleep Habits controls
  end to end.

- The scheduling-v2 suite (`scheduling_v2_test.dart`, `scheduling_v2_offset_test.dart`,
  `scheduling_v2_tz_test.dart`, `scheduling_v2_dst_test.dart`, `replan_test.dart`,
  `checkpoint_test.dart`, `apply_alarms_test.dart`, `next_wake_up_test.dart`,
  `replan_notifications_test.dart`, `app_state_scheduling_v2_test.dart`, `day_marker_test.dart`,
  `stored_values_test.dart`, `handler_replan_wiring_test.dart`,
  `handler_on_alarm_handled_test.dart`, `sleep_reminder_always_scheduled_test.dart`) is written

- `scheduling_v2_audit_test.dart`, `replan_audit_test.dart` and `checkpoint_audit_test.dart` are
  the regressions from the independent spec review of 2026-09-11 (`docs/TODO.md` T-104 … T-110), kept out of
  `scheduling_v2_test.dart` on purpose: that file's header promises every case is taken **verbatim**
  from a spec "Test:" bullet, and these are *derived* from the FR text instead. That distinction is
  worth preserving, because it is exactly what the review exposed - the spec works each requirement
  through for its simplest case, and three of the four deviations lived in the part the worked
  example never reaches (a ΔT=0 point at position 2 rather than 1; the notification duty on the
  branch that assigns a hardFloor directly; the valve after it has already fired). Every group in
  those two files carries at least one counter-test against overcorrection.
  test-first against `docs/scheduling-v2-spec.md`, with at least one `test()` per FR. Several files
  are named after the `docs/TODO.md` item whose regression they pin down - keep that convention,
  it is how a finding stays fixed. Note in particular that timezone/DST tests build their fixtures
  as `tz.TZDateTime`, **not** `DateTime.utc`: the dev VM runs at UTC+0, so UTC-tagged fixtures
  silently cannot reproduce the frame and DST bug classes at all (that is exactly how the first
  attempts at T-61 and T-74d passed while the bug was still there).

- `test/widget_test.dart`: a real, passing smoke test (builds `MyApp` under its required
  `ChangeNotifierProvider<AppState>`, mocks `SharedPreferences`, checks the splash screen renders).
  It replaced a stale `flutter create` counter-app placeholder that had never been adapted to this
  project and failed on every run (`ProviderNotFoundException`) - if `flutter test` ever goes red
  again on this file, that's a real regression, not a flaky leftover.
- `test/handler_stale_alarm_test.dart`: real `package:test` unit tests for the stale-alarm predicate
  in `lib/models/alarms/handler.dart`.
- `test/scheduling_test.dart` **no longer exists**: it tested only the old engine's functions and
  was deleted with them in Phase 6. Its historical note is worth keeping in mind, though - its
  cases had been ported from two standalone scripts (`test/adjustTime`, `test/getEarliestAlarm`)
  that `flutter test` never ran, didn't import `package:wakeywakey`, and whose algorithm didn't
  match production at all. Don't add "tests" outside the `flutter test` suite.
- `test/qr_scanner_validation_test.dart`: real unit tests for `isDeactivationCodeValid`
  (`lib/screens/scan_code/qr_scanner.dart`), the pure comparison at the heart of the "guaranteed
  wake-up" gate, similarly extracted so it's testable without a device.
- `test/custom_tone_test.dart` and `test/app_state_custom_tone_test.dart` (`docs/TODO.md` T-146):
  the user-imported-tone copy/validation logic and its `AppState` wiring, both against a real
  `dart:io` temporary directory rather than a mocked platform channel - `documentsDirectory` is
  injected the same way `fetchEvents`/`now` are elsewhere.
- `test/ringing_watch_test.dart`, `test/screen_alarm_active_ringing_test.dart`,
  `test/qr_scanner_ringing_test.dart` and `test/ringing_alarm_settings_test.dart`
  (`docs/TODO.md` T-147): a ring screen staying stuck open after its alarm was already stopped
  externally, and a real `Navigator` "!_debugLocked" crash after pressing Stop, found on a real
  device. The actual fix for the notification half is at the source
  (`ringing_alarm_settings.dart`'s `buildRingingAlarmSettings` sets `androidStopAlarmOnDismiss:
  false`, tested without a platform channel since constructing `AlarmSettings` is plain data); the
  crash's cause was `Alarm.stop()` updating `Alarm.ringing` as part of the same call the Stop
  button (or a successful Snooze) awaits, which the screens' `RingingWatch` also observes - two
  independent reactions to one change, one of them hitting the Navigator mid-transaction from the
  other. Fixed by claiming responsibility as early as possible (`SnoozeButton.onBeforeSnooze` fires
  synchronously before `Alarm.stop()` even runs) and guarding `Handler.onAlarmHandled` against a
  second call, observed via a `debugOnAlarmHandledOverride` seam on both screens.
  `RingingWatch` itself also had a second, compounding bug found along the way: it fired on every
  event where the watched alarm was absent, not just the present-to-absent edge, so an unrelated
  alarm's own ring/stop on the same shared stream could re-trigger it. The reusable watcher is
  tested in isolation against a fake `Stream<AlarmSet>`; both screens get their own
  `debugRingingStreamOverride` test seam (matching `qr_scanner.dart`'s existing
  `debugScanStreamOverride` pattern) since the real, static `Alarm.ringing` has no platform channel
  in `flutter test` and never carries a test's fake alarm id.
- `test/app_state_prefs_failure_test.dart` (`docs/TODO.md` T-45): a throwing `SharedPreferences
  .getInstance()` must not block `initialized` from completing. `getPrefsInstance` is injected the
  same way `documentsDirectory`/`fetchEvents`/`now` are, so the failure is simulated without a
  platform channel.
- `test/prune_scheduled_alarms_test.dart`, `test/app_state_prune_scheduled_alarms_test.dart` and
  `test/replan_prunes_scheduled_alarms_test.dart` (`docs/TODO.md` T-141): past `ScheduledAlarm`s no
  longer pile up in the list forever. Split across the same three layers as the `disabledDays`/
  FR-21 tests elsewhere in this list - the pure retention-bound filter (kept deliberately apart from
  `planAlarmSync`'s own safety-critical "never touch a possibly-ringing alarm" removal logic), the
  `AppState` persistence half, and the actual `replan()` wiring, whose sharpest case is today's
  alarm surviving even though its own time has already passed by the moment replan runs (it could
  still be ringing).
- `test/app_state_theme_mode_test.dart` and `test/page_appearance_theme_test.dart`
  (`docs/TODO.md` T-51): a new "Follow System Theme" option. `AppState.themeMode` combines it with
  the existing manual `darkMode` value in one place; the Settings > Appearance screen greys out the
  Dark Mode switch (`onChanged: null`, not a no-op callback) while following the system, and a
  disabled `Switch` genuinely can't be toggled by tapping it.
- `test/manual_alarm_repeat_test.dart` and `test/handler_manual_alarm_rearm_test.dart`
  (`docs/TODO.md` T-14): a `ManualAlarm`'s `repeatOnDays` is now honoured both when first picking a
  day (`nextManualOccurrence`) and by re-arming on every dismiss (`Handler.onAlarmHandled`, injecting
  `setManualAlarmEnabled` since the real `alarm` plugin has no channel in `flutter test`) - a
  platform alarm is one-shot, so only the first half would still have made "repeat" fire exactly
  once.
- `test/page_aboutpage_licenses_test.dart` and
  `test/page_aboutpage_third_party_licenses_test.dart` (`docs/TODO.md` T-36): the About page's new
  "License" (the project's own GPLv3 text, read from the bundled root `LICENSE` file) and
  "Third-Party Licenses" (Flutter's own `showLicensePage()`) buttons. Two files, not one - the same
  isolate-pairing quirk as `qr_scanner_gate_test.dart`/`qr_scanner_close_test.dart`: paired in one
  file the second case hangs on `pumpAndSettle` (against `LicensePage`'s own indefinitely-animating
  progress indicator), alone it passes cleanly.
- `test/ignored_events_test.dart`, `test/replan_ignored_events_test.dart`,
  `test/meeting_data_test.dart` and `test/ignore_event_ui_test.dart` (`docs/TODO.md` T-149): a
  calendar event can be marked "ignored" - excluded from `hardFloor` derivation, grayed out with an
  X on its `DayView`/`WeekView` tile, persisted by `device_calendar` event id
  (`AppState.ignoredEventIds`), never written back to the calendar. Split across four files by
  layer (persistence, scheduling filter, tile colour, tap-to-toggle UI), the same shape as the
  disabledDays/FR-21 tests elsewhere in this list.
- `integration_test/app_test.dart`: real end-to-end tests, driven against an actual Android
  emulator in `.github/workflows/release.yml`'s `e2e-tests` job, gating the signed release build.
  Seven scenarios are covered. Three predate scheduling-v2: a manual alarm firing and being
  dismissed via the default overlay, one dismissed via an injected QR scan result, and a created
  alarm read back after app state is rebuilt (see `docs/TODO.md` T-04 for why that last one proves
  less than its name suggests). Four exercise the new engine (T-91), each bound to a real finding:
  an injected calendar event becoming registered platform alarms (T-63), the registered alarm
  carrying the *local* reading of the planned instant (T-61), tone/volume/gentle-wake reaching the
  plugin (T-84/T-96), and a dismiss leaving the planned week registered (T-64).
  `integration_test/arm_alarm_test.dart` is a one-test prelude for the reboot-survival evidence
  script run inside *this* CI emulator job (`.github/scripts/check_alarm_survival.sh`, T-93/T-99) -
  a separate mechanism from `scripts/verify-alarm-survival.sh`'s real-USB-phone measurement
  (T-93's own entry has that result; this emulator-based leg is still evidence-only, not gating,
  and its detection patterns are still being locked down against real evidence, T-99).
  `integration_test/silent_notification_test.dart` (T-62) is likewise a one-test, non-gating leg:
  it schedules a real title/body-less notification and waits for `onNotificationCreatedMethod` to
  rewrite a sentinel value, confirming on a real device that FR-16 Checkpoint 2's entry point
  actually fires at all - previously only "verified from the package source" with no device to
  check it on.
  All seven `app_test.dart` scenarios **have now run green on a real emulator** (CI run
  34532845207, `🎉 7 tests passed`, with `applyPlannedAlarms: removed 0, added 7` in the device
  log) - that run is what closed T-91, so don't describe the engine as never having been on a
  device.
  Still not covered by anything: audible playback and the gentle-wake ramp (the CI emulator runs
  with audio disabled), and the real `device_calendar` boundary - every engine scenario injects its
  events through `fetchEvents`, so the chain that produced T-61 stays untested. Real camera QR
  decoding is separately confirmed (T-143), but on a real device by hand, not through this
  emulator-based suite (the CI emulator has no real camera to point at a code).
  `docs/device-trial-checklist.md` is the manual counterpart for exactly those gaps.
- A real on-device run now happens on every release build - do not describe Android verification as
  "build success plus static analysis only" going forward; that was true before the E2E work below
  and no longer is.

## Current APK

**After every newly built feature, a `current.apk` is placed at the repository root** so the
maintainer can flash the latest state without hunting for a CI artifact. It is gitignored - a
build output, ~80 MB, changing with every feature.

It is always *the current one*: overwrite it, never add versioned names beside it. Take the
`app-production-apk` artifact from the newest **green** CI run containing the feature
(`gh run download <run-id> -n app-production-apk`), verify it with `apksigner verify`, and report
the SHA-256 so it is clear whether the file on disk is the one just described. Building locally is
a fallback for when CI has not run yet - the CI build is the signed release build the release path
actually produces.

## Quality baseline snapshot

A point-in-time SAST/SCA/PII/security assessment and an end-to-end test plan live in
`docs/quality-baseline-2026-09.md`; an initial release-readiness assessment lives in
`docs/release-readiness-2026-09.md`. Both are gitignored (not tracked in version control, so a fresh
clone will not have them) and predate the E2E work described above - treat them purely as
historical, point-in-time snapshots, not living documents, and don't expect them to agree with the
testing status above. Re-run `scripts/security-scan.sh` and `flutter analyze` for current SAST/SCA
status, and see `docs/TODO.md` for current test/evidence status, rather than trusting either
snapshot file as still accurate.

## Project documentation

`docs/` also holds `REQUIREMENTS.md` (essential pre-`master` requirements - check this before any
production push), `licence-position.md` (the tracked GPLv3 decision for R8/R9 - see "Licence
position" above), `TODO.md` (every known open task, prioritised, with evidence and an acceptance
criterion - the living record of what's actually wrong or missing, as opposed to the two frozen
snapshots above), `device-trial-checklist.md` (the manual counterpart to the E2E suite, with a
result field per line), `scheduling-v2-spec.md` (FR-1 … FR-21), plus `personas.md`, `use-cases.md`
and `choice-of-technologies.md` from the original project planning. Those three markdown documents
predate the finished app and have been annotated inline where they describe features that were
planned but never implemented (e.g. NFC-tag deactivation, Do Not Disturb) or claims that no longer
hold - don't assume everything in them shipped as described.

**There is currently no UML diagram.** `UML_WakeyWakey.drawio` modelled the original
planning-phase design (including the removed old scheduling engine) with no way to annotate a
`.drawio` binary the way the markdown planning docs were annotated, so it was retired rather than
left stale (`docs/TODO.md` T-30, 2026-09-20). It will be redrawn from the current architecture once
a drawio-integration workflow exists to keep it in sync going forward - until then, this file's own
architecture tables and `docs/TODO.md` are the accurate structural description of the app.

**`docs/risk.png` is generated, not hand-drawn.** It used to be a planning-phase risk graphic
modelling features that were never built; since 2026-09-10 it is a real threat model
(`docs/TODO.md` T-101). Edit `docs/threat-model.svg` - which is text, and therefore diffable and
reviewable - and re-render with:

```sh
rsvg-convert -w 1400 -b white docs/threat-model.svg -o docs/risk.png
```

Two things about it are worth knowing before extending it. The primary asset here is
**availability**: for an alarm clock, "outage" means oversleeping, so denial of service is the
heaviest STRIDE category rather than the most annoying one - and the project's two worst findings
(T-64, T-78) were exactly that, self-inflicted alarm shutdowns. And in the guaranteed-wake-up
feature the adversary is partly **the user**, trying to defeat their own gate, which inverts the
usual assumptions.

## Review persona: External Compliance & Fitness-for-Purpose Auditor (review-only)

This persona exists to be adopted by an **independent review agent auditing the project** - never
for implementation work, and never by an agent that also wrote the code under review. It lives here
rather than in `docs/personas.md` because it is not a user WakeyWakey is designed for; it is an
outside evaluator with no stake in the project shipping.

**Who they are:** an external compliance/legal consultant retained by an organisation deciding
whether to recommend or permit an app like WakeyWakey for its people - a hospital assessing it for
night-shift nursing staff, a company considering it for traveling consultants. They have no
familiarity with this project's internal history or `docs/TODO.md` numbering, no obligation to be
encouraging, and their name goes on the finding. Ground the "shift workers and business people"
part of the mandate in the concrete personas already in `docs/personas.md` (Marie the nurse working
irregular shifts, Tom the business traveler) rather than treating the phrase abstractly.

**Mandate - two independent questions, both answered in writing:**

1. **Licence/legal acceptability.** Is everything in this repository - the app's own GPLv3 licence,
   every third-party dependency's licence, the privacy policy, the PII/data-handling practices, and
   the claims made about all of these - actually true and actually compliant, not merely asserted to
   be? Treat `docs/licence-position.md`'s "resolved"/"met" markers, `docs/TODO.md`'s "RESOLVED"/
   "IMPLEMENTED" labels, and `test/no_proprietary_dependencies_test.dart`'s green run as claims to
   verify against `pubspec.yaml`/`pubspec.lock`/actual `lib/` imports/`LICENSE`/
   `assets/text/Privacy.md`, not as proof by citation.
2. **Fitness for shift workers and business people.** Would they tell a hospital's night-shift staff,
   or a company outfitting traveling employees, that this app is reliable enough to depend on for
   actually waking up, and private enough to trust with a record of when someone sleeps and where
   they travel? This covers reliability (the "guaranteed wake-up" claim, alarm survival across
   reboot/force-stop per R3, the fail-safes against being trapped by a broken camera), data privacy
   adequacy for someone who cannot risk their sleep pattern or travel history leaking (the diagnostics
   log's PII-free design, the calendar/camera permission model), and the honesty of the claims made in
   `README.md`/`docs/USER_GUIDE.md` against what the code and tests actually demonstrate.

**Working method:**

- Verify claims against source, tests, and CI configuration - never take a doc's own status label at
  face value.
- In the written report, distinguish clearly between: a genuine defect that would block sign-off; a
  real but non-blocking risk to disclose to a client rather than silently accept; and a claim that
  checks out exactly as stated.
- Cite exact files/lines for every finding - a finding without a locator is not actionable.
- No stake in the outcome: neither soften a real finding to avoid friction, nor invent risk to look
  thorough.
