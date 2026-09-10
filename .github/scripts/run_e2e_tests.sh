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

PACKAGE=com.wakeywakey.wakeywakey
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
# docs/TODO.md T-92: die Geraetezeitzone auf eine Zone MIT Sommerzeit und
# ganzstuendigem Versatz stellen, bevor die App das erste Mal laeuft.
#
# Der Grund ist die dominante Fehlerklasse dieses Projekts: drei echte Bugs
# (docs/TODO.md T-61, T-74d, T-76) waren auf UTC+0 PRINZIPIELL unsichtbar, und
# der Emulator laeuft standardmaessig auf UTC. Ohne diesen Schritt beweist das
# Szenario "T-61: the registered alarm carries the local reading of the planned
# instant" nichts - es waere trivial wahr.
#
# `deviceUtcOffset` im Test zu injizieren reicht dafuer ausdruecklich NICHT:
# dieser Wert wandert nur durch die Domaenenschicht, waehrend
# `alarmPlatformTime` (lib/utils/utils.dart) die echte Geraetezone liest.
adb shell settings put global auto_time_zone 0 || true
adb shell setprop persist.sys.timezone "Europe/Berlin" || true
echo "device timezone now: $(adb shell getprop persist.sys.timezone)" \
  | tee -a "$EVIDENCE_DIR/manifest.log"

flutter build apk --debug
adb install -r -g build/app/outputs/flutter-apk/app-debug.apk

# SCHEDULE_EXACT_ALARM is a "special" app op, not a normal dangerous
# permission - `-g` at install time doesn't cover it.
adb shell appops set "$PACKAGE" SCHEDULE_EXACT_ALARM allow || true

flutter test integration_test/app_test.dart -d emulator-5554 2>&1 | tee "$EVIDENCE_DIR/test_output.log"
TEST_EXIT_CODE=${PIPESTATUS[0]}

# docs/TODO.md T-93 / docs/REQUIREMENTS.md R3: Ueberlebt ein gesetzter Alarm
# einen Reboot? Bis heute unverifiziert - und es ist die letzte offene Frage
# des Produktversprechens "garantiertes Aufwachen".
#
# Der Trick, der das billig und deterministisch macht: NICHT auf ein Klingeln
# warten, sondern `dumpsys alarm` auswerten. Damit ist pruefbar, OB ein Alarm
# registriert ist, ohne Zeit zu verbrauchen.
#
# Bewusst NICHT gatend (kein Einfluss auf TEST_EXIT_CODE): das Verhalten ist
# auf diesem Emulator-Image noch nie gemessen worden, und ein unverifiziertes
# Bein darf keinen Release blockieren. Es sammelt zuerst Beweise; sobald es
# einmal reproduzierbar gruen war, gehoert es scharf gestellt.
# Erst einen Alarm scharf stellen und STEHEN lassen - app_test.dart raeumt in
# tearDown konsequent auf, aus ihm heraus bleibt also nichts registriert.
flutter test integration_test/arm_alarm_test.dart -d emulator-5554 \
  2>&1 | tee "$EVIDENCE_DIR/arm_alarm.log" || true
bash .github/scripts/check_alarm_survival.sh "$PACKAGE" "$EVIDENCE_DIR" || true

# stop_evidence_collection runs via the EXIT trap regardless, but explicitly
# exiting with the real test result here (rather than trusting whatever
# exit status happens to be current when the trap fires) keeps this
# unambiguous.
exit "$TEST_EXIT_CODE"
