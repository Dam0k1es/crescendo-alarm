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
- **Manual device testing** by the maintainer has confirmed the ring-and-stop flow on real
  hardware; findings from it are tracked in [`docs/TODO.md`](docs/TODO.md).
- **Not covered by any automated verification:** alarm survival across a device reboot or an app
  force-stop; audio playback and the gentle-wake volume ramp (the CI emulator runs with audio
  disabled, and gentle wake defaults to off, so that code path never executes); decoding a real
  physical QR code through the camera; and calendar-derived scheduling (the CI emulator has no
  calendar accounts).
- **iOS** has never been built or run - no Mac/Xcode has been involved in this project.

### Open items

All known gaps are tracked as prioritised TODOs in [`docs/TODO.md`](docs/TODO.md) - device
feedback and audit findings in one list, with evidence and an acceptance criterion per item.

The ones that currently block a production push: Sleep-Habits durations are not subtracted from the
derived alarm time; calendar-derived times are discarded for most days; the background rescheduling
the requirements demand does not exist; the per-alarm enable switch does not stop an alarm; alarm
survival across a reboot or force-stop is unverified; a direct dependency is not open source (a
GPLv3 conflict); and the signed release APK is built with no quality gate.

### Project Documentation

See `docs/` for personas, use cases, technology choices and a UML diagram, plus the two documents
that matter most:

- [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) - the essential requirements that must be met (or
  have their current status honestly stated) before any push to `master`.
- [`docs/TODO.md`](docs/TODO.md) - every known open task, prioritised, with evidence and an
  acceptance criterion.

### Contributing

Contributions are welcome! Please fork this repository and submit pull requests. For major changes, please open an issue first to discuss what you would like to change.

### License

This project is licensed under the GNU General Public License v3.0 - see the LICENSE file for details.
