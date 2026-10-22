# Device Trial: 2026-10-19/20 night run (Fairphone 3, Android 13)

Copy of `docs/device-trial-checklist.md`, filled for this run. Rows without a result were not checked
(calendar-derived alarms were out of scope by maintainer decision).

<!-- template follows -->

# Device Trial: Checklist

Purpose: turn a trial run into **dated evidence** instead of impressions. Every line has a result
field — whatever is not filled in counts as not checked. `docs/REQUIREMENTS.md` points to this file
for R3 and R4.

Fill in per run. Copy the template, don't overwrite it.

| Field | Value |
|---|---|
| Date | 2026-10-19/20 (night run), 2026-10-23 (second run: A5-A7, C6, G, H2, H9) |
| Device (manufacturer, model) | Fairphone 3 (LineageOS) |
| Android version / API | 13 / 33 |
| Device time zone | Europe/Berlin (device clock ran ~1 day + 1 h ahead, no network; all checks relative) |
| APK (file, size, `apksigner` checksum) | dev builds signed with the shared dev key (cert SHA-256 2336317c…5dfc): CI run 39137471756 (current.apk, SHA-256 3d7016ad…da80), then local debug builds of the fixes |
| Build (commit) | 1bd03f1 (A, D, H8-H16, H1), d758412 (C1-C5 re-run, E, H3-H6, H12) |

## Why manual at all

Automation covers a lot by now: `flutter test` checks the domain logic in ten time zones, and the
E2E suite runs against a real emulator and proves FR-18 all the way to the alarm plugin. Four
things it structurally **cannot** show, and those are exactly what's here:

1. **Real calendar accounts.** The CI emulator has none. Every E2E scenario injects its
   appointments via the `fetchEvents` parameter — the real chain `device_calendar` → `eventToMeeting`
   → `TZDateTime` in the *appointment's own* zone stays unchecked. That is, of all things, the
   source of T-61.
2. **Sound.** The emulator runs without audio (`-noaudio`); the only substitute is a `dumpsys
   audio` log as circumstantial evidence.
3. **Camera.** The QR scan is injected via `QrScanner.debugScanStreamOverride`; real decoding has
   been confirmed on a real device by hand (T-143), never in CI (T-16).
4. **OEM behaviour.** Doze, battery saving, and manufacturer-specific process killers don't exist
   on a standard emulator.

## A — Core function

| # | Check | Expectation | Result |
|---|---|---|---|
| A1 | Install and start the app | Privacy policy → **Continue** → permissions → main screen | 2026-10-20 ✓ privacy policy → Continue (permissions pre-granted via adb) |
| A2 | Set a manual alarm for +2 min | rings, overlay appears | 2026-10-20 ✓ rang at the set minute |
| A3 | Switch off via "Stop" | overlay gone, no alarm still active | 2026-10-20 ✓ Stop ended it; the repeating alarm was re-armed for its next weekday (T-14) |
| A4 | Sound audible? Volume as set? | yes | |
| A5 | Gentle wake is on by default with a 5-min ramp (T-170); create a new manual alarm, let it ring | volume rises over ~5 min up to the set volume | 2026-10-23 partly: stored default is gentle wake on, 5-min ramp (settings and plugin storage: fade steps to 300 s); the audible rise was not listened to |
| A6 | Set "Ramp duration" to 1 min, create a **new** manual alarm, let it ring | the ramp now takes ~1 min (T-96); an alarm created before the change keeps its own 5-min ramp | 2026-10-23 ✓ (stored values): ramp set to 1 min, a NEW alarm carries 60 s, the alarms created before keep 300 s |
| A7 | Try setting the ramp below 1 min | not possible: 00:00 is raised to 00:01 (the minimum is stated in the option's **?** help, T-166) | 2026-10-23 ✓ 00:00 entered -> raised to 00:01, stored as 60 s |

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
| B9 | Switch tomorrow's scheduled alarm off, then press sync; check `dumpsys alarm` (C1's command) | the alarm stays in the Scheduled list with its switch off, at the same time; its platform entry is gone; still listed off after restarting the app (FR-21, T-221) | |
| B10 | Switch it back on | listed on, armed again (one more platform entry), rings at the day's planned time | |

## C — Survival (R3)

| # | Check | Expectation | Result |
|---|---|---|---|
| C1 | Set an alarm, `adb shell dumpsys alarm \| grep com.crescendoalarm.crescendoalarm` | entry present | 2026-10-20 ✓ registered (`AlarmReceiver`, 02:17) |
| C2 | Reboot the device **without** opening the app, then repeat C1 | entry present again | 2026-10-20 ✓ reboot, unlocked via adb, app not opened: the plugin's BootReceiver re-armed every alarm |
| C3 | Wait for the alarm to ring after the reboot | rings | 2026-10-20 ✓ rang at 02:17:02 - **together with the direct-boot siren** (two `USAGE_ALARM` players) → T-233, fixed in d758412; re-run at 02:27 with the fix: only the real alarm rang |
| C4 | `adb shell am force-stop com.crescendoalarm.crescendoalarm`, then C1 | **Unresolved** (`docs/REQUIREMENTS.md` R3, `docs/TODO.md` T-93): expected "entry gone" (platform behaviour), but a 2026-09-19 `dumpsys` measurement still found it registered. Record exactly what you see. | 2026-10-20 Android 13: force-stop removed **every** app alarm (no entry, uid absent from "Pending alarms per uid") - platform behaviour; T-93's "still registered (8)" not reproduced (cf. audit G7-02) |
| C5 | Open the app after C4 | alarms are re-armed (FR-17 recovery) | 2026-10-20 ✓ opening the app re-armed all 7 manual alarms at their next occurrence (T-217 reconcile) |
| C6 | Enable battery saver, set an alarm for +10 min, screen off | rings anyway | 2026-10-23 ✓ battery saver on, battery unplugged (simulated), screen off, deep Doze forced (`deviceidle deep=IDLE`): the sleep-time DND start alarm fired at 11:11:00.077 and the manual alarm rang at 11:16:08, screen woke, alarm audio started |

Known from the code regarding C1/C2: the `alarm` plugin registers a `BootReceiver`
(`com.gdelataillade.alarm.alarm.BootReceiver`) and re-arms the stored alarms after boot via
`setExactAndAllowWhileIdle(RTC_WAKEUP, …)`; in doing so it discards missed alarms as "stale". The
app's own `DirectBootReceiver` (T-158) only adds the locked-after-reboot fallback and re-arms the
sleep-time Do Not Disturb alarms. C2/C3 have been observed once on a real device (Findings below),
not yet through this table.

## D — Guaranteed wake-up (QR)

| # | Check | Expectation | Result |
|---|---|---|---|
| D1 | Generate a code on the **Scan Code** tab and print it (**Print**) | | |
| D2 | Let an alarm ring | QR scanner appears instead of "Stop" | |
| D3 | Scan the **wrong** code | alarm keeps running, scanner stays open | |
| D4 | Scan the correct code with the **real camera** | alarm stops (closes T-16) | |
| D5 | Check whether the scanned value appears anywhere on screen | **must not** — the scanner simply closes on the right code | |
| D6 | Arm a second manual alarm for later; let the first ring with a code set, cover the lens until "Camera not working - Stop alarm" appears; switch to another app and back | the button **stays** after the camera restarts (T-215) | 2026-10-20 partly (lens not covered): emergency stop offered ~31 s after the ring |
| D7 | Swipe the button aside, keep the lens covered ~30 s | it hides on the swipe and comes back after ~30 s without a valid code (T-215) | 2026-10-20 ✓ swiped aside, offered again ~32 s later (T-215) |
| D8 | Tap "Camera not working - Stop alarm" | only the ringing alarm stops; the later manual alarm is still armed (`adb shell dumpsys alarm`), a repeating one is re-armed for its next day (T-216) | 2026-10-20 ✓ stopped only the ringing alarm; the other alarm and the reminder stayed armed, the repeating one re-armed (T-216) |

## E — Diagnostics log (T-89)

| # | Check | Expectation | Result |
|---|---|---|---|
| E1 | Open Settings → Diagnostics, switch on **Record diagnostics** (off by default, T-173) | events visible after the next scheduling activity | 2026-10-20 ✓ off by default; switched on |
| E2 | Review the content (with "Also record wake and appointment times" off) | no time of day, no date, no appointment title, no calendar name, no QR code | 2026-10-20 ✓ counters and categories only, `preferredWakeUpMinuteOfDay=-1`, header "No timestamps, no calendar data, no wake times by design" |
| E3 | Check after B3 | `weekPlanComputed` with `plannedDays=7`, `windowDayCount == distinctDayKeys` | |
| E4 | Check after A3 | `alarmSync` **without** a large `toRemove` at `toAdd=0` (that would be T-64) | |
| E5 | Check after the morning alarm | `dayAdvance` with `daysProcessed >= 1` (0 would be T-75) | |
| E6 | Check at bedtime | *Superseded by T-199, see below* | |
| E7 | Press "Copy" and paste the text somewhere | complete, exclusively enum names and numbers | 2026-10-20 ✓ copied text pasted and checked by the maintainer on their own device (not readable via adb on Android 13) |
| E8 | Switch off, restart the app, check | no new events | 2026-10-20 ✓ switched off, app restarted: no new entries |

E6 was meant to confirm FR-16's checkpoint 2 on the device via a `timezoneCheck (bg)` entry at
bedtime. `docs/TODO.md` T-199 (from the plugin's own source) found that `onNotificationCreatedMethod`
fires when a notification is *scheduled*, in the main isolate, and not again when it comes due - so
`timezoneCheck` appears right after each checkpoint, not at bedtime and not marked `(bg)`. E6 as
written cannot pass until T-199 is resolved; do not record a missing bedtime entry as a new defect.

## F — Time zones and daylight saving

| # | Check | Expectation | Result |
|---|---|---|---|
| F1 | Change the device time zone (e.g. Berlin → Tokyo), open the app | days using the preferred wake-up time keep their **digits**, appointment days keep their **instant** (FR-16) | |
| F2 | Check the diagnostics log after F1 | `timezoneCheck` with `offsetChangeShape=3` (otherChange) | |
| F3 | Set the device clock to the day before a daylight-saving transition (automatic time off, device zone Europe/Berlin), `preferredWakeUpTime` 07:00, no appointment; let the day's alarm ring (or trigger a Sync) | the transition day's scheduled alarm reads **07:00** in the alarm list, not 08:00 (spring) / 06:00 (autumn), and so does every day after it (T-206; before it, a known one-hour error) | |
| F4 | A3 (`docs/TODO.md` T-206): after F3, before and after the transition, `adb shell dumpsys alarm` for the app's package | the armed alarm's trigger time is 07:00 **local** on the transition day - proving that Dart's local conversion on the phone applies the transition to a *future* instant (`deviceOffsetAt`), which no test can show. Run once around the March and once around the October transition | |

## G — Sleep-time Do Not Disturb (T-198)

The two Android models behave differently and must be recorded separately - a result on one never
covers the other (`CLAUDE.md`, "Sleep-time Do Not Disturb"). Fill the header's Android version in.

| # | Check | Expectation | Result |
|---|---|---|---|
| G1 | Sleep Habits → switch on **Do Not Disturb** for the first time | Android's Do Not Disturb access screen opens; without granting it the switch stays off | 2026-10-23 ✓ without access Android's DND-access screen opened and the switch stayed off; access then granted via `cmd notification allow_dnd` |
| G2 | Next alarm in more than one Sleep Goal: wait for (or move the alarm towards) bedtime = alarm − Sleep Goal, app closed | DND switches on at bedtime, "alarms only" | 2026-10-23 ✓ Sleep Goal 00:05, alarm 09:50: at 09:45 `zen_mode=3` (alarms only) |
| G3 | Let that alarm ring | DND switches off at the first ring, not at Stop; a snooze does not switch it on again | 2026-10-23 ✓ DND off at the first ring (09:50:04, zen=0 while ringing, before Stop); a snooze did not switch it on again |
| G4 | Next alarm **less** than one Sleep Goal away (e.g. a backup alarm +10 min) | after the first ring DND comes back on about two minutes later until that alarm rings (T-203) | 2026-10-23 ✓ backup alarm 4 min away armed 10:01:37: DND back on 10:03:36 (~2 min), off at its ring |
| G5 | Same as G4, but the closer manual alarm has **Exclude from Sleep Time** on | that alarm neither starts nor ends sleep time; DND follows the next non-excluded alarm | 2026-10-23 ✓ an alarm with Exclude from Sleep Time never started DND; with a normal alarm pending (DND on from 10:26) the excluded alarm at 10:28 rang with DND unchanged; DND ended at the normal alarm's ring 10:31:03 |
| G6 | Switch the Do Not Disturb setting off during sleep time | DND off right away | 2026-10-23 ✓ DND on 10:08:00; setting switched off 10:08:09 -> zen=0 within 4 s |
| G7 | Reboot during sleep time without opening the app | DND window still ends at the alarm's first ring (re-armed by `DirectBootReceiver`) | 2026-10-23 ✓ reboot at 10:49 during sleep time, unlocked without opening the app: zen stayed 3, log `SleepTimeDnd trigger=BOOT`, DND ended at the ring 10:53:02 |
| G8 | **Android 15 and newer:** check Settings → Modes and the quick-settings DND tile during sleep time | the app's own mode is on; the global DND tile is not; your own DND and other modes untouched | |
| G9 | **Android 14 and older:** switch DND on by hand before bedtime | the app leaves it alone and does not switch it off in the morning | 2026-10-23 ✓ DND set by hand (priority) before bedtime: untouched at window start, at the ring and after Stop (zen=1) |

## H — v1.5.0: restart/force-stop fallback, tones, permissions, tabs, ring notification (T-217, T-212, T-228, T-229)

Android 15+ re-sends the boot broadcasts on the first launch after a force-stop (`docs/TODO.md`
T-217), so H1–H5 cover a launch after a force-stop as well as a real reboot. Fill in the header's
Android version - Android 14 and older are not covered by a result on 15+.

| # | Check | Expectation | Result |
|---|---|---|---|
| H1 | Manual alarm +5 min with a secure lock screen; reboot and leave the phone **locked** past the due time | the fallback siren rings (vibration + siren) at the due time; **no** extra notification sound from the siren's notification (new silent channel); unlocking stops it | 2026-10-20 ✓ siren armed at the locked boot, rang at the due minute (first tone URI failed before unlock, the cached default played - by design); after unlocking no second ring |
| H2 | Same as H1, but unlock right after the reboot, **before** the due time | **no** siren at the due time; the real alarm rings with its own tone (and QR gate if set) | 2026-10-23 ✓ same as the T-233 re-run: unlocked after the reboot before the due time -> only the real alarm rang |
| H3 | Manual alarm, `am force-stop`, wait until **less than 60 min** past the due time, then open the app while unlocked | no siren; the real alarm rings late, within the 60-minute window | 2026-10-20 Android 13: nothing rang at the due time or on opening 31 min late; re-armed for the next occurrence. The expected result needs Android 15+ (boot broadcast re-sent after a force-stop) |
| H4 | Manual alarm, `am force-stop`, wait **more than 60 min** past the due time, then open the app | nothing rings; a silent **"Alarm missed"** notification names the alarm's time; tapping it opens the app | 2026-10-20 Android 13: nothing rang; **no "Alarm missed" notice** on opening 62 min late (Android 15+ path only) → T-234 |
| H5 | After H4: Settings → Apps → Crescendo Alarm → Notifications | only the silent siren channel ("Fallback alarm …") and "Missed alarms …" are listed; the old sound-playing fallback channel is gone | 2026-10-20 ✓ `direct_boot_fallback_silent`, `alarm_ringing_quiet`, `alarm_plugin_channel`; the old sound-playing fallback channel is gone; "Missed alarms" not created yet (created on first post) |
| H6 | Repeating manual alarm whose time passes during a force-stop; relaunch the app; `dumpsys alarm` (C1's command) | the manual alarm is armed again at its **next** occurrence and still shows switched on | 2026-10-20 ✓ armed at the next occurrence, still switched on, no immediate ring |
| H7 | Settings → Alarm Tones: preview every bundled tone by ear, and let one ring for a minute | each tone plays, sounds like its name, no clipping, no audible click at the loop point (the clock ring especially) | |
| H8 | Alarms screen | **Manual** is the left tab, **Scheduled** the right one; the screen opens on Scheduled; the bottom-right button is **+** on Manual and **Sync** on Scheduled | 2026-10-20 ✓ Manual left, Scheduled right, opens on Scheduled |
| H9 | After installing over v1.4.0 (14 permissions instead of 31): let an alarm ring, wait for the bedtime reminder, trigger an FR-6 notice | every notification still appears | 2026-10-23 partly ✓: real release APKs v1.4.0 -> v1.5.0 installed in place (no force-stop): the platform alarm entries survived, the alarm rang at 11:36:00 without the app being opened, alarm list / volume 0 % / vibration off kept, 14 permissions. Bedtime reminder and FR-6 notice not checked |
| H10 | Unlocked phone, **app open**: let a manual alarm +1 min ring (no QR code, then again with one) (T-229) | the ring screen shows **without** a notification banner over its top; the tone (and vibration, if on) keeps playing; the notification is in the shade (silent section) | 2026-10-20 ✓ no banner; notification on `alarm_ringing_quiet` (importance LOW, foreground-service flag) |
| H11 | Unlocked phone, **another app** in front when the alarm rings (T-229) | a heads-up appears as before (the way to the ring screen); tapping it opens the ring screen, and the banner is then gone; tone continues | 2026-10-20 ✓ heads-up with Settings in front |
| H12 | **Locked** phone, screen off, alarm rings (T-229) | the ring screen launches full-screen over the lock screen exactly as before (R4); tone continues | 2026-10-20 ✓ screen woke, ring screen full-screen over the lock screen |
| H13 | While ringing with the ring screen open: pull down the shade, swipe the alarm notification away (T-229, T-147) | the alarm keeps ringing; the notification comes back (the banner may reappear until the app is next brought to the front - known limit) | 2026-10-20 ✓ keeps ringing, notification comes back |
| H14 | Settings → Apps → Crescendo Alarm → Notifications after H10 (T-229) | a new channel "Ringing alarm (alarm screen open)" exists, set to silent; "Alarm Notification" unchanged | |
| H15 | While a manual alarm rings (no QR code, then again with one): open Recents and swipe the app away (T-230, T-231) | the alarm keeps ringing; tapping its notification within the same minute opens the ring screen (QR scanner with a code); Stop ends it | 2026-10-20 ✓ with T-230/T-231 (with and without a code): keeps ringing, no crash |
| H16 | A manual alarm rings while another app is in front (heads-up only); tap its notification 70-90 s later (no QR code, then again with one) (T-232) | the ring screen (QR scanner with a code) appears and the alarm keeps ringing; it does not stop on its own when the app opens | 2026-10-20 ✓ with T-232: ring screen / QR scanner appeared after 81-89 s, kept ringing |

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
- **2026-09-18, C2/C3 (real device):** device rebooted with a scheduled alarm armed, app **not**
  opened afterward - the alarm rang anyway. First real observation of this leg (previously only
  "already derivable from the code" in `docs/REQUIREMENTS.md` R3); not yet run through the
  scripted `dumpsys alarm` procedure (`.github/scripts/check_alarm_survival.sh`) or logged with
  device model/APK/commit via the table template above - do that on the next trial to make this a
  full, repeatable C1/C2 entry.
- **2026-09-18, C4 (real device): confirmed, and confirmed as a platform boundary, not a bug.**
  *(Contradicted the next day by a scripted `dumpsys alarm` measurement that still found the alarms
  registered after force-stop - unresolved, see `docs/REQUIREMENTS.md` R3 and `docs/TODO.md` T-93.)*
  `am force-stop` during a scheduled alarm loses it - no ring. This is Android's own documented
  behaviour (every AlarmManager entry a force-stopped package owns is dropped by the OS itself) and
  is not something app code can prevent - see `docs/REQUIREMENTS.md` R3's own note on this
  boundary.
- **2026-09-18, C5 (real device): confirmed - the actually fixable half of C4/C5.** After the
  force-stop above, opening the app again re-armed the alarm and it rang, via FR-17's recovery
  path. With this, every scenario R3 actually promises (UI swipe, reboot, force-stop-then-reopen)
  now has real-device confirmation - only the scripted `dumpsys alarm` procedure
  (`.github/scripts/check_alarm_survival.sh`) and this table's own device/APK/commit logging
  remain to turn these one-off observations into a repeatable, dated record.


## Second run (2026-10-23), additions

- **H3/H4 re-run with the T-234 build (`3f4794c`):** an alarm due 13:54, app force-stopped before, opened
  13:56: it rang 8 s after opening. An alarm due 01:34, opened 63 min late: nothing rang, notification
  id 535 "Alarm missed" - "Your alarm for Fri 01:34 could not ring ...", re-armed for the next
  Friday. An alarm ~60 h overdue: re-armed silently, no notice (beyond the 48 h window, by design).
- **G3-03 on the RELEASED v1.5.0:** the ringing notification tapped ~100 s after the ring started
  (old one-minute stale rule): no ring screen and the ring ended on its own - the bug T-232 fixes on
  `dev`.
- **T-205 / audit M2-01, manual alarm and time zone:** an alarm armed for 12:04 Berlin; device zone
  switched to Asia/Tokyo (local 18:41): the platform entry kept its absolute instant (19:04 Tokyo),
  the list kept showing "12:04", opening the app and Sync changed nothing.
- **A silent alarm has no timeout:** an alarm at volume 0 / vibration off rang for ~6 h at night until it
  was stopped (the loop never ends by design) - nothing woke the sleeper next door.
- Tabs: v1.4.0 had Scheduled left / Manual right, v1.5.0 has Manual left (T-228).
