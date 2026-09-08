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
- **iOS** has project scaffolding but has never actually been built or run - treat it as
  unverified, not supported, until someone with a Mac/Xcode does that work.

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

### Usage

- Open Wakey Wakey on your mobile device.
- Allow the app to sync with your calendar.
- Set up your alarm preferences and add necessary QR codes in remote locations.
- Enjoy a more reliable and interactive waking experience.

### Quality & Testing

Every change is automatically checked (static analysis, dependency/secret scanning) and tested,
including end-to-end tests on a real Android emulator that must pass before a signed release build
is produced. See [`CLAUDE.md`](CLAUDE.md) for exactly which checks run where, how to run them
locally, and the current, honest testing status - and [`docs/TODO.md`](docs/TODO.md) for the known
gaps in that coverage.

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

Copyright (C) 2026 Dam0k1es. Licensed under the GNU General Public License v3.0 - see the
[LICENSE](LICENSE) file for the full text.
