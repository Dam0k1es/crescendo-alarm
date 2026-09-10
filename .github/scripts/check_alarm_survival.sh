#!/usr/bin/env bash
# Beweissammlung zu docs/REQUIREMENTS.md R3: uebersteht ein gesetzter Alarm
# einen Reboot und einen Force-Stop?
#
# Warum ueber `dumpsys alarm` und nicht ueber ein echtes Klingeln: so ist
# "Alarm ist registriert" von "kein Alarm registriert" unterscheidbar, ohne
# Wartezeit. Ein Klingel-Test kostet pro Durchgang eine Minute Echtzeit und
# waere im E2E-Zeitbudget nicht unterzubringen.
#
# Was aus dem Code bereits bekannt ist (und was dieses Skript pruefen soll):
#   * Die App hat KEINEN eigenen BootReceiver (grep BOOT_COMPLETED lib/ android/
#     findet nur die uses-permission-Zeile).
#   * Das `alarm`-Plugin registriert einen eigenen
#     `com.gdelataillade.alarm.alarm.BootReceiver` und armiert die gespeicherten
#     Alarme nach dem Boot per `setExactAndAllowWhileIdle(RTC_WAKEUP, ...)` neu.
#     Reboot-Ueberleben ist dort also implementiert - erwartet wird GRUEN.
#   * Bei `am force-stop` cancelt Android plattformseitig alle AlarmManager-
#     Alarme des Pakets, und ein force-gestoppter Prozess empfaengt danach kein
#     BOOT_COMPLETED mehr, bis der Nutzer die App erneut startet. Erwartet wird
#     hier also ROT - und zwar by design, nicht als Fehler dieser App. Genau
#     das muss R3 dann als Grenze festhalten statt es als Bug zu fuehren.
set -uo pipefail

PACKAGE="${1:?package name required}"
EVIDENCE_DIR="${2:?evidence dir required}"
OUT="$EVIDENCE_DIR/alarm_survival.log"

note() { echo "$@" | tee -a "$OUT"; }

# Zaehlt die AlarmManager-Eintraege, die diesem Paket zugeordnet sind.
#
# docs/TODO.md T-99: die erste Fassung suchte nur nach dem Paketnamen und fand
# NULL, obwohl `arm_alarm_test.dart` im selben Lauf nachweislich einen Alarm
# gesetzt hatte ("1 test passed"). Die erwartete dumpsys-Signatur war also
# falsch geraten. Deshalb mehrere Muster - und `dump_alarms` schreibt den
# Rohauszug in die Beweisdatei, damit der naechste Lauf zeigt, wie die
# Eintraege wirklich aussehen, statt wieder nur "0" zu melden.
count_alarms() {
  adb shell dumpsys alarm 2>/dev/null \
    | grep -cE "$PACKAGE|AlarmReceiver|com\.gdelataillade\.alarm" || true
}

# Roher Kontext fuer die Diagnose: die Abschnitte von `dumpsys alarm`, in denen
# App-Alarme ueberhaupt auftauchen koennen.
dump_alarms() {
  local label="$1"
  {
    echo "--- dumpsys alarm ($label) ---"
    adb shell dumpsys alarm 2>/dev/null \
      | grep -iE "$PACKAGE|AlarmReceiver|gdelataillade|RTC_WAKEUP|Batch|Pending alarm" \
      | head -40
    echo "--- app-uid alarms ($label) ---"
    local uid
    uid=$(adb shell dumpsys package "$PACKAGE" 2>/dev/null | grep -m1 "userId=" | tr -d '\r')
    echo "  $uid"
  } >>"$OUT" 2>&1
}

note "=== alarm survival evidence ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="
note "package: $PACKAGE"

BEFORE=$(count_alarms)
note "registered alarm lines before reboot: $BEFORE"
dump_alarms "before reboot"

if [[ "$BEFORE" == "0" ]]; then
  note "RESULT: inconclusive - no matching alarm line found."
  note "Note that this is NOT the same as 'no alarm was set': in the first run"
  note "with this script, arm_alarm_test.dart had demonstrably registered one"
  note "('1 test passed') while this count was still 0 - the grep patterns were"
  note "wrong (docs/TODO.md T-99). The raw dumpsys excerpt above is there to"
  note "show what the entries actually look like, so the patterns can be fixed"
  note "from evidence instead of guessed again."
  exit 0
fi

note "--- rebooting ---"
adb reboot
adb wait-for-device
# Auf ein wirklich fertig gebootetes System warten, nicht nur auf adb.
for _ in $(seq 1 120); do
  if [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    break
  fi
  sleep 2
done
note "boot_completed: $(adb shell getprop sys.boot_completed | tr -d '\r')"

# Dem BootReceiver des Plugins Zeit geben, die Alarme neu zu armieren.
sleep 10
AFTER_REBOOT=$(count_alarms)
note "registered alarm lines after reboot: $AFTER_REBOOT"
adb shell dumpsys alarm 2>/dev/null | grep "$PACKAGE" | head -20 >>"$OUT" || true

if [[ "$AFTER_REBOOT" == "0" ]]; then
  note "RESULT reboot: FAIL - no alarm survived the reboot."
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
exit 0
