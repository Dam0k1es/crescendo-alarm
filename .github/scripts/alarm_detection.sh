#!/usr/bin/env bash
# Reading `dumpsys alarm`: does THIS app have alarms registered right now?
#
# Deliberately a file of its own, with no adb call in it: two scripts depend on
# this judgement - `.github/scripts/check_alarm_survival.sh` (the CI leg) and
# `scripts/verify-alarm-survival.sh` (the run against a real phone, with no CI
# and no emulator involved). A second copy of the counting would be a second
# copy of the two mistakes this detection has already made once each (see the
# self-test below, and docs/TODO.md T-99 / T-103).
#
# Expects `FIXTURES` to point at the recorded dumpsys output the self-test uses.
# Sourcing this file executes nothing on its own.

# ---------------------------------------------------------------------------
# Detection (the actual logic, kept apart from adb and therefore checkable
# without a device).
# ---------------------------------------------------------------------------

# Two independent readings, because `dumpsys alarm` has two representations.
#
# (a) The summary line `Pending alarms per uid: [..., u0a161:2, ...]`. That is
#     the most reliable number the dump offers: the system's own per-uid
#     counter, with no text-pattern guessing at all.
# (b) The entry lines carrying the package name. Needed when the summary line
#     is missing (older images) or the uid could not be resolved.
#
# What must NEVER go back in here: a generic substring such as "AlarmReceiver".
# It matches other apps (T-103) - and the summary line covers them all at once
# anyway.

# (a) Reads N out of `... u0a161:N ...`. Empty when the app does not appear
# there (= no pending alarms) or the line is missing.
pending_for_uid_token() {
  local token="$1"
  [[ -z "$token" ]] && return 0
  sed -n 's/.*Pending alarms per uid:.*/&/p' \
    | grep -oE "(^|[^0-9a-z])${token}:[0-9]+" \
    | grep -oE '[0-9]+$' \
    | head -1
}

# (b) Counts entry lines belonging to this app - explicitly WITHOUT the summary
# line, which lists every uid.
count_package_entry_lines() {
  local package="$1"
  grep -v "Pending alarms per uid:" \
    | grep -cE "${package}|com\\.gdelataillade\\.alarm" || true
}

# The number the verdict rests on: the summary line when it exists, the entry
# lines otherwise.
count_app_alarms() {
  local package="$1" token="${2:-}" dump="$3" n
  n=$(pending_for_uid_token "$token" <"$dump")
  if [[ -n "$n" ]]; then printf '%s' "$n"; return; fi
  count_package_entry_lines "$package" <"$dump"
}

# Converts the Linux uid into the token `dumpsys alarm` lists it under.
uid_token_for() {
  local uid="$1"
  if [[ "$uid" =~ ^[0-9]+$ ]] && (( uid >= 10000 )); then
    printf 'u0a%d' "$(( uid - 10000 ))"
  fi
}

# docs/TODO.md T-155: does THIS app have a still-standing awesome_notifications
# schedule (the sleep-time reminder's own hook) right now? Unlike
# count_app_alarms above, this asks about one SPECIFIC receiver, not "any
# alarm at all" - the `alarm` plugin's own AlarmReceiver entries surviving a
# reboot says nothing about whether awesome_notifications' schedule did too,
# since the two are unrelated native mechanisms with unrelated failure modes.
#
# Matched as "our package name / the receiver class" together, not the
# receiver class alone - the class belongs to a shared plugin, so a bare
# substring would risk counting another app's schedule (the exact T-103
# trap this file exists to avoid repeating).
has_scheduled_notification() {
  local package="$1"
  grep -qF "${package}/me.carda.awesome_notifications.DartScheduledNotificationReceiver"
}

# ---------------------------------------------------------------------------
# Self-check against recorded real output.
#
# The lesson from T-99/T-103 sits in the structure here, not in a comment: an
# instrument that delivers a verdict has to prove itself first. A pattern that
# counts other apps' alarms aborts the run before the measurement, rather than
# after the misreading.
# ---------------------------------------------------------------------------
self_test() {
  local failed=0 pkg='com.wakeywakey.wakeywakey' n

  # 1. A recording without a single alarm of our own must yield 0 - even when
  #    foreign entries carry "AlarmReceiver" in their name. The uid token here
  #    is deliberately one that does NOT occur in the file: which uid the app
  #    had in that run was exactly what was unknown.
  n=$(count_app_alarms "$pkg" u0a999 "$FIXTURES/dumpsys_alarm_foreign.txt")
  if [[ "$n" != "0" ]]; then
    echo "SELF-TEST FAIL: foreign recording yielded $n instead of 0." >&2
    failed=1
  fi

  # 2. The same without any uid token - then the package name alone carries it.
  n=$(count_app_alarms "$pkg" "" "$FIXTURES/dumpsys_alarm_foreign.txt")
  if [[ "$n" != "0" ]]; then
    echo "SELF-TEST FAIL: foreign recording without uid yielded $n instead of 0." >&2
    grep -nE "${pkg}|com\\.gdelataillade\\.alarm" "$FIXTURES/dumpsys_alarm_foreign.txt" >&2
    failed=1
  fi

  # 3. An alarm of our own MUST be found - otherwise 1 and 2 could be satisfied
  #    trivially by a pattern that no longer matches anything at all.
  n=$(count_app_alarms "$pkg" u0a310 "$FIXTURES/dumpsys_alarm_own.txt")
  if [[ "$n" != "9" ]]; then
    echo "SELF-TEST FAIL: own alarms: $n instead of 9 (summary line says u0a310:9)." >&2
    failed=1
  fi

  # 4. Without a resolvable uid the package name has to carry it too.
  n=$(count_app_alarms "$pkg" "" "$FIXTURES/dumpsys_alarm_own.txt")
  if (( n < 1 )); then
    echo "SELF-TEST FAIL: no own alarm found without a uid token ($n)." >&2
    failed=1
  fi

  # 5. The uid token must not swallow a longer one as a prefix.
  local tmp; tmp=$(mktemp)
  printf '  Pending alarms per uid: [u0a1610:7]\n' >"$tmp"
  n=$(count_app_alarms "$pkg" u0a161 "$tmp")
  rm -f "$tmp"
  if [[ "$n" != "0" ]]; then
    echo "SELF-TEST FAIL: u0a161 also matched u0a1610 ($n)." >&2
    failed=1
  fi

  # 6. The uid conversion.
  [[ "$(uid_token_for 10161)" == "u0a161" ]] || { echo "SELF-TEST FAIL: uid_token_for 10161" >&2; failed=1; }
  [[ -z "$(uid_token_for 1000)" ]] || { echo "SELF-TEST FAIL: uid_token_for must not translate system uids" >&2; failed=1; }

  # 7. docs/TODO.md T-155: the real recording has a standing
  #    awesome_notifications schedule for this app - must be found.
  if ! has_scheduled_notification "$pkg" <"$FIXTURES/dumpsys_alarm_own.txt"; then
    echo "SELF-TEST FAIL: has_scheduled_notification found nothing in a recording that has one." >&2
    failed=1
  fi

  # 8. The foreign recording must not produce a false positive.
  if has_scheduled_notification "$pkg" <"$FIXTURES/dumpsys_alarm_foreign.txt"; then
    echo "SELF-TEST FAIL: has_scheduled_notification matched a recording with none of our alarms." >&2
    failed=1
  fi

  if (( failed )); then
    echo "SELF-TEST FAIL - the alarm detection is broken; nothing will be measured." >&2
    return 1
  fi
  echo "self-test ok (alarm detection checked against recorded dumpsys output)"
}
