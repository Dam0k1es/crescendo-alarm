# T-206 - Requirements and test specification

The requirements and test plan for `docs/TODO.md` T-206 (scheduled wall-clock alarms around a
daylight-saving change), written as step 3 of that item's review pipeline: design proposal (review
persona Markus) → review of the proposal (review persona Günther) → **this document** → tests →
implementation → review of the implementation → simulation (persona Tom). Baseline: `dev` at
`8ac1d9e`.

**What refers to this file.** The identifiers used in `lib/` comments and in the T-206 tests -
requirement ids `T206-R1` … `T206-R21`, test ids `T01` … `T56`, `TW1` … `TW8b`, `P1`/`P2`, and
section numbers such as "requirements b.0" or "section 8.2" - are defined here. (The test ids are
not `docs/TODO.md` items: `T33` is a test in this table, `T-33` an unrelated TODO entry.)

**Sources.** Rows cite their origin as `M§n` or `M-Rn` (a section or requirement of Markus's design
proposal), `G#n`, `G§n` or `Kn` (an item, section or change item of Günther's review of it). Those two were working
documents of the pipeline and are not kept in the repository; every row restates what it takes
from them. The requirement text itself lives in `docs/timezone-requirements.md` (TZ-1 … TZ-9) and
`docs/scheduling-v2-spec.md` (FR-1 … FR-21); where this file and those two differ, they are
authoritative for the *requirement*, this file for the *test and stage plan*.

**Expected values.** Every instant below was computed with Python `zoneinfo` (system tzdata) by a
brute-force implementation of TZ-1's definition, independent of the app's resolver: scan minute by
minute backwards from +30 h and take `R(w) = min{ t : L(t) ≥ w and L(s) > w for all s > t }` (TZ-1
as corrected on 2026-09-28 - the formula first adopted, `min{ t : L(s) ≥ w for all s ≥ t }`, gave
the first occurrence at the first minute of a repeated range; no value below is at such a minute,
and re-running the computation with the corrected formula gave byte-identical output); `R_plan`
adds decision B's fallback. Those scripts were pipeline working material and are not in the
repository; section 8 reproduces the numbers used. The reproducible, checked-in counterpart is
`scripts/gen_dst_fixture.dart` (the sweep's oracle table from `package:timezone`'s own data),
`scripts/gen_dst_fixture.py` (the same from the system tzdata, compared informationally) and
`test/t206_dst_sweep_test.dart`.

---

## 0. Notation and decisions

- **Instant** `t`: a point in time. **Reading** `w`: a civil date plus a time of day, carried as
  "wall microseconds" (the epoch value of `DateTime.utc(y, m, d, h, min, ...)`); reading space has
  no transitions. **L(t)** = `t.toUtc() + offsetAt(t)` as a UTC-tagged reading.
  **R(w)**: TZ-1. **R_plan(w)** = `R(w) − 1 min` if the calendar date of `L(R(w))` is later than
  `w`'s date, else `R(w)`. **δ(w₁, w₂)** = time-of-day difference wrapped into (−12 h, +12 h]
  (today's `_wallClockDelta` semantics, including +12 h at exactly 12 h; T-115 stays open).
- **Planned clock time**: the reading a wall-clock-anchored day's value was planned as. Distinct
  term on purpose (Günther #11): `stored_values.dart` already uses "reading" for "interpretation of a
  stored value". The persisted key is `pendingDayClockTimes` (called `pendingDayReadings` in the
  proposal and review - same thing, renamed here).
- **Decision A** (verbatim "A: 1"): the clock reading counts. **Decision B** (verbatim "B: Passt,
  zur not vorziehen"): a value resolved onto the next date belongs to its planned day; pulling it
  earlier is allowed.

### 0.1 Decision B: the design uses the fallback (R_plan)

Primary rule considered and rejected, with the documented reason the maintainer's permission asks
for:

1. **Unsafe failure mode.** Keeping `00:00 on 29 Mar` as the value of `28 Mar` needs a window-day key
   carried from the plan to the ring through every consumer that today derives a day from an
   alarm's instant: ring-day identification (`replan.dart:104`, `:140` - `today = midnight(now)`,
   `concludedByTrigger = today`), the FR-21 toggle (`screen_alarms.dart:203`,
   `isoDate(alarm.time)`), the T-141 prune (`apply_alarms.dart:232`), plus a new persisted
   `ScheduledAlarm` field with a legacy fallback. A consumer that is missed fails toward the
   **wrong** day: an armed alarm the user switched off (FR-21), or a value that has not rung yet
   fixed as the next anchor (FR-11's "made-up anchor", `replan.dart:282-294`).
2. **It would decide open questions by accident.** The same key-versus-date mismatch is the subject
   of two open, postponed maintainer decisions: T-112 (a curve crossing midnight) and T-120 (lead
   times pushing a `hardFloor` before midnight). A general window-day key changes both; a key only
   for R's next-date case is a second, special-case mechanism.
3. **The fallback fails early, never late** (the threat model weights oversleeping highest), and is
   one condition in one resolver. Scope measured by a scan over every zone, 2026/27: exactly
   America/Nuuk, America/Godthab, America/Scoresbysund, spring change only (28 Mar 2026, 27 Mar
   2027), readings 23:00-23:59; the alarm rings 1-60 minutes early at 22:59.
4. **It keeps B's substance**: the value rings on its planned day, so every existing day derivation
   is right by construction, and the day's planned clock time (23:30) is kept so FR-4 continues
   from 23:30, not 22:59.

Relation to TZ-1's R: R_plan is R except in the next-date case, where it is **earlier** than every
occurrence of `w` - an explicit exception to R's "never before any occurrence" and to
`L(R(w)) ≥ w`, recorded as such in TZ-2a. R_plan is still never later than R, never drops an
alarm, and is monotone in `w` within a day (readings before the gap give `w − offset_before`, which
is at most `T − 1 min`, and every gap reading gives exactly `T − 1 min`). Manual alarms use R_plan too (Q2 answered: yes).

---

## (a) Requirements

Trace legend: TZ-x = `docs/timezone-requirements.md`; FR-x = spec; M§ = Markus's proposal
section; G§/G# = Günther's review section / section-7 change item; B1…B4 = Günther's blocking
points.

| ID | Requirement | Trace | Stage |
|---|---|---|---|
| **T206-R1** | **Zone rules as the one input.** `typedef ZoneOffsetAt = Duration Function(DateTime instant)`; production `deviceOffsetAt(t) = DateTime.fromMicrosecondsSinceEpoch(t.microsecondsSinceEpoch).timeZoneOffset`; `fixedOffset(Duration d)`. Pure-layer functions receive rules as a function value; no plugin, no ambient state. Where they live: `lib/utils/wall_clock.dart` (next to R). | M§3.1, TZ-3 | S1 |
| **T206-R2** | **One implementation of R.** `DateTime resolveWallClock(DateTime wallReading, ZoneOffsetAt offsetAt)`: input a UTC-tagged reading (a local-tagged input is a programming error - `assert`), output a UTC-tagged instant, microsecond resolution; algorithm = today's `localWallClockInstant` body (probe the offsets ±30 h, test candidates for validity, take the later valid one, else bisect to the transition). `localWallClockInstant(y, m, d, h, min)` becomes a wrapper over `deviceOffsetAt` returning the same local-tagged value as today - every T-202 test unchanged. | TZ-1, M§3.2, G§1.1 | S1 |
| **T206-R3** | **R_plan.** `DateTime resolvePlannedClockTime(DateTime clockTime, ZoneOffsetAt offsetAt)` = `r − 1 min` if the date of `L(r)` (with `offsetAt(r)`) is later than `clockTime`'s date, else `r`, where `r = resolveWallClock(...)`. The **only** function that turns a planned clock time into an instant: every wall-clock-anchored day in `computeWeekPlan`, FR-5's violation check, the anchor consistency check (R10), and Checkpoint 2 (R14). No zone is named anywhere. | TZ-2a, decision B, B1 | S3 |
| **T206-R4** | **Planning in reading space (decision A).** FR-4's hold/drift, FR-6's distribution, FR-5's grouping, FR-7's feasibility/bisection and both FR-6 overrun checks operate on readings; an instant enters as `L(t)` with the rules **at that instant**, or as the day's intact planned clock time. `day_i` = `A`'s reading + i calendar days ± step_i, built in reading space (the date follows the step across midnight as today - T-112 unchanged). `distribute`/FR-7's `feasible` must not resolve inside the bisection (δ and n only); R_plan is applied once per chosen value. `_dateTimeLike` and its local `DateTime(...)` branch are deleted. The size **and sign** of every shift is δ on readings. | FR-1, FR-4…FR-7, TZ-2, M§2.3, M§3.3, M§4.3, D2 | S3 |
| **T206-R5** | **Clamp after resolution, on instants.** For a day with a `hardFloor`: `value(D) = min_instant(R_plan(w_D), hardFloor(D))`. FR-5's violation check compares `R_plan(w_j)` with the intermediate point's `hardFloor` instant. No comparison with a `hardFloor` is ever made on readings. | FR-1, FR-2, FR-5, M§2.2 | S3 |
| **T206-R6** | **A DST change is not a shift.** Consequence of R4: identical readings on consecutive days give δ = 0, consume no `maxDailyDelta` and set no `overrunNotificationNeeded`, in every branch (gap path, run path, both clamp branches, cold start). A real reading change across a change is limited and flagged exactly as on any day. | decision A, TZ-2, FR-4, FR-6 | S3 |
| **T206-R7** | **Day assignment by the rules at the appointment's instant.** `eventsForDay` assigns event `e` to the date of `L(e)` with `offsetAt(e.from)`. The same rules drive `hardFloor`, `replan`'s FR-9/FR-12 day advance (`replan.dart:200-206`) and the diagnostics minute-of-day (`replan.dart:383-386`, `Diag.dayPlanned`/`Diag.dayEventTime`). Window days are interpreted by their calendar fields only (as today). Resolves T-119 (Q3 confirmed). | FR-2, T-119, M§1.4, G#7 | S2 |
| **T206-R8** | **Cold start.** FR-10's days use `R_plan(date(D), preferredWakeUpTime)` with that day's rules. | FR-10 | S3 |
| **T206-R9** | **Result carries the intent.** `WeekPlanResult.plannedClockTimes: Map<DateTime, DateTime>` (window day → UTC-tagged reading). Invariants: **P1** an entry exists ⇔ `valuesByDay[D] != null && !instantAnchoredDays.contains(D)`; **P2** `valuesByDay[D] == R_plan(plannedClockTimes[D])` exactly (µs). FR-9's valve and the `scheduleOnGapDays = false` mask (`scheduling_v2.dart:812-825`) remove the entry together with the value. | M§3.3, G§1.5 (FR-9, FR-21 rows), G#10 | S3 |
| **T206-R10** | **Anchor reading.** `computeWeekPlan` takes `DateTime? lastEffectiveClockTime`. The anchor's reading is it iff non-null and `R_plan(lastEffectiveClockTime).millisecondsSinceEpoch == lastEffectiveWakeTime.millisecondsSinceEpoch` (whole ms, the stored precision); otherwise `L(lastEffectiveWakeTime)`. Inside the loop the anchor for `D+1` is `plannedClockTimes[D]` if present, else `L(value(D))` (a clamped day). `pendingDayValues` stays the only source of *which* value rang (FR-3). | FR-3, FR-4, D4, M§3.3, G§1.5 (FR-3 row), G#6 | S3 |
| **T206-R11** | **Persistence `pendingDayClockTimes`.** Prefs key `pendingDayClockTimes`, JSON object ISO date → `{"c": <wall ms>, "v": <instant ms>}` (`v` = the paired value = `toStored(valuesByDay[D])` at planning time). `replan` writes it from the same merge as `pendingDayInstantAnchored` (`replan.dart:319-331`): entries with `worthKeeping(day)` kept, every window day set iff `plannedClockTimes` has it, removed otherwise; the key is written by every replan, `{}` when empty. Write order: `pendingDayValues`, `pendingDayInstantAnchored`, `pendingDayClockTimes`. `AppState` getter/setter; loaded by `_loadFromPreferences` (`app_state.dart:1602-1610` pattern) **and** `reloadSchedulingStateFromPreferences` (`:1512-1520`, T-69); unreadable JSON loads as an empty map (logged by `runtimeType` only). `replan` passes `lastEffectiveClockTime` from the `lastConcludedDay` entry only if its `v` equals `pendingDayValues[lastConcludedDay]`. `stored_values.dart` gains `DateTime? clockTimeFromStored(int? wallMillis)` (UTC-tagged, **not an instant**) and `int? clockTimeToStored(DateTime? clockTime)`, with the file's framing extended: "two readings of a stored instant, plus one stored planned clock time, which is not an instant and meets one only through `resolvePlannedClockTime`". | FR-3, M§3.4, B3, G§1.6, G#11 | S3 |
| **T206-R12** | **`replan` and the checkpoints thread the rules.** `replan`, `runSchedulingCheckpoint`, `runCheckpointSafely`: `Duration? deviceUtcOffset` → `ZoneOffsetAt? offsetAt`. S1: default `(_) => currentTime.timeZoneOffset`, and `replan` reduces it to `offset = offsetAt(currentTime)` for the pure layer (identical behaviour). S2: default `deviceOffsetAt`; the full rules reach day assignment; the reading arithmetic still gets `offsetAt(currentTime)`. S3: the full rules reach everything; the `Duration` path is gone. Checkpoint 1 records `lastCheckedUtcOffset = offsetAt(currentTime)` (`checkpoint.dart:151, :202`), so both checkpoints compare the same quantity. `today = midnight(currentTime)` and ring day = today stay (`replan.dart:104, :140`) - correct because of R3. | FR-16, M§3.5, G§1.1 (checkpoint row), G#18 | S1-S3 |
| **T206-R13** | **Diagnostics.** `_maxStepMinutes` (`replan.dart:569-589`) measures δ between consecutive planned days' planned clock times (or `L(value)` for clamped days), not `instant difference − 24 h × days`. `plannedMinuteOfDay`, `startMinuteOfDay`, `endMinuteOfDay` are minute-of-day of `L(instant)` - no new clock-shaped name in `test/diag_log_api_test.dart`. MAY add, within the log's rules (ints, no clock values, enum/field numbering append-only): a count of window days resolved inside a gap or overlap, and on Checkpoint 2 counts of re-resolved / legacy-shifted / skipped-torn days. | G§1.7, M§3.5 | S2 (minute), S3 |
| **T206-R14** | **Checkpoint 2: one rules source, one policy** (FR-16). Signature `runTimezoneCheckpoint2({ZoneOffsetAt? offsetAt, SharedPreferences? prefs, DateTime Function()? now})`; `readOffset` is removed (S1); `offset = (offsetAt ?? deviceOffsetAt)(nowValue)`. **Policy: re-resolve only when `offset != lastCheckedUtcOffset`.** Then, per day with `value.isAfter(now)`: (1) `pendingDayInstantAnchored[day] == true` → skip; (2) key `pendingDayClockTimes` absent from prefs → legacy `reinterpretForNewOffset` (today's code); (3) entry intact (`entry.v == pendingDayValues[day]`) → `v' = R_plan(entry.c)` under `offsetAt`; if `v' != v` write `pendingDayValues[day] = v'` and `entry.v = v'`; (4) otherwise (no entry, torn, unreadable) → skip. Always persist `lastCheckedUtcOffsetMinutes`. Exceptions stay swallowed (by `runtimeType`). The legacy branch is kept for the upgrade window and is not dead code to remove within T-206. | FR-16, B2, B3, M§3.5, G§1.3, G§1.4, G§1.6, G#2, G#3, G#10 | S1 (signature), S3 (policy) |
| **T206-R15** | **FR-11.** A concluded day's value and its `pendingDayClockTimes` entry survive every replan unchanged (outside the window, same `worthKeeping`) and every Checkpoint 2 (`!isAfter(now)` skip), also on the change day. | FR-11, M§4.2 case 11 | S3 |
| **T206-R16** | **FR-21.** The toggle keeps keying by `isoDate(alarm.time)`; R3 makes that the planned day. Switching a day off or on changes neither its value nor its planned clock time. | FR-21, TZ-2a, G§1.2 | S3 |
| **T206-R17** | **Unchanged consumers.** `localWallClockInstant` (plain R, T-202) stays as is, **but `nextManualOccurrence` switches to R_plan (Q2 = yes, see T206-R21)**; `apply_alarms.dart`, `next_wake_up.dart`, `sleep_time_dnd.dart`, `sleep_reminder.dart`, `hardFloor`'s instant arithmetic, `day_marker.dart` - no behaviour change. TZ-8 follows from R4/R5 through the instants they consume. | TZ-8, M§3.6, G§1.8 | all |
| **T206-R18** | **Public pure API stays instant-level.** `distribute`, `groupTarget`, `applyGapDayDrift`, `planGapOrRunStartDay`, `coldStart`, `computeWeekPlan`, `eventsForDay`, `hardFloor` keep instant-in/instant-out signatures (plus `offsetAt`, plus R10's optional `lastEffectiveClockTime`); the reading-space core sits behind them. `groupTarget` and `distribute` do need `offsetAt` (R for the violation check / resolved output). | G§2.3, G#18 | S2-S3 |
| **T206-R19** | **Docs at the end.** `timezone-requirements.md` state → "met"; CLAUDE.md: the "one place a local reading becomes an instant" rule retargeted to `resolveWallClock` (with `resolvePlannedClockTime` as the planning entry), the frame rule gains the planned-clock-time exception ("planning intent, not an instant, never compared with one"); `docs/device-trial-checklist.md` line for A3 (plan across the real transition, read `dumpsys alarm` and the alarm list on the phone); T-206 closed, T-119 closed if Q3 is confirmed. | M§5 (CLAUDE.md), G#20 | S5 |
| **T206-R20** | **Every stage is device-safe as `current.apk`**; per-day planning never ships without the Checkpoint 2 change, nor the reverse (section c). | G§4.1, G#18 | all |
| **T206-R21** | **Manual alarms use R_plan (Q2 = yes).** `nextManualOccurrence` resolves a manual alarm's reading with `resolvePlannedClockTime` and the device zone's `offsetAt`; a manual 23:30 on 28 Mar 2026 in Nuuk rings at 22:59 on the 28th. `localWallClockInstant` keeps plain R for every other caller; all T-202 manual-alarm tests outside the next-date case stay green unchanged. | TZ-2a, Q2 | S3 |

---

## (b) Tests

### b.0 Conventions for the tests step

- **Fixtures:** `tz.TZDateTime` or injected rules, never `DateTime.utc` as a stand-in for a local
  time (CLAUDE.md). Injected rules come from a new test helper
  `ZoneOffsetAt zoneRules(tz.Location loc) => (t) => Duration(milliseconds: loc.timeZone(t.millisecondsSinceEpoch).offset);`
  (`package:timezone` offset lookup is exact; only its *construction* resolution disagrees with
  TZ-1, and it is not used). `berlinRules`, `nuukRules`, … are this helper applied.
- **Two kinds of test, and where they are meaningful:**
  - **Injected** (pure layer, or `replan`/Checkpoint 2 with `offsetAt:` injected and a
    `tz.TZDateTime` `now` in that zone): exact digits from section 8, meaningful in **all ten**
    legs, identical results everywhere.
  - **Process-zone** (no rules injected, `offsetAt` defaults to `deviceOffsetAt`): values
    **derived at runtime** from `test/support/local_zone_transitions.dart` (never hard-coded Berlin
    digits, G#17); each leg exercises its own 2026 transitions; `skip: noTransitionReason` in UTC
    and Asia/Tokyo. Meaningful in the eight DST legs (Berlin, St_Johns, Chatham, Lord_Howe, Nuuk,
    Santiago, Troll, Dublin); only the first six legs are required checks - fine, as CLAUDE.md says.
    Section 8.2 lists the Python values each leg must produce, as a cross-check for the tests step.
- **Red-first baseline.** Each stage's new tests must fail against the code of the previous stage
  for the stated reason. Pure-level tests of a stage's new signature fail to compile first;
  therefore every pure-level regression has a **replan-level twin** that compiles against the
  previous stage and fails behaviourally (G#12). The twins marked "(8ac1d9e)" also compile against
  8ac1d9e itself (they inject nothing).
- Spec "Test:" bullets are implemented **verbatim** in `test/scheduling_v2_test.dart` (its header's
  promise, G#15), except FR-16's Checkpoint 2 bullets, which belong with the existing Checkpoint 2
  tests in `test/replan_test.dart` (group "runTimezoneCheckpoint2"), quoted verbatim there. Derived
  cases go into `test/t206_dst_planning_test.dart` (pure), `test/replan_dst_test.dart`
  (replan/Checkpoint 2), `test/t206_lemma_c_differential_test.dart`, `test/t206_dst_sweep_test.dart`.
- Every test asserting "no overrun" asserts `overrunNotificationNeeded == false` explicitly.

### b.1 Stage S1 - pure refactor (no behaviour change)

| ID | Test | Expect | Legs |
|---|---|---|---|
| **T01** (K1) | The whole existing suite after the mechanical edits only: `deviceUtcOffset: d` on `replan`/`runSchedulingCheckpoint`/`runCheckpointSafely` call sites → `offsetAt: fixedOffset(d)`; `readOffset: () => d` (`test/replan_test.dart:502, 534, 560, 581, 598`) → `offsetAt: fixedOffset(d)`. Pure-layer call sites untouched in S1. | green; **review gate: no `expect`/`reason` line edited** | all 10 |
| **T02** (K15) | **Differential Lemma-C test.** `test/support/scheduling_v2_legacy_8ac1d9e.dart` = verbatim copy of `lib/models/scheduling/scheduling_v2.dart` at 8ac1d9e (plus its imports; never imported from `lib/`). Seeded PRNG (fixed seed, e.g. `206`), ≥ 2,000 cases: window of 7 consecutive days starting on a random 2026/27 date, built UTC-tagged (the production frame - a local `_t`-style fixture would exercise the legacy file's local `_dateTimeLike` branch, G§1.1); offset ∈ {0, +1, +2, +5:30, +5:45, +9, +12:45, +13:45, −2:30, −3:30, −10} h; anchor null (20 %) or random instant within 30 h before the window; 0-4 events at random minutes (10 % all-day); `durationToWakeUp`/`durationToGetReady` ∈ {0, 15, 30, 60, 120} min; `preferredWakeUpTime` null (30 %) or random minute; `maxDailyDelta` ∈ {15, 20, 30, 45, 60, 90} min; `gapDayCounter` 0-8; `scheduleOnGapDays` random. Run legacy `computeWeekPlan(deviceUtcOffset: d)` and current `computeWeekPlan` with `fixedOffset(d)` (S1: same `Duration`). | per day `microsecondsSinceEpoch` equal (or both null); `overrunNotificationNeeded`, `safetyValveTriggered`, `instantAnchoredDays` equal. From S3 also P1/P2 on the new result. Must stay green through S2 and S3. | all 10 (pure) |
| **T03** | `resolveWallClock` = `localWallClockInstant`: for the process zone, every whole minute within ±90 min of each 2026/27 local transition plus 500 seeded ordinary readings, `resolveWallClock(wall, deviceOffsetAt).isAtSameMomentAs(localWallClockInstant(...))`. Injected fixed values (Berlin rules): wall 2026-03-29 02:30 → `2026-03-29T01:00Z`; 2026-03-28 02:30 → `01:30Z`; 2026-10-25 02:30 → `01:30Z`; 2026-10-24 02:30 → `00:30Z`; wall 2026-07-01 07:00:00.000123 → `05:00:00.000123Z` (µs kept); wall 2026-03-29 02:30:00.000123 → `01:00:00.000000Z`. | as stated | transitions: 8 DST legs; injected: all 10 |
| **T04** | Checkpoint 1 records the rules at its instant: `runSchedulingCheckpoint(trigger: appForeground, now: tz.TZDateTime(berlin, 2026, 3, 29, 3, 30), offsetAt: berlinRules)` on a fresh state. | `lastCheckedUtcOffset == 2 h` | all 10 |

### b.2 Stage S2 - FR-2 day assignment

| ID | Test | Expect (today) | Legs |
|---|---|---|---|
| **T10** (M-R7, spec FR-2 bullet, verbatim in `scheduling_v2_test.dart`) | `eventsForDay` / `hardFloor`, Berlin rules, event `from = tz.TZDateTime(berlin, 2026, 3, 30, 0, 30)` (= `2026-03-29T22:30Z`), 1 h long, lead times 0; days `tz.TZDateTime(berlin, 2026, 3, 29)` and `(…, 30)`. | `eventsForDay(30 Mar) == [event]`, `eventsForDay(29 Mar) == []`; `hardFloor(30 Mar) == 2026-03-29T22:30Z`, `hardFloor(29 Mar) == null`. (Under the planning day's +1 the event reads Sun 23:30 → assigned to 29 Mar.) Autumn mirror: event `tz.TZDateTime(berlin, 2026, 10, 26, 23, 30)` (= `22:30Z`) belongs to 26 Oct, not 27 Oct (under +2 it reads 27 Oct 00:30). | all 10 |
| **T11** (twin of T10, 8ac1d9e) | Process zone, for each 2026 local transition `T`: `Dafter = date(L(T)) + 1`; event reading = `Dafter 00:00 + |Δ|/2` for a gap, `Dafter 24:00 − |Δ|/2` for an overlap (unique readings; Lord Howe: 00:15 / 23:45), instant via `DateTime(y, m, d, h, min)`. Seed `lastProcessedConcludedDay = date(L(T)) − 1`, `pendingDayValues[that day] = DateTime(that day, 12, 0)`, P null, lead times 0; `replan(now: that value, todayAlreadyRang: true)`. | `pendingDayInstantAnchored[iso(Dafter)] == true` and `pendingDayValues[iso(Dafter)] == event ms`; the neighbour (`Dafter − 1` for a gap, `Dafter + 1` for an overlap) not anchored. Today the event lands on the neighbour. Berlin: event Mon 30 Mar 00:30 CEST (`29 Mar 22:30Z`) / Mon 26 Oct 23:30 CET (`22:30Z`). | 8 DST legs |
| **T12** | FR-12 day advance uses the same assignment: seed as T11 but with `lastProcessedConcludedDay = Dafter − 2` and the ring on `Dafter` (so the day advance walks `Dafter − 1 … Dafter`), event on `Dafter` at the T11 reading, `pendingDayValues[iso(Dafter)]` = a value later than the event. | `possiblyMissedAppointment == true` (the event is found on `Dafter`, not on the neighbour). | 8 DST legs |
| **T13** | Diagnostics minute: with `diagnosticsIncludeClockTimes = true`, the T11 event's `Diag.dayEventTime.startMinuteOfDay` is its local minute (Berlin 30 = 00:30) and its window-day index is `Dafter`'s. | as stated | 8 DST legs |
| **T14** (counter) | T-118a's constant-offset midnight tests and every existing FR-2 test unchanged (under `fixedOffset`); an appointment at Mon 30 Mar 12:00 CEST is on 30 Mar before and after. | green | all 10 |

### b.3 Stage S3 - regressions that must fail first

Pure tests use Berlin rules unless stated; window days `tz.TZDateTime(zone, y, m, d)`; lead times
0; `gapDayCounter: 0`; `scheduleOnGapDays: true`; no events unless stated. "Spec" = implemented
verbatim in `scheduling_v2_test.dart`.

| ID | Test | Inputs | Expect (new) | Fails today with | Legs |
|---|---|---|---|---|---|
| **T20** (M-R1, spec FR-4 "DST, spring") | hold across spring | window 29 Mar-4 Apr 2026; `lastEffectiveWakeTime` = 28 Mar 07:00 CET = `06:00Z`; P null; md 30 (variant P 07:00, md 15) | every day `05:00Z` (07:00 CEST); `plannedClockTimes[D]` = D 07:00; no overrun | 29 Mar `06:00Z` (08:00 CEST) | all 10 |
| **T21** (M-R2, spec FR-4 "DST, autumn") | hold across autumn | window 25-31 Oct 2026; anchor 24 Oct 07:00 CEST = `05:00Z`; P null; md 30 | every day `06:00Z` (07:00 CET); no overrun | 25 Oct `05:00Z` (06:00 CET) | all 10 |
| **T22** (M-R3) | transition on window day k | k = 0…6: window starts `29 Mar − k` (autumn: `25 Oct − k`); anchor = the day before the window at 07:00 local; P 07:00; md ∈ {15, 30} | `L(value(D))` = 07:00 on D for all D; instants: before the change `06:00Z` (spring) / `05:00Z` (autumn), from the change day `05:00Z` / `06:00Z` | days ≥ change day off by 1 h | all 10 |
| **TW1** (twin of T20/T21/T22, M-R4; 8ac1d9e) | real `replan` ring sequence | process zone, each 2026 transition, `D07` = first date whose 07:00 is after `T` (8.2); seed `lastProcessedConcludedDay = D07 − 3`, `pendingDayValues[D07 − 3] = DateTime(D07 − 3, 7, 0)`; P ∈ {07:00, null}, md ∈ {15, 30}; then for k = D07−3 … D07+3: `replan(now: pendingDayValues[k], todayAlreadyRang: true)` and read the next day's value | every value's `.toLocal()` is 07:00 on its own date; `overrunNotificationNeeded == false` every time | Berlin D07 reads 08:00 (spring) / 06:00 (autumn); per-leg values 8.2 | 8 DST legs |
| **TW3** (twin of T22; 8ac1d9e) | window position | process zone; for k = 0…6 one replan with `lastConcludedDay = D07 − k − 1` (seeded value 07:00 local), P 07:00, md 15 | all seven window values read 07:00 on their dates | days ≥ D07 off by Δ | 8 DST legs |
| **T23** (M-R5) + **TW5** (twin; 8ac1d9e) | recovery replan after the change reads the anchor with its own offset | pure: as T20 with md 15, P 07:00 (same expectation: 29 Mar `05:00Z`). Twin: process zone; seed `lastProcessedConcludedDay = D07 − 1`, `pendingDayValues[D07 − 1] = DateTime(D07 − 1, 7, 0)`, `lastReplanDate = D07 − 1`, P 07:00, md 15; `replan(now: DateTime(D07, 6, 30), todayAlreadyRang: false)`. **Assert the premise first** (G#13): the `D07 − 1` value exists and equals that instant, and `lastProcessedConcludedDay == D07 − 1` - without it the plan goes through the cold start and passes for the wrong reason (G§2.1) | `pendingDayValues[D07]` reads 07:00 on D07 | Berlin 07:45 CEST (md 15; with md 30 it would be 07:30 - md 15 keeps Lord Howe red, where Δ = md 30 would cancel) | pure: all 10; twin: 8 DST legs |
| **T24** (M-R8, spec FR-4 "held reading in the skipped hour") | held reading in the gap, one window | anchor 28 Mar 02:30 CET = `01:30Z`, `lastEffectiveClockTime` = 28 Mar 02:30 (and variant: none, falls back to `L = 02:30`, same result); P null | 29 Mar `01:00Z` (03:00 CEST), 30 Mar `00:30Z` (02:30 CEST) and `00:30Z` on every day after; `plannedClockTimes` all 02:30 | 29 Mar `01:30Z` (03:30 CEST), then 03:30 | all 10 |
| **TW8b** (M-R8b, G#13; 8ac1d9e) | held reading in the gap **across a ring, through persistence** | process zone, each 2026 **gap**: `w` = helper `midReading` on date `Dw`; seed `lastProcessedConcludedDay = Dw − 1`, `pendingDayValues[Dw − 1] = DateTime(Dw − 1, tod(w))` (a unique reading), P null, md 30. Ring 1: `replan(now: that value, todayAlreadyRang: true)`; ring 2: `replan(now: pendingDayValues[Dw], todayAlreadyRang: true)` | after ring 1 `value(Dw) = R_plan(w)` (Berlin `29 Mar 01:00Z`; Nuuk `29 Mar 00:59Z`, reads 28 Mar 22:59); after ring 2 `value(Dw + 1)` reads `tod(w)` on `Dw + 1` (Berlin `30 Mar 00:30Z`); `pendingDayClockTimes[Dw]` = w | Berlin ring 1 `01:30Z`; and a fix without `pendingDayClockTimes` would hold `L(v)` = 03:00 (Nuuk: 22:59 forever) - per-leg values 8.3 | 8 DST legs |
| **T25** (M-R9) | P in the skipped hour | P 02:30, md 15, anchor 28 Mar `01:30Z` (02:30 CET) | 29 Mar `01:00Z` (03:00), 30 Mar `00:30Z` | 29 Mar `01:30Z` | all 10 |
| **T26** (M-R10, spec FR-4 "P in the repeated hour") | P in the repeated hour | P 02:30, anchor 24 Oct 02:30 CEST = `00:30Z`, md 30 | 25 Oct `01:30Z` (02:30 CET, the later pass), 26 Oct `01:30Z` | 25 Oct `00:30Z` (first pass) | all 10 |
| **T27** (M-R6, spec FR-6 "no shift across a change") | a run across the change is planned in readings | `lastEffectiveWakeTime` = Fri 27 Mar 07:00 CET = `06:00Z`; window 28 Mar-3 Apr; P null; one event 07:30 CEST, `durationToWakeUp` 30 min, getting-ready 0 → `hardFloor` = 07:00 CEST; four rows: event Tue 31 Mar (`05:30Z`) or Mon 30 Mar (`05:30Z`) × md ∈ {15, 30} | every day 07:00 by the clock: 28 Mar `06:00Z`, 29 Mar-3 Apr `05:00Z`; the appointment day exactly `05:00Z`; overrun false | Tue/md 15: 28 Mar 06:45 CET, 29 Mar 07:30 CEST; Mon/md 15: 06:40, 07:20, overrun **true** | all 10 |
| **T28** (autumn run) | the same in autumn | anchor Fri 23 Oct 07:00 CEST = `05:00Z`; window 24-30 Oct; P 07:00; event Tue 27 Oct 07:30 CET (`06:30Z`), `durationToWakeUp` 30 min | 24 Oct `05:00Z`; 25-30 Oct `06:00Z`; overrun false | 25-30 Oct 06:00 CET (`05:00Z`) | all 10 |
| **T29** (K3, relabelled regression; spec FR-4 "real drift stays limited") | real drift across the change | anchor 28 Mar `06:00Z`, P 09:00, md 30 | 29 Mar `05:30Z` (07:30), 30 Mar `06:00Z` (08:00), 31 Mar `06:30Z` (08:30), 1 Apr `07:00Z` (09:00), 2 Apr `07:00Z` | 29 Mar `06:30Z` (08:30 CEST) | all 10 |
| **T30** (K4 mirror, relabelled regression; spec FR-6 "real shift … on readings") | N = 1 shift of exactly one hour | anchor 28 Mar 07:00 CET (`06:00Z`); event Sun 29 Mar 06:00 CEST (`04:00Z`), lead 0; P null | md 60: value `04:00Z`, overrun **false**; md 45: `04:00Z`, overrun true | md 60: overrun **true** (UTC digits give −120) | all 10 |
| **T31** (K6, relabelled regression; spec FR-1 "order") | resolve first, cap on instants | window 25 Oct-31 Oct; anchor 24 Oct 02:30 CEST (`00:30Z`); P 02:30; event 25 Oct `00:45Z` (the first 02:45), lead 0 | 25 Oct `00:45Z`, instant-anchored, no `plannedClockTimes` entry; 26 Oct `01:30Z` (02:30 CET) | 25 Oct `00:30Z` | all 10 |
| **T32** (M-R11, B-assert) | **Checkpoint 2 after a DST change leaves resolved values alone** (spec FR-16 "stale baseline", verbatim in `replan_test.dart`) | injected: mocked prefs; P 07:00, md 30; `lastProcessedConcludedDay = 27 Mar`, `pendingDayValues['2026-03-27'] = 27 Mar 06:00Z`, `['2026-03-28'] = 28 Mar 06:00Z`; `replan(now: tz.TZDateTime(berlin, 2026, 3, 28, 7), todayAlreadyRang: true, offsetAt: berlinRules)`; then set `lastCheckedUtcOffsetMinutes = 60`; `runTimezoneCheckpoint2(offsetAt: berlinRules, prefs: p, now: () => tz.TZDateTime(berlin, 2026, 3, 29, 3, 30))` | **after the replan:** `pendingDayValues['2026-03-29'] == 29 Mar 05:00Z`, `pendingDayClockTimes['2026-03-29'] == {c: wall 29 Mar 07:00, v: 05:00Z}` (**assert the entry exists**, G#13), `pendingDayInstantAnchored['2026-03-29'] == false`; **after Checkpoint 2:** still `05:00Z` (and 30 Mar-4 Apr still `05:00Z`), `lastCheckedUtcOffsetMinutes == 120` | assertion 1 fails (`06:00Z`); assertion 2 alone would pass today for the wrong reason (the legacy shift repairs 06:00Z → 05:00Z) - that is why both are asserted | all 10 |
| **T32p** | process-zone variant of T32 | process zone: the TW1 seed up to `D07 − 1`, replan at its value, `lastCheckedUtcOffsetMinutes` = the offset before `T`, Checkpoint 2 with `now = T + 30 min` | `pendingDayValues[D07]` unchanged across Checkpoint 2 and reads 07:00 | as T32 | 8 DST legs |
| **T33** (M-R12) | `pendingDayClockTimes` persistence (`app_state_scheduling_v2_test.dart`) | setter/getter; `_loadFromPreferences`; `reloadSchedulingStateFromPreferences` after an external prefs write (T-69); merge/prune in `replan` (entries before `oldestKeptDay` dropped, window days replaced, outside-window kept, removed when a window day becomes anchored or null); unreadable JSON | stored string exactly `{"2026-03-29":{"c":<ms>,"v":<ms>}}` for one entry; reload restores; prune bound identical to `pendingDayInstantAnchored`'s; unreadable → empty map, no throw | key missing | all 10 |

### b.4 Stage S3 - counter-tests against overcorrection

| ID | Test | Expect | Legs |
|---|---|---|---|
| **T40** (K2) | No-DST zones: rules for Asia/Tokyo, Asia/Kolkata, Asia/Kathmandu (+5:45), UTC vs `fixedOffset` of their constant offset, T02's generator (500 seeded cases each) | identical output (values µs, flags, anchored days, `plannedClockTimes`) | all 10 |
| **T41** (K11) | DST zones away from a transition: Europe/Berlin window 6-12 Jul 2026 vs `fixedOffset(+2)`; Australia/Lord_Howe 12-18 Jan 2026 vs `+11`; Pacific/Chatham 12-18 Jan 2026 vs `+13:45`; America/Santiago 13-19 Jul 2026 vs `−4`; T02's generator restricted to anchors/events ≥ 48 h from any transition (200 cases each) | identical output | all 10 |
| **T42** (K4) | a real overrun across the change is still reported: anchor 28 Mar 07:00 CET, event Sun 29 Mar 05:00 CEST (`03:00Z`), lead 0, md 30 | value `03:00Z` (K5: exactly the `hardFloor`, instant-anchored, no `plannedClockTimes` entry), overrun **true** (δ = −120) | all 10 |
| **T43** (K7) | FR-16 travel semantics unchanged: (a) no `pendingDayClockTimes` key: today's five Checkpoint 2 tests (legacy branch); (b) with an intact entry: value `08:00Z` planned under `fixedOffset(+1)` with clock time 09:00, Checkpoint 2 with `offsetAt: fixedOffset(+9)`, previous +1; (c) the same with `zoneRules(Asia/Tokyo)` | (a) unchanged; (b), (c) value becomes `00:00Z` - identical to `reinterpretForNewOffset` (`08:00Z + (1 − 9) h`), entry `v` updated | all 10 |
| **T44** (K8) | FR-11: after T32's sequence, and with a second Checkpoint 2 at `tz.TZDateTime(berlin, 2026, 3, 29, 7, 30)` | `pendingDayValues['2026-03-28']` and its entry unchanged by replan and both Checkpoint 2 runs; 29 Mar (now past) untouched by the second run | all 10 |
| **T45** (K9) | stale / inconsistent clock time ignored: `computeWeekPlan(lastEffectiveWakeTime: 28 Mar 06:30Z, lastEffectiveClockTime: 28 Mar 07:00, P null)`; consistency in whole ms: `lastEffectiveClockTime` 28 Mar 07:00:00.000999 with value `06:00:00.000Z` | first: 29 Mar `05:30Z` (from `L(v)` = 07:30), clock time 07:30; second: treated as consistent, 29 Mar `05:00Z` | all 10 |
| **T46** (K10) | FR-6 silence in every branch: T20/T21 (gap path), T27/T28 (run path, both clamp branches), and a cold start across the change (no anchor, P 07:00, event Tue 31 Mar 07:30 CEST, `durationToWakeUp` 30 min) | overrun false everywhere; cold start: 28 Mar `06:00Z`, 29 Mar-3 Apr `05:00Z` (spec FR-10 "DST" bullet: same without the event) | all 10 |
| **T47** (K12) | Checkpoint 2, same offset, intact pairs: T32's state with `lastCheckedUtcOffsetMinutes = 120`, Checkpoint 2 at Sun 29 Mar 03:30 CEST (spec FR-16 "no change") | the `pendingDayValues` and `pendingDayClockTimes` prefs strings byte-identical before/after; `lastCheckedUtcOffsetMinutes == 120` | all 10 |
| **T48** (K13, B3) | torn pairs (spec FR-16 "torn pair"): T32's state, `lastChecked` 60, then (a) entry `v` set to `06:00Z` while `pendingDayValues` stays `05:00Z`; (b) `pendingDayValues['2026-03-29'] = 06:00Z` while the entry says `05:00Z`; (c) key present, no entry for 29 Mar; (d) key holds unreadable JSON | 29 Mar untouched in every case: (a) `05:00Z`, (b) `06:00Z`, (c) `05:00Z`, (d) `05:00Z`; offset persisted as 120 in all | all 10 |
| **T49** (G§1.6 precedence; spec FR-16 "anchored wins") | `pendingDayInstantAnchored['2026-03-29'] = true` plus an intact entry whose re-resolution would differ (entry `c` = 29 Mar 08:00), offset changed | untouched | all 10 |
| **T50** (legacy branch) | T32's state with the `pendingDayClockTimes` key **removed**, offset +1 → +2 | legacy shift applies: 29 Mar `05:00Z` → `04:00Z` (documents why a present-but-empty key must not fall back to legacy) | all 10 |
| **T51** (K14) | `scheduleOnGapDays = false` with events Mon 30 Mar and Thu 2 Apr 07:30 CEST: masked days have no `plannedClockTimes` entry (pure) and no `pendingDayClockTimes` entry (after `replan`, injected rules). FR-21: `setDayEnabled('2026-03-29', false)` then a replan, then `true` and a replan, on the T32 state | masked: no entries. FR-21: 29 Mar value `05:00Z` and its entry unchanged by both switches; after re-enabling, a `ScheduledAlarm` at `05:00Z` exists | all 10 |
| **T52** (K16, B1; spec FR-1 "TZ-2a") | **Nuuk, pure** (Nuuk rules): window 28 Mar-3 Apr 2026; anchor 27 Mar 23:30 (−2) = `28 Mar 01:30Z`; P null (variant P 23:30); md 30 | 28 Mar `2026-03-29T00:59Z` (reads 28 Mar 22:59, −2), `plannedClockTimes[28 Mar]` = 28 Mar 23:30; 29 Mar `2026-03-30T00:30Z` (29 Mar 23:30, −1); 30 Mar `03-31T00:30Z`; overrun false. Today: 28 Mar `29 Mar 01:30Z` (reads 29 Mar 00:30). | all 10 |
| **T53** (spec FR-1 "TZ-2a" counter-tests) | plain R where the date does not change: Berlin 29 Mar 02:30 → `01:00Z`; Santiago rules, window 6-12 Sep 2026, anchor 5 Sep 00:30 (−4) = `04:30Z`, P null → 6 Sep `04:00Z` (reads 01:00, same date), 7 Sep `03:30Z` (00:30, −3); Nuuk autumn, window 24-30 Oct, anchor 23 Oct 23:30 (−1) = `24 Oct 00:30Z` → 24 Oct `25 Oct 01:30Z` (second pass, reads 24 Oct 23:30), 25 Oct `26 Oct 01:30Z` | as stated; no fallback applied | all 10 |
| **T54** (K16 in the Nuuk leg; 8ac1d9e) | **Nuuk, process zone**: detected generically - a local gap whose post-transition reading `L(T)` is on a later date than its `midReading` (skips in every other leg with a reason). Seed `lastProcessedConcludedDay = Dw − 1`, `pendingDayValues[Dw − 1] = DateTime(Dw − 1, 23, 30)`, P null, md 30. (1) `replan(now: that value, todayAlreadyRang: true)`; (2) FR-21: `setDayEnabled(isoDate(alarm.time), false)` for the `ScheduledAlarm` of `Dw`, replan (settings change, `now` = `Dw` 12:00), then re-enable; (3) ring: `replan(now: pendingDayValues[Dw], todayAlreadyRang: true)` | (1) `pendingDayValues[iso(Dw)]` = `T − 1 min` (Nuuk `2026-03-29T00:59Z`); its `ScheduledAlarm.time` local date is `Dw` (28 Mar), 22:59. (2) `disabledDays` contains `iso(Dw)`, not `iso(Dw + 1)`; `Dw`'s alarm is not armed, `Dw + 1`'s is. (3) `lastProcessedConcludedDay == Dw` (not `Dw + 1`); `pendingDayValues[iso(Dw + 1)]` reads 23:30 on `Dw + 1` (`2026-03-30T00:30Z`); `pendingDayValues[iso(Dw)]` unchanged. Today: (1) `29 Mar 01:30Z` → the alarm's date is 29 Mar. | America/Nuuk only (reports; not a required check) |
| **T55** | manual alarms aligned (Q2 = yes): `nextManualOccurrence` for a manual 23:30 on 28 Mar 2026 in Nuuk | 22:59 on 28 Mar (`00:59Z`), the minute before the gap; `localWallClockInstant` itself still plain R (29 Mar 00:00, `01:00Z`); every other T-202 test green unchanged | Nuuk (+ all 10: no other zone changes) |
| **T56** | `_maxStepMinutes` on readings: the T20 plan | `maxStepBucket` is the zero-step bucket, not a 60-minute step | all 10 |

### b.5 Spec "Test:" bullets → verbatim tests

| Spec bullet (new in step 3) | File / test ID |
|---|---|
| FR-1 "DST, spring" (ΔT = 0, 47 h), "DST, autumn" (49 h) | `scheduling_v2_test.dart`. Observable form: `computeWeekPlan` with the anchor, the `hardFloor` on its day, md 15, P null → every day 07:00 by the clock, the `hardFloor` day exactly its instant, no overrun (FR-5 step 2's ΔT = 0 point). |
| FR-1 "order" | `scheduling_v2_test.dart` = T31 |
| FR-1 "TZ-2a, America/Nuuk" and its counter-tests | `scheduling_v2_test.dart` = T52, T53 (single-day forms) |
| FR-2 "DST inside the window" | `scheduling_v2_test.dart` = T10 |
| FR-4 five "DST" bullets | `scheduling_v2_test.dart` = T20, T21, T24, T26, T29 |
| FR-6 "DST, no shift across a change", "DST, a real shift … on readings" | `scheduling_v2_test.dart` = T27, T30 (+ the 05:00 CEST / md 30 case = T42) |
| FR-10 "DST" | `scheduling_v2_test.dart` = T46's cold start without the event |
| FR-16 "daylight saving" (changed text), "stale baseline", "torn pair", "anchored wins", "no change" | `replan_test.dart` group "runTimezoneCheckpoint2" = T32, T48(a), T49, T47. The existing pure test `reinterpretForNewOffset … daylight saving` (`scheduling_v2_test.dart:705`) stays as a test of the legacy function; its comment says it implements the *withdrawn* bullet's arithmetic, now the legacy branch. |

Also in the same commit as FR-2's code: update the verbatim FR-2 quote in
`test/scheduling_v2_audit_test.dart:365-367` to the new sentence (G#7).

### b.6 Stage S4 - the sweep (TZ-9)

- **File:** `test/t206_dst_sweep_test.dart`, pure layer only. **Runs in CI's UTC leg only**: `skip`
  unless `Platform.environment['TZ'] == 'UTC'` (the result does not depend on the process zone;
  ten runs buy nothing; the UTC leg runs the suite twice, with and without coverage - budget both).
  Runtime budget: ≤ 60 s per run on the runner.
- **Data independence (G#16):** a checked-in table `test/fixtures/dst_transitions_2026_2027.json`
  generated by a Python script (`scripts/gen_dst_fixture.py`, `zoneinfo`, records the tzdata
  version) for **every** zone with a transition in 2026/27 (201 zones, 787 transitions by today's
  scan): transition instant, offset before/after, and `R_plan` for each whole-15-minute reading in
  the affected range ± 1 h plus 07:00 and 00:30 on the change date. The sweep first asserts that
  `package:timezone`'s rules reproduce every transition and every `R_plan` in the table (data
  cross-check; a mismatch names the zone - tzdata drift between the two sources must fail loudly,
  not be averaged away), then uses the table as the oracle. The algorithm is independent too (table
  from a minute scan; app from probing + bisection).
- **Cases:** every table transition × window position k ∈ {0, 3, 6} × P ∈ {07:00, 00:30, the table's
  readings}; plan = `computeWeekPlan` with the zone's rules, anchor = day before the window at P,
  P held (hold scenario) and P + 60 min with md 30 (drift scenario). Fixed seed for one random
  appointment per case (S).
- **Asserts:** **T** `value(D) == table R_plan(D, P)` in the hold scenario; **S** every day with a
  `hardFloor` has `value ≤ hardFloor`; **G** consecutive planned clock times differ by ≤ md (drift
  scenario) and no overrun in the hold scenario; **A1** no zone changes offset twice within ±30 h
  (from the table).
- **Stated limits (G#16):** the sweep asserts T only for holds; drift gets G only. It never touches
  persistence, Checkpoint 2 or `deviceOffsetAt` - those are the process-zone tests (TW*, T32p, T54)
  in ten legs.

### b.7 Test comments to correct (tests step, S1 commit)

- `test/scheduling_v2_dst_test.dart:37`: "05:00 UTC = 07:00 Berlin" on 27 Mar → **06:00 CET**.
- `test/scheduling_v2_dst_test.dart:73`: "04:40 UTC (= 06:40 Berlin" on **28 Mar** → **05:40 CET**
  (the transition is on the 29th). Lines 40-43 (3 Apr, CEST) are correct.
- Say in the test's header that it is a **day-count** test under a fixed `cest` offset (T-76), not a
  test of Berlin readings; under real Berlin rules its ΔT would be −80 min, not −140 (G§2.6).
- `test/scheduling_v2_offset_test.dart:228-253` ("distribute/groupTarget are frame-invariant … gets
  NO offset"): in S3 rename/re-comment - `groupTarget` now needs `offsetAt` (G§2.3).

---

## (c) Staged commit plan

> **As implemented (2026-09-29):** S1-S4 were implemented together and landed in **one** commit on
> `dev`, not as separate stages, so there is no per-stage red-first history. The tests were written
> first and were red against the old behaviour for the intended reasons (54 new tests failing,
> every existing test green); the review of the implementation then confirmed by mutation that
> they bite (see `docs/TODO.md` T-206). The plan below is kept as written.

Every stage is a separate commit on `dev`, green in all ten legs, and **device-safe as
`current.apk`** (the maintainer always runs the dev build). A stage's red-first evidence is shown
against the previous stage.

| Stage | Content | Device state after it | Requirements | Tests |
|---|---|---|---|---|
| **S0** (requirements) | Requirements in `docs/timezone-requirements.md`, `docs/scheduling-v2-spec.md`, `docs/TODO.md` | no code change | - | - |
| **S1** Pure refactor + differential test | `ZoneOffsetAt`/`deviceOffsetAt`/`fixedOffset`; `resolveWallClock` extracted, `localWallClockInstant` a wrapper; `replan`/`runSchedulingCheckpoint`/`runCheckpointSafely` take `offsetAt` (default `fixedOffset(currentTime.timeZoneOffset)`, reduced to one `Duration` for the pure layer); Checkpoint 2 takes `offsetAt` only (`readOffset` removed); Checkpoint 1 records `offsetAt(currentTime)`; legacy snapshot under `test/support/`; the two comment fixes (b.7) | identical behaviour | R1, R2, R12 (S1 part), R14 (signature) | T01 (gate: no `expect` edited), T02, T03, T04 |
| **S2** FR-2 day assignment | `eventsForDay`/`hardFloor` take `offsetAt` (date of `L(e)`); `computeWeekPlan` gains an optional `offsetAt` used **only** for its `hardFloor` calls (default `fixedOffset(deviceUtcOffset)` - no pure test edit); `replan` default rules `deviceOffsetAt`, full rules to day assignment, FR-9/FR-12 day advance, diagnostics minute; reading arithmetic still `offsetAt(currentTime)`; the FR-2 audit-test quote updated | appointments land on their own day; wall-clock values and Checkpoint 2 exactly as today (instant-anchored values are skipped by Checkpoint 2), so nothing new can go wrong | R7, R12 (S2 part), R13 (minute) | T10-T14; red first: T11, T12 (vs S1) |
| **S3** Reading-space planning + Checkpoint 2 - **one commit** | R_plan; reading-space FR-4…FR-7; clamp after R; `plannedClockTimes`; `lastEffectiveClockTime`; `pendingDayClockTimes` persistence and reload; Checkpoint 2 policy; `_maxStepMinutes`; `_dateTimeLike` deleted; `computeWeekPlan`'s `deviceUtcOffset` removed (mechanical test edits `deviceUtcOffset: d` → `offsetAt: fixedOffset(d)` for the remaining pure call sites); `replan` default rules to everything | T-206 fixed on the device | R3-R6, R8-R11, R13-R16, R18 | T20-T33, T40-T56; red first: TW1, TW3, TW5, TW8b, T54 (vs 8ac1d9e and S2), T32/T32p, T27-T31, T33 (vs S2). **Review gate:** edited `expect`s are frame-only (the `distribute` group's local `_t` fixtures → instant comparison), and T02 stays green |
| **S4** Sweep | Python generator + checked-in table; `t206_dst_sweep_test.dart` (UTC leg) | no code change | R19 (TZ-9 part) | b.6 |
| **S5** Docs | `timezone-requirements.md` state "met" (TZ-2/TZ-2a); CLAUDE.md rules (R19); `docs/device-trial-checklist.md` line (A3, March and October); T-206 closed; T-119 closed if Q3 confirmed | - | R19 | - |

**Why S3 cannot be split** (G§4.1): per-day planning without the Checkpoint 2 change ships D3 (a
stale-baseline Checkpoint 2 moves correct values an hour); the Checkpoint 2 re-resolution without
per-day planning would make Checkpoint 2 - which fires right after every replan's reminder
creation - rewrite values FR-18 has just armed differently; a per-day *offset* with UTC-digit
arithmetic (the proposal's rejected alternative A) keeps D2. `pendingDayClockTimes` belongs in S3
too: without it D4 is permanent for a held gap reading (Nuuk: 22:59 forever, 8.3).

---

## (d) Migration of persisted state on an installed app

| Key / state | Requirement |
|---|---|
| `pendingDayValues` | Format unchanged (ISO date → epoch ms). No rewrite on upgrade. Values planned by the old version keep ringing as armed; the first new replan replans the window. |
| `pendingDayInstantAnchored` | Format and meaning unchanged. Wins over a planned clock time (T49). |
| `pendingDayClockTimes` (new) | Absent after an upgrade: `replan` falls back to `L(v)` for the anchor (today's behaviour); Checkpoint 2 uses the legacy shift **only while the key is absent altogether**. The first new replan always writes the key (`{}` if empty), which ends the legacy branch for that install. A present key with a missing, torn or unreadable entry is **skipped**, never legacy-shifted (T48, T50). |
| Torn cross-isolate or crash-interrupted writes | Each entry is self-validating through its paired `v`; a mismatch with `pendingDayValues` in either direction is ignored by Checkpoint 2 and by the anchor lookup; the next replan rewrites all three keys. Write order in `replan`: values, anchored, clock times; in Checkpoint 2: values, then clock times. T-199 notes Checkpoint 2 actually runs in the main isolate for this event, but the design does not rely on that. |
| Downgrade then upgrade | An older build ignores the key, so it goes stale; stale entries fail the paired-`v` check and are ignored - no migration needed. |
| Upgrade inside a transition week | The first new plan may anchor on an already-rung D1 value (e.g. 08:00 CEST) and drift back once, over ⌈60 / md⌉ days. Accepted under the test-phase policy (memory "ignore-data-loss-during-test-phase"); recorded in T-206. |
| `ScheduledAlarm` JSON, `disabledDays`, `lastCheckedUtcOffsetMinutes` | Unchanged (the fallback in 0.1 needs no new `ScheduledAlarm` field). |
| Diagnostics | No persisted format change unless R13's optional counts are added; then append-only fields/enum values, so older exports still decode. |

---

## (e) Out of scope

- **Travel:** TZ-4 … TZ-7, T-205 (provisional, not promised). In particular manual-alarm re-arming
  on a zone change, an `ACTION_TIMEZONE_CHANGED` receiver, Checkpoint 2 re-arming armed alarms
  (T-113), Checkpoint 2 at bedtime (T-199), and the meaning of `pendingDayClockTimes` keys after a
  date-line jump (keys are civil dates in the zone the plan was made in - documented, not solved).
  The Checkpoint 2 change improves travel behaviour inside a gap/overlap but must not be advertised
  as travel support.
- **Open maintainer decisions not taken here:** T-112 (curve past midnight; reading-space
  construction keeps today's "date follows the step"), T-115 (exactly 12 h), T-120 (lead times past
  midnight - the "separate TODO" Günther asked for already exists as T-120), T-121, T-122.
- **Markus's T-202 review points the maintainer chose not to adopt.** Only the CI zones, TZ-1's
  formalisation and TZ-8's Sleep Goal were adopted (8ac1d9e); the rest stays as the maintainer left
  it and is not reopened by T-206. (That review is not in the repository, and its individual points
  are not listed here - see Q4.) Also out: T-202's own residuals (the `alarm` plugin's native
  snooze / `PLATFORM_REFUSAL` re-storage; no device run of A3 beyond the checklist line).
- **An "ease into DST" option** (spread the hour over several days) - a new feature needing its own
  requirement; decision A excludes it as default behaviour.
- **Unconditional Checkpoint 2 re-resolution** to catch a tzdata update between planning and ringing
  (Markus's U2 recommendation): rejected in FR-16 (Checkpoint 2 fires after every replan and re-arms
  nothing; the next replan corrects it).
- **`replan`'s `today = midnight(currentTime)`** derived from `L(now)` instead (Markus §3.6).

---

## (f) Maintainer answers (2026-09-28, verbatim: "Greenland: Yes. Manual alarms: yes. t-119: OK.")

- Q1 confirmed: the fallback R_plan stays the design.
- Q2 yes: manual alarms are aligned - `nextManualOccurrence` resolves with R_plan (new **T206-R21**:
  the manual-alarm path calls the same `resolvePlannedClockTime`, with the device's zone as
  `offsetAt`; `localWallClockInstant` keeps plain R for all other callers). Its stage is S3.
- Q3 confirmed: T-119 is part of T-206 (R7), closed with it.

### Original questions

- **Q1 - Decision B:** the design uses the permitted fallback (22:59 on 28 Mar in Nuuk) for the
  reasons in 0.1. Confirm, or ask for the primary rule (then a window-day key through
  `ScheduledAlarm`, the ring checkpoint and the FR-21 toggle, and T-112/T-120 have to be decided
  with it).
- **Q2 - Manual alarms in Nuuk:** they keep TZ-1's plain R (a manual 23:30 that night rings at
  00:00 on the 29th) while a scheduled 23:30 rings at 22:59 on the 28th. Align them, or leave it?
- **Q3 - T-119:** FR-2 now assigns an appointment by the device rules at its own instant. Markus,
  Günther and T-206's original acceptance all call for it, but T-119 was an open decision you
  postponed on 2026-09-24. Confirm it is part of T-206.
- **Q4 - Markus's T-202 gaps you chose to ignore:** listed generically in (e); if you want them
  named in T-206's out-of-scope list, point me to them.

---

## 7. Günther's review → where it is handled

| Item | Handled in |
|---|---|
| B1 Nuuk / next date | 0.1, R3, TZ-2a, T52-T54, TW8b |
| B2 one offset source for Checkpoint 2 | R14, R12, FR-16 "One rules source", T04, T01 |
| B3 pair integrity | R11 (`{c, v}`), R14 policy, FR-16 steps 1-4, T47-T50 |
| B4 FR-1 rewritten, not appended | spec FR-1 (size **and sign** on readings; bounds on instants), FR-5 precondition edited |
| #5 D3 rationale corrected | spec FR-16 "Why the re-resolution is needed", T-206 D3 |
| #6 FR-3 not a second source; `preferredWakeUpTime` row | spec FR-3 table + paragraph, R10 |
| #7 FR-2 `spec:97-99` + audit quote | spec FR-2 Testability rewritten; b.5 |
| #8 FR-1 DST test with dates | spec FR-1 (Sat 28 → Mon 30 Mar, 47 h; autumn 49 h) |
| #9 maintainer confirms the `maxDailyDelta` sentence | decision A ("A: 1"), TZ-2 |
| #10 anchored wins, gap-day mask, legacy branch kept | R9, R14, FR-16, T49, T50, T51 |
| #11 distinct term | "planned clock time", `pendingDayClockTimes` |
| #12 twins | TW1, TW3, TW5, TW8b, T11, T32p, T54 |
| #13 R5 premise, R11 entry + single injection, R8b persistence | TW5, T32, TW8b |
| #14 K3/K6 relabelled; K11-K16 | T29, T31; T41, T47, T48, T51, T02, T52-T54 |
| #15 spec bullets verbatim | b.5 |
| #16 sweep independence, cost, limits | b.6 |
| #17 derive process-zone digits | b.0 |
| #18 six-step order, wrappers, review gates | (c), R18 |
| #19 T-76 comments | b.7 |
| #20 device-trial line (A3) | R19, S5 |
| G§1.1 CP1 records `offsetAt(currentTime)` | R12, T04 |
| G§1.5 FR-9 valve drops readings; U3 | R9; U3 is moot after R7 (both clamps compare instants) |
| G§1.6 upgrade in a transition week | (d), T-206 |
| G§1.7 diag counts | R13 (optional) |
| G§2.3 Lemma C holds for S1 only; frame-only edits in S3 | (c) review gates, T02 |
| G§3.1 R7 twin, R11 assertions | T11, T32 |

---

## 8. Expected values (Python `zoneinfo`, brute-force R)

### 8.1 Europe/Berlin and the injected fixtures

```
R(2026-03-28 07:00) = 03-28T06:00Z (CET)      R(2026-03-29 07:00) = 03-29T05:00Z (CEST)
R(2026-03-30 07:00) = 03-30T05:00Z            R(2026-04-04 07:00) = 04-04T05:00Z
R(2026-10-24 07:00) = 10-24T05:00Z (CEST)     R(2026-10-25 07:00) = 10-25T06:00Z (CET), same to 10-31
R(2026-03-28 02:30) = 03-28T01:30Z            R(2026-03-29 02:30) = 03-29T01:00Z (reads 03:00 CEST)
R(2026-03-30 02:30) = 03-30T00:30Z            R(2026-10-24 02:30) = 10-24T00:30Z
R(2026-10-25 02:30) = 10-25T01:30Z (2nd pass) R(2026-10-26 02:30) = 10-26T01:30Z
first 02:45 on 10-25 = 10-25T00:45Z (CEST)
drift 07:00→09:00 md30: 03-29 07:30=05:30Z, 03-30 08:00=06:00Z, 03-31 08:30=06:30Z, 04-01 09:00=07:00Z
03-29 05:00 CEST = 03:00Z; 03-29 06:00 CEST = 04:00Z; 03-31 07:30 = 05:30Z; 03-30 07:30 = 05:30Z
03-27 07:00 CET = 06:00Z; 10-27 07:30 CET = 06:30Z
event Mon 03-30 00:30 CEST = 03-29T22:30Z (under fixed +1 reads 03-29 23:30)
L(03-28T06:30Z) = 07:30 CET; R(03-29 07:30) = 05:30Z
28 Mar 06:00Z → 30 Mar 05:00Z = 1 day 23 h (47 h)
Nuuk:  R(03-27 23:30) = 03-28T01:30Z;  R(03-28 23:30) = 03-29T01:00Z (reads 03-29 00:00)
       R_plan(03-28 23:00 … 23:59) = 03-29T00:59Z (reads 03-28 22:59, −2)
       R(03-29 00:00) = 03-29T01:00Z;  R(03-29 23:30) = 03-30T00:30Z (−1)
       R(10-23 23:30) = 10-24T00:30Z;  R(10-24 23:30) = 10-25T01:30Z (2nd pass, reads 10-24 23:30)
       R(10-25 23:30) = 10-26T01:30Z
Santiago: R(09-06 00:30) = 09-06T04:00Z (reads 01:00, same date, R_plan = R)
          R(09-05 23:30) = 09-06T03:30Z; R(09-07 00:30) = 09-07T03:30Z; R(04-04 23:30) = 04-05T03:30Z
Offsets: Berlin July +2; Lord Howe January +11
```

### 8.2 Per CI leg: 2026 transitions and the 07:00 ring sequence

`value` = R(date 07:00); `one offset` = what today's single-offset plan gives from the day before.

| Leg | Transition (UTC), offsets, affected readings | D07 − 1 / D07 / D07 + 1: value (one offset → reads) |
|---|---|---|
| UTC, Asia/Tokyo | none (process-zone DST tests skip) | - |
| Europe/Berlin | gap 03-29 01:00Z +1→+2 [02:00, 03:00) | 03-28 06:00Z / 03-29 05:00Z (06:00Z → 08:00) / 03-30 05:00Z (→ 08:00) |
| | overlap 10-25 01:00Z +2→+1 [02:00, 03:00) | 10-24 05:00Z / 10-25 06:00Z (05:00Z → 06:00) / 10-26 06:00Z (→ 06:00) |
| America/St_Johns | gap 03-08 05:30Z −3:30→−2:30 [02:00, 03:00) | 03-07 10:30Z / 03-08 09:30Z (→ 08:00) / 03-09 09:30Z |
| | overlap 11-01 04:30Z −2:30→−3:30 [01:00, 02:00) | 10-31 09:30Z / 11-01 10:30Z (→ 06:00) / 11-02 10:30Z |
| Pacific/Chatham | overlap 04-04 14:00Z +13:45→+12:45 [04-05 02:45, 03:45) | 04-03 17:15Z / 04-04 18:15Z (→ 06:00) / 04-05 18:15Z |
| | gap 09-26 14:00Z +12:45→+13:45 [09-27 02:45, 03:45) | 09-25 18:15Z / 09-26 17:15Z (→ 08:00) / 09-27 17:15Z |
| Australia/Lord_Howe | overlap 04-04 15:00Z +11→+10:30 [04-05 01:30, 02:00) | 04-03 20:00Z / 04-04 20:30Z (→ 06:30) / 04-05 20:30Z |
| | gap 10-03 15:30Z +10:30→+11 [10-04 02:00, 02:30) | 10-02 20:30Z / 10-03 20:00Z (→ 07:30) / 10-04 20:00Z |
| America/Nuuk | gap 03-29 01:00Z −2→−1 [03-28 23:00, 03-29 00:00) | 03-28 09:00Z / 03-29 08:00Z (→ 08:00) / 03-30 08:00Z |
| | overlap 10-25 01:00Z −1→−2 [10-24 23:00, 10-25 00:00) | 10-24 08:00Z / 10-25 09:00Z (→ 06:00) / 10-26 09:00Z |
| America/Santiago | overlap 04-05 03:00Z −3→−4 [04-04 23:00, 04-05 00:00) | 04-04 10:00Z / 04-05 11:00Z (→ 06:00) / 04-06 11:00Z |
| | gap 09-06 04:00Z −4→−3 [09-06 00:00, 01:00) | 09-05 11:00Z / 09-06 10:00Z (→ 08:00) / 09-07 10:00Z |
| Antarctica/Troll | gap 03-29 01:00Z +0→+2 [01:00, 03:00) | 03-28 07:00Z / 03-29 05:00Z (→ 09:00) / 03-30 05:00Z |
| | overlap 10-25 01:00Z +2→+0 [01:00, 03:00) | 10-24 05:00Z / 10-25 07:00Z (→ 05:00) / 10-26 07:00Z |
| Europe/Dublin | gap 03-29 01:00Z +0→+1 [01:00, 02:00) | 03-28 07:00Z / 03-29 06:00Z (→ 08:00) / 03-30 06:00Z |
| | overlap 10-25 01:00Z +1→+0 [01:00, 02:00) | 10-24 06:00Z / 10-25 07:00Z (→ 06:00) / 10-26 07:00Z |

### 8.3 Per CI leg: held gap reading (TW8b), `v(D) = R_plan(w)`, `v(D+1) = R(D+1, tod(w))`

| Leg | w (mid-gap) | v(D) (reads) | v(D+1) (reads) | if anchored on L(v) instead |
|---|---|---|---|---|
| Europe/Berlin | 03-29 02:30 | 03-29 01:00Z (03:00) | 03-30 00:30Z (02:30) | 03-30 01:00Z (03:00) |
| America/St_Johns | 03-08 02:30 | 03-08 05:30Z (03:00) | 03-09 05:00Z (02:30) | 03-09 05:30Z |
| Pacific/Chatham | 09-27 03:15 | 09-26 14:00Z (03:45) | 09-27 13:30Z (03:15) | 09-27 14:00Z |
| Australia/Lord_Howe | 10-04 02:15 | 10-03 15:30Z (02:30) | 10-04 15:15Z (02:15) | 10-04 15:30Z |
| America/Nuuk | 03-28 23:30 | **03-29 00:59Z (03-28 22:59)** - TZ-2a | 03-30 00:30Z (23:30) | 03-29 23:59Z (22:59, forever) |
| America/Santiago | 09-06 00:30 | 09-06 04:00Z (01:00) | 09-07 03:30Z (00:30) | 09-07 04:00Z |
| Antarctica/Troll | 03-29 02:00 | 03-29 01:00Z (03:00) | 03-30 00:00Z (02:00) | 03-30 01:00Z |
| Europe/Dublin | 03-29 01:30 | 03-29 01:00Z (02:00) | 03-30 00:30Z (01:30) | 03-30 01:00Z |

### 8.4 All-zone scan for TZ-2a (every zone in `zoneinfo`, 2026-2027)

201 zones with a transition, 787 transitions. Gaps whose end lies on a later date than the skipped
readings: America/Godthab, America/Nuuk, America/Scoresbysund - 2026-03-29T01:00Z (28 Mar 23:00 →
29 Mar 00:00) and 2027-03-28T01:00Z (27 Mar 23:00 → 28 Mar 00:00). None else (Santiago's gap
starts at 00:00 on the same date).
