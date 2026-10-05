# User Guide

Everything the app's five tabs let you do, screen by screen. For what's still missing or only
partially working, see `docs/use-cases.md`'s inline annotations and `docs/TODO.md`.

## First launch

The first thing you see is the privacy policy. Nothing is requested - no calendar, no camera,
no notifications - until you tap **Continue**. From then on, each permission is only requested at
the point you actually need it:

- **Camera** - the first time you open the QR scanner (either to set your first deactivation code,
  or to deactivate an alarm that requires one).
- **Calendar** - the first time you open the **Schedule** tab, or the first time you tap **Sync
  Alarms** on the **Alarms** tab.
- **Exact-alarm scheduling** and **notifications** - requested upfront, since the app cannot do its
  one job (ring an alarm) without them.
- **Do Not Disturb access** - only when you first switch on Sleep Habits > **Do Not Disturb**.

## Alarms

Two tabs: **Scheduled** (calendar-derived) and **Manual** (alarms you set yourself).

### Scheduled

Alarms the app itself worked out from your calendar - see "How scheduling works" below. You can:

- **Toggle one off** with its switch - it stays in the list as an inactive alarm, with its switch
  off, so you can turn it back on; it just won't ring. While it is off it still follows your plan
  (if a calendar change moves that day's wake-up time, the inactive entry moves with it), and
  turning it back on arms it for the day's current planned time. A day you switched off is also
  left out of the bedtime reminder and of Do Not Disturb's sleep time.
- **Swipe right** on one to delete it. The next re-plan (see below) creates it again from your
  calendar and settings - to skip a day for good, use its switch instead.
- **Swipe left** to delete every scheduled alarm at once (asks for confirmation first).
- Tap the **sync** button (bottom right) to re-check your calendar and re-plan immediately, instead
  of waiting for the next automatic checkpoint (a scheduled alarm ringing - a manual alarm's ring
  does not re-plan - opening the app - at most once a day - or changing a relevant setting). This is also one of the two moments calendar access is requested, if you haven't
  granted it yet.

You cannot edit a scheduled alarm directly - it's recomputed from your calendar and Sleep Habits
settings on every checkpoint, so an edit would just be overwritten. Change the underlying settings
instead (Sleep Habits, or the calendar event itself).

### Manual

Alarms you create yourself, independent of any calendar.

- Tap **+** (bottom right) to add one.
- Tap an existing alarm to edit it.
- **Swipe right** to delete one, **swipe left** to delete all manual alarms (with confirmation).
- The **switch** enables/disables it - like a scheduled alarm's switch, switching off cancels the
  underlying platform alarm right away and the alarm stays in the list; switching on arms it for its
  next occurrence.
- A row of small day letters under the time shows which days it repeats on.

**The add/edit dialog** offers:

- **Time** - tap the time to open a picker.
- **Title** - shown on the alarm list and as the ringing notification's text.
- **Gentle Wake Up** - ramps the volume up gradually instead of starting at full volume. The ramp
  length is copied from Sleep Habits' **Ramp duration** when the alarm is created; changing that
  setting later does not change existing manual alarms.
- **Tone** - pick from the bundled tones or any custom tone you've imported (Settings > Alarm
  Tones).
- **Volume**.
- **Snooze** - whether this specific alarm allows postponing, independent of the global Snooze
  setting under Sleep Habits.
- **Deactivation Code Required** - whether this specific alarm requires a deactivation-code scan to
  stop it (the app-wide "Guaranteed Wake-Up" feature - see "Scan Code" below). Greyed out and
  switched off whenever no code is configured at all there, since it would have no effect either
  way; becomes available once you generate or import one.
- **Exclude from Sleep Time** - off by default. Switch it on for an alarm that should not count as
  "the next alarm" for the Sleep Habits **Do Not Disturb** trigger (see below) - for example a
  medication reminder in the middle of the night: it neither ends the Do Not Disturb sleep time early
  nor defines when it starts. It has no effect on anything else (the bedtime reminder still counts
  every enabled manual alarm), and none at all while the Do Not Disturb trigger is off.
- **Repeat on** - a day-of-week picker. Defaults to just today, so a one-off alarm needs no
  interaction here at all; check more days for a recurring alarm. Repeating alarms re-arm themselves
  automatically each time you dismiss them.

## Schedule

A calendar view of your upcoming week, and the wake-up times the app has planned around it.

- **Day / Week / Work week / Month** - switch views from the calendar icon in the top bar.
- **Today** button - jumps back to today's date.
- **Calendars** button (the note icon) - choose which of your device's calendars feed both this
  view and the scheduling itself. Deselecting one hides its events and stops them from influencing
  your alarm times.
- **Tap an event** to open a small sheet with an **Ignore for scheduling** switch for it. An ignored
  event is grayed out with an X - it still shows on your calendar, but the app treats the day as if that appointment
  weren't there.

### How scheduling works

The app looks at your earliest non-all-day appointment each day and works backward from it (minus
your "Duration to get ready" and "Duration to wake up" - see Sleep Habits) to decide when to wake
you. Days with no appointment drift gradually toward your preferred wake-up time instead of jumping
straight there, and if nothing has an appointment for a long stretch, the app eventually stops
guessing and asks you to set a preferred time explicitly, rather than silently drifting forever.

## Scan Code (the "guaranteed wake-up" gate)

A physical QR code (or any barcode you already own) that you have to scan to turn off an alarm that
requires it - the idea being that if it's stuck somewhere across the room, you have to get up.

- **No code set yet:** tap **Generate** to make a new one (shown as a QR image you can screenshot or
  photograph and stick somewhere), or tap **Import** to scan an existing code you already own - a
  barcode on a household object works just as well as a printed QR code, it does not have to come
  from this app.
- **Once a code exists:** you're prompted once to write a short note ("What do you need to scan?")
  so you remember what it is later - useful because a re-rendered QR image of an already-imported
  code looks nothing like the original.
- **Remove** deletes the current code (an alarm can then be stopped normally, without scanning
  anything).
- **Share** exports the code as a PNG and opens Android's native share sheet - send it to any app
  you have installed. Works on the actual code even while the screen is showing your own
  description instead of the QR image.
- **Print** sends the same PNG straight to Android's own print framework - pick a printer (or save
  as PDF) without needing any particular app installed. Handy for sticking a physical copy
  somewhere across the room, which is the whole point of the "guaranteed wake-up" gate.

**If your camera can't decode anything at all** (a hardware kill-switch, a covered lens, or a
broken sensor), a "Camera not working - Stop alarm" button appears automatically after about 30
seconds of trying, so you're never physically trapped by a broken gate. If the camera never starts
at all (no picture ever reaches the scanner), the same button appears after about 10 seconds.

**If the ringing screen cannot be shown at all** (for example the app is still starting up when the
alarm fires), the app retries five times, three seconds apart, and then stops the alarm rather than
leave it ringing with nothing on screen to stop it. This fail-safe means a ring can, rarely, end
without a scan.

## Sleep Habits

Every option here has a small **?** button in its top-right corner with a short explanation - tap
it if a setting isn't obvious. The three group headings below (**Wake-up time**, **When the alarm
rings**, **Bedtime reminder**) can each be collapsed independently - tap the heading itself or the
small chevron on its right to hide or show that group's options.

**Wake-up time** - what determines whether/when the alarm rings at all:

- **Preferred wake-up time** - the target FR-4's drift aims for on days with no appointment.
- **Schedule an alarm on days without an appointment** - on, gap days still get an alarm (drifting
  toward your preferred time); off, they get none.
- **Max. daily shift** - how far the wake-up time may move per day while drifting.
- **Duration to wake up** - lead time reserved before an appointment for waking up. Also your
  snooze budget, if Snooze is on (see below).
- **Duration to get ready** - lead time reserved before an appointment for getting ready. Tap
  "Customize per weekday" to override it for specific days.

**When the alarm rings** - how it behaves once it actually rings:

- **Gentle WakeUp** - ramps the volume up gradually; **Ramp duration** controls how long that takes.
- **Snooze** - lets you postpone a ringing alarm by a fixed interval (**Snooze time**), up to the
  "Duration to wake up" budget above. Once that budget is used up, the snooze button simply stops
  appearing - there's no separate "maximum snooze count" setting, the budget does that job. The
  ring you get once the budget runs out - the one you can no longer postpone - always starts
  straight at full planned volume, even with Gentle WakeUp on: it's your last call, so it isn't
  eased into.

**Bedtime reminder** - a separate concern: sets your bedtime for the reminder and Do Not Disturb
below, never the alarm itself:

- **Sleep Goal** - how much sleep you're aiming for; sets the bedtime used by the reminder and by
  Do Not Disturb below, not the alarm itself.
- **Enable Reminder** - a notification reminding you to go to bed, timed this far before your Sleep
  Goal's bedtime.
- **Do Not Disturb** - off by default. When on, the app puts the phone into Do Not Disturb for your
  sleep time and takes it out again when you wake up:
  - **Sleep time starts** at your next alarm minus your Sleep Goal (not minus the reminder's lead
    time - the reminder comes earlier, Do Not Disturb when you should actually be asleep). It starts
    whether or not **Enable Reminder** is on.
  - **Sleep time ends** at the very first ring of that alarm - the moment it starts ringing, not
    when you stop it. A snooze does not start sleep time again.
  - "Your next alarm" is the next alarm that will actually ring: a planned day you switched off in
    the alarm list and a manual alarm with **Exclude from Sleep Time** on are skipped.
  - **Alarms still ring** - Do Not Disturb is set to "alarms only", so this app's alarms (and any
    other alarm clock's) sound as usual; notifications and calls are held back.
  - Switching it on the first time opens Android's **Do Not Disturb access** screen - allow
    Crescendo Alarm there and come back. Without that access the switch stays off.
  - If you switch it on (or change an alarm) while you are already inside your sleep time, Do Not
    Disturb starts about two minutes later. If the next alarm is further away than your Sleep Goal,
    nothing happens until bedtime.
  - This also applies right after an alarm has rung: if your next alarm is closer than your Sleep
    Goal (a backup alarm a few minutes later, or an alarm later that day), Do Not Disturb comes back
    on about two minutes later, until that alarm rings. If an alarm should not do that - a backup
    alarm, a medication reminder - switch on **Exclude from Sleep Time** for it.
  - Switching it off takes the phone out of Do Not Disturb right away, if the app had put it in.
  - **On Android 15 and newer (including Android 16)** the app gets its own Do Not Disturb mode, listed under Settings >
    Modes (shown as "Do Not Disturb (Crescendo Alarm)" or just "Crescendo Alarm", depending on the
    phone). The app only ever switches that mode on and off - never your own Do Not Disturb or your
    other modes. You can change what the mode lets through there; the app then keeps your choice.
  - So the quick-settings Do Not Disturb tile does **not** show the app's sleep time on Android 15+:
    look for the app's own mode instead. On Android 14 and older, sleep time switches the one,
    system-wide Do Not Disturb, and the tile does show it.
  - **On older Android versions** there is only one Do Not Disturb: if it is already on at bedtime
    (you switched it on yourself, or a schedule did), the app leaves it alone and does not switch it
    off in the morning either.
  - It is designed to work with the app closed and after a restart of the phone (this is still
    being confirmed on real phones). After **Force stop** (Android's app settings), Android removes
    everything the app had scheduled, alarms included, and the app cannot run again until you open
    it: if you force-stop it during your sleep time, Do Not Disturb stays on until you open the app
    (or switch Do Not Disturb off yourself).

## Settings

Four tabs.

### Alarm Tones

- Every bundled tone and every custom tone you've imported gets its own row: tap it to preview,
  flip its switch to select it as your default tone (used by scheduled alarms and newly-created
  manual alarms, and shown as an option in every alarm's own tone picker).
- **Add custom tone** (always at the bottom of the list) opens the system file picker
  (`.mp3`/`.wav`/`.m4a`/`.aac`/`.ogg`), then asks you to name it - pre-filled with the file's own
  name, so you usually don't need to type anything. You can import as many as you like; each one
  gets its own row. An imported tone cannot be removed again from inside the app yet.
- The default tone on a fresh install is **Playful Chime**.
- **Volume** and **Vibration** are the defaults: scheduled alarms always use them, and a new manual
  alarm starts with them. An existing manual alarm keeps the values it was created with (its own
  Volume can be changed in its dialog).

### Appearance

Dark mode (or follow the system setting) and an accent colour.

### About Page

The privacy policy, this project's own GPLv3 licence text, third-party licence notices (everything
the app depends on, plus the credits and licences of the bundled alarm tones and the app icon), and
native code notices (the third-party C/C++ compiled directly into the QR scanner). The app version
and build number are not shown here.

### Diagnostics

A local, PII-free event log for troubleshooting - readable here and exportable via the
clipboard (**Copy**) if you need to report a problem. Recording is **off by default**: switch on
**Record diagnostics** to start it; **Clear** deletes everything recorded so far. It never records anything that could identify you (no
calendar titles, no account names, no exception text) - see the export's own header for exactly
what mode produced it. Most of the log only ever records bucketed differences, never a clock time.

A separate, off-by-default switch lets you additionally include **exact clock times** (minute-of-
day, no date), for three things:

- Each window day's planned wake time and its earliest appointment, so a bug report can show *why*
  a day was planned the way it was.
- The start and end time of **every** calendar event in the planning window - not just the one
  picked as earliest - so a wrong pick can be checked against what the calendar actually held that
  day. This is still never the event's title, description, attendees, location, or which calendar
  it came from - only its timing. That boundary does not move, opt-in or not.
- Your **preferred wake-up time**, as part of the planning inputs (the other inputs - maximum daily
  shift and the two lead times - are durations, not clock times, and are recorded whenever
  diagnostics are on).

All three are real clock times, and together with the rest of the log they amount to a sleep pattern and
a daily routine - that is exactly why the switch is off by default and separate from ordinary
diagnostics. Turn it on only while actively investigating a scheduling problem, and remember it is
then included in anything you copy and share from this screen.

## Time zones and daylight saving

- **Daylight saving changes** where you are - in any region - are handled: an alarm keeps its clock
  time on the day of the change and afterwards. An alarm planned for 07:00 rings at 07:00 on the new
  clock; the change does not count as a shift of your wake-up time, so it uses none of the maximum
  daily change and raises no warning.
  - A time in the hour that repeats when the clocks go back (e.g. 02:30 when 02:00-03:00 happens
    twice) rings **once, at the second 02:30**.
  - A time that is skipped when the clocks go forward (02:30 when 02:00 jumps to 03:00) rings **as
    soon as the time exists** - at 03:00 - and is never skipped; the following days go back to
    02:30.
  - Where the clocks jump from 23:00 straight to midnight (Greenland, once a year in spring), an
    alarm set between 23:00 and 23:59 that night rings at **22:59**, the last minute before the
    jump, so that it still rings on its own day - up to an hour early rather than on the next day.
    Scheduled and manual alarms behave the same.
  - An appointment counts for the day your clock shows at its start, also in a week with a change.
  - The Do Not Disturb sleep time and the bedtime reminder follow the same moments. The Sleep Goal
    counts real hours: 8 hours before 07:00 starts at 22:00 on the night the clocks go forward and
    at 00:00 on the night they go back.
  - This is tested for every time zone with a change in 2026/2027, but has not yet been watched on
    a real phone across a real change - glance at your alarm list around the next one.
- **Travelling across time zones is not yet reliably supported.** In particular, the first manual
  alarm after a flight can still ring at the time it was set for in the old zone, and travel
  combined with daylight saving changes in several regions is not supported yet. Until that is
  solved, check your alarms after arriving in another time zone. Details:
  `docs/timezone-requirements.md`.

## When an alarm rings

A full-screen ringing display shows today's date, the current time, and:

- **Snooze** (if enabled and budget remains) - postpones the alarm by your configured snooze
  interval.
- **Stop** - a big button that ends the alarm.

If a deactivation code is set and the alarm requires it (every scheduled alarm; a manual alarm only
with **Deactivation Code Required** on), the QR scanner appears instead of this display - with
**Snooze** there too - and only scanning your code stops the alarm (see "Scan Code" above for the
broken-camera fail-safe). The alarm's title is shown in its ringing notification.
