#!/usr/bin/env bash
# Runs the E2E integration tests against the emulator started by
# reactivecircus/android-emulator-runner in .github/workflows/release.yml,
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

PACKAGE=com.wakeywakey.wakeywakey
EVIDENCE_DIR="${EVIDENCE_DIR:-e2e_evidence}"
mkdir -p "$EVIDENCE_DIR"

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
EOF

adb wait-for-device

# --- Start background evidence collection ---

STOP_FILE=$(mktemp)
rm -f "$STOP_FILE" # only its (non-)existence is used as the stop signal

record_segments() {
  local n=0
  while [ ! -e "$STOP_FILE" ]; do
    local device_path="/sdcard/recording_$n.mp4"
    adb shell screenrecord --time-limit 170 --bit-rate 4000000 "$device_path" || true
    adb pull "$device_path" "$EVIDENCE_DIR/recording_$n.mp4" >/dev/null 2>&1 || true
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
flutter build apk --debug
adb install -r -g build/app/outputs/flutter-apk/app-debug.apk

# SCHEDULE_EXACT_ALARM is a "special" app op, not a normal dangerous
# permission - `-g` at install time doesn't cover it.
adb shell appops set "$PACKAGE" SCHEDULE_EXACT_ALARM allow || true

flutter test integration_test/app_test.dart -d emulator-5554 2>&1 | tee "$EVIDENCE_DIR/test_output.log"
TEST_EXIT_CODE=${PIPESTATUS[0]}

# stop_evidence_collection runs via the EXIT trap regardless, but explicitly
# exiting with the real test result here (rather than trusting whatever
# exit status happens to be current when the trap fires) keeps this
# unambiguous.
exit "$TEST_EXIT_CODE"
