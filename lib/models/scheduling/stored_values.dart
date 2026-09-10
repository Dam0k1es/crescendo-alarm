// Die beiden erlaubten Lesarten eines gespeicherten Planwerts
// (docs/TODO.md T-83).
//
// `AppState.pendingDayValues` ist eine `Map<String, int?>` von ISO-Datum auf
// `millisecondsSinceEpoch` - diese Form ist Absicht, weil FR-16s Checkpoint 2
// denselben SharedPreferences-Schlüssel aus einem Hintergrund-Isolate ohne
// jeden AppState-Zugriff lesen und schreiben muss.
//
// Beim Zurücklesen gibt es zwei *unterschiedliche*, beide korrekte Antworten,
// und genau darin lag die Falle: die Karte wurde an fünf Stellen gelesen,
// dreimal mit `isUtc: true` und zweimal ohne. Das war kein Fehler, sondern
// notwendig - aber es sah wie eine Inkonsistenz aus, und ein gut gemeintes
// Vereinheitlichen hätte Anzeige und Alarmtitel still um den Geräteversatz
// verschoben. Deshalb keine rohen `DateTime.fromMillisecondsSinceEpoch`-Aufrufe
// mehr an den Aufrufstellen, sondern zwei Namen, die die Absicht tragen.

/// Für die **Domänenschicht** (`scheduling_v2.dart`, `replan.dart`):
/// UTC-getaggt.
///
/// Deren Arithmetik vergleicht Ziffernfelder (`_wallClockDelta` liest
/// `.hour`/`.minute`), also müssen alle Operanden im selben Frame liegen -
/// und der ist per Konvention UTC (FR-1: jeder Wert ist ein absoluter
/// Instant). Ein lokal getaggter Wert würde hier je nach Zeitzone der
/// Testmaschine bzw. des Geräts andere Ergebnisse liefern; genau das war T-61.
DateTime? instantFromStored(int? millis) => millis == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

/// Für **Plattform und Anzeige** (`apply_alarms.dart`, `next_wake_up.dart`):
/// lokal getaggt.
///
/// Dahinter liegen Leser, die die Ziffern als Wanduhrzeit interpretieren -
/// `ScheduledAlarm.title` über `formatDateTime`, die Alarmliste in der UI, und
/// `alarmPlatformTime` beim Übergang zum Alarm-Plugin. Derselbe reale Moment
/// wie [instantFromStored], nur eben in der Lesart, die diese Seite braucht.
DateTime? localFromStored(int? millis) =>
    millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);

/// Die Gegenrichtung. Frame-unabhängig (`millisecondsSinceEpoch` ist es
/// ohnehin) und nur der Vollständigkeit halber benannt, damit an den
/// Schreibstellen dasselbe Vokabular steht wie an den Lesestellen.
int? toStored(DateTime? value) => value?.millisecondsSinceEpoch;
