#!/usr/bin/env bash
# docs/TODO.md T-155: does a scheduled awesome_notifications notification
# (the sleep-time reminder's own FR-16 Checkpoint 2 hook) survive a reboot,
# the same way the `alarm` plugin's own ringing alarms already do (T-93)?
#
# Why this is a real, open question and not a duplicate of T-93: a real
# Fairphone 6 run gathering T-93's evidence incidentally showed the app's
# `awesome_notifications`-scheduled entries gone after a reboot, while its
# `alarm`-plugin entries survived and were correctly re-planned. Reading
# awesome_notifications' actual native boot-restore code
# (RefreshSchedulesReceiver -> NotificationScheduler.refreshScheduledNotifications,
# github.com/rafaelsetragni/AndroidAwnCore) found it unconditionally re-arms
# any schedule whose `hasNextValidDate()` is still true, and only removes
# ones that have genuinely expired - correct cleanup, not a failure. Since
# this app's sleep reminder is scheduled as a ONE-SHOT date, not a repeating
# schedule, the earlier observation is equally consistent with "the
# reminder's target time had already passed by the time of that reboot" (not
# a bug) as with "the restore genuinely failed" (a real bug) - the captured
# evidence could not tell those apart.
#
# This script settles it: schedule a notification hours out (so it is
# unambiguously still in the future at measurement time), reboot, and check
# whether it is still registered.
#
# Why a real phone, not CI: same reasoning as T-93/verify-alarm-survival.sh -
# `flutter test` uninstalls the app afterwards (T-131), and this project's
# dev VM cannot run an emulator reliably (T-94).
#
# Unlike verify-alarm-survival.sh, this does not need a pre-built --apk or
# any UI automation: `flutter test integration_test/... -d <device>` builds,
# installs and runs the arming step itself, and scheduling a notification is
# a plain Dart call, not something that needs to go through app screens.
# Needs a Flutter-capable checkout on this machine (not just an APK), with
# `flutter pub get` already run.
#
# The detection itself is NOT in this file, for the same reason as
# verify-alarm-survival.sh: it lives in `.github/scripts/alarm_detection.sh`,
# shared and self-tested there, so a mistake only has to be found once
# (docs/TODO.md T-99/T-103).
#
# Usage:
#   scripts/verify-notification-survival.sh --self-test     # no device needed
#   scripts/verify-notification-survival.sh [--no-reboot] [--yes] [-d <serial>]
#
# Exit codes: 0 = ran (see the verdict in the report), 1 = could not measure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
# shellcheck disable=SC2034  # used by alarm_detection.sh's self_test(), not directly here
FIXTURES="$REPO/.github/scripts/fixtures"
# shellcheck source=.github/scripts/alarm_detection.sh
source "$REPO/.github/scripts/alarm_detection.sh"

PACKAGE="com.wakeywakey.wakeywakey"
DO_REBOOT=1
ASSUME_YES=0
SELF_TEST_ONLY=0
DEVICE=""

while (( $# )); do
  case "$1" in
    --self-test) SELF_TEST_ONLY=1; shift ;;
    --no-reboot) DO_REBOOT=0; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --package) PACKAGE="${2:?--package needs a name}"; shift 2 ;;
    -d|--device) DEVICE="${2:?-d needs a device serial}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

if (( SELF_TEST_ONLY )); then
  self_test
  exit $?
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="$REPO/evidence/notification-survival-$STAMP"
mkdir -p "$EVIDENCE_DIR"
OUT="$EVIDENCE_DIR/notification_survival.log"

note() { echo "$@" | tee -a "$OUT"; }
raw()  { { echo "--- $1 ---"; cat; } >>"$OUT" 2>&1; }

note "=== notification-schedule survival on a real device ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="
note "package: $PACKAGE"
note "evidence: $EVIDENCE_DIR"

# The instrument proves itself before it measures anything (T-103).
if ! self_test >>"$OUT" 2>&1; then
  note "ABORT: the detection self-test failed - nothing was measured."
  exit 1
fi
note "self-test: detection ok"

# ---------------------------------------------------------------------------
# Device
# ---------------------------------------------------------------------------
if [[ -z "$DEVICE" ]]; then
  mapfile -t DEVICES < <(adb devices | awk 'NR>1 && $2=="device" {print $1}')
  if (( ${#DEVICES[@]} == 0 )); then
    note "ABORT: no device. Connect the phone by USB, allow USB debugging on it,"
    note "and check with 'adb devices' that it shows up as 'device' and not as"
    note "'unauthorized'."
    exit 1
  fi
  if (( ${#DEVICES[@]} > 1 )); then
    note "ABORT: ${#DEVICES[@]} devices connected - pass -d <serial> to pick one."
    exit 1
  fi
  DEVICE="${DEVICES[0]}"
fi
export ANDROID_SERIAL="$DEVICE"
note "device: $DEVICE ($(adb shell getprop ro.product.model | tr -d '\r'), Android $(adb shell getprop ro.build.version.release | tr -d '\r'))"

# SCHEDULE_EXACT_ALARM is a "special" app op; POST_NOTIFICATIONS is a normal
# dangerous permission granted at install time on most OS versions - neither
# is forced here, since a real phone previously used for this app should
# already have both from ordinary use. If scheduling silently fails below,
# check these first.
adb shell appops set "$PACKAGE" SCHEDULE_EXACT_ALARM allow || true

# ---------------------------------------------------------------------------
# Arm: schedule a notification several hours out, through the app's own
# code (not through the UI - scheduling is a plain Dart call, nothing here
# depends on which screen is showing).
# ---------------------------------------------------------------------------
note "--- scheduling a notification 6 hours out ---"
(
  cd "$REPO" \
    && flutter test integration_test/schedule_long_notification_test.dart -d "$DEVICE"
) 2>&1 | tee -a "$EVIDENCE_DIR/schedule_test.log"
SCHEDULE_EXIT_CODE=${PIPESTATUS[0]}
if (( SCHEDULE_EXIT_CODE != 0 )); then
  note "ABORT: scheduling the test notification failed (exit $SCHEDULE_EXIT_CODE) -"
  note "see $EVIDENCE_DIR/schedule_test.log. Nothing was armed to measure."
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
trap 'rm -f "$DUMP"' EXIT
dump_context() {
  {
    echo "--- dumpsys alarm (this app, $1) ---"
    grep -E "${PACKAGE}|com\\.gdelataillade\\.alarm|me\\.carda\\.awesome_notifications${UID_TOKEN:+|${UID_TOKEN}}" "$DUMP" | head -40
  } >>"$OUT" 2>&1
}

adb shell dumpsys alarm 2>/dev/null | tr -d '\r' >"$DUMP"
dump_context "before"
if has_scheduled_notification "$PACKAGE" <"$DUMP"; then
  note "confirmed: the scheduled notification reached AlarmManager"
else
  note ""
  note "RESULT: not measurable - the notification was reported as scheduled,"
  note "but does not appear in AlarmManager. This is a measurement gap, NOT a"
  note "finding: check POST_NOTIFICATIONS/SCHEDULE_EXACT_ALARM are granted and"
  note "re-run."
  exit 1
fi

if (( DO_REBOOT )); then
  if (( ! ASSUME_YES )); then
    echo ""
    echo "About to REBOOT $DEVICE. Unlock it afterwards if it asks for a PIN."
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
  # Give awesome_notifications' own BOOT_COMPLETED receiver time to run its
  # native restore pass (RefreshSchedulesReceiver) before checking.
  sleep 20

  APP_UID="$(resolve_uid)"
  UID_TOKEN="$(uid_token_for "${APP_UID:-}")"
  adb shell dumpsys alarm 2>/dev/null | tr -d '\r' >"$DUMP"
  dump_context "after reboot"

  if has_scheduled_notification "$PACKAGE" <"$DUMP"; then
    note "RESULT: PASS - the scheduled notification is still registered after"
    note "the reboot. T-155 closes as 'not a bug' - the earlier observation"
    note "was the notification's own one-shot target time having already"
    note "passed, not a restore failure."
  else
    note "RESULT: FAIL - the scheduled notification is GONE after the reboot,"
    note "despite its target time (6 hours out) still being well in the"
    note "future. This is the genuine gap T-155 was written to rule out -"
    note "next step: check for a silently swallowed exception in"
    note "AwesomeBroadcastReceiver.onReceive (every exception there is only"
    note "logged internally, never surfaced to this app)."
  fi
else
  note "--- reboot skipped (--no-reboot) ---"
fi

note "=== end ==="
exit 0
