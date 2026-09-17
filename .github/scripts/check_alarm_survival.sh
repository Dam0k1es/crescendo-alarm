#!/usr/bin/env bash
# Evidence collection for docs/REQUIREMENTS.md R3: does a set alarm survive
# a reboot and a force-stop?
#
# Why via `dumpsys alarm` and not via an actual ring: this way "alarm is
# registered" is distinguishable from "no alarm registered" without any
# waiting. A ringing test costs one minute of real time per run and
# wouldn't fit inside the E2E time budget.
#
# What's already known from the code (and what this script is meant to
# verify):
#   * The app has NO BootReceiver of its own (grep BOOT_COMPLETED lib/ android/
#     only finds the uses-permission line).
#   * The `alarm` plugin registers its own
#     `com.gdelataillade.alarm.alarm.BootReceiver` and re-arms the stored
#     alarms after boot via `setExactAndAllowWhileIdle(RTC_WAKEUP, ...)`.
#     Reboot survival is therefore implemented there - GREEN is expected.
#   * On `am force-stop`, Android cancels all of the package's AlarmManager
#     alarms at the platform level, and a force-stopped process no longer
#     receives BOOT_COMPLETED afterward until the user relaunches the app.
#     RED is therefore expected here - and by design, not as a defect of
#     this app. R3 must record exactly that as a boundary, rather than
#     carrying it as a bug.
#
# TWO FAILURES OF THIS SCRIPT that explain its current shape:
#
#   docs/TODO.md T-99 (run 1): the pattern searched only for the package
#   name and found NOTHING, even though `arm_alarm_test.dart` had provably
#   set an alarm in the same run. The reaction back then was: more patterns.
#
#   docs/TODO.md T-103 (run 2): one of those patterns was the bare
#   substring `AlarmReceiver` - which matches Google's
#   `com.android.wallpaper.module.DailyLoggingAlarmReceiver`. That put the
#   counter at 2 instead of 0, the script sailed past the `BEFORE == 0`
#   guard, and reported a confident "FAIL - no alarm survived the reboot"
#   that proved nothing: the app's own alarm had never been found.
#
# The lesson from that now lives in the structure, not in a comment: a
# measuring instrument that renders a verdict must first prove itself.
# `--self-test` checks the pattern detection against real, recorded
# dumpsys output (`fixtures/`) and runs automatically with every
# invocation. A pattern that counts foreign alarms aborts the run right
# here - before the measurement, not after the misinterpretation.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"

# shellcheck source=.github/scripts/alarm_detection.sh
source "$HERE/alarm_detection.sh"

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

# ---------------------------------------------------------------------------
# Measurement
# ---------------------------------------------------------------------------
PACKAGE="${1:?package name required}"
EVIDENCE_DIR="${2:?evidence dir required}"
OUT="$EVIDENCE_DIR/alarm_survival.log"

note() { echo "$@" | tee -a "$OUT"; }

note "=== alarm survival evidence ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="
note "package: $PACKAGE"

if ! self_test >>"$OUT" 2>&1; then
  note "RESULT: aborted - the detection self-test failed, see above. Nothing was"
  note "measured, deliberately: a broken instrument must not produce a verdict."
  exit 0
fi

# The app's uid. Three approaches, because the field is named differently
# depending on the Android version - and because run 34566962847 showed that
# `userId=` alone can come back empty.
#
# Every attempt logs its RAW OUTPUT into the evidence file (docs/TODO.md
# T-130). In run 34622086175 all approaches failed, and because their errors
# went to /dev/null, the evidence gave no way to tell why - even though
# `arm_alarm_test.dart` had provably set an alarm in the same run and the app
# was installed. Guessing the format has already led this script astray
# twice (T-99, T-103); this records it instead.
resolve_uid() {
  local uid raw
  {
    echo "--- uid attempt 1: pm list packages -U ---"
    raw=$(adb shell pm list packages -U 2>&1 | tr -d '\r' | grep -F "$PACKAGE" | head -5)
    echo "${raw:-(no line contains the package name)}"
  } >>"$OUT" 2>&1
  uid=$(printf '%s\n' "$raw" \
    | awk -v p="package:$PACKAGE" '$1 == p { for (i=1;i<=NF;i++) if ($i ~ /^uid:/) { sub(/^uid:/,"",$i); print $i } }' | head -1)
  if [[ -z "$uid" ]]; then
    # Less strict: any uid:NNN in a line that names the package.
    uid=$(printf '%s\n' "$raw" | grep -oE "uid:[0-9]+" | head -1 | cut -d: -f2)
  fi
  [[ -n "$uid" ]] && { printf '%s' "$uid"; return; }

  {
    echo "--- uid attempt 2: dumpsys package (userId=/appId=) ---"
    adb shell dumpsys package "$PACKAGE" 2>&1 | tr -d '\r' \
      | grep -E "userId=|appId=|versionName=|Unable|Error|not found" | head -5
  } >>"$OUT" 2>&1
  uid=$(adb shell dumpsys package "$PACKAGE" 2>/dev/null | tr -d '\r' \
    | grep -oE "(userId|appId)=[0-9]+" | head -1 | cut -d= -f2)
  [[ -n "$uid" ]] && { printf '%s' "$uid"; return; }

  {
    echo "--- uid attempt 3: stat of the data directory ---"
    adb shell "stat -c %u /data/data/$PACKAGE" 2>&1 | tr -d '\r' | head -2
  } >>"$OUT" 2>&1
  uid=$(adb shell "stat -c %u /data/data/$PACKAGE" 2>/dev/null | tr -d '\r' \
    | grep -oE '^[0-9]+$' | head -1)
  printf '%s' "$uid"
}

APP_UID=$(resolve_uid)
UID_TOKEN=$(uid_token_for "${APP_UID:-}")
note "app uid: ${APP_UID:-<not resolvable>}  token: ${UID_TOKEN:-<none>}"

# Is the app even installed? (docs/TODO.md T-131)
#
# Run 34627328009 showed the actual root cause, and it is structural: all
# three resolution approaches consistently reported "Unable to find
# package" resp. "No such file or directory" for /data/data/<package>. The
# app was UNINSTALLED at the time of measurement - `flutter test` installs
# it for the run and tears it down again afterward, and Android discards
# the package's AlarmManager entries along with it.
#
# That means the procedure "arm an alarm in a test, then interrogate
# dumpsys" fundamentally cannot measure anything here - regardless of any
# search pattern. That's exactly what T-99 misdiagnosed as "the pattern
# guessed wrong". Here it's called by its real name instead of being
# booked as a measurement gap again.
if ! adb shell pm path "$PACKAGE" 2>/dev/null | grep -q "package:"; then
  note "RESULT: not measurable - the app is NOT INSTALLED at the time of measurement."
  note "Android discards the package's AlarmManager entries along with it, so no"
  note "alarm could possibly be registered. This is NOT a finding about the"
  note "product and no longer a pattern question either, but a boundary of the"
  note "procedure: flutter test uninstalls the app after the run. As long as"
  note "that holds, the alarm must be armed by a different path"
  note "(an installed app plus UI automation) - see docs/TODO.md T-131."
  exit 0
fi
DUMP=$(mktemp)
snapshot() { adb shell dumpsys alarm 2>/dev/null | tr -d '\r' >"$DUMP"; }
count_alarms() { snapshot; count_app_alarms "$PACKAGE" "$UID_TOKEN" "$DUMP"; }

# Raw context for diagnosis. Deliberately BROADER than the counting
# pattern: it's meant to show what the entries actually look like if the
# counting pattern finds nothing. It must never feed into the count,
# though - that was T-103.
dump_alarms() {
  {
    echo "--- dumpsys alarm (matching this app, $1) ---"
    grep -E "${PACKAGE}|com\\.gdelataillade\\.alarm${UID_TOKEN:+|${UID_TOKEN}}" "$DUMP" | head -40
    echo "--- dumpsys alarm (broad context, NOT counted, $1) ---"
    grep -iE "RTC_WAKEUP|Pending alarm|Batch" "$DUMP" | head -40
  } >>"$OUT" 2>&1
}

BEFORE=$(count_alarms)
note "registered alarm lines before reboot: $BEFORE"
dump_alarms "before reboot"

if [[ "$BEFORE" == "0" ]]; then
  note "RESULT: inconclusive - this app has no alarm registered even BEFORE the"
  note "reboot, so the reboot cannot be measured at all. This is a measurement"
  note "gap, NOT a finding: do not read it as 'the alarm did not survive'."
  note "Check, in this order: did arm_alarm_test.dart really arm one (see"
  note "arm_alarm.log), was the uid resolvable (line 'app uid:' above), and does"
  note "the broad context excerpt show an entry this pattern should have caught?"
  exit 0
fi

note "--- rebooting ---"
adb reboot
adb wait-for-device
# Wait for a genuinely fully-booted system, not just for adb.
for _ in $(seq 1 120); do
  if [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    break
  fi
  sleep 2
done
note "boot_completed: $(adb shell getprop sys.boot_completed | tr -d '\r')"

# The uid cannot change across a reboot, but re-resolving the token costs
# nothing and catches a reinstall.
APP_UID=$(resolve_uid)
UID_TOKEN=$(uid_token_for "${APP_UID:-}")

# Give the plugin's BootReceiver time to re-arm the alarms.
sleep 10
AFTER_REBOOT=$(count_alarms)
note "registered alarm lines after reboot: $AFTER_REBOOT"
dump_alarms "after reboot"

if [[ "$AFTER_REBOOT" == "0" ]]; then
  note "RESULT reboot: FAIL - the alarm was registered before the reboot and is"
  note "gone after it. This one IS a finding (R3)."
else
  note "RESULT reboot: PASS - alarms are registered again after boot."
fi

note "--- force-stop ---"
adb shell am force-stop "$PACKAGE"
sleep 3
AFTER_FORCE_STOP=$(count_alarms)
note "registered alarm lines after force-stop: $AFTER_FORCE_STOP"
if [[ "$AFTER_FORCE_STOP" == "0" ]]; then
  note "RESULT force-stop: alarms gone - expected, this is Android platform"
  note "behaviour for a force-stopped package, not a defect of this app."
else
  note "RESULT force-stop: alarms still registered."
fi

note "=== end ==="
rm -f "$DUMP"
exit 0
