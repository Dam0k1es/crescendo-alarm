// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of WakeyWakey.
//
// WakeyWakey is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// WakeyWakey is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with WakeyWakey. If not, see <https://www.gnu.org/licenses/>.

/// The six bundled tones, always offered regardless of what's been imported.
///
/// Shared by `page_alarmtones.dart` (Settings' own tone list) and
/// `screen_alarms.dart` (the add/edit dialog's dropdown, and its
/// orphaned-value fallback - see that file's `_showAlarmOverlay` for why the
/// fallback needs the exact same list): before this file existed the two
/// screens each hardcoded their own copy of these six name/path pairs, which
/// is exactly the kind of duplication this project's own history warns
/// about (a second copy is a second chance for the two to quietly drift
/// apart, e.g. one screen getting a display-name update the other doesn't).
///
/// Display names are chosen to describe what the sound actually *is*
/// (docs/TODO.md T-167, maintainer request) - the two that used to be named
/// after the app itself ("WakeyWakey", "WakeyWakey 2") described neither the
/// sound nor anything a user could act on. `assets/sounds/CREDITS.md` has
/// each file's real Mixkit source title, which these names are grounded in
/// rather than invented. The file names/paths themselves are unchanged - see
/// that same CREDITS.md for why (kept identical to the audio-only swap
/// docs/TODO.md T-29 already made once).
const List<(String, String)> bundledTones = [
  ('Annoying Alarm', 'assets/sounds/annoying_alarm.mp3'),
  ('Playful Chime', 'assets/sounds/lollipop.mp3'),
  ('Old Telephone', 'assets/sounds/old_telephone_ring.mp3'),
  ('Wake Up', 'assets/sounds/wake_up.mp3'),
  ('Rooster Crow', 'assets/sounds/wakeywakey.mp3'),
  ('Critical Alarm', 'assets/sounds/wakeywakey2.mp3'),
];
