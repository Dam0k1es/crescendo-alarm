#!/usr/bin/env bash
# Runs the E2E integration tests against the emulator started by
# reactivecircus/android-emulator-runner in .github/workflows/e2e-tests.yml,
# while collecting evidence of the run: a segmented screen recording (video,
# no audio - see EVIDENCE.md note below), a coarse audio-focus timeline, and
# the raw test output. Everything lands in $EVIDENCE_DIR, which the workflow
# uploads as a build artifact.
#
# This lives in its own file rather than an inline `script:` block because
# that action appears to execute each line of a multi-line script value as
# its own separate `sh -c` invocation - a multi-line background subshell
# doesn't survive that, so it's kept here as one real script instead.
set -uo pipefail

PACKAGE=com.crescendoalarm.crescendoalarm
EVIDENCE_DIR="${EVIDENCE_DIR:-e2e_evidence}"
mkdir -p "$EVIDENCE_DIR"
MANIFEST="$EVIDENCE_DIR/manifest.log"
: > "$MANIFEST"

cat > "$EVIDENCE_DIR/README.md" <<'EOF'
# E2E run evidence

- `recording_*.mp4`: screen recording, split into ~170s segments (Android's
  `screenrecord` can't record longer than ~3 minutes in one invocation).
  Play them in order. No audio track - the emulator runs with `-noaudio`,
  and `adb shell screenrecord` cannot capture device audio output even when
  present (a long-standing limitation of the tool itself, not a
  configuration choice made here).
- `audio_focus.log`: a timestamped poll of `dumpsys audio`'s active audio
  focus holder, taken every ~3s for the whole run. Cross-reference its
  timestamps against the video to see that something actually requested
  audio focus while an alarm was ringing - an indirect proxy for "the alarm
  sound really would have played", since the recording itself carries no
  audio.
- `test_output.log`: the raw `flutter test` output for this run.
- `manifest.log`: what evidence collection actually managed to capture,
  including any segments that failed - segment failures don't fail the job
  (evidence gaps shouldn't block a real test result), so this is the only
  record of them; check it before trusting "the recording" as complete.
- `activity_manager.log`: raw `ActivityManager` logcat output for the whole
  run. A prior run's evidence video showed a system "Process system isn't
  responding" dialog throughout the test window (docs/TODO.md T-25) that the
  tests themselves never noticed (`integration_test` drives the widget tree,
  not the visible screen) - this makes that condition explicit instead of
  something only visible by scrubbing through a video nobody opens. The job
  summary reports whether an ANR was detected in this log.
EOF

adb wait-for-device

# Health check, before anything gets measured (docs/TODO.md T-129).
#
# `adb wait-for-device` already returns once the device entry exists - not
# only once the system is actually usable. In run 34622327599 the adb
# daemon never came up at all ("Unable to connect to adb daemon on port:
# 5037", then "device 'emulator-5554' not found"), the run proceeded
# anyway, and later failed on an assertion that looks like a product bug:
# "Alarm … was created in AppState but never reached the native alarm
# plugin". That it wasn't one could only be shown by the fact that `lib/`
# was byte-identical to the previous, green run.
#
# A piece of evidence that reports an environment glitch as a product bug
# is worse than one that finds nothing. Hence abort here, with a message
# that leaves no room for confusion.
for _ in $(seq 1 60); do
  if [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
    break
  fi
  sleep 5
done
BOOTED=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
if [ "$BOOTED" != "1" ]; then
  echo "::error::EMULATOR NOT USABLE - sys.boot_completed='$BOOTED'."
  echo "::error::This is an environment glitch, NOT a test result."
  adb devices -l || true
  exit 1
fi
echo "emulator ready: sys.boot_completed=1, $(adb shell getprop ro.build.version.sdk | tr -d '\r') as API level"

adb logcat -c # clear any backlog so this only captures the run below
adb logcat 'ActivityManager:I' '*:S' >"$EVIDENCE_DIR/activity_manager.log" 2>&1 &
LOGCAT_PID=$!

# --- Start background evidence collection ---

STOP_FILE=$(mktemp)
rm -f "$STOP_FILE" # only its (non-)existence is used as the stop signal

record_segments() {
  local n=0
  while [ ! -e "$STOP_FILE" ]; do
    local device_path="/sdcard/recording_$n.mp4"
    if ! adb shell screenrecord --time-limit 170 --bit-rate 4000000 "$device_path"; then
      echo "recording_$n.mp4: screenrecord failed (device likely not ready yet)" >>"$MANIFEST"
      adb shell rm -f "$device_path" || true
      n=$((n + 1))
      continue
    fi
    if adb pull "$device_path" "$EVIDENCE_DIR/recording_$n.mp4" >/dev/null 2>&1; then
      echo "recording_$n.mp4: collected" >>"$MANIFEST"
    else
      echo "recording_$n.mp4: screenrecord succeeded but adb pull failed" >>"$MANIFEST"
    fi
    adb shell rm -f "$device_path" || true
    n=$((n + 1))
  done
}

poll_audio_focus() {
  while [ ! -e "$STOP_FILE" ]; do
    {
      echo "--- $(date -u +%Y-%m-%dT%H:%M:%SZ) ---"
      adb shell dumpsys audio 2>/dev/null | grep -A3 "Audio Focus stack entries" || echo "(no focus info)"
    } >>"$EVIDENCE_DIR/audio_focus.log"
    sleep 3
  done
}

record_segments &
RECORD_PID=$!
poll_audio_focus &
AUDIO_PID=$!

stop_evidence_collection() {
  touch "$STOP_FILE"
  wait "$RECORD_PID" 2>/dev/null || true
  wait "$AUDIO_PID" 2>/dev/null || true
  rm -f "$STOP_FILE"
  kill "$LOGCAT_PID" 2>/dev/null || true
  wait "$LOGCAT_PID" 2>/dev/null || true

  local anr_count=0
  if [ -f "$EVIDENCE_DIR/activity_manager.log" ]; then
    anr_count=$(grep -c "ANR in" "$EVIDENCE_DIR/activity_manager.log" || true)
  fi

  # Make what was actually collected visible without opening the artifact -
  # both in the plain job log and, more prominently, the run's summary page.
  {
    echo "## E2E evidence collected"
    echo
    if [ "$anr_count" -gt 0 ]; then
      echo "**ANR detected: $anr_count occurrence(s) in activity_manager.log** (docs/TODO.md T-25)"
    else
      echo "No ANR detected in activity_manager.log."
    fi
    echo
    echo '```'
    ls -la "$EVIDENCE_DIR" 2>/dev/null
    echo '```'
    if [ -s "$MANIFEST" ]; then
      echo
      echo "Recording manifest:"
      echo '```'
      cat "$MANIFEST"
      echo '```'
    fi
  } | tee -a "$GITHUB_STEP_SUMMARY" >/dev/null 2>&1 || true
}
trap stop_evidence_collection EXIT

# --- Build, install, and run the actual tests ---

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
# docs/TODO.md T-92: set the device timezone to a zone WITH daylight saving
# and a whole-hour offset before the app runs for the first time.
#
# The reason is this project's dominant bug class: three real bugs
# (docs/TODO.md T-61, T-74d, T-76) were STRUCTURALLY invisible at UTC+0, and
# the emulator runs on UTC by default. Without this step, the scenario
# "T-61: the registered alarm carries the local reading of the planned
# instant" proves nothing - it would be trivially true.
#
# Injecting `deviceUtcOffset` in the test explicitly does NOT suffice for
# this: that value only travels through the domain layer, while
# `alarmPlatformTime` (lib/utils/utils.dart) reads the real device zone.
# `setprop persist.sys.timezone` as a normal shell user has no effect - in
# the first run with this line, the evidence still showed `Etc/UTC`
# afterward (docs/TODO.md T-99). On a google_apis image (no Play Store)
# this can be fixed via `adb root`; the feedback below says whether it
# worked.
adb root >/dev/null 2>&1 || true
adb wait-for-device
adb shell settings put global auto_time_zone 0 || true
adb shell su 0 setprop persist.sys.timezone "Europe/Berlin" 2>/dev/null \
  || adb shell setprop persist.sys.timezone "Europe/Berlin" || true
DEVICE_TZ=$(adb shell getprop persist.sys.timezone | tr -d '\r')
echo "device timezone now: $DEVICE_TZ" | tee -a "$EVIDENCE_DIR/manifest.log"
if [[ "$DEVICE_TZ" != "Europe/Berlin" ]]; then
  # Deliberately just a warning, not an abort: the suite is also valid on
  # UTC - only the T-61 scenario proves nothing there, because its
  # assertion becomes trivially true. That has to show up in the evidence
  # rather than pass silently.
  echo "WARNING: device timezone is '$DEVICE_TZ', not Europe/Berlin - the T-61" \
    "scenario is VACUOUS in this run (see docs/TODO.md T-99)." \
    | tee -a "$EVIDENCE_DIR/manifest.log"
  echo "::warning::Emulator timezone is $DEVICE_TZ, not Europe/Berlin - the T-61 frame scenario proves nothing in this run."
fi

flutter build apk --debug
adb install -r -g build/app/outputs/flutter-apk/app-debug.apk

# SCHEDULE_EXACT_ALARM is a "special" app op, not a normal dangerous
# permission - `-g` at install time doesn't cover it.
adb shell appops set "$PACKAGE" SCHEDULE_EXACT_ALARM allow || true

flutter test integration_test/app_test.dart -d emulator-5554 2>&1 | tee "$EVIDENCE_DIR/test_output.log"
TEST_EXIT_CODE=${PIPESTATUS[0]}

# docs/TODO.md T-62: does scheduling a title/body-less NotificationContent
# actually fire onNotificationCreatedMethod, on a real/emulated device?
# FR-16's own spec text calls this "verified from the package source, high
# confidence" but recommends a device confirmation before relying on it -
# there was none until this ran. Deliberately NOT gating on the first runs
# (no effect on TEST_EXIT_CODE), same reasoning as the alarm-survival leg
# below: this exact mechanism has never been measured on this emulator
# image before, and an unverified leg must not block a release.
flutter test integration_test/silent_notification_test.dart -d emulator-5554 \
  2>&1 | tee "$EVIDENCE_DIR/silent_notification.log" || true

# docs/TODO.md T-93 / docs/REQUIREMENTS.md R3: does a set alarm survive a
# reboot? Unverified to this day - and it's the last open question of the
# "guaranteed wake-up" product promise.
#
# The trick that makes this cheap and deterministic: NOT waiting for a
# ring, but evaluating `dumpsys alarm` instead. That way it's checkable
# WHETHER an alarm is registered, without spending any time.
#
# Deliberately NOT gating (no effect on TEST_EXIT_CODE): this behaviour has
# never been measured on this emulator image before, and an unverified leg
# must not block a release. It gathers evidence first; once it has been
# reproducibly green, it belongs gated for real.
# First arm an alarm and LEAVE it standing - app_test.dart consistently
# cleans up in tearDown, so nothing stays registered coming out of it.
flutter test integration_test/arm_alarm_test.dart -d emulator-5554 \
  2>&1 | tee "$EVIDENCE_DIR/arm_alarm.log" || true
bash .github/scripts/check_alarm_survival.sh "$PACKAGE" "$EVIDENCE_DIR" || true

# stop_evidence_collection runs via the EXIT trap regardless, but explicitly
# exiting with the real test result here (rather than trusting whatever
# exit status happens to be current when the trap fires) keeps this
# unambiguous.
exit "$TEST_EXIT_CODE"
