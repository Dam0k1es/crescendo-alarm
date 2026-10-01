# Time zone & daylight saving requirements (TZ-1 … TZ-9)

Derived with the maintainer on 2026-09-28 from their own list ("Ein Alarm klingelt in der Zeit der
Änderung … Ein Reisender kann zwischen zwei Zeitzonen wechseln …"). This file is the starting point
for all further work on the topic; the simulation of the persona Tom's world trip lives in
[`timezone-travel-analysis.md`](timezone-travel-analysis.md) (in progress).

## Scope and status - what is promised

| Area | Status |
|---|---|
| **Daylight saving changes while staying in one region** - any region, not only Germany (TZ-1, TZ-2, TZ-2a, TZ-3, and TZ-8/TZ-9 as far as they concern DST) | **Committed.** The change hour itself is fixed (`docs/TODO.md` T-202); scheduled wall-clock values around a change are **fixed** (T-206, 2026-09-29, on `dev`, not yet in a release; a real-device check across a real change is outstanding - `docs/device-trial-checklist.md` F3/F4). |
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
  - **As one function** (Markus's formalisation, adopted by the maintainer 2026-09-28): for a
    wall-clock reading `w`, the alarm instant is
    **R(w) = min{ t : L(t) ≥ w and L(s) > w for every s > t }**, where `L(t)` is the local clock
    reading at instant `t` (right-continuous: at a transition instant the clock already shows the
    new offset) - "the first moment at which the clock shows `w` or later and after which it never
    again shows `w` or anything earlier". For a unique reading that is its instant; for a repeated
    one the second pass, **at every minute of the repeated range including its first**; for a
    skipped one the transition instant. It is monotone (a later reading never rings earlier), never
    before any occurrence of `w`, and never skips (`L(R(w)) ≥ w`). The transition intervals are
    half-open: in Europe/Berlin, 02:00 is inside both the spring gap and the autumn overlap, 03:00
    is outside both.
    - *Corrected 2026-09-28 (T-206).* The formula first adopted,
      `min{ t : L(s) ≥ w for every s ≥ t }`, gave the **first** occurrence at exactly the first
      minute of a repeated range: after the first 02:00 in Europe/Berlin the clock never again shows
      anything earlier than 02:00, so the whole first pass qualifies. The prose, T-202's
      implementation and its tests all ring at the later occurrence there, and the maintainer
      confirmed it, verbatim: "Doubled hour soll zur späteren zeit klingeln" (the doubled hour shall
      ring at the later time). Only the formula was wrong. Checked with Python `zoneinfo` (tzdata
      2026c) by a minute scan of both formulas: Europe/Berlin 25 Oct 2026 02:00 - old 00:00 UTC,
      corrected 01:00 UTC; Africa/Cairo 29 Oct 2026 23:00 (repeated 23:00-23:59) - old 20:00 UTC,
      corrected 21:00 UTC; every other reading checked (inside and outside both ranges, skipped
      readings) is unchanged. `localWallClockInstant` gives the corrected values in both zones.
  - **Implementation.** `resolveWallClock(w, offsetAt)` (`lib/utils/wall_clock.dart`) implements R,
    correct by proof under one assumption: a zone changes its offset at most once within ±30 h of the
    reading (tzdata 2026c: the smallest spacing anywhere is 167 h). Since T-206 it takes the zone's
    rules as a parameter and is the one implementation of R (its body was `localWallClockInstant`'s
    until then; that is now a thin wrapper over the device's rules with no production caller, used
    by tests only). Production code reaches R through `resolvePlannedClockTime` (R_plan) - the
    scheduling engine's planned values and manual alarms alike - with the single exception stated
    in TZ-2a.
  - Note: platform defaults do **not** match these rules (`java.time`: repeated hour → earlier
    occurrence, gap → shifted by the gap length, i.e. 03:30). The app must resolve these cases
    explicitly rather than relying on a default.
- **TZ-2 · An alarm due after the change keeps the right time.** Wall-clock alarms keep their clock
  reading under the new offset (07:00 stays 07:00); appointment alarms keep their instant. Holds on
  the change day itself and every day after. (Maintainer: "vermute so, später nochmal zu klären" -
  this is the working rule until then.)
  - **The clock reading counts, not the length of the night** (maintainer decision A,
    2026-09-28). Asked whether (1) the clock reading counts or (2) the sleep duration stays
    constant and the alarm drifts back gradually, the maintainer answered, verbatim: "A: 1". So:
    - A planned wall-clock value (a manual alarm, `preferredWakeUpTime`, FR-4's held or drifted
      value, FR-6/FR-7's curve) is planned **as a clock reading** and becomes an instant only by
      TZ-1's R, with the zone's rules **for the day it applies to** - never with the offset in
      effect when the plan was made. "07:00" rings at 07:00 by the clock on the change day and on
      every day after.
    - The night before is therefore one real hour shorter in spring and one hour longer in autumn
      (in Europe/Berlin; the size is the zone's own DST difference - 30 minutes at Lord Howe, two
      hours at Troll).
    - The daily limit on gradual shifting (`maxDailyDelta`) and FR-6's overrun warning measure the
      change of the **clock reading** from one day to the next. A daylight saving change is not a
      shift: it consumes none of `maxDailyDelta` and never triggers the warning. A real change of
      the reading on the change day (a drift toward `preferredWakeUpTime`, a run toward an
      appointment) is limited and warned about exactly as on any other day.
    - Earlier/later against an appointment is still decided on instants: a planned value is
      resolved by R first and only then capped at the appointment's `hardFloor` instant, so a
      reading in the repeated hour can never slip past an appointment between its two
      occurrences.
    - An appointment is assigned to the calendar day the device's clock shows **at the
      appointment's own instant** (the zone's rules at that instant), so an appointment shortly
      after midnight after a change lands on its own day.
- **TZ-2a · A planned wall-clock value stays on the day it was planned for** (maintainer decision
  B, 2026-09-28). Where a skipped hour ends at midnight - America/Nuuk, America/Godthab and
  America/Scoresbysund, 23:00 → 00:00 on the spring change day, the only such zones in 2026/27 by
  a Python `zoneinfo` scan of every zone -
  R moves a reading in that hour onto the **next** date (23:30 on 28 Mar 2026 → 00:00 on 29 Mar).
  Such a value still belongs to its planned day, not to the date on which it would ring: for
  identifying the day that rang, for the day a switched-off alarm refers to (FR-21), for fixing a
  rung value (FR-11), and for anything else that derives a day from an alarm's instant.
  Maintainer, verbatim: "B: Passt, zur not vorziehen" (B: fine - pull it earlier if necessary).
  - **How it is met: the permitted fallback** (chosen in the T-206 requirements, reason in
    `docs/TODO.md` T-206). The scheduling engine resolves a planned reading `w` with
    **R_plan(w) = R(w) − 1 minute if R(w) falls on a later calendar date than `w`, otherwise
    R(w)** - that is, it rings at the last valid minute **before** the gap (22:59 in the
    example), on the planned day. Since R(w) of a skipped reading is the transition instant,
    R_plan(w) is the minute right before the transition.
  - **This is a stated exception to TZ-1's R**: R never rings before any occurrence of `w`;
    R_plan does, in exactly this case, by between 1 and the gap's length (60 minutes in the three
    zones), so TZ-1's property `L(R(w)) ≥ w` does not hold for R_plan in this one case. It never
    rings later than R, the alarm is still never dropped (it rings once, on its planned day), and
    it stays monotone in the reading within a day. It applies only where the next-date case
    occurs, which the zone's own rules decide (TZ-3) - no zone is named in code.
  - **The planned reading is kept.** The day's intended reading stays 23:30, so the next day is
    planned from 23:30, not from 22:59; FR-4 does not drift from the pulled-forward value.
  - **Scope:** planned values of the scheduling engine (FR-4, FR-6/FR-7, FR-10) **and manual
    alarms** (`nextManualOccurrence`). Maintainer, 2026-09-28: "Greenland: Yes. Manual alarms:
    yes." A manual 23:30 on that night in Nuuk rings at 22:59 on the 28th, like a scheduled one.
- **TZ-3 · Every region.** TZ-1, TZ-2 and TZ-2a hold in every IANA time zone: southern hemisphere, half-
  and quarter-hour offsets, 30-minute DST (Lord Howe), zones without DST, and zones whose rules
  change. The transition rules come from the device's time zone database, never from values
  hard-coded in the app ("wenn das Android schon kann, dann wäre es klüger als selbst
  implementieren") - only the resolution of the repeated / skipped hour (TZ-1) is the app's own
  rule, because the platform defaults differ from it.
- **TZ-8 (DST part) · Sleep time and bedtime reminder follow the same rules.** The Do Not Disturb
  window and the bedtime reminder are derived from the same instants as the alarms and are not an
  hour off either (maintainer: "genau"). **The Sleep Goal counts real hours, not a clock
  difference** (Markus's recommendation, maintainer: "ich empfehle das auch"): an 8-hour goal
  before a 07:00 alarm starts sleep time 8 real hours earlier, so in Europe/Berlin it starts at
  22:00 by the clock on a spring-forward night (9 hours of clock difference, 8 of sleep) and at
  00:00 on a fall-back night (7 hours of clock difference, 8 of sleep). This is what `sleepTimeWindow` already does
  (`target.subtract(sleepGoal)` on the instant).
  - **Consequence of TZ-2 (decision A), T-206:** because a scheduled 07:00 now rings at 07:00 by
    the clock on the change day, the window and the reminder follow it: on the spring night an 8 h
    goal starts sleep time at 22:00 CET (today, with the value an hour late at 08:00 CEST, it
    starts at 23:00). Decision A makes the night shorter or longer by the clock; it does not change
    the window's length, which stays the Sleep Goal in real hours. Nothing in
    `sleep_time_dnd.dart`, `sleep_reminder.dart` or `next_wake_up.dart` changes - they consume the
    planned instants.
  - **Consequence of TZ-2a:** where a planned value is pulled forward to the minute before a gap
    (Nuuk), the window ends at that pulled-forward instant and starts one Sleep Goal before it.
  - **No stale value in between:** FR-16's Checkpoint 2 must not shift a correctly resolved value
    after a change (T-206), or the window, the reminder and the direct-boot fallback would read the
    wrong hour until the next replan.
- **TZ-9 (DST part) · Verifiability.** Each rule is covered by tests that sweep all IANA zones and
  all 2026/2027 transitions against an independently computed expectation (the pattern of the
  T-201 review); time zone fixtures are `tz.TZDateTime`, never `DateTime.utc` (maintainer: "klingt
  gut").
  - **For TZ-2/TZ-2a (T-206):** the planning engine takes the zone's rules as a function, so its
    tests can inject any zone's rules and run identically in every CI leg. The all-zone sweep
    runs in CI's UTC leg only (it does not depend on the process zone), against a checked-in
    expectation table for every zone with a 2026/27 transition, computed by a brute-force minute
    scan independent of the app's algorithm. *Changed in T-206's implementation step:* the table's
    data is `package:timezone`'s own database - the rules the sweep plans with - not Python
    `zoneinfo`'s; a table from another database turned the databases' differences (nine zones)
    into apparent planning defects. The system tzdata is compared informationally (State, below).
    The sweep covers
    the pure planning layer only; persistence, FR-16's Checkpoint 2 and the production rules
    adapter are covered by process-zone tests in all ten CI legs (each leg exercises its own
    transitions, and UTC/Tokyo the no-transition branch). TZ-2a is exercised in the America/Nuuk
    leg.
  - Real-device evidence stays a manual step (`docs/device-trial-checklist.md`): the tests cannot
    show that Dart's local conversion reflects the phone's own tz database for future instants.

State (2026-09-29):

- **TZ-1 - met** (`docs/TODO.md` T-202). Appointment/planned alarms keep their exact instant through
  every hand-off to the platform (the alarm plugin, including its own persisted copy; the app's
  alarm list; the Do Not Disturb window; the bedtime reminder). Manual alarms resolve the repeated
  and the skipped hour by the rule above, in one place (`lib/utils/wall_clock.dart`,
  `resolveWallClock`, reached through `resolvePlannedClockTime` since T-206), using the device's
  zone rules.
- **TZ-8 (DST part) - met for the change hour** (same fix): the window and the reminder are derived
  from the same instants as the alarms.
- **TZ-2 / TZ-2a - met** (`docs/TODO.md` T-206, implemented 2026-09-29 and reviewed independently
  the same day - "go with changes", both blocking items fixed; **not yet in a release, the
  maintainer's acceptance is not recorded, and not yet confirmed on a device** - the checklist lines
  F3/F4 in `docs/device-trial-checklist.md`). The planning engine plans wall-clock values as local readings
  and resolves each day with that day's own rules (`resolvePlannedClockTime`, R_plan), caps at an
  appointment on instants after that, measures `maxDailyDelta` and FR-6's warning on readings,
  assigns an appointment by the rules at its own instant, stores each day's planned clock time
  (`pendingDayClockTimes`), and FR-16's Checkpoint 2 re-resolves those instead of shifting by the
  offset difference. Manual alarms use R_plan too (TZ-2a's scope). Until a real change has been
  watched on a device, "met" means: in code and in tests, all ten CI legs.
- **TZ-9 (DST part) - met, with one known limitation.** Tests derive the process zone's own
  2026/27 transitions at runtime and run under all ten CI zones; fixtures are `tz.TZDateTime` or
  injected zone rules. The all-zone sweep (`test/t206_dst_sweep_test.dart`, every zone with a
  2026/27 transition, CI's UTC leg) plans with `package:timezone`'s rules and so checks against a
  brute-force table generated from **that package's own database**
  (`scripts/gen_dst_fixture.dart`) - a table from another database would report the databases'
  differences as planning defects. **Limitation:** a device uses the operating system's tzdata,
  which may be newer than the package's bundled one (0.11.1: 2025c; nine zones differ from 2026c).
  The system tzdata is compared informationally: a Python `zoneinfo` table
  (`scripts/gen_dst_fixture.py`) names the differing zones as a skip reason, and must agree
  exactly wherever the rules agree.

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
- FR-16's accepted transition-day limitation (T-85e) is **withdrawn** in the spec by T-206 (a DST
  change needs no checkpoint once each day is resolved with its own rules). T-206 also makes Checkpoint 2 re-resolve a stored planned reading under
  the current rules instead of shifting by the offset difference - the natural basis for TZ-4 -
  but that is not a travel promise: re-arming (T-113) and the date line (TZ-7) stay open, and
  `pendingDayClockTimes` is keyed by the calendar date in the zone the plan was made in.
