#!/usr/bin/env bash
# R3 / docs/TODO.md T-04, T-93, T-164: does an armed alarm survive a reboot
# AND a force-stop over a genuinely long, untouched idle stretch - the app
# never reopened in between? That is the one scenario neither
# scripts/verify-alarm-survival.sh nor the CI leg can answer, because both
# only check *registration* a few seconds after the intervention. Whether the
# alarm actually rings, roughly a day later, with nobody having touched the
# phone in between, can only be confirmed by leaving it alone and coming
# back - so this script is split into two commands instead of one that would
# have to sleep for a day.
#
# `arm` reuses exactly the same UI-driven arming (~24h out, by not touching
# the pre-filled time and letting AppState roll it to the next day) and the
# same shared alarm-counting/tap-locating modules as
# scripts/verify-alarm-survival.sh - see that script's own header for why
# those live in .github/scripts/ and are never duplicated. It then reboots,
# waits for boot, force-stops, and stops there: the combination is the worst
# realistic case (an OTA reboot overnight, or the OS reclaiming memory by
# force-stopping an unused app) in one run, and directly targets T-93's own
# unresolved contradiction - one real-device run said force-stop loses the
# alarm, a later one said it survives.
#
# `check` is run separately, after the printed due time has passed, with the
# phone having sat untouched the whole time. It re-reads `dumpsys alarm` as a
# weak corroborating signal only (a one-shot alarm removes its own
# registration once it fires, so "gone" is consistent with - but not proof
# of - actually ringing), then asks directly whether the phone rang: the same
# standard every other real-device confirmation in this project was measured
# against (docs/TODO.md T-04/T-158), not a new automated detection pattern -
# see .github/scripts/alarm_detection.sh's own header for why inventing one
# under time pressure is a real, already-repeated risk here (T-99/T-103).
#
# Usage:
#   scripts/verify-long-idle-alarm-survival.sh --self-test
#   scripts/verify-long-idle-alarm-survival.sh arm [--apk PATH] [--yes]
#   scripts/verify-long-idle-alarm-survival.sh check <evidence-dir> [--force]
#
# Exit codes: 0 = ran (see the verdict on screen/in the log), 1 = could not
# measure, was aborted, or was run too early.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
FIXTURES="$REPO/.github/scripts/fixtures"
# shellcheck source=.github/scripts/alarm_detection.sh
source "$REPO/.github/scripts/alarm_detection.sh"
# shellcheck source=.github/scripts/ui_tap.sh
source "$REPO/.github/scripts/ui_tap.sh"

PACKAGE="com.wakeywakey.wakeywakey"

# How long the alarm must sit untouched before `check` is meaningful. Not a
# command-line option on purpose: shorter defeats the point of this script -
# scripts/verify-alarm-survival.sh already shows registration survives a few
# seconds in - and the actual target is "at least a full day, the way a
# shift worker's phone would realistically sit idle between shifts"
# (docs/TODO.md T-164).
MIN_IDLE_SECONDS=$(( 24 * 3600 ))

# Pure, no `adb` - checkable offline via --self-test.
enough_time_passed() {
  local armed_epoch="$1" now_epoch="$2"
  (( now_epoch - armed_epoch >= MIN_IDLE_SECONDS ))
}

self_test_time_math() {
  local failed=0
  enough_time_passed 1000 1000 \
    && { echo "SELF-TEST FAIL: zero elapsed counted as enough." >&2; failed=1; }
  enough_time_passed 1000 $(( 1000 + MIN_IDLE_SECONDS - 1 )) \
    && { echo "SELF-TEST FAIL: one second short counted as enough." >&2; failed=1; }
  enough_time_passed 1000 $(( 1000 + MIN_IDLE_SECONDS )) \
    || { echo "SELF-TEST FAIL: exactly enough was rejected." >&2; failed=1; }
  enough_time_passed 1000 $(( 1000 + MIN_IDLE_SECONDS + 3600 )) \
    || { echo "SELF-TEST FAIL: comfortably enough was rejected." >&2; failed=1; }
  (( failed )) && return 1
  echo "time-math self-test ok (>= ${MIN_IDLE_SECONDS}s required)"
}

COMMAND="${1:-}"
[[ $# -gt 0 ]] && shift

if [[ "$COMMAND" == "--self-test" ]]; then
  self_test && ui_self_test && self_test_time_math
  exit $?
fi

if [[ "$COMMAND" != "arm" && "$COMMAND" != "check" ]]; then
  echo "usage: $0 --self-test | arm [--apk PATH] [--yes] | check <evidence-dir> [--force]" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# `arm`
# ---------------------------------------------------------------------------
cmd_arm() {
  local apk="" assume_yes=0
  while (( $# )); do
    case "$1" in
      --apk) apk="${2:?--apk needs a path}"; shift 2 ;;
      --yes|-y) assume_yes=1; shift ;;
      *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
  done

  local stamp evidence_dir out
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  evidence_dir="$REPO/evidence/long-idle-alarm-survival-$stamp"
  mkdir -p "$evidence_dir"
  out="$evidence_dir/long_idle_alarm_survival.log"

  note() { echo "$@" | tee -a "$out"; }
  raw()  { { echo "--- $1 ---"; cat; } >>"$out" 2>&1; }

  note "=== long-idle alarm survival: arm ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="
  note "package: $PACKAGE"
  note "evidence: $evidence_dir"

  if ! self_test >>"$out" 2>&1; then
    note "ABORT: the detection self-test failed - nothing was measured."
    exit 1
  fi
  if ! ui_self_test >>"$out" 2>&1; then
    note "ABORT: the UI self-test failed - the taps would land on nothing."
    exit 1
  fi
  note "self-tests: detection ok, tap locating ok"

  mapfile -t devices < <(adb devices | awk 'NR>1 && $2=="device" {print $1}')
  if (( ${#devices[@]} == 0 )); then
    note "ABORT: no device. Connect the phone by USB, allow USB debugging on it,"
    note "and check with 'adb devices' that it shows up as 'device' and not as"
    note "'unauthorized'."
    exit 1
  fi
  if (( ${#devices[@]} > 1 )); then
    note "ABORT: ${#devices[@]} devices connected - refusing to guess which phone"
    note "to reboot. Disconnect all but one."
    exit 1
  fi
  export ANDROID_SERIAL="${devices[0]}"
  note "device: $ANDROID_SERIAL ($(adb shell getprop ro.product.model | tr -d '\r'), Android $(adb shell getprop ro.build.version.release | tr -d '\r'))"

  if [[ -n "$apk" ]]; then
    note "installing $apk ..."
    adb install -r "$apk" 2>&1 | raw "adb install"
  fi

  if ! adb shell pm path "$PACKAGE" 2>/dev/null | grep -q "package:"; then
    note "ABORT: $PACKAGE is not installed. Pass --apk current.apk, or install it"
    note "by hand first."
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

  local app_uid uid_token dump
  app_uid="$(resolve_uid)"
  uid_token="$(uid_token_for "${app_uid:-}")"
  note "app uid: ${app_uid:-<unresolved>}  token: ${uid_token:-<none>}"

  dump="$(mktemp)"
  trap 'rm -f "$dump" /tmp/ww_ui.xml' RETURN
  count_alarms() {
    adb shell dumpsys alarm 2>/dev/null | tr -d '\r' >"$dump"
    count_app_alarms "$PACKAGE" "$uid_token" "$dump"
  }
  dump_context() {
    {
      echo "--- dumpsys alarm (this app, $1) ---"
      grep -E "${PACKAGE}|com\\.gdelataillade\\.alarm${uid_token:+|${uid_token}}" "$dump" | head -40
      echo "--- broad context, NOT counted ($1) ---"
      grep -iE "RTC_WAKEUP|Pending alarms per uid" "$dump" | head -20
    } >>"$out" 2>&1
  }

  note "--- launching the app ---"
  adb shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 2>&1 | raw "launch"
  sleep 6

  note "--- arming an alarm through the UI (~24h out) ---"
  local missed_taps=0
  for label in "Manual" "Add A New Alarm" "Save"; do
    tap_label "$label" || missed_taps=$(( missed_taps + 1 ))
  done
  (( missed_taps )) && note "  $missed_taps of 3 taps could not be located"

  local armed_at_epoch armed_at_human before
  armed_at_epoch="$(date -u +%s)"
  armed_at_human="$(date -u -d "@$armed_at_epoch" +%Y-%m-%dT%H:%M:%SZ)"

  before="$(count_alarms)"
  note "registered alarms right after arming: $before"
  dump_context "after arming"

  if [[ "$before" == "0" ]]; then
    note ""
    note "RESULT: not measurable - no alarm of this app is registered even"
    note "right after arming. Not a finding - see"
    note "scripts/verify-alarm-survival.sh's own troubleshooting steps (missed"
    note "taps / missing permission / arm by hand and re-run with just the"
    note "counting)."
    exit 1
  fi

  if (( ! assume_yes )); then
    echo ""
    echo "About to REBOOT $ANDROID_SERIAL, then force-stop $PACKAGE. Unlock it"
    echo "afterwards if it asks for a PIN, and then DO NOT touch the phone"
    echo "again until the time printed at the end below."
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
  sleep 20 # give the plugin's BootReceiver time to re-arm the stored alarms

  app_uid="$(resolve_uid)"
  uid_token="$(uid_token_for "${app_uid:-}")"
  local after_reboot
  after_reboot="$(count_alarms)"
  note "registered alarms after the reboot (informational only, not the verdict): $after_reboot"
  dump_context "after reboot"

  note "--- force-stop ---"
  adb shell am force-stop "$PACKAGE"
  sleep 5
  local after_force_stop
  after_force_stop="$(count_alarms)"
  note "registered alarms after the force-stop (informational only, not the verdict): $after_force_stop"
  dump_context "after force-stop"

  local due_epoch due_human
  due_epoch=$(( armed_at_epoch + MIN_IDLE_SECONDS ))
  due_human="$(date -u -d "@$due_epoch" +%Y-%m-%dT%H:%M:%SZ)"

  cat > "$evidence_dir/resume.env" <<RESUME
PACKAGE="$PACKAGE"
ARMED_AT_EPOCH=$armed_at_epoch
ARMED_AT_HUMAN="$armed_at_human"
DUE_NOT_BEFORE_EPOCH=$due_epoch
DUE_NOT_BEFORE_HUMAN="$due_human"
RESUME

  note ""
  note "=== armed, rebooted, force-stopped - now DO NOT TOUCH THE PHONE ==="
  note "Armed at (UTC):        $armed_at_human"
  note "Do not check before:   $due_human  (that's $((MIN_IDLE_SECONDS/3600))h later)"
  note ""
  note "Leave the phone completely alone - no unlocking, no opening the app,"
  note "no dismissing notifications - until at least the time above. Then run:"
  note ""
  note "  scripts/verify-long-idle-alarm-survival.sh check \"$evidence_dir\""
  note ""
  note "=== end of arm phase ==="
}

# ---------------------------------------------------------------------------
# `check`
# ---------------------------------------------------------------------------
cmd_check() {
  local evidence_dir="${1:-}" force=0
  [[ -n "$evidence_dir" ]] && shift || true
  while (( $# )); do
    case "$1" in
      --force) force=1; shift ;;
      *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$evidence_dir" || ! -f "$evidence_dir/resume.env" ]]; then
    echo "usage: $0 check <evidence-dir-from-arm> [--force]" >&2
    echo "(expected to find resume.env inside it - pass the directory 'arm' printed)" >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  source "$evidence_dir/resume.env"

  local out
  out="$evidence_dir/long_idle_alarm_survival.log"
  note() { echo "$@" | tee -a "$out"; }
  raw()  { { echo "--- $1 ---"; cat; } >>"$out" 2>&1; }

  note ""
  note "=== long-idle alarm survival: check ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="

  local now_epoch
  now_epoch="$(date -u +%s)"
  if ! enough_time_passed "$ARMED_AT_EPOCH" "$now_epoch"; then
    local remaining=$(( DUE_NOT_BEFORE_EPOCH - now_epoch ))
    note "Too early: armed at $ARMED_AT_HUMAN, not due before $DUE_NOT_BEFORE_HUMAN"
    note "(about $(( remaining / 3600 ))h$(( (remaining % 3600) / 60 ))m left)."
    if (( ! force )); then
      note "Re-run later, or pass --force to check anyway (the result will say"
      note "less than a full run: the whole point is leaving it alone this long)."
      exit 1
    fi
    note "--force given: checking early anyway."
  fi

  mapfile -t devices < <(adb devices | awk 'NR>1 && $2=="device" {print $1}')
  if (( ${#devices[@]} != 1 )); then
    note "ABORT: expected exactly one connected device, found ${#devices[@]}."
    note "Reconnect the phone by USB (this alone does not count as 'touching'"
    note "the app - it only lets this script read dumpsys)."
    exit 1
  fi
  export ANDROID_SERIAL="${devices[0]}"

  resolve_uid() {
    local raw_line uid
    raw_line=$(adb shell pm list packages -U 2>&1 | tr -d '\r' | grep -F "$PACKAGE" | head -5)
    printf '%s\n' "$raw_line" | raw "uid attempt (check)"
    uid=$(printf '%s\n' "$raw_line" | grep -oE "uid:[0-9]+" | head -1 | cut -d: -f2)
    printf '%s' "$uid"
  }
  local app_uid uid_token dump final_count
  app_uid="$(resolve_uid)"
  uid_token="$(uid_token_for "${app_uid:-}")"
  dump="$(mktemp)"
  trap 'rm -f "$dump"' RETURN
  adb shell dumpsys alarm 2>/dev/null | tr -d '\r' >"$dump"
  final_count="$(count_app_alarms "$PACKAGE" "$uid_token" "$dump")"
  {
    echo "--- dumpsys alarm (this app, at check time) ---"
    grep -E "${PACKAGE}|com\\.gdelataillade\\.alarm${uid_token:+|${uid_token}}" "$dump" | head -40
  } >>"$out" 2>&1

  note "registered alarms at check time: $final_count"
  note "(weak signal only: a fired one-shot alarm removes its own"
  note "registration, so '0' is consistent with - but not proof of - it"
  note "having actually rung. A non-zero count whose own 'when=' is now in"
  note "the past would be a clearer red flag; see the raw dump above.)"

  note ""
  echo "Did the phone actually ring/vibrate the alarm around $DUE_NOT_BEFORE_HUMAN (UTC)?"
  read -r -p "[yes/no/unsure] " rang
  note "human observation - did it ring: $rang"

  echo ""
  echo "If 'Record diagnostics' + 'Also record wake and appointment times' were"
  echo "both on: does Settings > Diagnostics now show an alarmRang event around"
  echo "that time (knownToAppState/checkpointFired flags in particular)?"
  read -r -p "[yes/no/not-checked/diagnostics-was-off] " diag
  note "diagnostics log corroboration: $diag"

  note ""
  note "=== VERDICT (for docs/TODO.md T-04) ==="
  note "armed:              $ARMED_AT_HUMAN"
  note "due not before:     $DUE_NOT_BEFORE_HUMAN"
  note "checked:            $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  note "registered at check: $final_count"
  note "rang (human report): $rang"
  note "diagnostics log:     $diag"
  note "=== end ==="
}

case "$COMMAND" in
  arm) cmd_arm "$@" ;;
  check) cmd_check "$@" ;;
esac
