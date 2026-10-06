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

package com.crescendoalarm.crescendoalarm

/**
 * docs/TODO.md T-217: what [DirectBootReceiver] does with the mirrored due
 * time. Pure (no Android API), so it is JVM-tested
 * (`DirectBootFallbackPolicyTest`), like `SleepTimeDndPolicy`.
 *
 * Maintainer decision (2026-10-06, "Nur bis 60 Min überfällig"): the
 * fallback siren rings for an overdue alarm only up to [MAX_OVERDUE_MINUTES]
 * late, inclusive. Beyond that a siren tells the user nothing they cannot
 * already see and only startles them - the T-217 real-device report was one
 * ringing a day and a half late - so a silent "alarm missed" notification
 * is posted instead.
 *
 * The receiver does not only run at a real boot. On Android 15+ a
 * force-stopped app is sent LOCKED_BOOT_COMPLETED and BOOT_COMPLETED again
 * when the user next launches it (AOSP `ActivityManagerService`
 * `maybeSendBootCompletedLocked`, flag `stayStopped`), while the force-stop
 * itself cancelled every PendingIntent and nothing refreshed the mirror in
 * between - so the due time found here can be arbitrarily old.
 *
 * The window is the same as the `alarm` plugin's `androidStaleAfter`, which
 * `lib/models/alarms/ringing_alarm_settings.dart` sets to 60 minutes
 * (`overdueRingWindow`; test/direct_boot_fallback_contract_test.dart keeps
 * the two equal). The plugin's BootReceiver discards when
 * `now - due > staleAfter`, the same inclusive boundary as here. The two
 * are evaluated at different instants, though: this decision at
 * LOCKED_BOOT_COMPLETED, the plugin's at BOOT_COMPLETED after the first
 * unlock. An alarm 50 minutes overdue at boot rings the siren; if the first
 * unlock then comes 20 minutes later, the plugin drops the real alarm as 70
 * minutes overdue - the siren was the ring.
 */
object DirectBootFallbackPolicy {
    const val MAX_OVERDUE_MINUTES = 60L
    const val MAX_OVERDUE_MILLIS = MAX_OVERDUE_MINUTES * 60 * 1000L

    sealed class Decision {
        /** Nothing mirrored: no alarm to cover. */
        object Nothing : Decision()

        /** Arm the siren at [atMillis] (the due time, or now when it is already overdue). */
        data class ArmSiren(val atMillis: Long, val dueAtMillis: Long) : Decision()

        /** Too late to ring: tell the user silently that the alarm at [dueAtMillis] was missed. */
        data class NotifyMissed(val dueAtMillis: Long) : Decision()
    }

    /**
     * [userUnlocked]: whether credential-encrypted storage is already
     * unlocked when the receiver runs. On a real boot with a secure lock
     * screen it is not - the siren is the only thing that can ring. On a
     * launch after a force-stop (Android 15+), or a boot without a secure
     * lock screen, it is: the `alarm` plugin gets BOOT_COMPLETED right after
     * and re-arms the real alarm itself, so a siren would ring on top of it
     * (overdue) or stay armed for a mirrored time nothing tracks (future).
     * The missed notice beyond the window is kept either way - the plugin
     * drops such an alarm silently.
     */
    fun decide(dueAtMillis: Long?, nowMillis: Long, userUnlocked: Boolean): Decision {
        if (dueAtMillis == null) return Decision.Nothing
        val overdue = nowMillis - dueAtMillis
        if (overdue > MAX_OVERDUE_MILLIS) return Decision.NotifyMissed(dueAtMillis)
        if (userUnlocked) return Decision.Nothing
        if (dueAtMillis >= nowMillis) return Decision.ArmSiren(dueAtMillis, dueAtMillis)
        return Decision.ArmSiren(nowMillis, dueAtMillis)
    }

    /**
     * What the mirror holds after the siren armed for [firedForDueAt] fired
     * (or after the missed notice for it was posted): cleared only if it
     * still holds that due time. On a launch after a force-stop the receiver
     * runs alongside the Flutter side, which may already have mirrored the
     * next alarm - clearing that would leave the next reboot unprotected.
     * A null [firedForDueAt] (a siren armed by a build before this rule)
     * clears unconditionally, as before.
     */
    fun mirrorAfterConsuming(stored: Long?, firedForDueAt: Long?): Long? =
        if (firedForDueAt == null || stored == firedForDueAt) null else stored

    /**
     * Whether a mirror write from [previous] to [next] must cancel a siren
     * DirectBootReceiver may have armed for [previous] (docs/TODO.md T-217):
     * after a locked reboot the siren is armed for the old due time, and
     * deleting, disabling or moving that alarm after unlocking must not
     * leave it to ring at the old time.
     *
     * [fromApp]: the write came over the Dart channel. That only happens
     * once the device is unlocked and the `alarm` plugin's own re-arm has
     * run, so the siren is redundant even for an unchanged due time -
     * kept, it would ring together with the real alarm next morning.
     */
    fun cancelsArmedSiren(previous: Long?, next: Long?, fromApp: Boolean): Boolean =
        fromApp || previous != next
}
