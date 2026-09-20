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

import 'package:flutter/services.dart';

// docs/TODO.md T-158: a reboot followed by the device staying locked does
// not ring the alarm at all, because neither this app nor the `alarm`
// plugin is direct-boot-aware - `BOOT_COMPLETED` (and with it, the plugin's
// own re-arm of AlarmManager) is withheld entirely by Android until the
// device's first unlock after that boot, since the credential-encrypted
// storage both this app and the plugin use for their real alarm data isn't
// even decryptable before then.
//
// This mirrors only the single instant a native, direct-boot-aware receiver
// needs to arm a Direct-Boot-safe FALLBACK siren (the system's own default
// alarm sound plus a full-screen notification - never the user's real tone,
// volume or gentle-wake settings, none of which are reachable pre-unlock)
// into Android's device-protected storage, which - unlike the app's normal
// storage - IS readable before the first unlock. See
// `android/app/src/main/kotlin/com/wakeywakey/wakeywakey/DirectBootFallback.kt`
// for the native side.

const MethodChannel _directBootChannel =
    MethodChannel('com.wakeywakey.wakeywakey/direct_boot');

/// Mirrors [dueAt] (the next moment a real alarm is expected to ring, or
/// `null` when none is armed) into device-protected storage.
///
/// An injectable seam, the same shape as `fetchEvents`/`now`/
/// `documentsDirectory` elsewhere: there is no native implementation on
/// platforms other than Android (the Linux dev loop, `flutter test`), where
/// the channel call throws `MissingPluginException` and is swallowed - the
/// fallback simply doesn't exist there, the same way the rest of the app
/// degrades on platforms without a given plugin.
Future<void> Function(DateTime? dueAt) mirrorDirectBootFallback =
    _mirrorDirectBootFallback;

Future<void> _mirrorDirectBootFallback(DateTime? dueAt) async {
  try {
    await _directBootChannel.invokeMethod<void>('setNextAlarm', {
      'dueAtMillis': dueAt?.toUtc().millisecondsSinceEpoch,
    });
  } catch (e) {
    // Not just MissingPluginException: plenty of this suite's tests use
    // plain `package:test` with no Flutter binding at all, where even
    // *asking* for a MethodChannel throws a plain `StateError` before it
    // gets anywhere near "no native implementation". Either way there is
    // nothing more to do than not mirror - this must never surface as a
    // failure in a real arm/cancel, which is a much higher-stakes action
    // than this best-effort mirror.
  }
}
