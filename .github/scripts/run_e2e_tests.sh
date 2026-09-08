#!/usr/bin/env bash
# Runs the E2E integration tests against the emulator started by
# reactivecircus/android-emulator-runner in .github/workflows/release.yml.
#
# This lives in its own file rather than an inline `script:` block because
# that action appears to execute each line of a multi-line script value as
# its own separate `sh -c` invocation - a multi-line background subshell
# doesn't survive that, so it's kept here as one real script instead.
set -euo pipefail

PACKAGE=com.wakeywakey.wakeywakey

adb wait-for-device

# Build once and install with every dangerous permission pre-granted via
# `adb install -g`, *before* the app ever runs for the first time. An earlier
# version of this script tried to grant permissions via a background loop
# racing the app's own first launch instead, and lost that race: the app's
# PermissionsManager.requestPermissions() saw the camera permission as not
# yet granted and called Permission.camera.request() for real, which then
# collided with a later test's own request with
# "PlatformException: A request for permissions is already running" (the
# native permission_handler side only allows one request in flight at a
# time, and integration_test runs multiple testWidgets in the same process).
# `flutter test` below re-installs the same already-built APK over this one
# (adb install -r, not an uninstall+reinstall), which preserves permissions
# granted here.
flutter build apk --debug
adb install -r -g build/app/outputs/flutter-apk/app-debug.apk

# SCHEDULE_EXACT_ALARM is a "special" app op, not a normal dangerous
# permission - `-g` at install time doesn't cover it.
adb shell appops set "$PACKAGE" SCHEDULE_EXACT_ALARM allow || true

flutter test integration_test/app_test.dart -d emulator-5554
