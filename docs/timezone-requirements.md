# Time zone & daylight saving requirements (TZ-1 … TZ-9)

Derived with the maintainer on 2026-09-28 from their own list ("Ein Alarm klingelt in der Zeit der
Änderung … Ein Reisender kann zwischen zwei Zeitzonen wechseln …"). This file is the starting point
for all further work on the topic; the simulation of the persona Tom's world trip lives in
[`timezone-travel-analysis.md`](timezone-travel-analysis.md) (in progress).

## Scope and status - what is promised

| Area | Status |
|---|---|
| **Daylight saving changes while staying in one region** - any region, not only Germany (TZ-1, TZ-2, TZ-3, and TZ-8/TZ-9 as far as they concern DST) | **Committed.** The change hour itself is fixed (`docs/TODO.md` T-202); scheduled wall-clock values around a change are still open (T-206). |
| **Travelling across time zones** (TZ-4, TZ-6, TZ-7, TZ-8/TZ-9 as far as they concern travel) | **Provisional - not promised.** Requirements recorded so work can resume here; the app makes no claim to support world travel reliably yet. |
| **Travelling combined with daylight saving changes in several regions** (TZ-5) | **Provisional - explicitly not promised as functional.** |

Maintainer, verbatim: "noch geben wir kein versprechen zu reisenden die um die ganze welt fliegen.
zeitwechsel in deutschland sind davon nicht betroffen. existierende tests werden auch nicht
verworfen. es geht nur darum, dass kein versprechen gemacht wird, das noch nicht gehalten werden
kann. … das problem mit sommer und winterzeit - auch in anderen regionen - klären wir jetzt. nur
reisen mit timeshift + sommer/winterzeit für mehrere regionen ist noch nicht versprochen
funktional." (We give no promise yet to travellers flying around the world. Time changes in Germany
are not affected. Existing tests are not discarded either. It is only about not making a promise
that cannot be kept yet. … The daylight saving problem - in other regions too - we solve now. Only
travel with a time shift plus daylight saving for several regions is not yet promised as
functional.)

Nothing is removed by this scoping: FR-16's existing time zone handling and every existing test
stay as they are. What changes is only what the app promises (`README.md`, `docs/USER_GUIDE.md`,
`docs/personas.md`).

## Basic distinction: two kinds of alarm time

- **Wall-clock alarms** - a manual alarm ("07:00"), `preferredWakeUpTime`, FR-4's drift / gap-day
  values. "The right time" is that reading on the **local clock** where the phone is.
- **Appointment alarms** - a scheduled alarm derived from a calendar appointment. "The right time"
  is the appointment's **instant** minus the lead times - *provided the calendar entry carries the
  time zone the user actually means*. Maintainer's objection (recorded, relevant for travel): an
  appointment entered as "08:00" in the origin zone but meant as 08:00 at the destination is wrong
  data, not a wrong alarm; how the app should treat that is a travel question (see the analysis
  file).

## Committed - daylight saving within one region

- **TZ-1 · An alarm due during the change hour picks the right moment.**
  - Appointment alarms ring at their exact instant, also inside a repeated or a skipped hour.
  - Wall-clock alarm in the **repeated** hour (clocks go back, e.g. 02:30 occurs twice): rings
    **once, at the later occurrence** (maintainer decision).
  - Wall-clock alarm in the **skipped** hour (clocks go forward, e.g. 02:30 does not exist): rings
    **as soon as the time exists** - at the first valid instant after the gap (03:00 in
    Europe/Berlin). **No alarm is ever skipped** (maintainer decision).
  - Note: platform defaults do **not** match these rules (`java.time`: repeated hour → earlier
    occurrence, gap → shifted by the gap length, i.e. 03:30). The app must resolve these cases
    explicitly rather than relying on a default.
- **TZ-2 · An alarm due after the change keeps the right time.** Wall-clock alarms keep their clock
  reading under the new offset (07:00 stays 07:00); appointment alarms keep their instant. Holds on
  the change day itself and every day after. (Maintainer: "vermute so, später nochmal zu klären" -
  this is the working rule until then.)
- **TZ-3 · Every region.** TZ-1 and TZ-2 hold in every IANA time zone: southern hemisphere, half-
  and quarter-hour offsets, 30-minute DST (Lord Howe), zones without DST, and zones whose rules
  change. The transition rules come from the device's time zone database, never from values
  hard-coded in the app ("wenn das Android schon kann, dann wäre es klüger als selbst
  implementieren") - only the resolution of the repeated / skipped hour (TZ-1) is the app's own
  rule, because the platform defaults differ from it.
- **TZ-8 (DST part) · Sleep time and bedtime reminder follow the same rules.** The Do Not Disturb
  window and the bedtime reminder are derived from the same instants as the alarms and are not an
  hour off either (maintainer: "genau").
- **TZ-9 (DST part) · Verifiability.** Each rule is covered by tests that sweep all IANA zones and
  all 2026/2027 transitions against an independently computed expectation (the pattern of the
  T-201 review); time zone fixtures are `tz.TZDateTime`, never `DateTime.utc` (maintainer: "klingt
  gut").

State (2026-09-28):

- **TZ-1 - met** (`docs/TODO.md` T-202). Appointment/planned alarms keep their exact instant through
  every hand-off to the platform (the alarm plugin, including its own persisted copy; the app's
  alarm list; the Do Not Disturb window; the bedtime reminder). Manual alarms resolve the repeated
  and the skipped hour by the rule above, in one place (`lib/utils/wall_clock.dart`,
  `localWallClockInstant`), using the device's zone rules.
- **TZ-8 (DST part) - met for the change hour** (same fix): the window and the reminder are derived
  from the same instants as the alarms.
- **TZ-2 - still violated for scheduled wall-clock values** (`docs/TODO.md` T-206: `replan` plans
  the whole window with one offset, so a gap-day / `preferredWakeUpTime` alarm is an hour off on
  the change day and drifts back over the following days). Manual alarms and appointment alarms
  meet TZ-2.
- **TZ-9 (DST part) - partly.** In the repository: tests derive the process zone's own 2026/27
  transitions at runtime and run under all six CI zones; fixtures are `tz.TZDateTime`. An all-zone
  sweep (every IANA zone, every 2026/27 transition, expectations from Python `zoneinfo`) was run for
  T-202 outside the repository (result recorded in T-202); it is not part of CI.

## Provisional - travelling (not promised)

- **TZ-4 · Travelling forward or backward.** Wall-clock alarms follow the new local time ("07:00"
  set in Berlin rings at 07:00 in New York); appointment alarms keep their instant. (Maintainer:
  open.)
- **TZ-5 · Travelling between zones with different DST dates** - the rules of the zone the phone is
  in right now apply; no assumption from the origin zone carries over. (Maintainer: open; not
  promised as functional.)
- **TZ-6 · Detecting the change in time.** A zone or offset change updates all wall-clock alarms
  before their next due time, also with the app closed and after a reboot; atomically, no double
  ring. (Maintainer: open.)
- **TZ-7 · Date line and long jumps.** No skipped day, no double ring (maintainer: "genau").
- **TZ-8 / TZ-9 (travel part)** - as above, applied to travel.

Known gaps against these (verified in code on 2026-09-28, detail in the analysis file):

- A **manual** alarm is armed only on create/edit/toggle and after it rings; nothing re-arms it on a
  zone change (`replan` deliberately never touches manual alarms, FR-15). The first manual alarm
  after a flight still rings at its old instant.
- The app has **no receiver for `ACTION_TIMEZONE_CHANGED`**; the `alarm` plugin arms by epoch
  instant, so armed alarms do not move with a zone change until a replan (a scheduled alarm's ring,
  opening the app, a settings change, Sync).
- FR-16's Checkpoint 2 re-arms nothing (`docs/TODO.md` T-113) and does not run at bedtime (T-199).
- FR-16 explicitly accepts a transition-day limitation (T-85e) that contradicts TZ-2/TZ-4 once
  travel is in scope.
