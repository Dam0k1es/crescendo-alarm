# Geräte-Probelauf: Checkliste

Zweck: aus einem Probelauf **datierte Belege** machen statt Eindrücke. Jede Zeile hat ein
Ergebnisfeld — was nicht eingetragen ist, gilt als nicht geprüft. `docs/REQUIREMENTS.md` verweist
für R3 und R4 auf diese Datei.

Auszufüllen pro Lauf. Vorlage kopieren, nicht überschreiben.

| Feld | Wert |
|---|---|
| Datum | |
| Gerät (Hersteller, Modell) | |
| Android-Version / API | |
| Gerätezeitzone | |
| APK (Datei, Größe, `apksigner`-Prüfsumme) | |
| Build (Commit) | |

## Warum überhaupt manuell

Die Automatisierung deckt inzwischen viel ab: `flutter test` prüft die Domänenlogik in sechs
Zeitzonen, und die E2E-Suite fährt gegen einen echten Emulator und belegt dort FR-18 bis zum
Alarm-Plugin. Vier Dinge kann sie strukturell **nicht** zeig, und genau die stehen hier:

1. **Echte Kalenderkonten.** Der CI-Emulator hat keine. Jedes E2E-Szenario injiziert seine Termine
   über den `fetchEvents`-Parameter — die reale Kette `device_calendar` → `eventToMeeting` →
   `TZDateTime` in der *Termin-eigenen* Zone bleibt damit ungeprüft. Das ist ausgerechnet die
   Quelle von T-61.
2. **Ton.** Der Emulator läuft ohne Audio (`-noaudio`); der einzige Ersatz ist ein
   `dumpsys audio`-Protokoll als Indiz.
3. **Kamera.** Der QR-Scan wird über `debugBarcodeStreamOverride` injiziert, echte Dekodierung ist
   nie gelaufen (T-16).
4. **OEM-Verhalten.** Doze, Batteriesparen und herstellereigene Prozess-Killer gibt es auf einem
   Standard-Emulator nicht.

## A — Grundfunktion

| # | Prüfung | Erwartung | Ergebnis |
|---|---|---|---|
| A1 | App installieren und starten | Splash → Berechtigungen → Hauptbildschirm | |
| A2 | Manuellen Alarm auf +2 min setzen | klingelt, Overlay erscheint | |
| A3 | Über "Stop" abschalten | Overlay weg, kein Alarm mehr aktiv | |
| A4 | Ton hörbar? Lautstärke wie eingestellt? | ja | |
| A5 | Gentle Wake aktivieren, Alarm wiederholen | Lautstärke steigt über ~60 s an | |

## B — Kalenderabgeleitetes Wecken (der eigentliche Produktpfad)

| # | Prüfung | Erwartung | Ergebnis |
|---|---|---|---|
| B1 | Echtes Kalenderkonto einrichten, Termin für morgen früh anlegen | | |
| B2 | In den Einstellungen "Duration to wake up"/"to get ready" setzen | | |
| B3 | Sync-Knopf in der Alarmliste drücken | Alarme für die nächsten 7 Tage erscheinen | |
| B4 | Erster Alarm gegen Terminbeginn − Vorlaufzeiten prüfen | stimmt auf die Minute | |
| B5 | Termin im Kalender **verschieben**, Sync erneut | Alarm folgt | |
| B6 | Termin löschen, Sync erneut | Tag driftet zur Wunschzeit bzw. fällt weg | |
| B7 | Termin mit **fremder Zeitzone** anlegen (z. B. Asia/Tokyo) | Alarm richtet sich nach der **Geräte**zone, nicht der Terminzone (FR-2) | |
| B8 | Ganztägigen Termin anlegen | wird ignoriert, Tag bleibt Lückentag (FR-2) | |

## C — Überleben (R3)

| # | Prüfung | Erwartung | Ergebnis |
|---|---|---|---|
| C1 | Alarm setzen, `adb shell dumpsys alarm \| grep com.wakeywakey` | Eintrag vorhanden | |
| C2 | Gerät neu starten, **ohne** die App zu öffnen, dann C1 wiederholen | Eintrag wieder vorhanden | |
| C3 | Alarm nach dem Reboot abwarten | klingelt | |
| C4 | `adb shell am force-stop com.wakeywakey.wakeywakey`, dann C1 | **Erwartung: Eintrag weg** — Android löscht die Alarme eines force-gestoppten Pakets, das ist Plattformverhalten, kein Fehler der App. Hier festhalten, damit R3 es als Grenze führt statt als Bug. | |
| C5 | Nach C4 die App öffnen | Alarme werden neu gesetzt (FR-17-Erholung) | |
| C6 | Batteriesparen einschalten, Alarm auf +10 min, Bildschirm aus | klingelt trotzdem | |

Zu C1/C2 aus dem Code bekannt: die App hat **keinen** eigenen `BootReceiver`. Das `alarm`-Plugin
registriert einen (`com.gdelataillade.alarm.alarm.BootReceiver`) und armiert die gespeicherten
Alarme nach dem Boot per `setExactAndAllowWhileIdle(RTC_WAKEUP, …)` neu; es verwirft dabei
verpasste Alarme als "stale". C2 sollte also grün sein — geprüft wurde es nie.

## D — Garantiertes Aufwachen (QR)

| # | Prüfung | Erwartung | Ergebnis |
|---|---|---|---|
| D1 | QR-Code in den Einstellungen erzeugen und ausdrucken | | |
| D2 | Alarm klingeln lassen | QR-Scanner erscheint statt "Stop" | |
| D3 | **Falschen** Code scannen | Alarm läuft weiter, Scanner bleibt offen | |
| D4 | Richtigen Code mit der **echten Kamera** scannen | Alarm stoppt (schließt T-16) | |
| D5 | Prüfen, ob der gescannte Wert irgendwo auf dem Bildschirm steht | **darf nicht** — nur "QR Code detected" | |

## E — Diagnose-Log (T-89)

| # | Prüfung | Erwartung | Ergebnis |
|---|---|---|---|
| E1 | Einstellungen → Diagnostics öffnen | Ereignisse sichtbar | |
| E2 | Inhalt durchsehen | keine Uhrzeit, kein Datum, kein Termintitel, kein Kalendername, kein QR-Code | |
| E3 | Nach B3 nachsehen | `weekPlanComputed` mit `plannedDays=7`, `windowDayCount == distinctDayKeys` | |
| E4 | Nach A3 nachsehen | `alarmSync` **ohne** großes `toRemove` bei `toAdd=0` (das wäre T-64) | |
| E5 | Nach dem Morgenalarm nachsehen | `dayAdvance` mit `daysProcessed >= 1` (0 wäre T-75) | |
| E6 | Zur Bettzeit nachsehen | `timezoneCheck` vorhanden und mit `(bg)` markiert → **schließt T-62** | |
| E7 | "Copy" drücken und den Text irgendwo einfügen | vollständig, ausschließlich Enum-Namen und Zahlen | |
| E8 | Schalter aus, App neu starten, nachsehen | keine neuen Ereignisse | |

E6 ist der Punkt mit dem größten Hebel: dass eine stille Notification
`onNotificationCreatedMethod` überhaupt auslöst, ist bislang nur aus dem Paketquellcode
abgeleitet. Erscheint `timezoneCheck (bg)` im Log, ist FR-16s Checkpoint 2 auf dem Gerät belegt.

## F — Zeitzonen und Sommerzeit

| # | Prüfung | Erwartung | Ergebnis |
|---|---|---|---|
| F1 | Gerätezeitzone wechseln (z. B. Berlin → Tokio), App öffnen | Wunschzeit-Tage behalten ihre **Ziffern**, Termintage ihren **Moment** (FR-16) | |
| F2 | Nach F1 ins Diagnose-Log sehen | `timezoneCheck` mit `offsetChangeShape=3` (otherChange) | |
| F3 | Geräteuhr auf den Tag vor einer Sommerzeitumstellung stellen, Alarm für den Umstellungstag | **bekannte Grenze:** an diesem einen Tag kann der Alarm um eine Stunde falsch liegen (siehe FR-16 in `docs/scheduling-v2-spec.md`) | |

## Befunde

Alles Auffällige hier mit Datum eintragen und in `docs/TODO.md` als eigene Nummer aufnehmen —
diese Datei ist der Beleg, nicht die Aufgabenliste.
