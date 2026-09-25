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

## Alarms

Two tabs: **Scheduled** (calendar-derived) and **Manual** (alarms you set yourself).

### Scheduled

Alarms the app itself worked out from your calendar - see "How scheduling works" below. You can:

- **Toggle one off** with its switch - it stays in the list (so you can turn it back on), it just
  won't ring.
- **Swipe right** on one to delete it outright.
- **Swipe left** to delete every scheduled alarm at once (asks for confirmation first).
- Tap the **sync** button (bottom right) to re-check your calendar and re-plan immediately, instead
  of waiting for the next automatic checkpoint (an alarm ringing, the bedtime reminder, or opening
  the app). This is also one of the two moments calendar access is requested, if you haven't
  granted it yet.

You cannot edit a scheduled alarm directly - it's recomputed from your calendar and Sleep Habits
settings on every checkpoint, so an edit would just be overwritten. Change the underlying settings
instead (Sleep Habits, or the calendar event itself).

### Manual

Alarms you create yourself, independent of any calendar.

- Tap **+** (bottom right) to add one.
- Tap an existing alarm to edit it.
- **Swipe right** to delete one, **swipe left** to delete all manual alarms (with confirmation).
- The **switch** enables/disables it - unlike a scheduled alarm's switch, this one genuinely cancels
  the underlying platform alarm.
- A row of small day letters under the time shows which days it repeats on.

**The add/edit dialog** offers:

- **Time** - tap the time to open a picker.
- **Title** - shown on the alarm list and as the ringing notification's text.
- **Gentle Wake Up** - ramps the volume up gradually instead of starting at full volume (see Sleep
  Habits for how long the ramp takes).
- **Tone** - pick from the bundled tones or any custom tone you've imported (Settings > Alarm
  Tones).
- **Volume**.
- **Snooze** - whether this specific alarm allows postponing, independent of the global Snooze
  setting under Sleep Habits.
- **Guaranteed Wake-Up** - whether this specific alarm requires a deactivation-code scan to stop it
  (see "Scan Code" below). Only takes effect once a code is actually configured there; with none
  set, no alarm requires a scan regardless of this toggle.
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
- **Tap an event** to ignore or un-ignore it for scheduling purposes. An ignored event is grayed out
  with an X - it still shows on your calendar, but the app treats the day as if that appointment
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
- **Share** is not implemented yet - it currently just says so.

**If your camera can't decode anything at all** (a hardware kill-switch, a covered lens, or a
broken sensor), a "Camera not working - Stop alarm" button appears automatically after about 30
seconds of trying, so you're never physically trapped by a broken gate.

## Sleep Habits

Every option here has a small **?** button in its top-right corner with a short explanation - tap
it if a setting isn't obvious.

- **Preferred wake-up time** - the target FR-4's drift aims for on days with no appointment.
- **Schedule an alarm on days without an appointment** - on, gap days still get an alarm (drifting
  toward your preferred time); off, they get none.
- **Max. daily shift** - how far the wake-up time may move per day while drifting.
- **Duration to wake up** - lead time reserved before an appointment for waking up. Also your
  snooze budget, if Snooze is on (see below).
- **Duration to get ready** - lead time reserved before an appointment for getting ready. Tap
  "Customize per weekday" to override it for specific days.
- **Sleep Goal** - how much sleep you're aiming for; shifts the bedtime reminder below, not the
  alarm itself.
- **Enable Reminder** - a notification reminding you to go to bed, timed this far before your Sleep
  Goal's bedtime.
- **Gentle WakeUp** - ramps the volume up gradually; **Ramp duration** controls how long that takes.
- **Snooze** - lets you postpone a ringing alarm by a fixed interval (**Snooze time**), up to the
  "Duration to wake up" budget above. Once that budget is used up, the snooze button simply stops
  appearing - there's no separate "maximum snooze count" setting, the budget does that job.

## Settings

Four tabs.

### Alarm Tones

- Every bundled tone and every custom tone you've imported gets its own row: tap it to preview,
  flip its switch to select it as your default tone (used by newly-created alarms and shown as an
  option in every alarm's own tone picker).
- **Add custom tone** (always at the bottom of the list) opens the system file picker
  (`.mp3`/`.wav`/`.m4a`/`.aac`/`.ogg`), then asks you to name it - pre-filled with the file's own
  name, so you usually don't need to type anything. You can import as many as you like; each one
  gets its own row.
- **Volume** and **Vibration** apply to every alarm that doesn't override them individually.

### Appearance

Dark mode (or follow the system setting) and an accent colour.

### About Page

App version/build number, the privacy policy, this project's own GPLv3 licence text, third-party
licence notices (everything the app depends on), and native code notices (the third-party C/C++
compiled directly into the QR scanner).

### Diagnostics

A local, privacy-free event log for troubleshooting - readable here and exportable via the
clipboard if you need to report a problem. It never records anything that could identify you (no
calendar titles, no account names, no exception text) - see the export's own header for exactly
what mode produced it. Most of the log only ever records bucketed differences, never a clock time.

A separate, off-by-default switch lets you additionally include **exact clock times** (minute-of-
day, no date), for two things:

- Each window day's planned wake time and its earliest appointment, so a bug report can show *why*
  a day was planned the way it was.
- The start and end time of **every** calendar event in the planning window - not just the one
  picked as earliest - so a wrong pick can be checked against what the calendar actually held that
  day. This is still never the event's title, description, attendees, location, or which calendar
  it came from - only its timing. That boundary does not move, opt-in or not.

Both are real clock times, and together with the rest of the log they amount to a sleep pattern and
a daily routine - that is exactly why the switch is off by default and separate from ordinary
diagnostics. Turn it on only while actively investigating a scheduling problem, and remember it is
then included in anything you copy and share from this screen.

## When an alarm rings

A full-screen ringing display shows the alarm's title, the current time, and:

- **Snooze** (if enabled and budget remains) - postpones the alarm by your configured snooze
  interval.
- **Stop** - a big button that ends the alarm... unless a deactivation code is set, in which case it
  opens the QR scanner instead, and you have to scan your code to actually stop it.
