// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of Crescendo Alarm.
//
// Crescendo Alarm is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Crescendo Alarm is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Crescendo Alarm. If not, see <https://www.gnu.org/licenses/>.

// docs/TODO.md T-67/T-74a/T-74b/T-81/T-88: turning a ReplanResult's flags into
// user notifications used to live inline in Handler with an inline
// Notifications() - so it ran on the ring path only, all three notifications
// shared one try/catch, and it was untestable. Every replan caller now goes
// through here (in practice: `runSchedulingCheckpoint`).

import 'package:flutter/foundation.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/scheduling/replan.dart';
import 'package:crescendo_alarm/utils/notifications.dart';

/// Reports [result]'s three flags (FR-6, FR-9, FR-12) to the user.
///
/// Called from **every** replan path - the ring checkpoint, FR-17's recovery
/// checkpoint and a settings change - because FR-12 explicitly names FR-8 *or*
/// FR-17 ("je nachdem was zuerst eintritt") and its flag is only ever computed
/// on the day-advance that one of them performs: whoever advances the day is
/// the only one who can report it (`docs/TODO.md` T-67).
///
/// Each notification gets its **own** try/catch (T-74b): they are independent
/// warnings, and a failure of the first must not swallow the other two.
///
/// FR-6's and FR-9's warnings are each sent **once per episode**, not once per
/// replan (T-74a, T-81): both flags are re-derived by `computeWeekPlan` on
/// every replan and would otherwise repeat on every app open and every
/// settings change - contradicting FR-6's "einmalig", and especially bad for
/// FR-9, whose episode can last indefinitely. `AppState`'s
/// `overrunNotificationSent` / `safetyValveNotificationSent` remember that the
/// respective warning was sent, and reset as soon as its flag goes away again.
///
/// FR-12 has deliberately **no** such throttle: unlike the other two it is not
/// a standing condition but a one-off observation about a specific day, made
/// exactly once, on the day-advance that discovers it.
Future<void> reportReplanNotifications(
  AppState appState,
  ReplanResult result, {
  Notifications? notifications,
}) async {
  final notifier = notifications ?? Notifications();

  /// Sends [body] at most once per episode, tracked by [alreadySent]/[remember].
  ///
  /// The flag is set **after** a successful send (`docs/TODO.md` T-88):
  /// setting it up front meant a failed notification still counted as sent and
  /// was never retried for the rest of the episode - which, for FR-9, is
  /// exactly the situation the user most needs to hear about.
  Future<void> oncePerEpisode({
    required bool needed,
    required bool alreadySent,
    required void Function(bool) remember,
    required String body,
    required String label,
  }) async {
    if (needed) {
      if (alreadySent) return;
      try {
        await notifier.scheduleNotification(title: 'Crescendo Alarm', body: body);
        remember(true);
      } catch (e) {
        debugPrint("=====reportReplanNotifications: $label failed: ${e.runtimeType}");
      }
    } else if (alreadySent) {
      // Episode over - the next one may notify again.
      remember(false);
    }
  }

  await oncePerEpisode(
    needed: result.overrunNotificationNeeded,
    alreadySent: appState.overrunNotificationSent,
    remember: (v) => appState.overrunNotificationSent = v,
    label: 'FR-6',
    body: 'Your wake-up time had to be adjusted more than usual to '
        'make it to an upcoming appointment in time.',
  );

  await oncePerEpisode(
    needed: result.safetyValveTriggered,
    alreadySent: appState.safetyValveNotificationSent,
    remember: (v) => appState.safetyValveNotificationSent = v,
    label: 'FR-9',
    body: 'No upcoming appointments found for a while - automatic '
        'wake-up scheduling has paused. Check your schedule.',
  );

  if (result.possiblyMissedAppointment) {
    try {
      await notifier.scheduleNotification(
        title: 'Crescendo Alarm',
        body: 'A newly-added appointment may not have been accounted for '
            'by your last alarm.',
      );
    } catch (e) {
      debugPrint("=====reportReplanNotifications: FR-12 failed: ${e.runtimeType}");
    }
  }
}
