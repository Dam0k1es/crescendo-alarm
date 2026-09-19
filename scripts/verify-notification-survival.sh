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
# docs/TODO.md's standing "ignore data loss during the test phase" policy is
# about persisted-data SCHEMA changes, not about this: the maintainer's
# explicit, standing instruction for real-device scripts is that their own
# phone runs production only, never a debug/dev build, and no test may
# replace, rebuild or reinstall anything on it under any circumstance - a
# script that cannot satisfy its precondition against whatever is already
# installed MUST refuse to run, not fall back to installing something else.
#
# This script therefore does NOT build, install or schedule anything. It
# reads whatever is ALREADY scheduled by the production app installed on the
# phone from ordinary use (the sleep reminder gets (re-)scheduled on every
# app-foreground/settings-change checkpoint - see
# lib/models/scheduling/checkpoint.dart), checks it is comfortably far
# enough in the future to survive a reboot without expiring naturally in the
# meantime (this app's sleep reminder is a ONE-SHOT schedule, and a one-shot
# schedule that has already passed is correctly cleaned up on boot - not a
# bug, and not what this script is trying to measure - see the long comment
# above), then reboots and checks whether it is still there.
#
# If nothing is currently scheduled with enough lead time - reminders
# disabled, or the next one is too close - this refuses to run rather than
# creating one. Re-run once a real reminder with more lead time exists
# (nothing to do here: it schedules itself on the app's own next checkpoint).
#
# Why a real phone, not CI: same reasoning as T-93/verify-alarm-survival.sh -
# `flutter test` uninstalls the app afterwards (T-131), and this project's
# dev VM cannot run an emulator reliably (T-94).
#
# The detection itself is NOT in this file, for the same reason as
# verify-alarm-survival.sh: it lives in `.github/scripts/alarm_detection.sh`,
# shared and self-tested there, so a mistake only has to be found once
# (docs/TODO.md T-99/T-103).
#
# Usage:
#   scripts/verify-notification-survival.sh --self-test     # no device needed
#   scripts/verify-notification-survival.sh [--no-reboot] [--yes] [-d <serial>]
#     [--min-lead-minutes N]   # default 30 - refuses to run below this
#
# Exit codes: 0 = ran (see the verdict in the report), 1 = could not measure
# (including: precondition not met - a debug build installed, or nothing
# scheduled far enough out).
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
MIN_LEAD_MINUTES=30

while (( $# )); do
  case "$1" in
    --self-test) SELF_TEST_ONLY=1; shift ;;
    --no-reboot) DO_REBOOT=0; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --package) PACKAGE="${2:?--package needs a name}"; shift 2 ;;
    -d|--device) DEVICE="${2:?-d needs a device serial}"; shift 2 ;;
    --min-lead-minutes) MIN_LEAD_MINUTES="${2:?--min-lead-minutes needs a number}"; shift 2 ;;
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
note "mode: READ-ONLY - nothing is built, installed, scheduled or otherwise changed on the device"

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

# ---------------------------------------------------------------------------
# Precondition 1: the installed app must be a production build, never a
# debug one - checked, not assumed. `android:debuggable` (set automatically
# by every `flutter build apk --debug`, never by a release build) shows up
# in `dumpsys package`'s own flags line.
# ---------------------------------------------------------------------------
if ! adb shell pm path "$PACKAGE" 2>/dev/null | grep -q "package:"; then
  note "ABORT: $PACKAGE is not installed at all. This script never installs"
  note "anything - install the real production build by hand first."
  exit 1
fi

PKG_DUMP="$(adb shell dumpsys package "$PACKAGE" 2>/dev/null | tr -d '\r')"
printf '%s\n' "$PKG_DUMP" | raw "dumpsys package (flags)"
if printf '%s\n' "$PKG_DUMP" | grep -qE 'flags=\[[^]]*\bDEBUGGABLE\b'; then
  note ""
  note "ABORT: the installed app is a DEBUG build (DEBUGGABLE flag set)."
  note "This script refuses to run against anything but the real production"
  note "install - per the maintainer's standing instruction, no test may ever"
  note "replace it with a dev/debug build. Install the production APK by hand"
  note "and re-run."
  exit 1
fi
note "precondition: installed build is production (not debuggable)"

# ---------------------------------------------------------------------------
# Precondition 2: something must already be scheduled, with enough lead time
# to unambiguously still be in the future after a reboot - not created here.
# ---------------------------------------------------------------------------
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

if ! has_scheduled_notification "$PACKAGE" <"$DUMP"; then
  note ""
  note "ABORT: no awesome_notifications schedule found for $PACKAGE right now -"
  note "nothing to measure, and this script does not create one. The sleep"
  note "reminder schedules itself on the app's own next checkpoint (opening"
  note "the app, or a settings change) - make sure it is enabled with a"
  note "bedtime far enough out, then re-run."
  exit 1
fi

ORIGWHEN_MS="$(notification_origwhen_ms "$PACKAGE" <"$DUMP")"
if [[ -z "$ORIGWHEN_MS" ]]; then
  note ""
  note "ABORT: the schedule was found but its target time could not be parsed -"
  note "see the raw excerpt in $OUT. Not measurable without knowing the lead"
  note "time."
  exit 1
fi

# Device clock, not the host's - avoids any host/device clock-skew confound.
DEVICE_NOW_MS="$(adb shell date +%s%3N | tr -d '\r')"
LEAD_MINUTES=$(( (ORIGWHEN_MS - DEVICE_NOW_MS) / 60000 ))
note "scheduled notification target: $LEAD_MINUTES minutes from now (device clock)"

if (( LEAD_MINUTES < MIN_LEAD_MINUTES )); then
  note ""
  note "ABORT: only $LEAD_MINUTES minute(s) of lead time (need >= $MIN_LEAD_MINUTES) -"
  note "too close to call a disappearance after reboot a restore failure rather"
  note "than the schedule simply having reached its own, correct, one-shot"
  note "expiry in the meantime. Not measurable right now; re-run once the next"
  note "scheduled reminder is further out (or pass --min-lead-minutes lower,"
  note "at the cost of that ambiguity)."
  exit 1
fi
note "precondition: lead time is sufficient"

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
  echo ""
  echo "If the phone asks for a PIN/pattern to unlock, do that now."
  echo "awesome_notifications' own restore receiver runs once right after boot"
  echo "(before unlock, while app storage may still be credential-encrypted and"
  echo "inaccessible) and again after the device is actually unlocked - a real"
  echo "run showed the SECOND attempt, ~70s after the first, as the one that"
  echo "actually succeeded (logcat: \"Scheduled created (NotificationScheduler:228)\")."
  if (( ! ASSUME_YES )); then
    read -r -p "Press Enter once the phone is unlocked and at the home screen: " _
  fi

  # Poll rather than a single fixed wait: the restore that matters can be
  # gated on the human actually unlocking the device, not just boot_completed
  # - a fixed 20s sleep measured a real run BEFORE that second, successful
  # attempt and reported a false FAIL (docs/TODO.md T-155).
  RESTORED=0
  RESTORE_ELAPSED=0
  for _ in $(seq 1 18); do
    APP_UID="$(resolve_uid)"
    UID_TOKEN="$(uid_token_for "${APP_UID:-}")"
    adb shell dumpsys alarm 2>/dev/null | tr -d '\r' >"$DUMP"
    if has_scheduled_notification "$PACKAGE" <"$DUMP"; then
      RESTORED=1
      break
    fi
    sleep 10
    RESTORE_ELAPSED=$(( RESTORE_ELAPSED + 10 ))
  done
  dump_context "after reboot (waited ${RESTORE_ELAPSED}s past unlock confirmation)"

  # Always captured, not only on FAIL: this is exactly what showed the T-155
  # "FAIL" was a timing artifact (DartRefreshSchedulesReceiver running twice,
  # only the second, unlock-gated attempt logging "Scheduled created") - worth
  # having on a PASS too, to see how many attempts and how much delay a
  # future run needed.
  adb logcat -d 2>/dev/null \
    | grep -iE "carda|awesome_notif|RefreshSchedules|NotificationScheduler|System\\.err" \
    | raw "logcat (awesome_notifications boot restore)"

  if (( RESTORED )); then
    note "RESULT: PASS - the scheduled notification is registered again after"
    note "the reboot (took up to ${RESTORE_ELAPSED}s after unlock to reappear),"
    note "well before its target time. T-155 closes as 'not a bug'."
  else
    note "RESULT: FAIL - the scheduled notification is still GONE after"
    note "${RESTORE_ELAPSED}s of polling post-unlock, despite $LEAD_MINUTES minutes"
    note "of lead time remaining at measurement start. This is the genuine gap"
    note "T-155 was written to rule out - next step: check"
    note "  adb logcat -d | grep -iE 'carda|awesome_notif|RefreshSchedules|NotificationScheduler|System.err'"
    note "for a swallowed exception (AwesomeBroadcastReceiver.onReceive only"
    note "logs internally via e.printStackTrace(), never surfaces one to this"
    note "app - but that goes through System.err, which does reach logcat)."
  fi
else
  note "--- reboot skipped (--no-reboot) ---"
fi

note "=== end ==="
exit 0
