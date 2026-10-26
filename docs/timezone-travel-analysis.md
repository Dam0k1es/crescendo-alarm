# Time zone travel analysis - Tom's world trip

> **Status:** working material, not a specification. The requirements themselves live in
> [`timezone-requirements.md`](timezone-requirements.md) and are not repeated here; this file only
> refers to them by ID (TZ-1 … TZ-9).
>
> **Scope, as decided by the maintainer on 2026-09-28:** daylight saving changes *within one
> region* (TZ-1, TZ-2, TZ-3, and the DST parts of TZ-8/TZ-9) are **committed** and being fixed now
> (`docs/TODO.md` T-202). Travelling across time zones (TZ-4, TZ-6, TZ-7 and the travel parts of
> TZ-8/TZ-9) is **provisional and not promised**; travel combined with DST in several regions (TZ-5)
> is explicitly not promised as functional. Accordingly, this document has two parts:
>
> - **Part I - DST within one region.** Findings that feed the fix being done now. Kept separate on
>   purpose.
> - **Part II - Travel.** "Where to resume" material for the provisional requirements: what the
>   current code actually does on a real itinerary, why, and which decisions are still open.
>
> Everything below was measured against the `dev` worktree at `e8eacbb` (2026-09-28). Nothing in
> `lib/`, `test/` or any other tracked file was changed; all simulation code was temporary and has
> been deleted. Section 7 lists what could **not** be verified.

## 1. Summary

### Part I - DST within one region (committed scope)

Ranked by the risk of oversleeping or missing an appointment.

1. **Scheduled wall-clock values are an hour off on the transition day, and the error takes
   several days to go away** (TZ-2 ✗). In Europe/Berlin with `preferredWakeUpTime` 07:00 and
   `maxDailyDelta` 30 min, the real `replan()` plans **08:00 CEST on the spring-forward day
   (Sun 28 Mar 2027, one hour late: oversleeping)** and 07:30 the day after; in autumn it plans
   06:00 CET on Sun 31 Oct 2027 and 06:30 the day after. Cause: one `deviceUtcOffset` for the whole
   7-day window (`lib/models/scheduling/replan.dart:102`), so every window day after the transition
   is computed with the old offset. FR-4 then drifts back from that wrong anchor by only
   `maxDailyDelta` a day. That contradicts T-85e, which says the error is "corrected at the ring
   checkpoint that same morning or at the latest the following day". At 30 min it takes two days;
   at 15 min it would take four.
2. **T-202 is confirmed for a real appointment alarm, not only for Do Not Disturb.** An appointment
   whose `hardFloor` falls in the second 02:30 of 31 Oct 2027 (CET) is handed to the plugin as the
   first 02:30 (CEST): it rings **one hour early**, and the sleep-time window ends an hour early as
   well (`lib/utils/utils.dart:199-202`, `lib/utils/sleep_time_dnd.dart:119`).
3. **None of the three platform defaults matches the maintainer's TZ-1 decision**, so the fix has
   to resolve both cases explicitly (table in section 3.1). Dart's `DateTime(...)` picks the
   *first* occurrence of a repeated time in every zone tested, and shifts a skipped time by the gap
   length (02:30 → 03:30). `package:timezone` picks the *later* occurrence in some zones but the
   *first* in others: first in America/New_York, Havana, Nuuk, Santiago and St_Johns. `java.time`
   picks the earlier occurrence and shifts by the gap length. The decision says "later" for a
   repeated time and "first valid instant", i.e. 03:00, for a skipped one.
4. **Manual alarms survive DST correctly** (07:00 every day on both 2027 transitions), because
   `nextManualOccurrence` rebuilds the local time for the target date. The only deviations are
   inside the change hour itself, per item 3.
5. **Caveat for the T-202 fix:** `ScheduledAlarm` persists its time as a local ISO string with no
   offset (`lib/models/alarms/scheduled_alarm.dart:74`, parsed back at `:48`). A second-pass
   instant written this way comes back as the first pass after any process restart. Within one
   region this only affects the repeated hour. It is the same defect that dominates Part II
   (finding T5).

### Part II - Travel (provisional scope, "where to resume")

Ranked by risk. The trip covers 10 legs and 34 days, and every leg fails at least one expectation.

1. **T1 - Wall-clock scheduled values never reach local time during the trip.** On gap days with
   `preferredWakeUpTime` 07:00, the plan keeps the *instant* of the last rung value and drifts it
   by `maxDailyDelta` per day. The results are "jet lag by design": New York 02:30 → 04:00 over
   four days, Tokyo 18:00 → 16:30, Honolulu 22:00 → 23:30, Kolkata 13:30 → 12:00. FR-16's
   same-digits rule never survives. Checkpoint 2 *does* reinterpret the stored values, which was
   measured directly, but the next replan recomputes the window from the old anchor instant
   (`scheduling_v2.dart:188-221`, `replan.dart:246`). Checkpoint 1, meanwhile, only records the new
   offset (`checkpoint.dart:202`) and reinterprets nothing.
2. **T2 - The first manual alarm after every flight rings at the old instant.** Eastbound this
   means **late**: Honolulu at 12:00 instead of 07:00, Kathmandu at 07:15. Westbound it means early
   *plus* a second ring at 07:00 on the same morning, on 7 of the 10 legs: London 06:00, New York
   02:00, Singapore 01:00. Nothing re-arms a manual alarm on a zone change
   (apart from add, edit and toggle, `lib/models/alarms/handler.dart:342` is the only re-arm path).
3. **T4 - An appointment entered in the origin zone is honoured as stored, so every real meeting
   east of Berlin is missed.** An event stored as 08:00 Europe/Berlin but meant as local time gives
   alarms at 14:00 in Tokyo, 13:00 in Singapore, 10:30 in Kolkata, 10:45 in Kathmandu and 09:00 in
   Dubai. In Honolulu it rings the evening before. The alarm is correct for the *data*; this is the
   maintainer's objection, answered in section 4.
4. **T5 - After a process restart in a new zone, the app's alarm list and the platform
   disagree.** FR-18 keeps a wrong platform alarm because the list entry *looks* right:
   `ScheduledAlarm.time` is stored as local digits without an offset. This produces double rings
   (Tokyo 18:00 + 19:00, Singapore 17:00 + 18:00). Back home in Berlin it leaves alarms at **05:00
   while the plan and the alarm list say 07:00**, for up to a week.
5. **T3 - Appointment alarms with correct data are never late, but often much too early. One was
   effectively missed.** The planned value is the minimum of the curve and the `hardFloor`. The
   curve carries the old instant, so New York gets 01:00 or 02:30 instead of 07:00. FR-5/FR-6 also
   pre-shift the curve toward an appointment in a *later* zone of the trip. For the San Francisco
   meeting on Tue 22 Jun this put the only alarm at 21:38 the evening before, in flight, and gave
   no morning alarm at all.
6. **T6 - Date line: the stored day keys are local dates of the zone they were planned in.** After
   a westbound crossing, a value filed under "Fri 2 Jul" falls on Sat 3 Jul locally, so Singapore
   gets 01:00 *and* 07:00. After an eastbound crossing without an app open, Honolulu gets two rings
   an hour apart (21:30 and 22:30) (TZ-7 ✗).
7. **T7 - Sleep time and bedtime reminder keep the old instants until the next push.** On landing
   in Honolulu at 09:00, "alarms only" Do Not Disturb stays active until 12:00. After a push, a
   manual alarm's window is computed from *local now* (07:00) while the armed alarm is still at the
   old instant: in New York Do Not Disturb runs until 07:00 although the alarm rang at 02:00 (TZ-8
   ✗).
8. **T8 - Calendar changes reach the alarms only at app open, a scheduled ring, a settings change,
   or Sync.** There is no calendar observer. `PROVIDER_CHANGED` cannot reach a manifest receiver
   on Android 8+, and a content-URI job would be the native route (section 4.4).

## 2. Itinerary

All zones were verified with Python `zoneinfo` to have **no offset change between 1 Jun and 31 Jul
2027**, so no DST effect is mixed into Part II. The phone is assumed to switch zones **at landing**:
in airplane mode, the zone stays the origin's until network time or location updates it. The
emulated rings follow that phone clock. ✈ marks a ring that falls during a flight; its time is shown on the phone clock, i.e. the origin zone.

| # | From → To | Departure (UTC) | Departure (local) | Arrival (UTC) | Arrival (local) | Offset change |
| L1 | Europe/Berlin → Europe/London | 15 Jun 08:00 | Tue 15 Jun 10:00 (+02:00) | 15 Jun 09:55 | Tue 15 Jun 10:55 (+01:00) | −1:00 |
| L2 | Europe/London → America/New_York | 17 Jun 10:00 | Thu 17 Jun 11:00 (+01:00) | 17 Jun 18:00 | Thu 17 Jun 14:00 (-04:00) | −5:00 |
| L3 | America/New_York → America/Los_Angeles | 21 Jun 22:00 | Mon 21 Jun 18:00 (-04:00) | 22 Jun 04:30 | Mon 21 Jun 21:30 (-07:00) | −3:00 |
| L4 | America/Los_Angeles → Asia/Tokyo | 24 Jun 18:00 | Thu 24 Jun 11:00 (-07:00) | 25 Jun 05:30 | Fri 25 Jun 14:30 (+09:00) | +16:00 |
| L5 | Asia/Tokyo → Pacific/Honolulu | 28 Jun 12:00 | Mon 28 Jun 21:00 (+09:00) | 28 Jun 19:00 | Mon 28 Jun 09:00 (-10:00) | −19:00 |
| L6 | Pacific/Honolulu → Asia/Singapore | 01 Jul 22:00 | Thu 01 Jul 12:00 (-10:00) | 02 Jul 15:30 | Fri 02 Jul 23:30 (+08:00) | +18:00 |
| L7 | Asia/Singapore → Asia/Kolkata | 05 Jul 00:00 | Mon 05 Jul 08:00 (+08:00) | 05 Jul 04:00 | Mon 05 Jul 09:30 (+05:30) | −2:30 |
| L8 | Asia/Kolkata → Asia/Kathmandu | 08 Jul 06:30 | Thu 08 Jul 12:00 (+05:30) | 08 Jul 07:45 | Thu 08 Jul 13:30 (+05:45) | +0:15 |
| L9 | Asia/Kathmandu → Asia/Dubai | 10 Jul 15:15 | Sat 10 Jul 21:00 (+05:45) | 10 Jul 20:00 | Sun 11 Jul 00:00 (+04:00) | −1:45 |
| L10 | Asia/Dubai → Europe/Berlin | 12 Jul 22:30 | Tue 13 Jul 02:30 (+04:00) | 13 Jul 05:15 | Tue 13 Jul 07:15 (+02:00) | −2:00 |

Tom's home settings, set in Berlin on Sat 12 Jun 20:00 CEST: `preferredWakeUpTime` 07:00,
`maxDailyDelta` 30 min, `durationToWakeUp` 15 min, `durationToGetReady` 45 min (60 min lead in
total), Sleep Goal 8 h, bedtime reminder 30 min, sleep-time Do Not Disturb on.

## 3. Per-scenario results

### How the numbers were produced

- **Engine values are real.** A temporary `flutter test` harness (outside the repo) drove the
  production entry points: `runSchedulingCheckpoint` / `runCheckpointSafely`, which include
  `replan()` and FR-18's `applyPlannedAlarms`; `runTimezoneCheckpoint2`; `setManualAlarmEnabled`
  (the `Handler.onAlarmHandled` re-arm path); `scheduleSleepReminder`; and `refreshSleepTimeDnd`.
  The only injections were `fetchEvents`, `now`, a recording `Notifications` and a recording
  `pushSleepTimeWindow`.
- **One process per stay, with the process `TZ` set to that stay's zone.** `now` is a real local
  `DateTime` and **no `deviceUtcOffset` was injected**, so the offset comes from the same place as
  on the device (`currentTime.timeZoneOffset`). State is carried between processes via a dump of
  the mocked `SharedPreferences`.
  - **"Cold"** variants are exactly that: the process restarted during the flight.
  - **"Warm"** variants (suffix `w`) rewrite the persisted alarm list so it keeps its instants. That
    is what a process that stayed alive would hold in memory.
- **The platform is emulated from the app's calls.** The `alarm` plugin has no channel in
  `flutter test`, so the harness keeps its own `id → epoch` map: an id armed via
  `alarmPlatformTime(time)` is added, and removal by id is `Alarm.stop`. **Rings are driven by that
  map, not by the app's list.** That is what exposed T5.
- **A ring is simulated in production order:** ring checkpoint (scheduled alarms only), then the
  resume triggered by the full-screen intent (`appForeground` + `manualSync`), then
  `onAlarmHandled` (reminder → Checkpoint 2 → re-arm → Do Not Disturb push).
- **"App opened" means the cold-start/resume sequence** of `lib/main.dart:335-376`, run 30 minutes
  after landing.
- **Expected values are independent.** A Python `zoneinfo` walk of the phone clock minute by
  minute gives "the first 07:00 on the phone clock after the previous ring". For appointments it
  gives the event instant minus 60 minutes. The Dart engine is not used to compute them. For (A),
  a separate Python model of the current code (armed instant kept; re-arm at the next local 07:00)
  reproduces every simulated ring exactly.

### 3.1 Part I - DST within one region (Europe/Berlin, committed scope)

**TZ-1: what the defaults do.** Measured empirically: Dart under `TZ=<zone>` in `flutter test`,
across 52 transitions in 2026-2027 in 15 sample zones, 13 of them with DST (Berlin, London, New York, St_Johns, Havana,
Santiago, Nuuk, Beirut, Cairo, Troll, Lord_Howe, Sydney, Chatham, Tehran, Kolkata). Java was run on
OpenJDK 17 on the VM.

| Resolution of … | Repeated time (e.g. 02:30 on 25 Oct 2026) | Skipped time (e.g. 02:30 on 29 Mar 2026) | Matches TZ-1 decision? |
|---|---|---|---|
| Maintainer decision (TZ-1) | **later** occurrence (02:30 CET) | **first valid instant** (03:00 CEST) | - |
| Dart `DateTime(y,m,d,h,min)` (used by `nextManualOccurrence`, `alarmPlatformTime`, `DateTime.parse`) | first, in all 26 overlaps tested | shifted by the gap (03:30), in all 26 gaps tested | ✗ / ✗ |
| `package:timezone` `TZDateTime(loc, …)` | later in 16 overlaps, **first** in 10 (all five negative-offset zones: New York, St_Johns, Havana, Nuuk, Santiago) | shifted by the gap (03:30) everywhere | inconsistent / ✗ |
| `java.time` `ZonedDateTime.of(ldt, zone)` | earlier (`withLaterOffsetAtOverlap()` gives the later one) | shifted by the gap (03:30); `ZoneRules.getTransition(ldt).getInstant()` gives 03:00 | ✗ by default, both available explicitly |
| `java.util.Calendar` (lenient, OpenJDK 17) | later (01:30Z) | shifted (03:30) | ✓ / ✗ (Android's ICU-backed `Calendar` not tested) |

Consequence for the fix: neither Dart default can be relied on. The one API family that offers both
decisions explicitly is `java.time`: `withLaterOffsetAtOverlap` for the repeated time, and the
transition instant for the gap. In Dart the same can be obtained from the OS's own local-time
conversion, by probing the two candidate offsets of the day. That keeps TZ-3's "rules from the
device" intact. `package:timezone` would substitute its own bundled database for the device's.

**TZ-2: what the engine does across a transition** (warm and cold identical; manual = one daily
07:00 manual alarm; scheduled = gap days with `preferredWakeUpTime` 07:00):

| Transition | Alarm kind | Expected (TZ-2) | Actual per day (Berlin local) | |
|---|---|---|---|---|
| Spring, Sun 28 Mar 2027 | scheduled wall-clock | 07:00 every day | Fri 07:00, Sat 07:00, **Sun 08:00 CEST**, Mon 07:30, Tue 07:00 | ✗ - 1 h late on the day, 30 min the next |
| Autumn, Sun 31 Oct 2027 | scheduled wall-clock | 07:00 every day | Fri 07:00, Sat 07:00, **Sun 06:00 CET**, Mon 06:30, Tue 07:00 | ✗ - 1 h early, then 30 min |
| Both | manual 07:00 | 07:00 every day | 07:00 every day | ✓ |
| Autumn, appointment at 03:30 CET → `hardFloor` 02:30 CET (second pass) | appointment | 02:30 CET (01:30Z) | armed and rang at **02:30 CEST (00:30Z)**; Do Not Disturb window end at 02:30 CEST too | ✗ - T-202 |

Locators: the offset is fixed once per replan (`replan.dart:102`) and passed to `computeWeekPlan`
for all 7 days. `applyGapDayDrift` (`scheduling_v2.dart:188`) and `coldStart` combine
`preferredWakeUpTime` with that one offset. The anchor of the following day is the value that
actually rang (`replan.dart:246`), and FR-4 moves away from it by `maxDailyDelta` at most. FR-16's
T-85e paragraph ("corrected … at the latest the following day") is therefore not accurate for
`maxDailyDelta` below one hour.

### 3.2 Part II - (A) Manual daily alarm 07:00, armed at home

| Stay (zone) | Expected (07:00 on the phone clock) | Actual (simulated) | |
|---|---|---|---|
| Europe/Berlin | Sun 13 07:00, Mon 14 07:00, Tue 15 07:00 | Sun 13 07:00, Mon 14 07:00, Tue 15 07:00 | ✓ |
| Europe/London | Wed 16 07:00, Thu 17 07:00 | Wed 16 06:00, Wed 16 07:00, Thu 17 07:00 | ✗ |
| America/New_York | Fri 18 07:00, Sat 19 07:00, Sun 20 07:00, Mon 21 07:00 | Fri 18 02:00, Fri 18 07:00, Sat 19 07:00, Sun 20 07:00, Mon 21 07:00 | ✗ |
| America/Los_Angeles | Tue 22 07:00, Wed 23 07:00, Thu 24 07:00 | Tue 22 04:00, Tue 22 07:00, Wed 23 07:00, Thu 24 07:00 | ✗ |
| Asia/Tokyo | Sat 26 07:00, Sun 27 07:00, Mon 28 07:00 | Fri 25 23:00, Sat 26 07:00, Sun 27 07:00, Mon 28 07:00 | ✗ |
| Pacific/Honolulu | Tue 29 07:00, Wed 30 07:00, Thu 01 07:00 | Mon 28 12:00, Tue 29 07:00, Wed 30 07:00, Thu 01 07:00 | ✗ |
| Asia/Singapore | Sat 03 07:00, Sun 04 07:00, Mon 05 07:00 | Sat 03 01:00, Sat 03 07:00, Sun 04 07:00, Mon 05 07:00 | ✗ |
| Asia/Kolkata | Tue 06 07:00, Wed 07 07:00, Thu 08 07:00 | Tue 06 04:30, Tue 06 07:00, Wed 07 07:00, Thu 08 07:00 | ✗ |
| Asia/Kathmandu | Fri 09 07:00, Sat 10 07:00 | Fri 09 07:15, Sat 10 07:00 | ✗ |
| Asia/Dubai | Sun 11 07:00, Mon 12 07:00, Tue 13 07:00 ✈ | Sun 11 05:15, Sun 11 07:00, Mon 12 07:00, Tue 13 07:00 ✈ | ✗ |
| Europe/Berlin | Wed 14 07:00, Thu 15 07:00 | Wed 14 05:00, Wed 14 07:00, Thu 15 07:00 | ✗ |

- **Why:**
  - The armed platform alarm is an epoch instant (`alarm-5.12.0/lib/model/alarm_settings.dart:315`,
    reached via `lib/app_state.dart:1094-1110` and `alarmPlatformTime`).
  - A manual alarm is re-armed only on add, edit and toggle (`app_state.dart:877`, `:964`,
    `:1060`) and after it rings (`handler.dart:342`).
  - `replan` never touches it (FR-15). There is no `ACTION_TIMEZONE_CHANGED` / `TIME_SET` receiver
    anywhere in `android/app/src/main`, in the `alarm` plugin, or in `awesome_notifications`
    0.12.1's manifests.
- **Second day after each arrival:** ✓ in every stay. The post-ring re-arm uses the new local now
  (`manual_alarm_enable.dart:72-95`), so from the second ring on it is 07:00 local.
- **Pattern:**
  - After a **westbound** jump the stale ring comes early, followed by a second ring at 07:00 the
    same morning. That is a double ring on 7 legs: London, New York, San Francisco, Singapore,
    Kolkata, Dubai, Berlin.
  - After an **eastbound** jump it comes **late**: Honolulu 12:00 (+5 h, because Tokyo→Honolulu is
    −19 h ≡ +5 h), Kathmandu 07:15 (+15 min). This is the oversleeping case. A trip in the
    opposite direction would make almost every leg late.
  - Tokyo (+16 h ≡ −8 h) gets an extra ring at 23:00 on the evening of arrival.
- **During a flight:** the Dubai→Berlin night flight rings at 07:00 Dubai time (03:00Z, over the
  sea), which is what "the phone clock" also expects. Whether that is wanted is open decision Q4.

### 3.3 Part II - (B) Scheduled wall-clock values with the real engine

**B1w** - app opened 30 min after each landing, process stayed alive:

| Stay (zone) | Expected (07:00 local, FR-16 same digits) | Actual (simulated) | |
|---|---|---|---|
| Europe/Berlin | Sun 13 07:00, Mon 14 07:00, Tue 15 07:00 | Sun 13 07:00, Mon 14 07:00, Tue 15 07:00 | ✓ |
| Europe/London | Wed 16 07:00, Thu 17 07:00 | Wed 16 06:30, Thu 17 07:00 | ✗ |
| America/New_York | Fri 18 07:00, Sat 19 07:00, Sun 20 07:00, Mon 21 07:00 | Fri 18 02:30, Sat 19 03:00, Sun 20 03:30, Mon 21 04:00 | ✗ |
| America/Los_Angeles | Tue 22 07:00, Wed 23 07:00, Thu 24 07:00 | Tue 22 01:30, Wed 23 02:00, Thu 24 02:30 | ✗ |
| Asia/Tokyo | Sat 26 07:00, Sun 27 07:00, Mon 28 07:00 | Fri 25 18:00, Sat 26 17:30, Sun 27 17:00, Mon 28 16:30 | ✗ |
| Pacific/Honolulu | Tue 29 07:00, Wed 30 07:00, Thu 01 07:00 | Mon 28 22:00, Tue 29 22:30, Wed 30 23:00, Thu 01 23:30 ✈ | ✗ |
| Asia/Singapore | Sat 03 07:00, Sun 04 07:00, Mon 05 07:00 | Sat 03 17:00, Sun 04 16:30 | ✗ |
| Asia/Kolkata | Tue 06 07:00, Wed 07 07:00, Thu 08 07:00 | Mon 05 13:30, Tue 06 13:00, Wed 07 12:30, Thu 08 12:00 ✈ | ✗ |
| Asia/Kathmandu | Fri 09 07:00, Sat 10 07:00 | Fri 09 11:45, Sat 10 11:15 | ✗ |
| Asia/Dubai | Sun 11 07:00, Mon 12 07:00, Tue 13 07:00 ✈ | Sun 11 09:00, Mon 12 08:30, Tue 13 08:00 ✈ | ✗ |
| Europe/Berlin | Wed 14 07:00, Thu 15 07:00 | Wed 14 06:30, Thu 15 07:00 | ✗ |

**B2w** - app never opened after landing, only rings (process alive):

| Stay (zone) | Expected (07:00 local) | Actual (simulated) | |
|---|---|---|---|
| Europe/Berlin | Sun 13 07:00, Mon 14 07:00, Tue 15 07:00 | Sun 13 07:00, Mon 14 07:00, Tue 15 07:00 | ✓ |
| Europe/London | Wed 16 07:00, Thu 17 07:00 | Wed 16 06:00, Thu 17 06:30 | ✗ |
| America/New_York | Fri 18 07:00, Sat 19 07:00, Sun 20 07:00, Mon 21 07:00 | Fri 18 02:00, Sat 19 02:30, Sun 20 03:00, Mon 21 03:30 | ✗ |
| America/Los_Angeles | Tue 22 07:00, Wed 23 07:00, Thu 24 07:00 | Tue 22 01:00, Wed 23 01:30, Thu 24 02:00 | ✗ |
| Asia/Tokyo | Sat 26 07:00, Sun 27 07:00, Mon 28 07:00 | Fri 25 18:30, Sat 26 18:00, Sun 27 17:30, Mon 28 17:00 | ✗ |
| Pacific/Honolulu | Tue 29 07:00, Wed 30 07:00, Thu 01 07:00 | Mon 28 21:30, Mon 28 22:30, Tue 29 23:00, Wed 30 23:30, Fri 02 00:00 ✈ | ✗ |
| Asia/Singapore | Sat 03 07:00, Sun 04 07:00, Mon 05 07:00 | Sat 03 18:30, Sun 04 18:00 | ✗ |
| Asia/Kolkata | Tue 06 07:00, Wed 07 07:00, Thu 08 07:00 | Mon 05 15:00, Tue 06 14:30, Wed 07 14:00 | ✗ |
| Asia/Kathmandu | Fri 09 07:00, Sat 10 07:00 | Thu 08 13:45, Fri 09 13:15, Sat 10 12:45 | ✗ |
| Asia/Dubai | Sun 11 07:00, Mon 12 07:00, Tue 13 07:00 ✈ | Sun 11 10:30, Mon 12 10:00 | ✗ |
| Europe/Berlin | Wed 14 07:00, Thu 15 07:00 | Tue 13 07:30, Wed 14 07:00, Thu 15 07:00 | ✗ |

**B1** - as B1w, but the process was restarted during each flight (cold start):

| Stay (zone) | Expected (07:00 local) | Actual (simulated) | |
|---|---|---|---|
| Europe/Berlin | Sun 13 07:00, Mon 14 07:00, Tue 15 07:00 | Sun 13 07:00, Mon 14 07:00, Tue 15 07:00 | ✓ |
| Europe/London | Wed 16 07:00, Thu 17 07:00 | Wed 16 06:30, Thu 17 06:00 | ✗ |
| America/New_York | Fri 18 07:00, Sat 19 07:00, Sun 20 07:00, Mon 21 07:00 | Fri 18 02:30, Sat 19 03:00, Sun 20 03:30, Mon 21 04:00 | ✗ |
| America/Los_Angeles | Tue 22 07:00, Wed 23 07:00, Thu 24 07:00 | Tue 22 01:30, Wed 23 02:00, Thu 24 02:30 | ✗ |
| Asia/Tokyo | Sat 26 07:00, Sun 27 07:00, Mon 28 07:00 | Fri 25 18:00, Fri 25 19:00, Sat 26 17:30, Sun 27 17:00, Mon 28 16:30 | ✗ |
| Pacific/Honolulu | Tue 29 07:00, Wed 30 07:00, Thu 01 07:00 | Mon 28 22:00, Tue 29 22:30, Wed 30 23:00, Thu 01 23:30 ✈ | ✗ |
| Asia/Singapore | Sat 03 07:00, Sun 04 07:00, Mon 05 07:00 | Sat 03 17:00, Sat 03 18:00, Sun 04 16:30 | ✗ |
| Asia/Kolkata | Tue 06 07:00, Wed 07 07:00, Thu 08 07:00 | Mon 05 13:30, Tue 06 13:00, Wed 07 12:30, Thu 08 12:00 ✈ | ✗ |
| Asia/Kathmandu | Fri 09 07:00, Sat 10 07:00 | Fri 09 11:45, Sat 10 11:15 | ✗ |
| Asia/Dubai | Sun 11 07:00, Mon 12 07:00, Tue 13 07:00 ✈ | Sun 11 09:00, Mon 12 08:30, Tue 13 08:00 ✈ | ✗ |
| Europe/Berlin | Wed 14 07:00, Thu 15 07:00 | Wed 14 06:30, Thu 15 05:00 | ✗ |

- **Why, step by step:**
  - After landing, the next checkpoint (app open or ring) replans the window.
  - Its anchor is `lastEffectiveWakeTime`, the stored instant of the last concluded day.
  - `applyGapDayDrift` reads that instant **in the new offset**: 07:00 London is 02:00 in New
    York. It then moves it toward `preferredWakeUpTime` by `maxDailyDelta` at most, choosing the
    shorter way round the clock (`_wallClockDelta`, ±12 h, `scheduling_v2.dart:78`). That is why
    Tokyo drifts *earlier*, 18:00 → 16:30, toward 07:00.
- **Is it the spec, or the implementation?** Both. FR-1's own test ("anchor 07:00 CET, hardFloor
  07:00 JST → ΔT = 8 h") and FR-4 ("drifts toward `preferredWakeUpTime` … bounded by
  `maxDailyDelta`") produce exactly this. FR-16 says wall-clock values keep their digits, but only
  says so for the *stored plan*, and adds "no full recomputation … that only follows at the next
  regular planning run". That next run undoes it.
  - **What Checkpoint 2 does.** In variant `B3w` (not tabled; its rings are identical to `B1w`),
    Checkpoint 2 was run *before* the first checkpoint on landing, as a lost-event replay at
    `setListeners` would do (T-199). It rewrote the stored values to 07:00 local exactly as
    specified, and the checkpoint a moment later replaced them with the drift values.
  - **Why Checkpoint 2 rarely even sees the change.** Every checkpoint records the new offset
    first (`checkpoint.dart:202`), so the reminder it schedules triggers a Checkpoint 2 that
    compares equal offsets.
- **What the maintainer would expect:** 07:00 local from the first morning (TZ-4, "wall-clock
  alarms follow the new local time"). **What the persona asks for:** "helps him adjust his sleep
  schedule … to different time zones". A gradual shift *could* be a feature, but only toward the
  zone Tom is in, over a bounded number of days, and never one that sets his alarm at 22:00 or
  16:30. As built, the drift has no notion of "adapting" at all. It is the gap-day smoothing rule
  applied to an instant that no longer means what it meant (open decision Q1).
- **Between landing and the next checkpoint**, the platform keeps the previous plan's instants,
  for example 01:00 in New York in the no-open variant. A checkpoint happens only at app open, at
  the next scheduled ring, on a settings change or on Sync; nothing reacts to the zone change
  itself.
- **Cold-start rows (last table): T5.** `ScheduledAlarm.toJson` writes `time.toIso8601String()` of a
  *local* `DateTime`, with no offset (`scheduled_alarm.dart:74`), and `DateTime.parse` reads it
  back as local digits in the *new* zone (`:48`). The app's list then shows "07:00" while the
  platform still holds the old instant. `planAlarmSync` matches by minute
  (`apply_alarms.dart:138`, `:191`) and finds the list entry "in plan", so it keeps it.
  - When the shift moves an entry into the past, it is never removed at all: past entries are
    protected, which is correct for a ringing alarm (FR-18). That produces the Tokyo 18:00 + 19:00
    and Singapore 17:00 + 18:00 double rings.
  - Back in Berlin the plan says 07:00 and the phone rings at 05:00, for every day that was armed
    before the flight (up to 7).

### 3.4 Part II - (C) Appointment alarm, event stored in the destination zone (the correct data)

One 08:00 local appointment on the first full day after each landing, stored with the destination's
zone. Expected: 07:00 local (instant − 60 min). A ring less than a minute off counts as a match; ✗
MISSED means no ring in the 12 h before the real meeting.

**C1w** - with `preferredWakeUpTime` 07:00 and gap days on (Tom's normal setup):

| Appointment (as stored) | Real meeting (local) | Expected alarm | Actual rings, 24 h before to 6 h after the real meeting | |
|---|---|---|---|---|
| Mon 14 Jun 08:00 Europe/Berlin | Mon 14 08:00 Europe/Berlin | Mon 14 07:00 | Mon 14 07:00 | ✓ |
| Wed 16 Jun 08:00 Europe/London | Wed 16 08:00 Europe/London | Wed 16 07:00 | Wed 16 06:30 | ✗ |
| Fri 18 Jun 08:00 America/New_York | Fri 18 08:00 America/New_York | Fri 18 07:00 | Fri 18 02:30 | ✗ |
| Tue 22 Jun 08:00 America/Los_Angeles | Tue 22 08:00 America/Los_Angeles | Tue 22 07:00 | Mon 21 21:38 ✈ | ✗ MISSED |
| Sat 26 Jun 08:00 Asia/Tokyo | Sat 26 08:00 Asia/Tokyo | Sat 26 07:00 | Sat 26 06:06 | ✗ |
| Tue 29 Jun 08:00 Pacific/Honolulu | Tue 29 08:00 Pacific/Honolulu | Tue 29 07:00 | Tue 29 03:01 ✈, Tue 29 07:00 | ✓ |
| Sat 03 Jul 08:00 Asia/Singapore | Sat 03 08:00 Asia/Singapore | Sat 03 07:00 | Sat 03 01:00, Sat 03 07:00 | ✗ |
| Tue 06 Jul 08:00 Asia/Kolkata | Tue 06 08:00 Asia/Kolkata | Tue 06 07:00 | Tue 06 05:00 | ✗ |
| Fri 09 Jul 08:00 Asia/Kathmandu | Fri 09 08:00 Asia/Kathmandu | Fri 09 07:00 | Fri 09 06:45 | ✗ |
| Mon 12 Jul 08:00 Asia/Dubai | Mon 12 08:00 Asia/Dubai | Mon 12 07:00 | Mon 12 06:15 | ✗ |
| Wed 14 Jul 08:00 Europe/Berlin | Wed 14 08:00 Europe/Berlin | Wed 14 07:00 | Wed 14 05:15 | ✗ |

**C2w** - appointment days only (`preferredWakeUpTime` unset, "schedule on gap days" off):

| Appointment (as stored) | Real meeting (local) | Expected alarm | Actual rings, 24 h before to 6 h after the real meeting | |
|---|---|---|---|---|
| Mon 14 Jun 08:00 Europe/Berlin | Mon 14 08:00 Europe/Berlin | Mon 14 07:00 | Mon 14 07:00 | ✓ |
| Wed 16 Jun 08:00 Europe/London | Wed 16 08:00 Europe/London | Wed 16 07:00 | Wed 16 06:00 | ✗ |
| Fri 18 Jun 08:00 America/New_York | Fri 18 08:00 America/New_York | Fri 18 07:00 | Fri 18 01:00 | ✗ |
| Tue 22 Jun 08:00 America/Los_Angeles | Tue 22 08:00 America/Los_Angeles | Tue 22 07:00 | Mon 21 21:00 ✈, Tue 22 07:00 | ✓ |
| Sat 26 Jun 08:00 Asia/Tokyo | Sat 26 08:00 Asia/Tokyo | Sat 26 07:00 | Sat 26 07:00 | ✓ |
| Tue 29 Jun 08:00 Pacific/Honolulu | Tue 29 08:00 Pacific/Honolulu | Tue 29 07:00 | Tue 29 07:00 | ✓ |
| Sat 03 Jul 08:00 Asia/Singapore | Sat 03 08:00 Asia/Singapore | Sat 03 07:00 | Sat 03 01:00, Sat 03 07:00 | ✗ |
| Tue 06 Jul 08:00 Asia/Kolkata | Tue 06 08:00 Asia/Kolkata | Tue 06 07:00 | Tue 06 07:00 | ✓ |
| Fri 09 Jul 08:00 Asia/Kathmandu | Fri 09 08:00 Asia/Kathmandu | Fri 09 07:00 | Fri 09 07:00 | ✓ |
| Mon 12 Jul 08:00 Asia/Dubai | Mon 12 08:00 Asia/Dubai | Mon 12 07:00 | Mon 12 07:00 | ✓ |
| Wed 14 Jul 08:00 Europe/Berlin | Wed 14 08:00 Europe/Berlin | Wed 14 07:00 | Wed 14 05:00 | ✗ |

- **Day assignment (FR-2) is right in every case.** `eventsForDay` buckets by the device offset at
  evaluation time (`scheduling_v2.dart:227`), and that offset is the destination's by the time the
  appointment day is planned. `hardFloor` itself is exactly instant − lead (`:242`).
- **What goes wrong is the value, not the bound.** The planned value is the curve, clamped to
  `hardFloor` only when the curve is *later* (FR-2's "upper bound"). The curve carries the old
  instant (T1), so a westbound jump leaves it earlier than the appointment requires: London 06:00,
  New York 01:00, Berlin on return 05:00. A `hardFloor` later than the curve never pulls it
  (`scheduling_v2.dart:416`, T-132 by design).
- **Cross-zone pre-shifting (C1w, San Francisco).** With several appointments in the window,
  FR-5/FR-6 build a run toward the *farthest* reachable point. That was the Tokyo appointment, and
  the run was computed by UTC time of day. The curve therefore shifted about 1 h 13 min per day
  (beyond `maxDailyDelta`, so an overrun), and the San Francisco day's value became 21:38 EDT the
  evening before, during the flight. No morning alarm remained for the 08:00 meeting.
- **Date line (C1w/C2w, Singapore): TZ-7.** The value stored under the key `2027-07-02`, planned in
  Honolulu, is 07:00 HST = 01:00 SGT on 3 Jul. The first replan in Singapore starts its window at
  3 Jul, keeps the out-of-window 2 Jul key (`replan.dart:280`, retention by design), and FR-18 arms
  every future value in the map. Result: 01:00 and 07:00.

### 3.5 Part II - (D) Appointment entered in the ORIGIN zone (08:00 Europe/Berlin, meant as local)

Same appointments, but every one stored as 08:00 **Europe/Berlin** on the intended date: what Tom
gets if he books them at home without changing the event's time zone. "data" is what the stored
event demands; "intent" is what Tom meant.

**D2w** - appointment days only:

| Appointment (as stored) | Real meeting (local) | Expected alarm | Actual rings, 24 h before to 6 h after the real meeting | |
|---|---|---|---|---|
| Mon 14 Jun 08:00 Europe/Berlin | Mon 14 08:00 Europe/Berlin | data: Mon 14 07:00 / intent: Mon 14 07:00 | Mon 14 07:00 | ✓ |
| Wed 16 Jun 08:00 Europe/Berlin | Wed 16 08:00 Europe/London | data: Wed 16 06:00 / intent: Wed 16 07:00 | Wed 16 06:00 | ✗ |
| Fri 18 Jun 08:00 Europe/Berlin | Fri 18 08:00 America/New_York | data: Fri 18 01:00 / intent: Fri 18 07:00 | Fri 18 01:00 | ✗ |
| Tue 22 Jun 08:00 Europe/Berlin | Tue 22 08:00 America/Los_Angeles | data: Mon 21 22:00 / intent: Tue 22 07:00 | Mon 21 22:00 | ✗ |
| Sat 26 Jun 08:00 Europe/Berlin | Sat 26 08:00 Asia/Tokyo | data: Sat 26 14:00 / intent: Sat 26 07:00 | Sat 26 14:00 (after meeting) | ✗ MISSED |
| Tue 29 Jun 08:00 Europe/Berlin | Tue 29 08:00 Pacific/Honolulu | data: Mon 28 19:00 / intent: Tue 29 07:00 | Mon 28 19:00 | ✗ MISSED |
| Sat 03 Jul 08:00 Europe/Berlin | Sat 03 08:00 Asia/Singapore | data: Sat 03 13:00 / intent: Sat 03 07:00 | Sat 03 13:00 (after meeting) | ✗ MISSED |
| Tue 06 Jul 08:00 Europe/Berlin | Tue 06 08:00 Asia/Kolkata | data: Tue 06 10:30 / intent: Tue 06 07:00 | Tue 06 10:30 (after meeting) | ✗ MISSED |
| Fri 09 Jul 08:00 Europe/Berlin | Fri 09 08:00 Asia/Kathmandu | data: Fri 09 10:45 / intent: Fri 09 07:00 | Fri 09 10:45 (after meeting) | ✗ MISSED |
| Mon 12 Jul 08:00 Europe/Berlin | Mon 12 08:00 Asia/Dubai | data: Mon 12 09:00 / intent: Mon 12 07:00 | Mon 12 09:00 (after meeting) | ✗ MISSED |
| Wed 14 Jul 08:00 Europe/Berlin | Wed 14 08:00 Europe/Berlin | data: Wed 14 07:00 / intent: Wed 14 07:00 | Wed 14 07:00 | ✓ |

**D1w** - with `preferredWakeUpTime` 07:00 (the curve can only make it earlier):

| Appointment (as stored) | Real meeting (local) | Expected alarm | Actual rings, 24 h before to 6 h after the real meeting | |
|---|---|---|---|---|
| Mon 14 Jun 08:00 Europe/Berlin | Mon 14 08:00 Europe/Berlin | data: Mon 14 07:00 / intent: Mon 14 07:00 | Mon 14 07:00 | ✓ |
| Wed 16 Jun 08:00 Europe/Berlin | Wed 16 08:00 Europe/London | data: Wed 16 06:00 / intent: Wed 16 07:00 | Wed 16 06:00 | ✗ |
| Fri 18 Jun 08:00 Europe/Berlin | Fri 18 08:00 America/New_York | data: Fri 18 01:00 / intent: Fri 18 07:00 | Fri 18 01:00 | ✗ |
| Tue 22 Jun 08:00 Europe/Berlin | Tue 22 08:00 America/Los_Angeles | data: Mon 21 22:00 / intent: Tue 22 07:00 | Mon 21 22:00, Mon 21 23:00 | ✗ |
| Sat 26 Jun 08:00 Europe/Berlin | Sat 26 08:00 Asia/Tokyo | data: Sat 26 14:00 / intent: Sat 26 07:00 | Sat 26 14:00 (after meeting) | ✗ MISSED |
| Tue 29 Jun 08:00 Europe/Berlin | Tue 29 08:00 Pacific/Honolulu | data: Mon 28 19:00 / intent: Tue 29 07:00 | Mon 28 17:30 | ✗ MISSED |
| Sat 03 Jul 08:00 Europe/Berlin | Sat 03 08:00 Asia/Singapore | data: Sat 03 13:00 / intent: Sat 03 07:00 | Thu 01 16:00 ✈, Sat 03 09:30 (after meeting) | ✗ MISSED |
| Tue 06 Jul 08:00 Europe/Berlin | Tue 06 08:00 Asia/Kolkata | data: Tue 06 10:30 / intent: Tue 06 07:00 | Tue 06 06:30 | ✗ |
| Fri 09 Jul 08:00 Europe/Berlin | Fri 09 08:00 Asia/Kathmandu | data: Fri 09 10:45 / intent: Fri 09 07:00 | Fri 09 07:00 | ✓ |
| Mon 12 Jul 08:00 Europe/Berlin | Mon 12 08:00 Asia/Dubai | data: Mon 12 09:00 / intent: Mon 12 07:00 | Mon 12 06:15 | ✗ |
| Wed 14 Jul 08:00 Europe/Berlin | Wed 14 08:00 Europe/Berlin | data: Wed 14 07:00 / intent: Wed 14 07:00 | Wed 14 05:15 | ✗ |

The app does exactly what the data says: every D2w alarm equals the stored instant minus 60 min.
East of Berlin that instant lies *after* the real local meeting, so every such meeting is missed:
Tokyo, Singapore, Kolkata, Kathmandu and Dubai. Honolulu's alarm comes the evening before. West of
Berlin it is merely hours early.

### 3.6 Part II - (E) Sleep-time Do Not Disturb and bedtime reminder after each jump

**(A) manual alarm -** DND window as last pushed before landing, read on the destination clock

| Landing in | Last pushed window (origin clock) | Same window on the destination clock | Alarm it was derived from rings at (dest. clock) | Window after the first push in the destination |
|---|---|---|---|---|
| Europe/London | Tue 15 23:00 – Wed 16 07:00 | Tue 15 22:00 – Wed 16 06:00 | 06:00 | Tue 15 23:00 – Wed 16 07:00 (open app) |
| America/New_York | Thu 17 23:00 – Fri 18 07:00 | Thu 17 18:00 – Fri 18 02:00 | 02:00 | Thu 17 23:00 – Fri 18 07:00 (open app) |
| America/Los_Angeles | Mon 21 23:00 – Tue 22 07:00 | Mon 21 20:00 – Tue 22 04:00 | 04:00 | Mon 21 23:00 – Tue 22 07:00 (open app) |
| Asia/Tokyo | Thu 24 23:00 – Fri 25 07:00 | Fri 25 15:00 – Fri 25 23:00 | 23:00 | Fri 25 23:00 – Sat 26 07:00 (open app) |
| Pacific/Honolulu | Mon 28 23:00 – Tue 29 07:00 | Mon 28 04:00 – Mon 28 12:00 | 12:00 | Mon 28 23:00 – Tue 29 07:00 (open app) |
| Asia/Singapore | Thu 01 23:00 – Fri 02 07:00 | Fri 02 17:00 – Sat 03 01:00 | 01:00 | Fri 02 23:00 – Sat 03 07:00 (open app) |
| Asia/Kolkata | Mon 05 23:00 – Tue 06 07:00 | Mon 05 20:30 – Tue 06 04:30 | 04:30 | Mon 05 23:00 – Tue 06 07:00 (open app) |
| Asia/Kathmandu | Thu 08 23:00 – Fri 09 07:00 | Thu 08 23:15 – Fri 09 07:15 | 07:15 | Thu 08 23:00 – Fri 09 07:00 (open app) |
| Asia/Dubai | Sat 10 23:00 – Sun 11 07:00 | Sat 10 21:15 – Sun 11 05:15 | 05:15 | Sat 10 23:00 – Sun 11 07:00 (open app) |
| Europe/Berlin | Tue 13 23:00 – Wed 14 07:00 | Tue 13 21:00 – Wed 14 05:00 | 05:00 | Tue 13 23:00 – Wed 14 07:00 (open app) |

**(B1w) scheduled wall-clock values -** DND window as last pushed before landing, read on the destination clock

| Landing in | Last pushed window (origin clock) | Same window on the destination clock | Alarm it was derived from rings at (dest. clock) | Window after the first push in the destination |
|---|---|---|---|---|
| Europe/London | Tue 15 23:00 – Wed 16 07:00 | Tue 15 22:00 – Wed 16 06:00 | 06:00 | Tue 15 22:30 – Wed 16 06:30 (open app) |
| America/New_York | Thu 17 23:00 – Fri 18 07:00 | Thu 17 18:00 – Fri 18 02:00 | 02:00 | Thu 17 18:30 – Fri 18 02:30 (open app) |
| America/Los_Angeles | Mon 21 20:30 – Tue 22 04:30 | Mon 21 17:30 – Tue 22 01:30 | 01:30 | Mon 21 17:30 – Tue 22 01:30 (open app) |
| Asia/Tokyo | Thu 24 19:00 – Fri 25 03:00 | Fri 25 11:00 – Fri 25 19:00 | 19:00 | Fri 25 10:00 – Fri 25 18:00 (open app) |
| Pacific/Honolulu | Tue 29 08:00 – Tue 29 16:00 | Mon 28 13:00 – Mon 28 21:00 | 21:00 | Mon 28 14:00 – Mon 28 22:00 (open app) |
| Asia/Singapore | Fri 02 16:00 – Sat 03 00:00 | Sat 03 10:00 – Sat 03 18:00 | 18:00 | Sat 03 09:00 – Sat 03 17:00 (open app) |
| Asia/Kolkata | Mon 05 08:00 – Mon 05 16:00 | Mon 05 05:30 – Mon 05 13:30 | 13:30 | Mon 05 05:30 – Mon 05 13:30 (open app) |
| Asia/Kathmandu | Fri 09 03:30 – Fri 09 11:30 | Fri 09 03:45 – Fri 09 11:45 | 11:45 | Fri 09 03:45 – Fri 09 11:45 (open app) |
| Asia/Dubai | Sun 11 02:45 – Sun 11 10:45 | Sun 11 01:00 – Sun 11 09:00 | 09:00 | Sun 11 01:00 – Sun 11 09:00 (open app) |
| Europe/Berlin | Tue 13 23:30 – Wed 14 07:30 | Tue 13 21:30 – Wed 14 05:30 | 05:30 | Tue 13 22:30 – Wed 14 06:30 (open app) |

- **Until the next push, the window is the old instants read on the new clock.** On landing in
  Honolulu at 09:00, Do Not Disturb ("alarms only") is **active until 12:00**. In New York it would
  start at 18:00, in the middle of the evening.
- **Pushes happen** at every arm/cancel, every checkpoint, `onAlarmHandled`, cold start, and when
  the switch is toggled (CLAUDE.md, "Sleep-time Do Not Disturb").
- **A push fixes the window for scheduled alarms** (window and alarm come from the same
  `pendingDayValues`), but only to the drifted plan of T1.
- **For a manual alarm a push makes window and alarm disagree.** The window comes from
  `nextWakeUpTime`, i.e. `nextManualOccurrence` with *local now* (`next_wake_up.dart:84`,
  `sleep_time_dnd.dart:119`), while the platform alarm is still at the old instant. In New York the
  window ends at 07:00 but the alarm rang at 02:00, so the phone stays silenced for five hours
  after the first ring. That breaks the rule "the end is the native end alarm at the target
  alarm's `alarmPlatformTime`".
- **Bedtime reminder** (from the source, not simulated; its scheduling uses the real clock):
  - It fires at the instant it was scheduled with: `NotificationCalendar.fromDate` takes the local
    fields plus the zone name (`awesome_notifications-0.12.1/lib/src/models/notification_calendar.dart:83-98`).
  - That zone name is cached **once**, in `initialize()`
    (`awesome_notifications_method_channel.dart:334`).
  - In a process that survives a zone change, a reminder rescheduled afterwards therefore carries
    the new local digits with the **old** zone name, and fires off by the offset difference. This
    is inferred from the source only.
  - Checkpoint 2 hangs off the same notification and does not run at bedtime anyway (T-199).

### 3.7 Part II - (F) Offset-only effects (half-hour and 45-minute zones)

| Check | Expected | Actual | |
|---|---|---|---|
| FR-16's offset comparison, Kolkata (+05:30) → Kathmandu (+05:45) | change detected | `lastCheckedUtcOffsetMinutes` 330 → 345 at the first checkpoint; whole minutes, compared with `!=` (`replan.dart:497`) | ✓ |
| Engine arithmetic in :30/:45 zones | values keep quarter-hour digits | e.g. 13:30 IST, 11:45 NPT; `_wallClockDelta` and `eventsForDay` are offset-agnostic | ✓ (arithmetic) / ✗ (T1 still applies) |
| Manual alarm, +15 min jump | 07:00 NPT | 07:15 NPT once, then 07:00 | ✗ (15 min late) |
| Appointment, Kathmandu, dest. zone | 07:00 NPT | 06:45 (C1w, curve) / 07:00 (C2w) | ✗ / ✓ |
| `currentTimeZone` from `getLocationFromAbbreviation` (`main.dart:321`) | - | read only at cold start; `IST` maps to Asia/Kolkata (it is also Israel and Ireland); only stored into `Meeting.startTimeZone` for display, and no scheduling code reads it | harmless today |

## 4. The calendar question - the maintainer's objection, answered

> "That is only true if the calendar itself respects the time zone and the change is also fed into
> the scheduled alarms in between. If I travel from Germany to America and have to get up there at
> 8 o'clock (just like here at 8), the alarm has to ring at calendar start time minus the timezone
> shift. That depends on the time zone - a problem of its own?"

### 4.1 How an event's time is stored and read

- **Android stores a timed event as an instant.** `CalendarContract.Events.DTSTART`/`DTEND` are "UTC
  milliseconds since the epoch", and `EVENT_TIMEZONE` is required on insert (Android developer
  guide, "Calendar Provider", rules for inserting events). The zone does not change the stored
  instant of a single event. It says which zone the event is *displayed and repeated* in: RRULE
  expansion and the `Instances` table's `START_DAY`/`START_MINUTE` use it.
- **`device_calendar` 4.3.3 reads the instant, not the digits.**
  - It queries `CalendarContract.Instances` (`CalendarDelegate.kt:324`) and takes `Instances.BEGIN`
    in UTC milliseconds (`Constants.kt:58`), plus `EVENT_TIMEZONE`.
  - `Event.fromJson` builds `TZDateTime.fromMillisecondsSinceEpoch(location, BEGIN)`
    (`lib/src/models/event.dart:115-119`), i.e. the same instant expressed in the event's zone. It
    falls back to `tz.local` when the zone name is unknown to `package:timezone`, which does not
    move the instant either.
- **The app then works on that instant only.**
  - `fetchMeetingsUncached` discards the zone name (`calendar.dart:169`, `startTimeZone: ''`).
  - `hardFloor` converts to UTC (`scheduling_v2.dart:242-270`).
  - `convertToTZDateTime` (`lib/utils/utils.dart:30`), which FR-2 names as "already existing
    functionality", has **no caller** in `lib/`. The spec's pointer is stale; the behaviour it
    describes is delivered by `device_calendar` itself.

So "calendar start time minus the timezone shift" is exactly what already happens, *when the event
carries the zone Tom means*.

### 4.2 Destination zone versus origin zone

| Tom enters "08:00 on Fri 18 Jun" … | Stored instant | Shown in New York | Alarm (lead 60 min) | Real meeting 08:00 EDT |
|---|---|---|---|---|
| with the event zone set to America/New_York (or accepts an invite whose organiser used New York) | 12:00Z | 08:00 | 07:00 EDT ✓ | caught |
| at home, with the default zone Europe/Berlin | 06:00Z | 02:00 | 01:00 EDT (6 h early) | caught, but far too early |
| same, for Tokyo (08:00 Berlin = 15:00 JST) | 06:00Z | 15:00 | 14:00 JST | **missed** (7 h before) |

The calendar app shows the second and third rows at 02:00 and 15:00 too. Tom's own calendar would
show the wrong time before the alarm app ever sees it. The alarm app cannot tell a meeting that
*really* is at 08:00 Berlin (a video call with the office) from one that was mis-entered. Both are
the same row in `CalendarContract`. Correcting the time by "the timezone shift" would be right for
one and would make the other ring hours late. Hence: **appointment alarms keep the stored instant
(TZ-4 as drafted), and the origin-zone case is a data problem.** The app can, at most, *surface* it
(open decision Q3).

### 4.3 Floating and all-day events

- **Floating timed events** ("08:00 wherever I am") do not exist in Android's calendar model: a
  timed event always has an instant plus a required zone. Whether a sync adapter imports an iCal
  floating time as the device zone at import time was not verified.
- **All-day events are the one floating kind**: date only, `ALL_DAY=1`, occupying "the entire day,
  as defined by the local time zone" (developer guide). `device_calendar` normalises their start
  back to a midnight to keep the calendar date (`event.dart:130-142`).
- They never produce an alarm: `hardFloor` ignores them (`scheduling_v2.dart:254`) and the
  `dayPlanned` diagnostics filter them (`replan.dart:392`). Travel only affects which day they are
  *drawn* on, which was not verified on a device.

### 4.4 When a calendar change actually reaches the armed alarms

| Trigger | Re-reads the calendar and re-arms scheduled alarms? | Runs with the app closed? |
|---|---|---|
| App open, cold start or resume (`main.dart:335-376`: `appForeground` + `resyncCalendarData` + `manualSync`) | yes (T-60: uncached, every open) | no |
| A **scheduled** alarm rings (`handler.dart:130`) | yes | the ring starts the app |
| A **manual** alarm rings | no replan (only the resume that follows, as above) | - |
| Settings change, Sync button | yes | no |
| Calendar change while closed | **nothing** | - |
| FR-16 Checkpoint 2 | no (reinterprets stored values only; no calendar access, no re-arm - T-113) | no - runs when a notification is *scheduled* (T-199) |

- **What Android offers natively:**
  - `Intent.ACTION_PROVIDER_CHANGED` is **not** on the implicit-broadcast exception list (checked
    against the list on developer.android.com), so a manifest receiver gets nothing on Android 8+.
    A runtime receiver only works while the process is alive.
  - The route that works with the app closed is a `JobScheduler` job with `addTriggerContentUri`
    on the calendar provider URI (API 24+; WorkManager wraps the same). The OS batches and delays
    it. FR-11 already records it as "buildable but disproportionate".
  - `ACTION_EVENT_REMINDER` *is* exempt, but it only fires for events with a reminder.
- **For travel the important point is different.** Once an event carries the right zone, nothing
  about it changes on a flight. The calendar data does not need to be "fed in between"; the *armed
  alarms* do (T1/T2/T5), and they react to a checkpoint, not to the zone change.

## 5. Evaluation of the maintainer's TZ answers

| ID | Maintainer's answer | Evaluation | Proposed answer / note |
|---|---|---|---|
| TZ-1 | repeated → later; skipped → first valid instant, never skipped (decided) | Consistent and implementable. No default matches (section 3.1). Dart's gap shift never *skips* (✓ no skip) but lands at 03:30, not 03:00. | Implement explicitly. Note the interaction with the persisted local-digit format (Part I, item 5). |
| TZ-2 | "I suppose so, to be clarified later" (working rule) | Violated today for scheduled wall-clock values (Part I, item 1). Contradicts T-85e's accepted limitation, which must be withdrawn now that TZ-2 is committed. | **Yes**: 07:00 stays 07:00 on the transition day itself and every day after; appointment alarms keep their instant. That requires each window day to use *that day's* offset (from the device zone rules), which FR-16 deliberately avoided ("compare offsets, don't interpret zone names"). FR-16's model needs amending for this. |
| TZ-3 | "if Android can already do that, it would be smarter than implementing it ourselves" | Partly already true: every instant↔local conversion in the scheduling path uses the OS (`DateTime.toLocal`, `timeZoneOffset`), i.e. the device tzdata that Android updates as a system module. `package:timezone`'s bundled database is only used for `device_calendar`'s event objects, where it does not affect the instant. Android does **not** re-arm anyone's alarms, and has no wall-clock alarm type: `AlarmManager` RTC is UTC-based. | "Android can do it" means: the tz rules, zone detection and the change broadcast come from the platform. Resolving the repeated/skipped hour and re-arming alarms is the app's own job. |
| TZ-4 | "no idea" | The simulation makes the answer concrete: every wall-clock alarm failed on the first morning after every leg, and scheduled wall-clock values never reached local time (T1/T2). | **Proposed:** wall-clock alarms (manual, `preferredWakeUpTime`, gap-day values) follow the new local clock from the first due time after the change. Appointment alarms keep the stored instant. *Deliberate* gradual adaptation, if wanted at all, is a separate opt-in feature with its own bounds (Q1), not a side effect of FR-4. |
| TZ-5 | "no idea"; not promised | Not simulated (out of scope). Short assessment: the Part I defect (one offset per window) and the Part II defects (no reaction to a zone change) compound, since after landing the window's later days may also cross the *destination's* DST date. Both fixes (per-day offset from the current zone's rules, re-arm on change) would cover TZ-5 as a by-product. | **Proposed:** "the rules of the zone the phone is in apply, per day", which follows from TZ-2's per-day offset. No separate mechanism. |
| TZ-6 | "no idea" | Nothing in the app reacts to a zone change: no receiver, and Checkpoint 2 re-arms nothing (T-113) and does not run at bedtime (T-199). Everything depends on the next checkpoint, which may be *after* the wrong ring (Honolulu, New York). | **Proposed:** a manifest receiver for `ACTION_TIMEZONE_CHANGED` and `TIME_SET` (both exempt from the implicit-broadcast ban) re-arms all wall-clock alarms natively or via one checkpoint. Also a check at boot, because a reboot in the new zone fires no change broadcast. Re-arm by **id replacement** (`Alarm.set` with the same id replaces), so there is never an old and a new alarm at once. Known hole: a force-stopped app receives no broadcasts until it is opened. |
| TZ-7 | yes | Violated: double rings after both date-line directions (T6, and the stale manual ring in Tokyo/Honolulu). No *skipped* local day was observed for manual alarms. For scheduled values, day keys lose their meaning across the line. | Keep as stated. Needs day keys that survive a zone change, or re-keying at the change. |
| TZ-8 | yes | Violated during travel (E). Within DST, the window follows the alarm instants and so inherits Part I, items 1-2. | Keep. Derive the window from the **armed** instant, not from a recomputation, so window and alarm cannot disagree. |
| TZ-9 | yes | The sweep approach worked here for Dart's DST resolution (15 zones, 52 transitions). The travel harness shows that tests must drive the *platform* state separately from the app's list, or T5 is invisible. | Keep. Add: independent expected values from `zoneinfo`; process-per-zone runs; the platform state modelled by id. |

**Contradictions in the current spec / TODO:**

- FR-16's same-digits rule versus FR-4/FR-1: FR-16 is overwritten by the next replan (T1). One of
  the two has to give.
- T-85e ("accepted") versus committed TZ-2, and T-85e's "corrected … at the latest the following
  day" is not true for `maxDailyDelta` below 1 h.
- T-113 ("postponed") is the travel mechanism TZ-6 needs.
- FR-16's "background isolate" and "at the computed bedtime instant" are both superseded by T-199.
- FR-2's reference to `convertToTZDateTime` is stale (no caller).
- FR-3 calls `preferredWakeUpTime` "combined with a day + the current zone at the point of use".
  For days after a DST change within the same window this is not what happens (one offset per
  replan).

## 6. Open decisions for the maintainer

- **Q1 - After a flight, should wall-clock scheduled values jump to local time or adapt gradually?**
  - (a) Jump: 07:00 local from the first morning, as TZ-4 is drafted. Simple and predictable, and
    what an alarm clock usually does.
  - (b) Gradual, but *toward the new local time*, bounded, e.g. at most N days and never outside a
    sane window. This is a jet-lag feature; it needs its own spec, and the persona asks for it.
  - (c) Keep today's behaviour. That means 16:30 in Tokyo. Not recommended.
  - Consequence of (a): FR-4's anchor has to be re-read in local digits after a detected change
    (FR-16's rule applied to the anchor too), not only to the stored future values.
- **Q2 - Who reacts to a zone change while the app is closed?**
  - (a) A native receiver re-arms everything itself, like T-198's Do Not Disturb (no Flutter
    engine needed).
  - (b) The receiver starts one checkpoint (engine start in the background; the plugin-channel
    risk of T-79/T-113).
  - (c) Wait for the next app open or ring, as today.
  - Consequence: (a) needs the manual-alarm rule and the plan in native-readable form. (b) is less
    code, but the calendar read and replan then run without UI, which is the failure class T-79
    was.
- **Q3 - Should the app warn about appointments whose zone differs from the device zone?** For
  example: "This appointment is stored in Europe/Berlin: 08:00 there is 14:00 here".
  - (a) No: data is data.
  - (b) A passive hint in the Schedule view and the alarm list.
  - (c) A notification when the resulting alarm falls outside typical waking hours.
  - Consequence: (b)/(c) need the zone name, which `fetchMeetingsUncached` currently discards
    (`calendar.dart:169`).
- **Q4 - A wall-clock alarm due during a flight** (the phone is still on the origin clock): ring
  (today), or skip until landing?
  - Recommendation: ring. The app cannot know about the flight, and skipping risks the TZ-7 "no
    skipped day" rule.
- **Q5 - Should cross-zone appointments pre-shift the curve?** FR-5/FR-6 today pull the week's
  curve toward an appointment in a later zone, by UTC time of day (the San Francisco miss).
  - (a) Forbid runs across a detected zone change.
  - (b) Only allow them when the target is in the current zone.
  - (c) Keep them as a "pre-adaptation" feature with a bound.
- **Q6 - Persistence format of `ScheduledAlarm.time`**, which affects the committed DST work too.
  - (a) Store epoch milliseconds or an ISO string with offset. This is a persisted-key change; the
    test-phase data-loss policy applies.
  - (b) Keep it and re-derive the list from the platform (`Alarm.getAlarms()`) at every load.

## 7. Fix directions (prose only)

**For Part I (DST, now):**

- **Resolve wall-clock → instant in one place, with the TZ-1 rules.** One function should turn "day
  D, 07:00" into an instant using the *device's* zone rules, choosing the later occurrence for a
  repeated time and the transition instant for a skipped one. Every wall-clock conversion should
  use it: `nextManualOccurrence`, `coldStart`/`applyGapDayDrift`, and the reminder and window
  derivation.
- **Stop rebuilding instants from local fields at the platform boundary.** `alarmPlatformTime`
  should truncate the instant to whole minutes rather than rebuild it from local fields. That is
  T-202's own acceptance criterion, "preserves the instant". The `alarm` plugin already takes
  epoch milliseconds, so nothing downstream needs local digits. `awesome_notifications` does
  (fields plus zone name), so the reminder should be scheduled with the UTC fields and the UTC
  identifier, which that API supports (`notification_calendar.dart:89-91`).
- **Use one offset per window day, not one per replan.** Evaluate each day's
  `preferredWakeUpTime`/drift in that day's own offset, and assign events to days by that day's
  offset. This withdraws T-85e. The device's zone rules are needed for it, which is available to
  Dart only through the OS local-time conversion (probing) or a native call.
- **Store `ScheduledAlarm.time` as an instant** (Q6). It is harmless within a region except in the
  repeated hour, but it is the prerequisite for Part II.

**For Part II (travel, when resumed):**

- **Re-arm natively on `ACTION_TIMEZONE_CHANGED`/`TIME_SET`, and at boot.** Both broadcasts are
  exempt from Android 8's implicit-broadcast restriction, so a manifest receiver fires with the
  app closed; after a force-stop it does not. Compare the stored offset or zone at
  `LOCKED_BOOT_COMPLETED` via the existing `DirectBootReceiver`. Re-arm every wall-clock alarm by
  id replacement: an atomic replace, never "add new, then remove old" (TZ-6's no double ring). The
  platform supplies the zone, the rules and the broadcast; the re-arming is the app's job. Every
  alarm app does this itself (AOSP's DeskClock is believed to handle these broadcasts in its init
  receiver; not re-verified here).
- **Make the anchor follow FR-16.** After a detected change, read `lastEffectiveWakeTime` (and
  every other wall-clock-anchored value) in its old local digits and re-anchor it in the new zone,
  or decide Q1(b) and specify the adaptation explicitly.
- **Checkpoint 2 has to re-arm or disappear** (T-113/T-199). With a native change receiver it is
  redundant: the offset comparison becomes "at every checkpoint and on the broadcast".
- **Derive the Do Not Disturb window and the reminder from the armed alarm instants** (the
  platform's `id → instant`), not from a parallel recomputation, so they cannot disagree with what
  will ring.
- **Day keys across the date line:** re-key `pendingDayValues` on a detected change, or drop
  out-of-window keys whose instant falls into the new window's first day.
- **Calendar observer (optional, Q3/T8):** a `JobScheduler` content-URI trigger on the calendar
  provider is the only closed-app route. It is batched by the OS, so the ring and open checkpoints
  stay the reliable path.

## 8. What was not verified

- **Nothing here ran on a device or emulator.** Platform behaviour is emulated from the app's calls
  (section 3, method). In particular the following were not verified:
  - that the plugin replaces an alarm with the same id atomically;
  - that Dart's local time follows a zone change inside a live Android process (bionic re-reads the
    zone property; assumed, not tested);
  - when exactly Android switches the zone after landing.
- **Java/`Calendar` results are from OpenJDK 17 on the VM**, not Android's ICU-backed
  implementation.
- **The DST sweep covers 15 sample zones (13 with DST) and 52 transitions**, not all IANA zones. Eight `nextManualOccurrence`
  overlap cases whose repeated hour lies late in the evening were inconclusive (a test-setup artefact); they are excluded from the
  counts.
- **The bedtime reminder's instant was not simulated:** `scheduleSleepReminder` reads the real
  clock. Section 3.6 on the reminder is from the source.
- **Not verified:** how `CalendarContract` computes all-day `Instances.BEGIN` after a zone change,
  and how sync adapters import iCal floating times.
  - The `CalendarContract.Events` / `Instances` reference pages did not render for verification;
    section 4 relies on the developer guide page instead.
  - The implicit-broadcast exception list *was* checked against developer.android.com.
- **The harness's Checkpoint 2 reads the simulated offset.** A first run read the machine's real
  offset, which made the DST runs wrong; it was fixed and every run repeated. The travel runs were
  unaffected, because each zone's real September 2026 offset equals its June/July 2027 offset.
