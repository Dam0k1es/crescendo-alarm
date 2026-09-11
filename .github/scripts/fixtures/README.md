# dumpsys-Fixtures für `check_alarm_survival.sh --self-test`

- **`dumpsys_alarm_foreign.txt` ist eine echte Aufzeichnung.** Wörtlich aus der
  Beweisdatei von Lauf 34566962847 (2026-09-11). Keine einzige Zeile darin
  gehört dieser App — sie ist der Negativfall: das damalige Zählmuster hat hier
  zwei Treffer produziert (Googles `DailyLoggingAlarmReceiver` enthält die
  Teilzeichenkette `AlarmReceiver`), woraufhin das Skript ein unbegründetes
  "FAIL" meldete. Jedes künftige Muster muss auf dieser Datei **0** liefern.

- **`dumpsys_alarm_own.txt` ist KONSTRUIERT, keine Aufzeichnung.** Wie ein
  eigener Alarm in `dumpsys alarm` wirklich aussieht, ist auf diesem
  Emulator-Image bis heute nie beobachtet worden. Die Datei bildet das
  AOSP-Format nach und deckt beide plausiblen Formen ab: eine Zeile, die den
  Paketnamen trägt, und eine, in der nur das uid-Token steht. Sie beweist
  deshalb **nicht**, dass die Erkennung in der Realität greift — sie verhindert
  nur, dass jemand den Negativtest trivial dadurch erfüllt, dass das Muster
  überhaupt nichts mehr trifft.

  Sobald ein Lauf einen eigenen Alarm tatsächlich zeigt, gehört dessen echte
  Ausgabe hier hinein und dieser Absatz gestrichen.
