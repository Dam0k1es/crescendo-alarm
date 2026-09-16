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

## uiautomator_*.xml

Recorded accessibility trees for `scripts/verify-alarm-survival.sh`, which taps
its way through the app to arm an alarm before measuring. Two things about them
are deliberate:

- In `uiautomator_alarms_screen.xml` the node `Manual Alarm List` comes
  **before** the tab `Manual`. A pattern that matches a label as a prefix then
  grabs the wrong node, and the self-test turns red. In the original ordering
  the same broken pattern passed by luck, because `head -1` still happened to
  take the right node - a compensating error of exactly the kind this project
  has been bitten by before.
- `uiautomator_empty.xml` is the tree a Flutter app shows on the *first* dump:
  the semantics tree is only built once an accessibility client connects, and
  `uiautomator dump` is that client. The script therefore retries, and the
  self-test pins that an empty tree yields no coordinate rather than a bogus one.
