> Note (2026-09): items marked **not implemented** below were planned but
> didn't make it into the shipped app. A few other items are annotated as
> shipped but not working as described (a UI control exists but the
> underlying behaviour is a no-op, or a stub) - those are tracked as bugs in
> `docs/TODO.md`, not planning gaps. Everything else reflects real,
> implemented, working features.

# FEATURES

- Alarm (Core feature)

- Dynamic Schedule

- Deactivation Code (QR Code; NFC Tag was considered, **not implemented**)

- Sleep Habit Configuration

- Settings

  

---
# USE CASES

## Alarm (core feature)

- Create alarm

- Manage alarms

- Edit alarm

- Disable alarm (**shipped as a UI switch, but currently a no-op** - toggling it off does not
  actually cancel the underlying alarm; see `docs/TODO.md` T-03)

- Remove alarm

  

## Dynamic Schedule

- Select Calendar for interconnection

- GrantCalendarPermissions

- Preview of the Calendar to Sync with

- Algorithm to calculate alarm time based on sleep goal, duration to wake up and duration to get ready

  

## Sleep Habits Configuration

- Sleep Goal
- Duration to wake up
- Duration to get ready (between getting up and setting off)
- Reminder Feature (Reminders for bedtime to encourage a regular sleep schedule)
- Gentle Wake Feature
- Do Not Disturb Feature (**implemented, docs/TODO.md T-184, 2026-09-25** - maintainer
  request; see `CLAUDE.md`'s architecture notes for how)
  - Turn off notifications
  - Turn off calls
  - Both via Android's own Do Not Disturb "Alarms only" filter, which silences everything
    except this app's own alarm - not a separate, per-channel toggle for notifications vs.
    calls



## Deactivation Code

- Create Deactivation Code
- Manage Deactivation Codes (**only one code exists at a time** - "manage" is Generate/Remove, not
  a list of multiple codes)
- Disable Deactivation Code (**not implemented as distinct from removing it** - there is Generate
  and Remove, no way to keep a code stored but temporarily inactive)
- Remove Deactivation Codes
- Print Deactivation Code as QR Code (="QR Code") (**partially implemented**: the code is rendered
  and displayed as a QR image on-screen; the "share/print" action is an explicit stub that shows
  "This is a future feature!" and does nothing)
- Scan QR Code (**two roles, both implemented, and not limited to QR**: with a code already
  stored, a scan validates against it (the "guaranteed wake-up" gate); with none stored yet, a scan
  **adopts whatever code was just scanned as the new deactivation code, verbatim and with no
  format of its own** - any pre-existing QR code *or ordinary barcode* someone already has works,
  not only one Crescendo Alarm generated. See `docs/REQUIREMENTS.md` R13.)
- Optional: Write Deactivation Code to NFC Tag (="Deactivation Tag") - **not implemented**
- Optional: Read Deactivation Tag - **not implemented**



## Settings

- Appearance
- Tone
- About 
  - About this app (Versioning, Build number)
  - Privacy Policy
- Diagnostics (**not in the original plan** - added later: a local, PII-free event log for
  troubleshooting, exportable via the clipboard, with its own switch for including clock times.
  See `CLAUDE.md`, "Diagnostics log".)
- Licence (**not in the original plan** - the project's own GPLv3 text and Flutter's collected
  third-party notices, added for `docs/REQUIREMENTS.md` R9's in-app notice obligation)
- Native Code Notices (**not in the original plan** - the Apache-2.0/BSD-3 notices for
  `flutter_zxing`'s compiled-in native code, which Flutter's own licence collector cannot see)

