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
- Windows and macOS scaffolding (leftover from the initial `flutter create`) has been removed, as
  neither was ever a real target.

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

- **`dev`**: fast feedback only - `flutter analyze` + `flutter test`.
- **`master`** (and PRs into it): the full pipeline - analyze, test, dependency vulnerability scan
  ([osv-scanner](https://github.com/google/osv-scanner)), secret scan
  ([trufflehog](https://github.com/trufflesecurity/trufflehog)), Android source SAST
  ([mobsfscan](https://github.com/MobSF/mobsfscan)), an Android debug build, and a full
  [MobSF](https://mobsf.github.io/docs/) static scan of that build. Only Android is actually built
  in CI - see "Supported Platforms" above for why Linux/iOS aren't.
- Signed release APKs are built by a separate [release workflow](.github/workflows/release.yml),
  triggered by pushing a `v*.*.*` tag, and attached to a GitHub Release.

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

- Automated: a Flutter widget smoke test (`flutter test`) plus the static analysis/scans above.
- **No build has been installed or run on an actual Android device or emulator** as part of this
  project's verification so far - Android is currently checked by build success and static
  analysis only. If you're picking this project up, installing a build on a real device and
  walking through the core alarm flow (create → ring → deactivate, with and without a QR
  deactivation code) is the highest-value next testing step.

### Contributing

Contributions are welcome! Please fork this repository and submit pull requests. For major changes, please open an issue first to discuss what you would like to change.

### License

This project is licensed under the GNU General Public License v3.0 - see the LICENSE file for details.
