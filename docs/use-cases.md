> Note (2026-09): items marked **not implemented** below were planned but
> didn't make it into the shipped app. Two items were once annotated as
> shipped but not working (the disable switch, the share/print stub); both
> have since been fixed, as their annotations say. Everything else reflects
> real, implemented, working features.

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

- Disable alarm (**fixed 2026-09-16**, `docs/TODO.md` T-03 / FR-21: the switch used to be a no-op;
  switching off now cancels the armed alarm, for scheduled and manual alarms alike, and it stays off
  across re-plans and restarts)

- Remove alarm

  

## Dynamic Schedule

- Select Calendar for interconnection

- GrantCalendarPermissions

- Preview of the Calendar to Sync with

- Algorithm to calculate alarm time based on sleep goal, duration to wake up and duration to get ready
  (**as shipped, the Sleep Goal does not feed the alarm time** - it only sets the bedtime for the
  reminder and Do Not Disturb; the alarm time comes from the earliest appointment minus the two
  durations, and the preferred wake-up time on days without one)

  

## Sleep Habits Configuration

- Sleep Goal
- Duration to wake up
- Duration to get ready (between getting up and setting off)
- Reminder Feature (Reminders for bedtime to encourage a regular sleep schedule)
- Gentle Wake Feature
- Do Not Disturb Feature (**implemented again**, docs/TODO.md T-198, 2026-09-27: a Sleep Habits
  switch, default off, that puts the phone into "alarms only" Do Not Disturb from the next alarm
  minus the Sleep Goal until that alarm's first ring. History: a first version shipped as T-184 on
  2026-09-25, misbehaved on a real phone after several fixes and was removed completely in T-197;
  T-198 is a new design, not that code restored. Device confirmation of T-198 is still pending -
  see that entry.)
  - Turn off notifications - yes (held back during sleep time)
  - Turn off calls - yes, as part of the same "alarms only" Do Not Disturb (there is no separate
    calls-only option)



## Deactivation Code

- Create Deactivation Code
- Manage Deactivation Codes (**only one code exists at a time** - "manage" is Generate/Remove, not
  a list of multiple codes)
- Disable Deactivation Code (**not implemented as distinct from removing it** - there is Generate
  and Remove, no way to keep a code stored but temporarily inactive)
- Remove Deactivation Codes
- Print Deactivation Code as QR Code (="QR Code") (**implemented**, `docs/TODO.md` T-182: the code is
  shown as a QR image, and **Share** (Android's share sheet) and **Print** (Android's print
  framework) export it as a PNG)
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
  - About this app (Versioning, Build number) - **not implemented**: the About page shows no app
    version or build number (maintainer decision 2026-10-05: not claimed in the user guide).
  - Privacy Policy
- Diagnostics (**not in the original plan** - added later: a local, PII-free event log for
  troubleshooting, exportable via the clipboard, with its own switch for including clock times.
  See `CLAUDE.md`, "Diagnostics log".)
- Licence (**not in the original plan** - the project's own GPLv3 text and Flutter's collected
  third-party notices, added for `docs/REQUIREMENTS.md` R9's in-app notice obligation; since
  `docs/TODO.md` T-213 these also include the Android libraries, `desugar_jdk_libs`, the Material
  Icons font, and the credits of the bundled alarm tones and app icon)
- Native Code Notices (**not in the original plan** - the notices for `flutter_zxing`'s
  compiled-in native code, which Flutter's own licence collector cannot see: zxing-cpp and librscpp
  (Apache-2.0), libzueci and zint (BSD-3-Clause), two embedded MIT pieces, zint's embedded fonts
  (Apache-2.0, and an unrestricted-use OCR-B), and the BSI terms for two GS1 DataBar functions)

