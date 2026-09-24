#!/usr/bin/env bash
# Locating and tapping a UI element via `uiautomator dump` - shared by
# scripts/verify-alarm-survival.sh and
# scripts/verify-long-idle-alarm-survival.sh (docs/TODO.md T-04/T-164). A
# second copy would be a second chance to repeat a mistake, the same
# reasoning `.github/scripts/alarm_detection.sh` already documents for the
# alarm-counting half of these scripts.
#
# Contract for the sourcing script: define `note()` (logging) before calling
# `tap_label`, and set `FIXTURES` (a directory of recorded accessibility
# trees) before calling `ui_self_test`. Sourcing this file executes nothing
# on its own - no `adb` call happens until `ui_dump`/`tap_label` is actually
# invoked.

# Prints "x y" for the centre of the first node whose text or content-desc
# equals the label.
node_center() {
  local label="$1" xml="$2"
  printf '%s' "$xml" \
    | sed 's/></>\n</g' \
    | grep -F -e "text=\"$label\"" -e "content-desc=\"$label\"" \
    | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' \
    | head -1 \
    | grep -oE '[0-9]+' \
    | paste -sd' ' - \
    | awk 'NF==4 { printf "%d %d", ($1+$3)/2, ($2+$4)/2 }'
}

ui_dump() {
  adb shell uiautomator dump /sdcard/ww_ui.xml >/dev/null 2>&1
  adb shell cat /sdcard/ww_ui.xml 2>/dev/null | tr -d '\r'
}

tap_label() {
  local label="$1" xml center
  for attempt in 1 2 3; do
    # The first dump after launch is regularly empty: a Flutter app only builds
    # its semantics tree once an accessibility client connects, and uiautomator
    # IS that client - so the tree exists from the second dump on.
    xml="$(ui_dump)"
    center="$(node_center "$label" "$xml")"
    if [[ -n "$center" ]]; then
      note "  tap '$label' at ($center)  [dump $attempt]"
      # shellcheck disable=SC2086
      adb shell input tap $center
      sleep 2
      return 0
    fi
    sleep 2
  done
  printf '%s' "$xml" | raw "ui dump without a node named '$label'"
  note "  could not find '$label' in the accessibility tree"
  return 1
}

# The tap locating proves itself too, against recorded accessibility trees -
# the same principle the alarm counting learned the hard way (T-99/T-103). A
# tap that lands on nothing would arm no alarm, and the script would then
# report "not measurable" while the app was perfectly fine.
ui_self_test() {
  local failed=0 xml center

  xml="$(cat "$FIXTURES/uiautomator_alarms_screen.xml")"
  center="$(node_center "Add A New Alarm" "$xml")"
  [[ "$center" == "936 1776" ]] || { echo "UI SELF-TEST FAIL: add button at '$center' instead of '936 1776'." >&2; failed=1; }

  # A label must not match a longer one that contains it: "Manual" sits next to
  # "Manual Alarm List" in that very tree.
  center="$(node_center "Manual" "$xml")"
  [[ "$center" == "810 360" ]] || { echo "UI SELF-TEST FAIL: 'Manual' at '$center' instead of '810 360' (matched 'Manual Alarm List'?)." >&2; failed=1; }

  xml="$(cat "$FIXTURES/uiautomator_add_dialog.xml")"
  center="$(node_center "Save" "$xml")"
  [[ "$center" == "800 1945" ]] || { echo "UI SELF-TEST FAIL: 'Save' at '$center' instead of '800 1945'." >&2; failed=1; }
  # Cancel and Save sit side by side - hitting the wrong one would silently
  # create no alarm at all.
  center="$(node_center "Cancel" "$xml")"
  [[ "$center" == "600 1945" ]] || { echo "UI SELF-TEST FAIL: 'Cancel' at '$center' instead of '600 1945'." >&2; failed=1; }

  # An empty tree (the usual first dump of a Flutter app) must yield nothing,
  # not a bogus coordinate - that is what the retry loop depends on.
  xml="$(cat "$FIXTURES/uiautomator_empty.xml")"
  center="$(node_center "Save" "$xml")"
  [[ -z "$center" ]] || { echo "UI SELF-TEST FAIL: empty tree yielded '$center'." >&2; failed=1; }

  (( failed )) && return 1
  echo "ui self-test ok (tap locating checked against recorded accessibility trees)"
}
