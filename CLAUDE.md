# WakeyWakey

A Flutter alarm-clock app for people with irregular sleep schedules: calendar-derived alarm
scheduling, gentle wake-up (gradual volume ramp), and a "guaranteed wake-up" mode that requires
scanning a physical QR code to deactivate the alarm. Fully offline - no network calls anywhere in
`lib/`.

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
- **Windows, macOS, and web scaffolding were removed** (they existed from the original
  `flutter create` template but were never a real target and added maintenance surface for no
  benefit).

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

Two workflows under `.github/workflows/`:

- **`ci.yml`** runs on every push and PR, scaled by branch: `dev` gets fast feedback only
  (`flutter analyze` + `flutter test`, plus a debug development APK uploaded as an artifact).
  `master` (and PRs into it) additionally runs `osv-scanner` (SCA) and `trufflehog` (secrets) - both
  of which can fail the run - plus `mobsfscan` and a full MobSF static scan, which currently cannot
  (see `docs/TODO.md` T-11), and builds+uploads a signed production release APK, currently
  regardless of whether the checks above passed (T-06 - `build-android-release` has no `needs:`).
- **`release.yml`** runs `integration_test/app_test.dart` against a real Android emulator and gates
  its own signed release build on that suite passing; triggered by a `v*.*.*` tag (which additionally
  attaches the APK to a formal GitHub Release with generated notes) or manually via
  `workflow_dispatch`. Run the same E2E suite locally with a connected device or running emulator:
  `flutter test integration_test/app_test.dart -d <device-id>`.
- `scripts/security-scan.sh` mirrors part of the `master` pipeline locally (`flutter analyze` +
  `osv-scanner` + `trufflehog`) but is narrower than CI - no `mobsfscan`/MobSF, and its secret-scan
  step currently can't fail on a finding the way CI's does (`docs/TODO.md` T-26).

The tag → GitHub Release path has never actually been exercised (no tag has been pushed yet) - see
`docs/TODO.md` T-13 before relying on it.

## Toolchain versions (as verified working, September 2026)

| Component | Version | Notes |
|---|---|---|
| Flutter | 3.47.2 (stable) | `fvm` used to pin this on the dev VM |
| Dart | 3.13.2 | bundled with the above Flutter |
| JDK | 17 (OpenJDK) | required by AGP 9.x / Gradle 9.x |
| Gradle | 9.3.1 | `android/gradle/wrapper/gradle-wrapper.properties` |
| Android Gradle Plugin (AGP) | 9.1.0 | `android/settings.gradle.kts` |
| Kotlin Gradle Plugin | 2.4.0 | `android/settings.gradle.kts` |
| compileSdk | 36 (Flutter default) | see "compileSdk override" below |
| minSdk | 24 (pinned explicitly) | `android/app/build.gradle.kts` - was intended to stay below Flutter's own default (also 24, coincidentally, on current Flutter) for older-device support, but MobSF found the *compiled* APK's merged manifest already enforced minSdk=24 regardless, because several plugins (`image_picker_android`, `shared_preferences_android`, `flutter_plugin_android_lifecycle`) declare `minSdk=24` in their own Gradle modules, and manifest merging always takes the highest value across the app + all dependencies. Pinned explicitly to 24 to match the real enforced floor instead of leaving a misleadingly lower number. Also: this value has silently regressed to `flutter.minSdkVersion` (dropping any pin at all) more than once in this project's history - if you ever intend to actually push it lower than 24 again, you'd first need to downgrade those three plugins, not just change this line. |
| targetSdk | 36 (Flutter default, `flutter.targetSdkVersion`) | |
| NDK | intentionally left unset in `app/build.gradle.kts` (no `ndkVersion = flutter.ndkVersion` line) | AGP uses whichever NDK is installed (currently 28.2.13676358) instead of requiring an exact pin |

**Android SDK packages this build needs installed** (via `sdkmanager`): `platform-tools`,
`platforms;android-36`, `build-tools;36.0.0`, plus whatever additional `platforms;android-NN` /
`build-tools;NN.0.0` the currently-resolved plugin versions demand (Flutter's own doctor check has
asked for `build-tools;28.0.3` historically; AGP may also pull a newer one automatically). NDK
`28.2.13676358` under `Sdk/ndk/`.

### compileSdk override for plugin subprojects

`android/build.gradle.kts` forces every Android library subproject to `compileSdk = 36` via an
`afterEvaluate` hook, registered **before** `evaluationDependsOn(":app")` (registering it after
throws `Cannot run Project.afterEvaluate(Action) when the project is already evaluated`). This
exists because `awesome_notifications_core` (last published Feb 2025, `compileSdkVersion 33`
hardcoded, no update since) fails AAR-metadata checks against its own newer AndroidX transitive
dependencies otherwise. If a future dependency bump makes this override redundant, it's safe to
remove - but check `flutter build apk` still succeeds first.

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

- `test/widget_test.dart`: a real, passing smoke test (builds `MyApp` under its required
  `ChangeNotifierProvider<AppState>`, mocks `SharedPreferences`, checks the splash screen renders).
  It replaced a stale `flutter create` counter-app placeholder that had never been adapted to this
  project and failed on every run (`ProviderNotFoundException`) - if `flutter test` ever goes red
  again on this file, that's a real regression, not a flaky leftover.
- `test/handler_stale_alarm_test.dart`: real `package:test` unit tests for the stale-alarm predicate
  in `lib/models/alarms/handler.dart`. `flutter test` runs 6 tests total (1 widget + 5 here), not
  just the one widget smoke test.
- `test/adjustTime/` and `test/getEarliestAlarm/`: standalone interactive scripts (`main.dart`, uses
  `print`, and in `adjustTime/`'s case also `stdin.readLineSync()`), not `package:test` tests -
  `flutter test` does not run them. Do not convert them as-is: neither imports
  `package:wakeywakey`, and `test/adjustTime/`'s algorithm no longer matches the production
  scheduler in `lib/models/scheduling/scheduling.dart` - see `docs/TODO.md` (T-10) for what porting
  them properly requires. The scheduling engine itself currently has no automated coverage at all.
- `integration_test/app_test.dart`: real end-to-end tests, driven against an actual Android
  emulator in `.github/workflows/release.yml`'s `e2e-tests` job, gating the signed release build.
  Three scenarios are covered and currently pass: a manual alarm firing and being dismissed via the
  default overlay, one being dismissed via an injected QR scan result, and a created alarm being
  read back after app state is rebuilt (see `docs/TODO.md` T-04 for why that last one proves less
  than its name suggests). Not covered by this suite or anything else: alarm survival across a
  reboot or force-stop, audio playback and the gentle-wake volume ramp (the CI emulator runs with
  audio disabled and gentle wake defaults to off), real camera QR decoding, and calendar-derived
  scheduling (the CI emulator has no calendar accounts). See `docs/TODO.md` for the complete,
  current list of test-quality and coverage gaps.
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
snapshots above), `personas.md`, `use-cases.md`, `choice-of-technologies.md`, a risk/dataflow
diagram (`risk.png`) and a UML diagram (`UML_WakeyWakey.drawio`) from the original project
planning. `use-cases.md`, `personas.md` and `choice-of-technologies.md` predate the finished app
and have been annotated inline where they describe features that were planned but never
implemented (e.g. NFC-tag deactivation, Do Not Disturb) or claims that no longer hold - don't assume
everything in them shipped as described. `risk.png` and the UML diagram are images from the same
planning phase and carry no such annotation; cross-check them against `docs/TODO.md` (T-30) before
trusting what they model.
