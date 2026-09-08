#!/usr/bin/env bash
# Runs the E2E integration tests against the emulator started by
# reactivecircus/android-emulator-runner in .github/workflows/release.yml.
#
# This lives in its own file rather than an inline `script:` block because
# that action appears to execute each line of a multi-line script value as
# its own separate `sh -c` invocation - a multi-line background subshell
# (`( ... ) &`) doesn't survive that, so it's kept here as one real script
# instead.
set -euo pipefail

adb wait-for-device

# flutter test (run at the bottom of this script) builds, installs, and runs
# the app - grant the permissions PermissionsManager.requestPermissions()
# will ask for as soon as the package actually appears, in the background, so
# the real run never hits an OS permission dialog.
(
  for _ in $(seq 1 120); do
    if adb shell pm list packages | grep -q com.wakeywakey.wakeywakey; then
      adb shell pm grant com.wakeywakey.wakeywakey android.permission.CAMERA || true
      adb shell pm grant com.wakeywakey.wakeywakey android.permission.READ_CALENDAR || true
      adb shell pm grant com.wakeywakey.wakeywakey android.permission.WRITE_CALENDAR || true
      adb shell pm grant com.wakeywakey.wakeywakey android.permission.POST_NOTIFICATIONS || true
      adb shell appops set com.wakeywakey.wakeywakey SCHEDULE_EXACT_ALARM allow || true
      break
    fi
    sleep 2
  done
) &

flutter test integration_test/app_test.dart -d emulator-5554
