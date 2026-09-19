# dumpsys fixtures for `check_alarm_survival.sh --self-test`

- **`dumpsys_alarm_foreign.txt` is a real recording.** Taken verbatim from
  the evidence file of run 34566962847 (2026-09-11). Not a single line in
  it belongs to this app — it is the negative case: the counting pattern in
  use at the time produced two hits here (Google's
  `DailyLoggingAlarmReceiver` contains the substring `AlarmReceiver`),
  whereupon the script reported an unfounded "FAIL". Every future pattern
  must return **0** against this file.

- **`dumpsys_alarm_own.txt` is a real recording (docs/TODO.md T-99, 2026-09-19).**
  Taken verbatim (aside from being the `grep`-filtered excerpt
  `verify-alarm-survival.sh` actually captures, not a full unfiltered dump)
  from a real Fairphone 6 run of `scripts/verify-alarm-survival.sh`, before
  any intervention: 9 alarms of this app's own (uid `u0a310`), a mix of the
  `alarm` plugin's `AlarmReceiver` entries and `awesome_notifications`'
  `DartScheduledNotificationReceiver` entries, with the reliable
  `Pending alarms per uid: [..., u0a310:9]` summary line present. This
  confirmed the summary-line-based counting (path (a) in
  `alarm_detection.sh`) actually works against genuine device output, not
  only synthetic fixtures - previously this file was constructed by hand
  because no real recording of the app's own alarms had ever been captured.
  It was **not** captured on the CI emulator image specifically (a real
  phone, not GitHub's hosted AVD) - but the summary-line format comes from
  AOSP's own `AlarmManagerService.dump()`, identical platform code
  regardless of real vs. virtual hardware, so this is treated as sufficient
  evidence for the emulator image too rather than requiring a separate,
  costly CI run only to re-observe the same platform-level format.

## uiautomator_*.xml

Recorded accessibility trees for `scripts/verify-alarm-survival.sh`, which taps
its way through the app to arm an alarm before measuring. Two things about them
are deliberate:

- In `uiautomator_alarms_screen.xml` the node `Manual Alarm List` comes
  **before** the tab `Manual`. A pattern that matches a label as a prefix then
  grabs the wrong node, and the self-test turns red. In the original ordering
  the same broken pattern passed by luck, because `head -1` still happened to
  take the right node - a compensating error of exactly the kind this project
  has been bitten by before.
- `uiautomator_empty.xml` is the tree a Flutter app shows on the *first* dump:
  the semantics tree is only built once an accessibility client connects, and
  `uiautomator dump` is that client. The script therefore retries, and the
  self-test pins that an empty tree yields no coordinate rather than a bogus one.
