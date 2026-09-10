// Kalender-Tagesarithmetik für scheduling-v2, an einer Stelle (docs/TODO.md
// T-87). Vorher lag dieselbe Rechnung dreimal verstreut - als `_midnight`/
// `_dayMarker` in replan.dart und als Ad-hoc-`add(Duration(days: n))` bzw.
// `difference(...).inDays` in scheduling_v2.dart - und genau die verstreuten
// Kopien waren die Ursache von T-74d und T-76.
//
// Der Kern der Sache: ein Tagesmarker ist ein **Kalenderdatum**, keine Dauer.
// Auf einem lokal getaggten (oder `tz.TZDateTime`-) Marker liefert
// `add(Duration(days: 1))` an einer Sommerzeit-Umstellung 23:00 des Vortags,
// und `difference(...).inDays` zählt um einen Tag zu wenig, weil der
// betroffene Tag nur 23 Stunden hat. Beides muss über die Datumsfelder
// laufen, nicht über absolute Dauern.

/// Mitternacht von [t]s eigenem Kalendertag, im selben Frame wie [t]
/// (`DateTime(...)` baut immer einen *lokalen* Wert, unabhängig von der
/// Herkunft der Komponenten - auf einem UTC-getaggten [t] würde das dessen
/// Ziffern im Host-Versatz reinterpretieren).
DateTime midnight(DateTime t) =>
    t.isUtc ? DateTime.utc(t.year, t.month, t.day) : DateTime(t.year, t.month, t.day);

/// [base]s Kalenderdatum um [days] verschoben, über die Datumsfelder gerechnet
/// (`DateTime`s Konstruktor normalisiert Überläufe wie `day: 32` selbst).
DateTime dayMarker(DateTime base, int days) => base.isUtc
    ? DateTime.utc(base.year, base.month, base.day + days)
    : DateTime(base.year, base.month, base.day + days);

/// Ein frame-freier, vergleichbarer Stempel für [t]s Kalendertag: dessen
/// Datumsziffern, als UTC-Mitternacht getragen. UTC kennt keine Umstellung,
/// deshalb ist die Differenz zweier solcher Stempel immer exakt ein Vielfaches
/// von 24 Stunden - genau das, was [dayDistance] braucht.
///
/// Bewusst frame-übergreifend: [t] darf ein UTC-Instant, ein lokaler Marker
/// oder ein `tz.TZDateTime` sein. Verglichen wird das Kalenderdatum, das [t]
/// in seinem *eigenen* Frame benennt - für Fensterttage (Datumsmarker) ist das
/// die gesuchte Bedeutung.
DateTime dayStamp(DateTime t) => DateTime.utc(t.year, t.month, t.day);

/// Wie viele Kalendertage [a]s Datum nach [b]s Datum liegt (negativ, wenn
/// davor). Ersetzt `a.difference(b).inDays`, das an einer
/// Sommerzeit-Umstellung um einen Tag zu klein ist.
int dayDistance(DateTime a, DateTime b) =>
    dayStamp(a).difference(dayStamp(b)).inDays;

/// Der `YYYY-MM-DD`-Schlüssel, unter dem ein Tag in `AppState.pendingDayValues`
/// und `pendingDayInstantAnchored` steht.
String isoDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
