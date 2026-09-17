// Calendar day arithmetic for scheduling-v2, in one place (docs/TODO.md
// T-87). Previously the same computation was scattered three times - as
// `_midnight`/`_dayMarker` in replan.dart and as ad-hoc
// `add(Duration(days: n))` or `difference(...).inDays` in scheduling_v2.dart
// - and exactly those scattered copies were the cause of T-74d and T-76.
//
// The heart of the matter: a day marker is a **calendar date**, not a
// duration. On a locally-tagged (or `tz.TZDateTime`) marker, across a
// daylight-saving transition `add(Duration(days: 1))` yields 23:00 of the
// previous day, and `difference(...).inDays` counts one day too few, because
// the affected day only has 23 hours. Both must run over the date fields,
// not over absolute durations.

/// Midnight of [t]'s own calendar day, in the same frame as [t]
/// (`DateTime(...)` always builds a *local* value, regardless of where the
/// components came from - on a UTC-tagged [t] this would reinterpret its
/// digits in the host offset).
DateTime midnight(DateTime t) =>
    t.isUtc ? DateTime.utc(t.year, t.month, t.day) : DateTime(t.year, t.month, t.day);

/// [base]'s calendar date shifted by [days], computed over the date fields
/// (`DateTime`'s constructor normalizes overflows like `day: 32` itself).
DateTime dayMarker(DateTime base, int days) => base.isUtc
    ? DateTime.utc(base.year, base.month, base.day + days)
    : DateTime(base.year, base.month, base.day + days);

/// A frame-free, comparable stamp for [t]'s calendar day: its date digits,
/// carried as UTC midnight. UTC has no transitions, so the difference between
/// two such stamps is always exactly a multiple of 24 hours - exactly what
/// [dayDistance] needs.
///
/// Deliberately frame-crossing: [t] may be a UTC instant, a local marker, or
/// a `tz.TZDateTime`. What's compared is the calendar date that [t] names in
/// its *own* frame - for window days (date markers) that is the meaning
/// wanted.
DateTime dayStamp(DateTime t) => DateTime.utc(t.year, t.month, t.day);

/// How many calendar days [a]'s date lies after [b]'s date (negative if
/// before). Replaces `a.difference(b).inDays`, which is one day too small
/// across a daylight-saving transition.
int dayDistance(DateTime a, DateTime b) =>
    dayStamp(a).difference(dayStamp(b)).inDays;

/// The `YYYY-MM-DD` key under which a day is stored in
/// `AppState.pendingDayValues` and `pendingDayInstantAnchored`.
String isoDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
