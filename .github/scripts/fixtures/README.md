# dumpsys fixtures for `check_alarm_survival.sh --self-test`

- **`dumpsys_alarm_foreign.txt` is a real recording.** Taken verbatim from
  the evidence file of run 34566962847 (2026-09-11). Not a single line in
  it belongs to this app — it is the negative case: the counting pattern in
  use at the time produced two hits here (Google's
  `DailyLoggingAlarmReceiver` contains the substring `AlarmReceiver`),
  whereupon the script reported an unfounded "FAIL". Every future pattern
  must return **0** against this file.

- **`dumpsys_alarm_own.txt` is CONSTRUCTED, not a recording.** What one of
  this app's own alarms actually looks like in `dumpsys alarm` has never
  been observed on this emulator image to this day. The file reproduces
  the AOSP format and covers both plausible shapes: one line that carries
  the package name, and one where only the uid token appears. It therefore
  does **not** prove that detection actually works in reality — it only
  prevents someone from trivially satisfying the negative test by having
  the pattern match nothing at all any more.

  Once a run actually shows one of the app's own alarms, that real output
  belongs here instead, and this paragraph should be struck.

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
