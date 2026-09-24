#!/usr/bin/env bash
# R3 / docs/TODO.md T-04 + T-93: does an armed alarm survive a reboot and a
# force-stop? Measured against a REAL phone over USB - no GitHub Actions, no
# emulator.
#
# Why this exists next to `.github/scripts/check_alarm_survival.sh`, which asks
# the same question: that one runs inside the CI E2E job, and there the question
# is structurally unanswerable (docs/TODO.md T-131). `flutter test` installs the
# app for the run and removes it afterwards, and Android discards a package's
# AlarmManager entries along with the package - so at measurement time there can
# be no alarm registered, whatever the search pattern does. Two runs were
# misread as a pattern problem before that was understood.
#
# Nor can it be answered on this project's dev VM: the Android emulator is
# unreliable under its nested virtualisation, and running two emulators once
# left kernel threads stuck in D-state until a reboot (docs/TODO.md T-94).
#
# What is left is the maintainer's own phone, and it is the better instrument
# anyway: it is a real vendor image with real battery optimisation, which is
# exactly where alarm delivery is decided. It costs one reboot.
#
# The counting itself is NOT in this file. It lives in
# `.github/scripts/alarm_detection.sh` together with its self-test, because a
# second copy would be a second chance to repeat T-99/T-103 - a verdict about
# alarms that had counted somebody else's.
#
# Usage:
#   scripts/verify-alarm-survival.sh --self-test        # no device needed
#   scripts/verify-alarm-survival.sh [--apk current.apk] [--no-reboot] [--yes]
#
# Exit codes: 0 = ran (see the verdict in the report), 1 = could not measure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
FIXTURES="$REPO/.github/scripts/fixtures"
# shellcheck source=.github/scripts/alarm_detection.sh
source "$REPO/.github/scripts/alarm_detection.sh"
# shellcheck source=.github/scripts/ui_tap.sh
source "$REPO/.github/scripts/ui_tap.sh"

PACKAGE="com.wakeywakey.wakeywakey"
APK=""
DO_REBOOT=1
ASSUME_YES=0
SELF_TEST_ONLY=0

while (( $# )); do
  case "$1" in
    --self-test) SELF_TEST_ONLY=1; shift ;;
    --apk) APK="${2:?--apk needs a path}"; shift 2 ;;
    --no-reboot) DO_REBOOT=0; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --package) PACKAGE="${2:?--package needs a name}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

if (( SELF_TEST_ONLY )); then
  self_test && ui_self_test
  exit $?
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="$REPO/evidence/alarm-survival-$STAMP"
mkdir -p "$EVIDENCE_DIR"
OUT="$EVIDENCE_DIR/alarm_survival.log"

note() { echo "$@" | tee -a "$OUT"; }
raw()  { { echo "--- $1 ---"; cat; } >>"$OUT" 2>&1; }

note "=== alarm survival on a real device ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="
note "package: $PACKAGE"
note "evidence: $EVIDENCE_DIR"

# The instrument proves itself before it measures anything (T-103).
if ! self_test >>"$OUT" 2>&1; then
  note "ABORT: the detection self-test failed - nothing was measured."
  exit 1
fi
if ! ui_self_test >>"$OUT" 2>&1; then
  note "ABORT: the UI self-test failed - the taps would land on nothing."
  exit 1
fi
note "self-tests: detection ok, tap locating ok"

# ---------------------------------------------------------------------------
# Device
# ---------------------------------------------------------------------------
mapfile -t DEVICES < <(adb devices | awk 'NR>1 && $2=="device" {print $1}')
if (( ${#DEVICES[@]} == 0 )); then
  note "ABORT: no device. Connect the phone by USB, allow USB debugging on it,"
  note "and check with 'adb devices' that it shows up as 'device' and not as"
  note "'unauthorized'."
  exit 1
fi
if (( ${#DEVICES[@]} > 1 )); then
  note "ABORT: ${#DEVICES[@]} devices connected - refusing to guess which phone"
  note "to reboot. Disconnect all but one."
  exit 1
fi
export ANDROID_SERIAL="${DEVICES[0]}"
note "device: $ANDROID_SERIAL ($(adb shell getprop ro.product.model | tr -d '\r'), Android $(adb shell getprop ro.build.version.release | tr -d '\r'))"

if [[ -n "$APK" ]]; then
  note "installing $APK ..."
  adb install -r "$APK" 2>&1 | raw "adb install"
fi

if ! adb shell pm path "$PACKAGE" 2>/dev/null | grep -q "package:"; then
  note "ABORT: $PACKAGE is not installed. Pass --apk current.apk, or install it"
  note "by hand first. (An uninstalled package has no AlarmManager entries, so"
  note "there would be nothing to measure - that is exactly the blind spot the"
  note "CI leg ran into, docs/TODO.md T-131.)"
  exit 1
fi

resolve_uid() {
  local raw_line uid
  raw_line=$(adb shell pm list packages -U 2>&1 | tr -d '\r' | grep -F "$PACKAGE" | head -5)
  printf '%s\n' "$raw_line" | raw "uid attempt 1: pm list packages -U"
  uid=$(printf '%s\n' "$raw_line" | grep -oE "uid:[0-9]+" | head -1 | cut -d: -f2)
  [[ -n "$uid" ]] && { printf '%s' "$uid"; return; }
  uid=$(adb shell dumpsys package "$PACKAGE" 2>/dev/null | tr -d '\r' \
    | grep -oE "(userId|appId)=[0-9]+" | head -1 | cut -d= -f2)
  [[ -n "$uid" ]] && { printf '%s' "$uid"; return; }
  adb shell "stat -c %u /data/data/$PACKAGE" 2>/dev/null | tr -d '\r' | grep -oE '^[0-9]+$' | head -1
}

APP_UID="$(resolve_uid)"
UID_TOKEN="$(uid_token_for "${APP_UID:-}")"
note "app uid: ${APP_UID:-<unresolved>}  token: ${UID_TOKEN:-<none>}"

DUMP="$(mktemp)"
trap 'rm -f "$DUMP" /tmp/ww_ui.xml' EXIT
count_alarms() {
  adb shell dumpsys alarm 2>/dev/null | tr -d '\r' >"$DUMP"
  count_app_alarms "$PACKAGE" "$UID_TOKEN" "$DUMP"
}
dump_context() {
  {
    echo "--- dumpsys alarm (this app, $1) ---"
    grep -E "${PACKAGE}|com\\.gdelataillade\\.alarm${UID_TOKEN:+|${UID_TOKEN}}" "$DUMP" | head -40
    echo "--- broad context, NOT counted ($1) ---"
    grep -iE "RTC_WAKEUP|Pending alarms per uid" "$DUMP" | head -20
  } >>"$OUT" 2>&1
}

# ---------------------------------------------------------------------------
# Arming the alarm through the app's own UI
#
# Through the UI on purpose: the question is whether an alarm THE APP set
# survives, so anything that pokes the platform directly would measure the
# wrong thing. The taps are located through the accessibility tree
# (`uiautomator dump`), not through fixed coordinates, so the script does not
# depend on this one phone's screen size.
#
# The created alarm lands roughly 24 hours out: the dialog pre-fills the
# current time, and AppState moves a time that is not still ahead to the next
# day. So nothing rings during the measurement.
#
# node_center/ui_dump/tap_label/ui_self_test come from ui_tap.sh (sourced
# above) - shared with scripts/verify-long-idle-alarm-survival.sh.
# ---------------------------------------------------------------------------

note "--- launching the app ---"
adb shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>&1 | raw "launch"
sleep 6

note "--- arming an alarm through the UI ---"
MISSED_TAPS=0
for label in "Manual" "Add A New Alarm" "Save"; do
  tap_label "$label" || MISSED_TAPS=$(( MISSED_TAPS + 1 ))
done
(( MISSED_TAPS )) && note "  $MISSED_TAPS of 3 taps could not be located"

BEFORE="$(count_alarms)"
note "registered alarms before the intervention: $BEFORE"
dump_context "before"

if [[ "$BEFORE" == "0" ]]; then
  note ""
  note "RESULT: not measurable - no alarm of this app is registered even BEFORE"
  note "anything was done to the device. This is a measurement gap, NOT a"
  note "finding: do not read it as 'the alarm did not survive'."
  note ""
  note "What to check, in this order:"
  note " 1. Did the UI automation reach the dialog? The taps are logged above;"
  note "    a missing node is logged with the whole accessibility tree."
  note " 2. Is the alarm permission granted? Android 12+ needs SCHEDULE_EXACT_ALARM,"
  note "    and notifications need POST_NOTIFICATIONS."
  note " 3. Arm an alarm BY HAND in the app and run this script again with"
  note "    --no-reboot: it then only reads, and you see whether the counting"
  note "    sees your alarm."
  exit 1
fi

if (( DO_REBOOT )); then
  if (( ! ASSUME_YES )); then
    echo ""
    echo "About to REBOOT $ANDROID_SERIAL. Unlock it afterwards if it asks for a PIN."
    read -r -p "Continue? [y/N] " answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] || { note "aborted by the user before the reboot"; exit 1; }
  fi

  note "--- rebooting ---"
  adb reboot
  adb wait-for-device
  for _ in $(seq 1 180); do
    [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]] && break
    sleep 2
  done
  note "boot_completed: $(adb shell getprop sys.boot_completed | tr -d '\r')"
  # Give the plugin's BootReceiver time to re-arm the stored alarms.
  sleep 20

  APP_UID="$(resolve_uid)"
  UID_TOKEN="$(uid_token_for "${APP_UID:-}")"
  AFTER_REBOOT="$(count_alarms)"
  note "registered alarms after the reboot: $AFTER_REBOOT"
  dump_context "after reboot"

  if [[ "$AFTER_REBOOT" == "0" ]]; then
    note "RESULT reboot: FAIL - registered before, gone after. This one IS a"
    note "finding against R3."
  else
    note "RESULT reboot: PASS - alarms are registered again after boot."
  fi
else
  note "--- reboot skipped (--no-reboot) ---"
fi

note "--- force-stop ---"
adb shell am force-stop "$PACKAGE"
sleep 5
AFTER_FORCE_STOP="$(count_alarms)"
note "registered alarms after the force-stop: $AFTER_FORCE_STOP"
dump_context "after force-stop"

if [[ "$AFTER_FORCE_STOP" == "0" ]]; then
  note "RESULT force-stop: alarms gone. Expected - Android cancels a"
  note "force-stopped package's alarms, and the package receives no"
  note "BOOT_COMPLETED afterwards until the user opens it again. This is a"
  note "platform boundary that belongs in R3 as a limit, not a defect of this app."
else
  note "RESULT force-stop: alarms still registered ($AFTER_FORCE_STOP)."
fi

note ""
note "NOTE: the app was force-stopped last, so its alarms are gone now. Open it"
note "once on the phone to get your real alarms back."
note "=== end ==="
exit 0
