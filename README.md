# wakeywakey

[![CI](https://github.com/Dam0k1es/wakeywakey/actions/workflows/ci.yml/badge.svg)](https://github.com/Dam0k1es/wakeywakey/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

Welcome to Wakey Wakey, an innovative alarm clock app designed for individuals with irregular sleep patterns. Whether you work shifts, travel frequently, or simply have trouble waking up, Wakey Wakey has features tailored to your needs.

## Features

- **Calendar Integration:** Syncs with your mobile calendar to derive intelligent alarm schedules based on your commitments.
- **Gentle Wake-Up:** Alarm volume increases gradually for a smoother start to your day.
- **Guaranteed Wake-Up:** Requires scanning a physical QR code to turn off the alarm, ensuring you get out of bed.

## Technologies Used

- **Flutter:** For cross-platform development.
- **Figma:** For design and wireframing.

## Supported Platforms

- **Android** is the actual target platform. `minSdk` 24 (Android 7.0), `targetSdk` 36 (Android 16).
- **Linux desktop** builds and runs, but only as a fast local dev/debug loop - it is not a
  supported deployment target. Calendar integration always no-ops there (no Linux implementation
  of the calendar plugin exists), by design.
- **iOS** has project scaffolding but has never actually been built or run - treat it as
  unverified, not supported, until someone with a Mac/Xcode does that work.
- Windows, macOS, and web scaffolding (leftover from the initial `flutter create`) has been
  removed, as none of them was ever a real target.

## Installation Instructions

### Prerequisites

Ensure you have the following installed:

- [Flutter](https://flutter.dev/docs/get-started/install)
- [Dart](https://dart.dev/get-dart)

### Steps

1. **Clone the Repository**
   ```sh
   git clone https://github.com/Dam0k1es/wakeywakey.git
   cd wakeywakey
   ```

2. *Install Dependencies*
   ```sh
   flutter pub get
   ```

3. *Run the app*
   ```sh
   flutter run
   ```

The launcher icons for Android/iOS are already generated and checked into the repository, so this
step isn't needed on a fresh clone. Only regenerate them if you change `assets/icons/icon.png`:

```sh
dart run flutter_launcher_icons
```

### Usage

- Open Wakey Wakey on your mobile device.
- Allow the app to sync with your calendar.
- Set up your alarm preferences and add necessary QR codes in remote locations.
- Enjoy a more reliable and interactive waking experience.

### Quality Checks

CI runs via [GitHub Actions](.github/workflows/ci.yml) and scales with the branch:

- **`dev`**: fast feedback (`flutter analyze` + `flutter test`) plus a debug **development** APK,
  uploaded as a downloadable build artifact on the run.
- **`master`** (and PRs into it): the full pipeline - analyze, test, dependency vulnerability scan
  ([osv-scanner](https://github.com/google/osv-scanner)), secret scan
  ([trufflehog](https://github.com/trufflesecurity/trufflehog)), Android source SAST
  ([mobsfscan](https://github.com/MobSF/mobsfscan)), a signed **production** release APK build, and
  a full [MobSF](https://mobsf.github.io/docs/) static scan of that build. The production APK is
  uploaded as a build artifact on every run. Only Android is actually built in CI - see "Supported
  Platforms" above for why Linux/iOS aren't.
- Tagged releases: pushing a `v*.*.*` tag runs a separate
  [release workflow](.github/workflows/release.yml) that builds the same signed production APK and
  attaches it to a formal GitHub Release (with generated release notes) - use this for actual
  version bumps; the per-push artifact above is for grabbing "whatever's on master right now."

To run the same checks locally before committing:

```sh
flutter analyze                # static analysis / lints
flutter test                   # unit tests
bash scripts/security-scan.sh  # analyze + osv-scanner + trufflehog
flutter build apk --debug      # verify the Android build
```

Note: `flutter` commands that need to create plugin symlinks (`analyze`, `build`, `test`, `run`,
`pub get`) will fail with a `PathAccessException` on a checkout living on a filesystem without
symlink support (e.g. a VirtualBox/vboxsf shared folder) - use a checkout on a native filesystem.

### Testing status

- **Unit/widget (`flutter test`, 6 tests):** one widget smoke test that renders the splash screen,
  plus five cases covering a single stale-alarm predicate. This is a thin gate, not a regression
  net - see "Open items" below.
- **End-to-end on a real Android emulator:** `integration_test/app_test.dart` runs against an
  API-34 emulator in the [release workflow](.github/workflows/release.yml) and gates the signed
  release build. Three scenarios are covered and currently pass: a manual alarm firing and being
  dismissed through the default overlay, a manual alarm being dismissed through an injected QR
  scan result, and a created alarm being read back after app state is rebuilt. Each run uploads an
  `e2e-evidence` artifact (screen recording without audio, an audio-focus timeline, and the raw
  test log).
- **Static and supply-chain:** `flutter analyze`, `osv-scanner`, `trufflehog`, `mobsfscan` and a
  full MobSF scan of the built APK, as described under "Quality Checks" - but note which of those
  can actually fail a run (see "Open items").
- **Not verified on a device yet:** alarm survival across a device reboot or an app force-stop;
  audio playback and the gentle-wake volume ramp (the CI emulator runs with audio disabled);
  decoding a real physical QR code through the camera; and calendar-derived scheduling (the CI
  emulator has no calendar accounts, so that path is never executed).
- **iOS** has never been built or run - no Mac/Xcode has been involved in this project.

### Open items

Known gaps, ordered roughly by how much they matter. This list is deliberately honest about the
difference between "this is broken", "this is untested", and "this is documented as unfinished".
Requirement IDs refer to [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md).

**Correctness of the core product**

1. **Calendar-derived alarm times are largely discarded (R2).** `_adjustAlarmTimes` compares each
   day's alarm against an absolute `DateTime` derived from the earliest day, so for every day after
   that earliest day the comparison is decided by the date alone: the day's real, calendar-derived
   time is replaced by the earliest day's wake-up time. Conversely, on days *before* the earliest
   day the synthetic 23:59 "no calendar entry" placeholder is left untouched and armed as a real
   alarm. Scheduling also aborts silently and schedules nothing at all once seven or more alarms
   had to be estimated.
2. **Alarm survival across reboot/force-stop is unverified (R3).** Nothing in the test suite or CI
   restarts the process, force-stops the app, or reboots the device. The one test named
   "survives being reloaded from on-device storage" does not test storage: `SharedPreferences`
   memoises its instance and serves an in-process cache, so rebuilding app state re-reads the same
   in-memory map. For an alarm clock this is the highest-value gap that remains.
3. **The per-alarm enable switch is inert.** The `enabled` flag is stored, serialized and compared,
   but never consulted when arming or cancelling an OS alarm - switching an alarm off does not stop
   it from ringing.
4. **Per-weekday repeat is inert.** `repeatOnDays` is editable and persisted but never read when
   scheduling; manual alarms are effectively one-shot (today or tomorrow).
5. **The global volume setting never reaches calendar-derived alarms.** `ScheduledAlarm` carries no
   volume, so those alarms always ring at the hardcoded default regardless of the user's setting.

**Test quality**

6. **The QR deactivation gate has no negative test.** Only the correct payload is ever injected, so
   removing the payload comparison entirely would keep the suite green. The branches that treat a
   missing stored code as "valid", and that adopt the first scanned code as the deactivation code,
   are untested too. This is the app's one differentiating security property.
7. **Both dismissal tests assert navigation only.** They check that a screen disappeared, never
   that the alarm actually stopped - and both production paths navigate away even when stopping the
   alarm throws. No test queries the alarm plugin's state.
8. **The scheduling engine has no real tests.** `test/adjustTime/` and `test/getEarliestAlarm/` are
   standalone interactive scripts that `flutter test` never runs; they do not import the app at all,
   and `test/adjustTime/` implements helper functions and a two-pass algorithm that exist nowhere in
   `lib/`. Converting them to `test()` blocks as-is would test a fork, not the shipped scheduler -
   the production functions need to be made testable first.
9. **The QR test seam does not isolate the camera.** With the barcode-stream override set, the
   scanner widget still starts the real camera (the controller auto-starts), so the "never touch the
   real camera" comment is inaccurate, an app-lifecycle event can silently drop the injected stream,
   and the seam is a mutable static that also ships in release builds.
10. **The E2E harness has known flake mechanisms.** State is sampled once every 500 ms, so
    short-lived screens can be missed; the "now + 1 minute" alarm default is minute-truncated and
    can land 24 hours out if the save crosses a minute boundary; and no teardown stops leftover
    alarms between scenarios, so one failure can cascade into the next.

**Evidence and gating**

11. **The signed release APK is built and published with no quality gate.** In `ci.yml` the release
    build job declares no `needs:`, so it runs regardless of whether analyze, tests, SCA, secret
    scanning or SAST failed; the release workflow runs no SCA/secret/SAST jobs at all. A red run
    still produces a downloadable, signed, signature-verified APK.
12. **Two of the five security tools in R1 cannot fail a run.** `mobsfscan` runs with `--no-fail`
    and the MobSF step only prints counts with no threshold. The current MobSF report on master
    carries one HIGH finding and a security score of 51 while the job concludes success. There is
    also no tracked record accepting either that HIGH or the task-hijacking finding R1 cites as a
    known false positive.
13. **The evidence R1/R2/R6/R11 cite is not in the repository.** The two snapshot documents that
    those requirements point to for their "checked by"/"met" justification are excluded by
    `.gitignore`, so anyone cloning this repo gets a requirements register whose evidence is
    missing. They are referenced from tracked files in roughly a dozen places.
14. **The tag → GitHub Release path has never run and would currently fail.** No tag or release
    exists yet, and the release-attach step has no `contents: write` permission while the
    repository's default workflow token is read-only. Dry-run it with a throwaway tag before
    relying on it.
15. **The gentle-wake ramp has no evidence of any kind.** It defaults to off, so no test enables it
    and the fade code path is never executed; the emulator also runs without audio. The audio-focus
    log does show the app taking alarm-usage audio focus, but that is circumstantial and says
    nothing about a gradual ramp.
16. **Evidence collection degrades silently and nothing reads it.** Recording and pull failures are
    swallowed (in the last green run 7 of 12 screen-recording segments were lost without affecting
    the job's result), an empty evidence directory would only warn, and no CI step parses the
    recording or logs. The retention script also keeps only the newest run and the newest
    *successful* run, so failure evidence is deleted and past failure claims cannot be re-derived
    from artifacts.
17. **`scripts/security-scan.sh` can report a false all-clear.** Its trufflehog step omits the
    `--fail` flag that CI uses, so the script can print "All checks completed cleanly" while
    findings exist. It also covers only two of R1's five tools and excludes paths CI scans.

**Legal and documentation**

18. **A direct dependency is not open source (R8, R9).** The Syncfusion calendar/datepicker/core
    packages ship under the Syncfusion Essential Studio licence, which requires either a commercial
    licence or qualifying for their community programme (revenue and team-size limits). R8's "all
    dependencies are open-source - met" is therefore incorrect, and this is a concrete
    GPLv3-compatibility problem for distributing the APK, not merely an unrun licence scan.
19. **Bundled asset provenance is still unrecorded (R10).** There is no record of where the alarm
    sounds and icons came from, or under what licence.
20. **The privacy policy does not match the app (R11).** It describes data the app cannot collect
    while omitting camera, gallery, calendar-write and locally stored deactivation codes; the
    "met" status was based on checking the contact address only.
21. **Descriptive docs lag the code in both directions.** The README's three headline features
    understate what is actually shipped, while the personas/use-case/UML artifacts still model
    features and classes that were never built and carry no annotation saying so.

### Project Documentation

See `docs/` for personas, use cases, technology choices, a UML diagram, and - most importantly -
[`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md), the essential requirements that must be met (or
have their current status honestly stated) before any push to `master`.

### Contributing

Contributions are welcome! Please fork this repository and submit pull requests. For major changes, please open an issue first to discuss what you would like to change.

### License

This project is licensed under the GNU General Public License v3.0 - see the LICENSE file for details.
