# WakeyWakey

A Flutter alarm-clock app for people with irregular sleep schedules: calendar-derived alarm
scheduling, gentle wake-up (gradual volume ramp), and a "guaranteed wake-up" mode that requires
scanning a physical QR code to deactivate the alarm. Fully offline - no network calls anywhere in
`lib/`.

## Scheduling engine (`lib/models/scheduling/`)

Calendar-derived wake times come from **scheduling-v2**, specified in
`docs/scheduling-v2-spec.md` (FR-1 … FR-18) and implemented test-first against that spec. The old
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
- **Every domain value is an absolute instant, UTC-tagged**, while `wunschzeit` is a bare
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

- **No clock values.** Days are relative (via `dayDistance`, so the logger does not rebuild T-76
  inside itself); moments appear only as *bucketed differences*; the absolute UTC offset is never
  recorded, only the shape of a change. A history of wake times plus offsets is a sleep pattern and
  a travel trace - identifying without any name.
- **Exceptions go in as `runtimeType`** through an identity table to an int; `toString()` is never
  called on a `Type` (R8 obfuscation is then irrelevant).
- **The background isolate has its own ring buffer.** FR-16's Checkpoint 2 runs in a separate
  isolate, so there are two `SharedPreferences` keys and a merge on read - the same trap as T-69,
  one level down. `Diag.init` belongs at the isolate's *entry point*
  (`onNotificationCreatedMethod`), never inside the checkpoint: it mutates global state.
- Persisted via `shared_preferences`, not a file via `path_provider`, precisely because that
  isolate already talks to it directly - a file logger would depend on plugin-channel availability
  there, which is the failure class T-79 was.

License: GNU GPLv3 (see `LICENSE`). Author/copyright holder: Dam0k1es. Do not add other personal
names, emails, or locations to tracked files - see "PII policy" below.

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
- **`security-gate.yml`** (reusable, `workflow_call`) is the SCA/secret/SAST gate: `osv-scanner`,
  `trufflehog --fail`, and `mobsfscan` filtered through `.github/security-exceptions.json`. It
  lives in its own file because the **tag-triggered release path used to have no security gate at
  all** (`docs/TODO.md` T-92) - a signed APK could be attached to a GitHub Release with a
  vulnerable dependency that the same commit on `master` would have been rejected for.
- **`release.yml`** is triggered by a `v*.*.*` tag or `workflow_dispatch` and gates its signed
  build on **both** `e2e-tests` and `security-gate`.

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

`scripts/security-scan.sh` mirrors part of the pipeline locally (analyze + osv-scanner +
trufflehog) but is narrower than CI - no mobsfscan/MobSF.

**Validate workflow changes locally before pushing: `actionlint` is installed on the dev VM** and
checks all four workflows (plus shellcheck over every `run:` block) in under a second. Invalid
workflow YAML does not fail loudly on GitHub - the run starts, executes *no step*, and concludes
as a failure in a few seconds, which reads like an infrastructure blip rather than a syntax error.
Three runs were burned that way on one commit (a duplicated `restore-keys:` inside one `with:`
mapping) before the cause was found.

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
  `timezone: ^0.9.0`, while `syncfusion_flutter_calendar` requires `^0.11.0` - a real unresolved
  conflict between the two packages' declared constraints. Forcing 0.11.x is safe in practice: the
  public API (`TZDateTime`, `Location`, `getLocation`) is unchanged between 0.9.x and 0.11.x, only
  the bundled IANA timezone data was refreshed. Revisit once `device_calendar` allows `^0.11.0`.

Both overrides carry explanatory comments in `pubspec.yaml` itself - keep them in sync if you
change either.

## PII policy

Don't add real personal names, emails, addresses, or other identifying info to any tracked file.
The privacy-policy contact (`assets/text/Privacy.md`) intentionally uses an alias contact address,
not the maintainer's real one. `android/key.properties` (gitignored) intentionally uses a
project-relative placeholder path, not a real machine username. `.idea/` is fully gitignored
(blanket rule) - JetBrains IDEs write more local/user-specific files than can be enumerated
individually, including AI-assistant chat history that can leak real usernames and local paths.

## Testing status (as of September 2026)

`flutter test` currently runs **209 tests across 24 files**, and CI runs them six times over -
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

- The scheduling-v2 suite (`scheduling_v2_test.dart`, `scheduling_v2_offset_test.dart`,
  `scheduling_v2_tz_test.dart`, `scheduling_v2_dst_test.dart`, `replan_test.dart`,
  `checkpoint_test.dart`, `apply_alarms_test.dart`, `next_wake_up_test.dart`,
  `replan_notifications_test.dart`, `app_state_scheduling_v2_test.dart`, `day_marker_test.dart`,
  `stored_values_test.dart`, `handler_replan_wiring_test.dart`,
  `handler_on_alarm_handled_test.dart`, `sleep_reminder_always_scheduled_test.dart`) is written
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
  script (T-93). All seven scenarios **have now run green on a real emulator** (CI run 34532845207,
  `🎉 7 tests passed`, with `applyPlannedAlarms: removed 0, added 7` in the device log) - that run
  is what closed T-91, so don't describe the engine as never having been on a device.
  Still not covered by anything: alarm survival across a reboot or force-stop (T-93 has the
  procedure, no result yet), audible playback and the gentle-wake ramp (the CI emulator runs with
  audio disabled), real camera QR decoding, and the real `device_calendar` boundary - every engine
  scenario injects its events through `fetchEvents`, so the chain that produced T-61 stays
  untested. `docs/device-trial-checklist.md` is the manual counterpart for exactly those gaps.
- A real on-device run now happens on every release build - do not describe Android verification as
  "build success plus static analysis only" going forward; that was true before the E2E work below
  and no longer is.

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
production push), `TODO.md` (every known open task, prioritised, with evidence and an acceptance
criterion - the living record of what's actually wrong or missing, as opposed to the two frozen
snapshots above), `device-trial-checklist.md` (the manual counterpart to the E2E suite, with a
result field per line), `scheduling-v2-spec.md` (FR-1 … FR-18), plus `personas.md`,
`use-cases.md`, `choice-of-technologies.md` and a UML diagram (`UML_WakeyWakey.drawio`) from the
original project planning. Those three markdown documents predate the finished app and have been
annotated inline where they describe features that were planned but never implemented (e.g.
NFC-tag deactivation, Do Not Disturb) or claims that no longer hold - don't assume everything in
them shipped as described. The UML diagram carries no such annotation; cross-check it against
`docs/TODO.md` (T-30) before trusting what it models.

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
