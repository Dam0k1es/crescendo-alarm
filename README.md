# wakeywakey

Welcome to Wakey Wakey, an innovative alarm clock app designed for individuals with irregular sleep patterns. Whether you work shifts, travel frequently, or simply have trouble waking up, Wakey Wakey has features tailored to your needs.

## Features

- **Calendar Integration:** Syncs with your mobile calendar to derive intelligent alarm schedules based on your commitments.
- **Gentle Wake-Up:** Alarm volume increases gradually for a smoother start to your day.
- **Guaranteed Wake-Up:** Requires scanning a physical QR code to turn off the alarm, ensuring you get out of bed.

## Technologies Used

- **Flutter:** For cross-platform development.
- **Figma:** For design and wireframing.

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

Before committing or opening a pull request, run:

```sh
flutter analyze                # static analysis / lints
flutter test                   # unit tests
bash scripts/security-scan.sh  # analyze + dependency vulnerability scan (osv-scanner) + secret scan (trufflehog)
flutter build linux --debug    # verify the Linux desktop build
flutter build apk --debug      # verify the Android build
```

`scripts/security-scan.sh` requires [osv-scanner](https://github.com/google/osv-scanner) and
[trufflehog](https://github.com/trufflesecurity/trufflehog) on `PATH`. All of the above are plain
shell/Flutter commands with no repository-specific setup, so they can be dropped into a CI
pipeline (e.g. GitHub Actions) as-is once one is set up.

Note: `flutter` commands that need to create plugin symlinks (`analyze`, `build`, `test`, `run`,
`pub get`) will fail with a `PathAccessException` on a checkout living on a filesystem without
symlink support (e.g. a VirtualBox/vboxsf shared folder) - use a checkout on a native filesystem.

### Contributing

Contributions are welcome! Please fork this repository and submit pull requests. For major changes, please open an issue first to discuss what you would like to change.

### License

This project is licensed under the GNU General Public License v3.0 - see the LICENSE file for details.
