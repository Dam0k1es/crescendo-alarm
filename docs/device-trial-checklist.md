# Device Trial: Checklist

Purpose: turn a trial run into **dated evidence** instead of impressions. Every line has a result
field — whatever is not filled in counts as not checked. `docs/REQUIREMENTS.md` points to this file
for R3 and R4.

Fill in per run. Copy the template, don't overwrite it.

| Field | Value |
|---|---|
| Date | |
| Device (manufacturer, model) | |
| Android version / API | |
| Device time zone | |
| APK (file, size, `apksigner` checksum) | |
| Build (commit) | |

## Why manual at all

Automation covers a lot by now: `flutter test` checks the domain logic in six time zones, and the
E2E suite runs against a real emulator and proves FR-18 all the way to the alarm plugin. Four
things it structurally **cannot** show, and those are exactly what's here:

1. **Real calendar accounts.** The CI emulator has none. Every E2E scenario injects its
   appointments via the `fetchEvents` parameter — the real chain `device_calendar` → `eventToMeeting`
   → `TZDateTime` in the *appointment's own* zone stays unchecked. That is, of all things, the
   source of T-61.
2. **Sound.** The emulator runs without audio (`-noaudio`); the only substitute is a `dumpsys
   audio` log as circumstantial evidence.
3. **Camera.** The QR scan is injected via `debugBarcodeStreamOverride`; real decoding has never
   run (T-16).
4. **OEM behaviour.** Doze, battery saving, and manufacturer-specific process killers don't exist
   on a standard emulator.

## A — Core function

| # | Check | Expectation | Result |
|---|---|---|---|
| A1 | Install and start the app | Splash → permissions → main screen | |
| A2 | Set a manual alarm for +2 min | rings, overlay appears | |
| A3 | Switch off via "Stop" | overlay gone, no alarm still active | |
| A4 | Sound audible? Volume as set? | yes | |
| A5 | Enable gentle wake (default ramp 1 min), repeat the alarm | volume rises over ~60 s up to the set volume | |
| A6 | Set "Ramp duration" to 5 min, repeat the alarm | the ramp now takes ~5 min, no longer 1 min (T-96) | |
| A7 | Try setting the ramp below 1 min | not possible, "At least 00:01 h" message appears | |

## B — Calendar-derived wake-up (the actual product path)

| # | Check | Expectation | Result |
|---|---|---|---|
| B1 | Set up a real calendar account, create an appointment for tomorrow morning | | |
| B2 | Set "Duration to wake up"/"to get ready" in settings | | |
| B3 | Press the sync button in the alarm list | alarms for the next 7 days appear | |
| B4 | Check the first alarm against appointment start − lead times | correct to the minute | |
| B5 | **Move** the appointment in the calendar, sync again | alarm follows | |
| B6 | Delete the appointment, sync again | the day drifts toward the preferred wake-up time, or drops out | |
| B7 | Create an appointment with a **foreign time zone** (e.g. Asia/Tokyo) | the alarm follows the **device's** zone, not the appointment's zone (FR-2) | |
| B8 | Create an all-day appointment | ignored, the day stays a gap day (FR-2) | |

## C — Survival (R3)

| # | Check | Expectation | Result |
|---|---|---|---|
| C1 | Set an alarm, `adb shell dumpsys alarm \| grep com.wakeywakey` | entry present | |
| C2 | Reboot the device **without** opening the app, then repeat C1 | entry present again | |
| C3 | Wait for the alarm to ring after the reboot | rings | |
| C4 | `adb shell am force-stop com.wakeywakey.wakeywakey`, then C1 | **Expectation: entry gone** — Android removes the alarms of a force-stopped package; this is platform behaviour, not an app defect. Record it here so R3 tracks it as a boundary, not a bug. | |
| C5 | Open the app after C4 | alarms are re-armed (FR-17 recovery) | |
| C6 | Enable battery saver, set an alarm for +10 min, screen off | rings anyway | |

Known from the code regarding C1/C2: the app has **no** `BootReceiver` of its own. The `alarm`
plugin registers one (`com.gdelataillade.alarm.alarm.BootReceiver`) and re-arms the stored alarms
after boot via `setExactAndAllowWhileIdle(RTC_WAKEUP, …)`; in doing so it discards missed alarms as
"stale". So C2 should be green — it has just never been checked.

## D — Guaranteed wake-up (QR)

| # | Check | Expectation | Result |
|---|---|---|---|
| D1 | Generate and print a QR code in settings | | |
| D2 | Let an alarm ring | QR scanner appears instead of "Stop" | |
| D3 | Scan the **wrong** code | alarm keeps running, scanner stays open | |
| D4 | Scan the correct code with the **real camera** | alarm stops (closes T-16) | |
| D5 | Check whether the scanned value appears anywhere on screen | **must not** — only "QR Code detected" | |

## E — Diagnostics log (T-89)

| # | Check | Expectation | Result |
|---|---|---|---|
| E1 | Open Settings → Diagnostics | events visible | |
| E2 | Review the content | no time of day, no date, no appointment title, no calendar name, no QR code | |
| E3 | Check after B3 | `weekPlanComputed` with `plannedDays=7`, `windowDayCount == distinctDayKeys` | |
| E4 | Check after A3 | `alarmSync` **without** a large `toRemove` at `toAdd=0` (that would be T-64) | |
| E5 | Check after the morning alarm | `dayAdvance` with `daysProcessed >= 1` (0 would be T-75) | |
| E6 | Check at bedtime | `timezoneCheck` present and marked with `(bg)` → **closes T-62** | |
| E7 | Press "Copy" and paste the text somewhere | complete, exclusively enum names and numbers | |
| E8 | Switch off, restart the app, check | no new events | |

E6 is the point with the biggest leverage: that a silent notification actually triggers
`onNotificationCreatedMethod` has so far only been inferred from the package source. If
`timezoneCheck (bg)` appears in the log, FR-16's checkpoint 2 is confirmed on the device.

## F — Time zones and daylight saving

| # | Check | Expectation | Result |
|---|---|---|---|
| F1 | Change the device time zone (e.g. Berlin → Tokyo), open the app | days using the preferred wake-up time keep their **digits**, appointment days keep their **instant** (FR-16) | |
| F2 | Check the diagnostics log after F1 | `timezoneCheck` with `offsetChangeShape=3` (otherChange) | |
| F3 | Set the device clock to the day before a daylight-saving transition, alarm for the transition day | **known limitation:** on this one day the alarm can be off by one hour (see FR-16 in `docs/scheduling-v2-spec.md`) | |

## Findings

Enter anything notable here with a date and give it its own number in `docs/TODO.md` — this file
is the evidence, not the task list.

- **2026-09-18, C-adjacent (real device):** the app's UI was swiped away from the recent-apps list
  (not `am force-stop`) while a manual alarm was armed. The alarm rang correctly. This is a
  different process-death path from C1–C6 above (a user swipe rather than a forced kill or reboot)
  and is the one most users actually trigger day to day - recorded here since the checklist above
  has no line for it yet.
- **2026-09-18, found via the same session:** an alarm switched off via its notification (swipe,
  no app UI open) instead left the ring screen stuck showing on the next app open, with nothing
  actually ringing behind it. Fixed - see `docs/TODO.md` T-147.
