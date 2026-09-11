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
#
# ZWEI FEHLSCHLAEGE DIESES SKRIPTS, die seine heutige Form erklaeren:
#
#   docs/TODO.md T-99 (Lauf 1): das Muster suchte nur den Paketnamen und fand
#   NULL, obwohl `arm_alarm_test.dart` im selben Lauf nachweislich einen Alarm
#   gesetzt hatte. Reaktion damals: mehr Muster.
#
#   docs/TODO.md T-103 (Lauf 2): eines dieser Muster war die blosse
#   Teilzeichenkette `AlarmReceiver` - und die trifft Googles
#   `com.android.wallpaper.module.DailyLoggingAlarmReceiver`. Der Zaehler stand
#   dadurch auf 2 statt 0, das Skript lief am `BEFORE == 0`-Waechter vorbei und
#   meldete ein selbstbewusstes "FAIL - no alarm survived the reboot", das
#   nichts belegte: der eigene Alarm war nie gefunden worden.
#
# Die Lehre daraus steckt jetzt in der Struktur, nicht in einem Kommentar:
# ein Messinstrument, das ein Urteil faellt, muss sich vorher selbst beweisen.
# `--self-test` prueft die Mustererkennung gegen echte, aufgezeichnete
# dumpsys-Ausgabe (`fixtures/`) und laeuft bei jedem Aufruf automatisch mit.
# Ein Muster, das fremde Alarme mitzaehlt, bricht den Lauf hier ab - vor der
# Messung, nicht nach der Fehlinterpretation.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"

# ---------------------------------------------------------------------------
# Mustererkennung (die eigentliche Logik, bewusst von adb getrennt und dadurch
# ohne Emulator pruefbar).
# ---------------------------------------------------------------------------

# Zwei unabhaengige Ablesungen, weil `dumpsys alarm` zwei Darstellungen hat.
#
# (a) Die Summenzeile `Pending alarms per uid: [..., u0a161:2, ...]`. Das ist
#     die verlaesslichste Zahl, die der Dump hergibt: der Kernel-eigene Zaehler
#     pro uid, ohne jede Textmustersucherei.
# (b) Die Eintragszeilen, die den Paketnamen tragen. Noetig, falls die
#     Summenzeile fehlt (aeltere Images) oder die uid nicht aufloesbar war.
#
# Was hier NIE wieder hineingehoert: eine generische Teilzeichenkette wie
# "AlarmReceiver". Sie trifft fremde Apps (T-103 im Kopf) - und die
# Summenzeile trifft sie ohnehin alle auf einmal.

# (a) Liest N aus `... u0a161:N ...`. Leer, wenn die App dort nicht vorkommt
# (= keine anstehenden Alarme) oder die Zeile fehlt.
pending_for_uid_token() {
  local token="$1"
  [[ -z "$token" ]] && return 0
  sed -n 's/.*Pending alarms per uid:.*/&/p' \
    | grep -oE "(^|[^0-9a-z])${token}:[0-9]+" \
    | grep -oE '[0-9]+$' \
    | head -1
}

# (b) Zaehlt Eintragszeilen, die dieser App gehoeren - ausdruecklich OHNE die
# Summenzeile, die ja jede uid auffuehrt.
count_package_entry_lines() {
  local package="$1"
  grep -v "Pending alarms per uid:" \
    | grep -cE "${package}|com\\.gdelataillade\\.alarm" || true
}

# Die Zahl, auf die sich das Urteil stuetzt: die Summenzeile, wenn es sie gibt,
# sonst die Eintragszeilen.
count_app_alarms() {
  local package="$1" token="${2:-}" dump="$3" n
  n=$(pending_for_uid_token "$token" <"$dump")
  if [[ -n "$n" ]]; then printf '%s' "$n"; return; fi
  count_package_entry_lines "$package" <"$dump"
}

# Rechnet die Linux-uid in das Token um, unter dem `dumpsys alarm` sie fuehrt.
uid_token_for() {
  local uid="$1"
  if [[ "$uid" =~ ^[0-9]+$ ]] && (( uid >= 10000 )); then
    printf 'u0a%d' "$(( uid - 10000 ))"
  fi
}

# ---------------------------------------------------------------------------
# Selbstpruefung gegen aufgezeichnete Echtausgabe.
# ---------------------------------------------------------------------------
self_test() {
  local failed=0 pkg='com.wakeywakey.wakeywakey' n

  # 1. Eine Aufzeichnung ohne einen einzigen eigenen Alarm muss 0 ergeben -
  #    auch dann, wenn fremde Eintraege "AlarmReceiver" im Namen tragen.
  #    Das uid-Token ist hier bewusst eines, das in der Datei NICHT vorkommt:
  #    welche uid die App in jenem Lauf hatte, ist gerade unbekannt gewesen.
  n=$(count_app_alarms "$pkg" u0a999 "$FIXTURES/dumpsys_alarm_foreign.txt")
  if [[ "$n" != "0" ]]; then
    echo "SELF-TEST FAIL: fremde Aufzeichnung ergab $n statt 0." >&2
    failed=1
  fi

  # 2. Dasselbe ohne jedes uid-Token - dann traegt allein der Paketname.
  n=$(count_app_alarms "$pkg" "" "$FIXTURES/dumpsys_alarm_foreign.txt")
  if [[ "$n" != "0" ]]; then
    echo "SELF-TEST FAIL: fremde Aufzeichnung ohne uid ergab $n statt 0." >&2
    grep -nE "${pkg}|com\\.gdelataillade\\.alarm" "$FIXTURES/dumpsys_alarm_foreign.txt" >&2
    failed=1
  fi

  # 3. Ein eigener Alarm MUSS gefunden werden - sonst waeren 1 und 2 trivial
  #    dadurch zu erfuellen, dass das Muster gar nichts mehr trifft.
  n=$(count_app_alarms "$pkg" u0a161 "$FIXTURES/dumpsys_alarm_own.txt")
  if [[ "$n" != "2" ]]; then
    echo "SELF-TEST FAIL: eigene Alarme: $n statt 2 (Summenzeile sagt u0a161:2)." >&2
    failed=1
  fi

  # 4. Auch ohne aufloesbare uid muss der Paketname tragen.
  n=$(count_app_alarms "$pkg" "" "$FIXTURES/dumpsys_alarm_own.txt")
  if (( n < 1 )); then
    echo "SELF-TEST FAIL: ohne uid-Token kein eigener Alarm gefunden ($n)." >&2
    failed=1
  fi

  # 5. Das uid-Token darf sich nicht praefix-verschlucken.
  local tmp; tmp=$(mktemp)
  printf '  Pending alarms per uid: [u0a1610:7]\n' >"$tmp"
  n=$(count_app_alarms "$pkg" u0a161 "$tmp")
  rm -f "$tmp"
  if [[ "$n" != "0" ]]; then
    echo "SELF-TEST FAIL: u0a161 hat u0a1610 mitgetroffen ($n)." >&2
    failed=1
  fi

  # 6. Die uid-Umrechnung.
  [[ "$(uid_token_for 10161)" == "u0a161" ]] || { echo "SELF-TEST FAIL: uid_token_for 10161" >&2; failed=1; }
  [[ -z "$(uid_token_for 1000)" ]] || { echo "SELF-TEST FAIL: uid_token_for darf System-uids nicht uebersetzen" >&2; failed=1; }

  if (( failed )); then
    echo "SELF-TEST FAIL - die Alarmerkennung ist kaputt; es wird nichts gemessen." >&2
    return 1
  fi
  echo "self-test ok (Alarmerkennung gegen aufgezeichnete dumpsys-Ausgabe geprueft)"
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

# ---------------------------------------------------------------------------
# Messung
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

# Die uid der App. Drei Wege, weil das Feld je nach Android-Version anders
# heisst - und weil Lauf 34566962847 zeigte, dass `userId=` allein leer bleibt.
resolve_uid() {
  local uid
  uid=$(adb shell pm list packages -U 2>/dev/null | tr -d '\r' \
    | awk -v p="package:$PACKAGE" '$1 == p { for (i=1;i<=NF;i++) if ($i ~ /^uid:/) { sub(/^uid:/,"",$i); print $i } }' | head -1)
  [[ -n "$uid" ]] && { printf '%s' "$uid"; return; }
  uid=$(adb shell dumpsys package "$PACKAGE" 2>/dev/null | tr -d '\r' \
    | grep -oE "(userId|appId)=[0-9]+" | head -1 | cut -d= -f2)
  printf '%s' "$uid"
}

APP_UID=$(resolve_uid)
UID_TOKEN=$(uid_token_for "${APP_UID:-}")
note "app uid: ${APP_UID:-<nicht aufloesbar>}  token: ${UID_TOKEN:-<keins>}"
DUMP=$(mktemp)
snapshot() { adb shell dumpsys alarm 2>/dev/null | tr -d '\r' >"$DUMP"; }
count_alarms() { snapshot; count_app_alarms "$PACKAGE" "$UID_TOKEN" "$DUMP"; }

# Roher Kontext fuer die Diagnose. Bewusst BREITER als das Zaehlmuster: er soll
# zeigen, wie die Eintraege wirklich aussehen, falls das Zaehlmuster nichts
# findet. Er darf aber nie in die Zaehlung einfliessen - das war T-103.
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
# Auf ein wirklich fertig gebootetes System warten, nicht nur auf adb.
for _ in $(seq 1 120); do
  if [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
    break
  fi
  sleep 2
done
note "boot_completed: $(adb shell getprop sys.boot_completed | tr -d '\r')"

# Die uid kann sich ueber einen Reboot nicht aendern, aber das Token neu
# aufzuloesen kostet nichts und faengt einen Neuinstall ab.
APP_UID=$(resolve_uid)
UID_TOKEN=$(uid_token_for "${APP_UID:-}")

# Dem BootReceiver des Plugins Zeit geben, die Alarme neu zu armieren.
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
