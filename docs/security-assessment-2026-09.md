# WakeyWakey — Security Assessment

**Assessment date:** 2026-09-24
**Target:** WakeyWakey (Flutter/Android alarm-clock application), `dev` branch, commit
`5898d969359bd41f83507b3395f6d63f989accab` (2026-09-24)
**Assessment type:** Static / source-available application security review (no dynamic or
on-device testing — see Scope & Methodology)
**Prepared for:** the project maintainer
**Remediation pass:** 2026-09-24, same day — Finding F1 was verified further, revised, fixed, and
build-verified before this report was finalized; see F1's own "Verification update" and
"Remediation" sections for exactly what changed and why.

**Naming note (2026-09-25, post-assessment):** the app assessed below as "WakeyWakey" was renamed
to "Crescendo Alarm" the day after this report was finalized (`applicationId`
`com.wakeywakey.wakeywakey` → `com.crescendoalarm.crescendoalarm`, no other functional change).
Every reference to "WakeyWakey", the old `applicationId`, and old file paths below is left
unchanged as a point-in-time record of the assessed commit
(`5898d969359bd41f83507b3395f6d63f989accab`) - this is the same application, under its current
name, not a different one.

## Confidentiality

**Correction (2026-09-24, post-review):** this section originally framed this report as needing to
stay confidential "until public release" — that framing was already false the moment it was
written: per `docs/licence-position.md` (R9) and `docs/TODO.md` (T-34), the repository has been
public since 2026-09-20, four days before this assessment was drafted, and v1.0.0 was already
released. The findings below were nonetheless committed and pushed to the (already-public) `dev`
branch alongside their fixes, not held back — in practice this was defensible only because the one
substantive finding (F1) was fixed and build-verified before this report was finalized, and the
remaining findings (F2–F5) are Low/Informational and describe accepted risks, not open,
practically exploitable bypasses. That was the right outcome, but it should not be read as evidence
that a pre-release confidentiality window was ever actually in effect - there was none, and any
future assessment of this kind must be written against the repository's real visibility, not an
assumed one. No exploitation was carried out against a real device, a real user, or any system
outside the source tree and local toolchain of this review.

---

## 1. Scope & Methodology

### 1.1 Scope

The reviewed target is the WakeyWakey Android application as defined by the source tree at
`~/projects/wwmaster` (the `dev` branch), its declared Flutter/Dart dependencies (`pubspec.yaml` /
`pubspec.lock`), its Android build configuration (`android/`), and the native Android manifests
merged in from its plugin dependencies. The application is confirmed, and treated throughout this
report, as making **no network calls anywhere in `lib/`** and declaring **no `INTERNET`
permission** — there is no remote/network attack surface to assess. This is a local/on-device
threat model only: what a co-located Android component (another installed app, or someone with
physical/local access to the device) can do to WakeyWakey's data or its safety-critical alarm
behaviour.

Areas examined, following the project's own architecture as documented in `CLAUDE.md`:

1. The exported Android component surface — WakeyWakey's own `AndroidManifest.xml` plus every
   manifest merged in from `device_calendar`, `alarm`, `awesome_notifications`,
   `camera_android_camerax`, and `flutter_zxing`.
2. The "guaranteed wake-up" deactivation-code mechanism: generation, storage, and comparison.
3. The native QR/barcode decoding attack surface (`flutter_zxing` / zxing-cpp).
4. Local data-at-rest: what is persisted, where, and under what OS-level protection.
5. Debug/logging leftovers reachable in a release build.
6. Dependency vulnerabilities (Dart/Flutter side, via a fresh `osv-scanner` run).
7. The availability/DoS angle specific to this app's own threat model (`docs/threat-model.svg`,
   `docs/TODO.md` T-101): for an alarm clock, an outage *is* the harm, so this review treated
   "can another app degrade this app's ability to ring or be dismissed correctly" as a primary
   question, not an afterthought.

Two items were explicitly treated as already closed and were not re-litigated, per the review
brief:

- **T-160** (`docs/TODO.md`): MobSF's `DirectBootReceiver` "unprotected exported component"
  finding — already independently reviewed under this project's security-researcher persona and
  accepted, on the verified grounds that `LOCKED_BOOT_COMPLETED` is an AOSP protected-broadcast
  action no third-party app can originate. This review's own independent check (Section 4,
  Appendix) reached the same AOSP source and confirms that reasoning was correct; it is referenced,
  not repeated, below.
- **T-161**: a separate compliance/licensing/fitness-for-audience audit; out of scope here.

### 1.2 Methodology and limitations (read before the findings)

This was a **static, source-available review**, not a penetration test against a running system.
That distinction matters and is stated plainly rather than implied:

- **No Android device or emulator was available in this environment.** There was no APK
  installation, no ADB interaction, no live broadcast-injection proof-of-concept against a running
  app, and no dynamic tapjacking/overlay demonstration. Every finding below that concerns runtime
  behaviour is derived from reading the actual Kotlin/Dart source of the app and its exact pinned
  plugin versions (from `~/.pub-cache`), and is evidenced by that source plus, where a platform
  claim is being made, an authoritative external source (AOSP manifest source, official Android
  documentation) fetched and checked directly rather than recalled from memory. Where a claim
  *would* need a live device to become fully certain (e.g. "this exact broadcast reaches the
  receiver on a stock, unrooted Android 14 device and produces this exact effect"), this is stated
  explicitly rather than asserted as demonstrated fact.
- **No APK decompiler (apktool/jadx/aapt2) and no local MobSF/mobsfscan were used.** Having the
  actual source of a project that ships its own code under GPLv3 is strictly better than reasoning
  from decompiled output, and was used throughout. CI already runs `mobsfscan` and a full MobSF
  binary scan on every push to `master`/PRs into it, filtered through
  `.github/security-exceptions.json`; this review cross-references that record (Section 4) rather
  than duplicating it.
- **`osv-scanner` was actually run** against `pubspec.lock` from the repository root — see Section
  4.6 and the Appendix for the exact command and output. This is current, not cited from an old doc.
- **No exploitation was carried out against a real device or a real person.** Findings that concern
  the ability to silence the "guaranteed wake-up" alarm are described at the level of: what
  component, what data, what code path, and what the code does with it — evidenced by the exact
  source lines — without providing an operational, ready-to-run attack recipe against somebody's
  phone. This is a deliberate boundary of this report, not a gap in the analysis.

### 1.3 Tools used

- `Read`/`grep`/source inspection of `~/projects/wwmaster` (the app) and
  `~/.pub-cache/hosted/pub.dev/{alarm-5.12.0, awesome_notifications-0.12.1,
  camera_android_camerax-0.7.4+8, device_calendar-4.3.2, flutter_zxing-3.0.1}` (every plugin
  contributing to the merged Android manifest and to the native barcode-decoding surface).
- `osv-scanner` 2.5.1 (installed on the review VM, on `PATH`) against `pubspec.lock`.
- Live fetch of `https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/master/core/res/AndroidManifest.xml`
  to verify protected-broadcast status of specific actions directly against AOSP source, not from
  memory.
- Web search for CVE/advisory history against `zxing-cpp`/`flutter_zxing`.
- `git`, standard shell tools.

---

## 2. Executive Summary

WakeyWakey is an offline, no-network Android app, which eliminates an entire class of concerns
(remote exploitation, data exfiltration over the wire, server-side issues) by construction — a
genuine and verifiable architectural strength, not a claim taken on faith (confirmed: no
`INTERNET` permission in the merged manifest, no network code anywhere in `lib/`). The project's
existing engineering culture — a PII-free, structurally-enforced diagnostics logger; six-timezone
CI; a documented, previously-reviewed exported-component decision (T-160); a scoped SBOM catching a
real transitive CVE (`gson`, forced to a fixed version) — reflects real security maturity for a
project of this size.

This review's headline finding sits exactly where this app's core promise lives: the third-party
`alarm` plugin (v5.12.0) that implements alarm ringing/scheduling declares its `AlarmReceiver` as an
**exported, unauthenticated** `BroadcastReceiver` that will fully and silently stop a ringing alarm
— bypassing the QR-scan "guaranteed wake-up" gate entirely — for any caller that can address it with
the correct alarm ID. WakeyWakey's own manifest did not override this. An initial reading treated a
notification-PendingIntent-extraction technique as the realistic, no-guessing-needed exploitation
path and rated this High; verifying that specific claim against this application's own configuration
(not the plugin's general capability) found it does not apply here - this app's ringing notification
never exposes a Stop/Snooze action for anything to extract - which narrows the realistic path to
brute-force ID guessing and revises the severity to **Medium**. That narrower path is still real,
needs no special permission, and directly threatens the one feature this application exists to
guarantee, so it was fixed rather than accepted - a manifest override matching a pattern already
used elsewhere in this exact file, applied and **verified against a real build's own manifest-merger
output** (see Finding F1's "Remediation" section) rather than left as a recommendation.

Beyond that, this review found a small number of low-severity or effectively theoretical items —
most of which this review recommends *accepting as-is*, with reasoning, per the review persona's
own standard that unnecessary hardening is itself a failure of judgement, not diligence — and one
clean, current dependency-vulnerability scan.

### Findings table

| ID | Title | Severity | Status |
|----|-------|----------|--------|
| F1 | Exported, unauthenticated `AlarmReceiver` (alarm plugin) could stop a ringing "guaranteed wake-up" alarm without the QR code via brute-force ID guessing (notification-PendingIntent extraction verified not applicable to this app's configuration) | **Medium** | **Fixed** (2026-09-24, build-verified) |
| F2 | Deactivation-code comparison is not constant-time (`String ==`) | Low | Accepted — effectively theoretical |
| F3 | `awesome_notifications`' `DartRefreshSchedulesReceiver` reachable via an unprotected broadcast action | Low / Informational | Accepted |
| F4 | Release build ships without R8/ProGuard code shrinking or obfuscation | Low | Accepted — optional hardening, not a priority |
| F5 | Native barcode decoding (`flutter_zxing`/zxing-cpp) parses untrusted camera input with no known CVEs identified at the pinned version | Informational | Accepted |

No Critical or High findings remain open. No findings at Medium remain open (F1 fixed). Dart/Flutter
dependency scan (`osv-scanner` against `pubspec.lock`, 142 packages): **clean, no issues** (Section
4.6). `allowBackup="false"` is correctly set, debug logging is verifiably a no-op in release builds,
and PendingIntents used by the alarm plugin are correctly `FLAG_IMMUTABLE` — see Section 5 for the
full list of areas examined with no material finding.

---

## 3. Detailed Findings

### F1 — Exported, unauthenticated `AlarmReceiver` can silence a ringing "guaranteed wake-up" alarm without the QR code

**Severity: Medium** (revised from an initial High rating during remediation — see "Verification
update" below, which narrows the realistic attack surface but does not eliminate it).

*Justification:* this defeats the application's entire stated purpose (a wake-up that cannot be
silenced without physically scanning a code) via a documented Android mechanism, with no
cryptography to break and no privilege escalation required, and needs zero special Android
permissions to attempt. It is not High/Critical because, once this application's own actual
runtime configuration is checked (not just the plugin's general capability), the only realistic
exploitation path left is a brute-force explicit-broadcast guess against a ~10^8-value ID space
within a narrow ringing window — real, and not something to leave unfixed, but meaningfully harder
than "no guessing required" (see below).

> **Verification update (performed while remediating this finding, before it was accepted as
> written):** the initial draft of this finding treated "an app holding Android's Notification
> access permission can extract the ringing alarm's Stop-button `PendingIntent` from the visible
> notification and re-fire it directly, no ID-guessing needed" as the realistic exploitation path,
> and rated this finding **High** primarily on that basis. That mechanism is real in general — Android's
> own security documentation names exactly this technique
> (`https://developer.android.com/privacy-and-security/risks/sender-of-pending-intents`: "the
> sender might be a malicious app that acquired another app's PendingIntent using a variety of
> mechanisms, for example: from `NotificationListenerService`") — and firing a `PendingIntent` a
> foreign app holds is **not** blocked by the target receiver's `android:exported="false"` (a
> `PendingIntent`, once handed to another process, still resolves regardless of the target's export
> status; only a *foreign app's own* `Context.sendBroadcast()` call against an unexported
> component is blocked). So this update does not change the remediation - it changes which specific
> claim about this application, not about Android in general, is actually true.
>
> Checked directly against this application's own configuration of the `alarm` plugin rather than
> the plugin's general capability: `lib/models/alarms/ringing_alarm_settings.dart` builds every
> ringing alarm's `NotificationSettings` with only `title`, `body`, `androidStopAlarmOnDismiss:
> false`, and `icon` - it never sets `stopButton` or `androidSnoozeButton` (confirmed via that
> file's own doc comment: *"there is deliberately no `stopButton` on the notification either,
> since the maintainer's call was that the notification itself has no role in stopping the alarm at
> all"* - a T-147 fix, unrelated to this review, that turns out to also close this path as a side
> effect). The plugin's own native notification-building code
> (`~/.pub-cache/hosted/pub.dev/alarm-5.12.0/android/.../services/NotificationService.kt:139-141,
> 146-157`) only calls `notificationBuilder.addAction(0, it.stopButton, stopPendingIntent)` /
> `addAction(0, it.androidSnoozeButton, snoozePendingIntent)` **inside an `if (it.stopButton !=
> null)` / `if (it.androidSnoozeButton != null && canSnooze)` guard** - since this app never sets
> either field, neither action, and therefore neither `PendingIntent`, is ever attached to any
> notification this app actually ships. The notification's `setContentIntent`/
> `setFullScreenIntent` both use a *different*, separately-passed `pendingIntent` (opens the app;
> not a stop action), and its `setDeleteIntent` - since `androidStopAlarmOnDismiss` is `false` -
> uses `restorePendingIntent` (fires `ACTION_ALARM_RESTORE`, which re-posts the notification, not
> `ACTION_ALARM_STOP`). **There is therefore no Stop/Snooze-action `PendingIntent` anywhere in this
> app's actual notifications for a Notification-access-holding app to extract.** That specific path
> does not apply to this application as configured, and the finding is revised accordingly - down
> to Medium, with the brute-force path (below) as the operative one, not eliminated to
> Informational, since that remaining path is real and the fix closes it completely regardless.

**Affected component:**
`com.gdelataillade.alarm.alarm.AlarmReceiver`, declared in the `alarm` plugin's own manifest at
`~/.pub-cache/hosted/pub.dev/alarm-5.12.0/android/src/main/AndroidManifest.xml:15`:

```xml
<receiver android:name="com.gdelataillade.alarm.alarm.AlarmReceiver" android:exported="true" />
```

with no `android:permission` and no `<intent-filter>` (meaning it accepts only *explicit* Intents —
but `exported="true"` with no permission means **any** app on the device, not just WakeyWakey, may
send it one). WakeyWakey's own `android/app/src/main/AndroidManifest.xml` does not declare, merge,
or override this component at all — it is silently inherited as-is into the shipped app. This is
not WakeyWakey's own code; it is a plugin dependency, but it ships inside WakeyWakey's APK under
WakeyWakey's `applicationId`, and the app is in a position to override it (see Remediation).

**Description:**

`AlarmReceiver.onReceive` (`.../alarm-5.12.0/.../AlarmReceiver.kt:23-92`) dispatches on the
Intent's `action` string:

```kotlin
const val ACTION_ALARM_STOP = "com.gdelataillade.alarm.ACTION_STOP"
const val ACTION_ALARM_SNOOZE = "com.gdelataillade.alarm.ACTION_SNOOZE"
const val ACTION_ALARM_RESTORE = "com.gdelataillade.alarm.ACTION_RESTORE"
...
if (intent.action == ACTION_ALARM_STOP) {
    val id = intent.getIntExtra("id", 0)
    ...
    val service = AlarmService.instance
    if (service != null) {
        service.handleStopAlarmCommand(id)
    } else if (id != 0) {
        AlarmStorage(context).unsaveAlarm(id)
        NotificationHandler(context).cancelNotification(id)
        AlarmPlugin.alarmTriggerApi?.alarmStopped(id.toLong()) { ... }
    }
    return
}
```

`handleStopAlarmCommand` (`.../AlarmService.kt:408-411`) is a two-line pass-through:

```kotlin
fun handleStopAlarmCommand(alarmId: Int) {
    if (alarmId == 0) return
    unsaveAlarm(alarmId)
}
```

`unsaveAlarm` → `stopAlarm` (`.../AlarmService.kt:584-627`) performs a **complete** stop: it stops
the audio (`audioService?.stopAudio(id)`), stops vibration, restores system volume, abandons audio
focus, and — once no other alarm is ringing — tears down the foreground service entirely
(`ServiceCompat.stopForeground(...)`, `stopSelf()`). This is functionally identical to what happens
when the user *successfully scans the deactivation QR code* in `qr_scanner.dart`'s
`_validateDeactivationCode` (`lib/screens/scan_code/qr_scanner.dart:294-348`), which itself calls
`Alarm.stop(id)` after validating the scan. **No validation of any kind happens in the
`AlarmReceiver` code path** — the QR check lives entirely in WakeyWakey's Dart layer and is never
consulted by this native receiver.

The upstream plugin authors were aware `AlarmReceiver` is exported and reachable by foreign apps —
but only partially defended against it. `SnoozeCoordinator.snooze` (used by the same receiver's
`ACTION_ALARM_SNOOZE` branch) contains this comment, quoted verbatim
(`.../SnoozeCoordinator.kt:44-53`):

```kotlin
// Both halves are required, matching the notification action and the
// ring-activity label: an alarm that never offered snooze anywhere must
// not be deferrable by broadcasting the action directly. AlarmReceiver
// is exported, so this is the only thing enforcing that.
if (!settings.canSnooze ||
    durationMillis == null ||
    settings.notificationSettings.androidSnoozeButton == null
) {
```

— i.e. the plugin authors added a narrow guard ("only snooze-configured alarms can be
snoozed by a forged broadcast") specifically *because* they know the receiver is exported to the
world. **No equivalent guard exists on the `ACTION_ALARM_STOP` path** (`handleStopAlarmCommand`
above has no such check at all) — the one action that fully defeats "guaranteed wake-up" is the one
action left completely unguarded.

**Who could trigger this, with what capability — stated precisely:**

1. **Blind guessing, by a bare app with no special permission.** WakeyWakey assigns each alarm's
   `id` via `getRandom()` (`lib/utils/utils.dart:26-28`: `Random().nextInt(99999999)` — a
   non-cryptographic PRNG over roughly 10^8 values, ~26.6 bits), used directly as the platform
   alarm ID (`lib/models/alarms/myalarm.dart:71`: `id = id ?? getRandom();`). This ID is never
   exposed to other apps through any observable channel this review could find — it is not written
   to a world-readable location, not exposed via a content provider (none exists), and not
   retrievable without root or `dumpsys` access an ordinary app does not have. Blindly enumerating
   ~10^8 explicit-broadcast sends within the few-minute window an alarm is actually ringing is not
   a realistic real-time attack. **This path is not practically exploitable as a zero-precondition
   attack**, and this review is explicit that it is not claiming otherwise.
2. **An app holding Android's "Notification access" (`BIND_NOTIFICATION_LISTENER_SERVICE`)
   permission — does NOT apply to this application, verified.** In general, an app with this
   permission could enumerate an active notification's `Notification.actions[]` and re-fire
   whichever `PendingIntent` a Stop button carries, with no ID-guessing needed - this is real,
   documented Android behaviour (see the "Verification update" above). **But WakeyWakey's own
   ringing notification never carries a Stop or Snooze action at all** - confirmed directly against
   `lib/models/alarms/ringing_alarm_settings.dart` (no `stopButton`/`androidSnoozeButton` ever set)
   and the plugin's own `NotificationService.kt:139-157` (both actions, and their `PendingIntent`s,
   are only attached when those fields are non-null). There is nothing of this kind for a
   Notification-access-holding app to extract from this specific application. This path is listed
   to document that it was checked and ruled out, not because it applies here.
3. **Local/physical access with `adb` (USB debugging enabled).** Someone with the device unlocked
   and USB-debugging access could read the ringing alarm's ID off-screen or via other observable
   state and issue an explicit broadcast directly. This precondition already implies a much
   stronger attacker capability than "an installed app," so it adds little beyond what physical
   device access already grants.

**Proof of concept / evidence (source-level, not an operational device recipe):**

- The exact component name and its `exported="true"`, no-permission declaration is shown above,
  read directly from the plugin's own manifest at the version this app currently pins
  (`pubspec.yaml:48`, `alarm: ^5.12.0`; resolved to `alarm-5.12.0` in `~/.pub-cache`).
- The full code path from `ACTION_ALARM_STOP` to a complete alarm stop (audio, vibration, volume,
  foreground service teardown) is quoted verbatim above from `AlarmReceiver.kt` and
  `AlarmService.kt`, with no QR/deactivation-code check anywhere on that path — confirmed by
  reading `_validateDeactivationCode` in `qr_scanner.dart:294-348`, which is the *only* place in
  this entire codebase that calls `isDeactivationCodeValid`; `AlarmReceiver.kt` never imports or
  calls into any Dart/Flutter code before acting.
- The plugin's own source comment (`SnoozeCoordinator.kt:44-53`, quoted above) independently
  confirms, in the upstream authors' own words, that this receiver is exported and reachable by
  foreign apps, and that they consider it something requiring a guard — a guard present for snooze,
  absent for stop.
- Notification-listener access as a general technique for reading/invoking another app's
  notification action `PendingIntent`s is documented, standard `NotificationListenerService`
  behaviour (Android SDK: `StatusBarNotification.getNotification().actions`), not a novel or
  unverified claim in this report.

**Real-world impact:**

With path 2 (notification-PendingIntent extraction) verified not to apply, the realistic remaining
path is a bare, permissionless app running a tight loop of explicit `ACTION_ALARM_STOP` broadcasts
covering the ~10^8-value ID space during the window an alarm is actually ringing (typically minutes,
extendable somewhat by snooze). That is real - it needs zero special permissions and zero user
interaction to attempt, which is precisely why this remains a genuine finding rather than being
downgraded to informational - but it is meaningfully harder than "instant, no guessing" as the
initial draft characterized it, and Android's background-execution limits work against a purely
backgrounded attempt (a foreground app/service could sustain a faster broadcast rate, at the cost of
being visibly running and consuming battery/CPU the whole time). Even at this narrower scope, a
successful hit produces exactly the class of harm this project's own threat model
(`docs/threat-model.svg`, `docs/TODO.md` T-101) identifies as the heaviest category for an alarm
clock: availability, where "outage" means oversleeping, with no trace visible to the device owner
beyond the alarm simply not ringing. It remains a different animal from the already-accepted
`DirectBootReceiver` finding (T-160): that action (`LOCKED_BOOT_COMPLETED`) is a protected broadcast
no app can forge at all; `com.gdelataillade.alarm.ACTION_STOP` is an arbitrary custom action string
with zero OS-level sender restriction, reachable (if now only via brute force, not extraction) by
any installed app with no permission at all.

**Remediation: implemented and build-verified (2026-09-24), see `docs/TODO.md` T-165.**

WakeyWakey cannot edit the `alarm` plugin's vendored source directly (it lives in `~/.pub-cache`,
reinstalled on every `pub get`), but it does not need to: the Android manifest merger lets an app
override a merged library manifest's attributes for a component it re-declares by name, and this
exact file already uses that mechanism today for a different plugin
(`android/app/src/main/AndroidManifest.xml`, `tools:replace="android:required"` on the camera
`<uses-feature>` entries). The same pattern was applied directly, inside `<application>`:

```xml
<receiver
    android:name="com.gdelataillade.alarm.alarm.AlarmReceiver"
    android:exported="false"
    tools:replace="android:exported" />
```

**Verified, not just applied and assumed correct:** a real `flutter build apk --release` was run
against the patched manifest. The Gradle manifest merger's own blame report
(`build/app/outputs/logs/manifest-merger-release-report.txt`) confirms the override actually took
effect rather than silently failing to merge:

```
receiver#com.gdelataillade.alarm.alarm.AlarmReceiver
    android:exported
        ADDED from .../android/app/src/main/AndroidManifest.xml:181:13-37
        REJECTED from [:alarm] .../build/alarm/intermediates/merged_manifest/release/.../AndroidManifest.xml:22:13-36
```

and the final merged manifest
(`build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml`)
shows `android:name="com.gdelataillade.alarm.alarm.AlarmReceiver" android:exported="false"` in the
actual, buildable output - not merely in the source file. `test/alarm_receiver_not_exported_test.dart`
(new) guards this against silently regressing in a future manifest edit; confirmed against `git
show HEAD~1:android/app/src/main/AndroidManifest.xml` that the same test would have failed against
the pre-fix manifest (the component name did not appear in it at all).

This does not break either legitimate use of the receiver, for the reason established in the
"Verification update" above: `AlarmManager`'s own delivery of a scheduled alarm, and this app's own
Dart-side `Alarm.stop()`/`Alarm.snooze()` calls, both resolve to the app addressing its own
component, unaffected by `exported="false"` - and per the notification-configuration finding above,
this app has no Stop/Snooze notification action to break in the first place. **On-device
confirmation (a real ring-to-dismiss cycle after this change) is still recommended before the next
release build**, per this project's own `docs/device-trial-checklist.md` practice for exactly this
class of native-layer change - this review/remediation pass had no device available (Section 1.2),
and static/build-level verification, however solid, is not a substitute for one live ring.

**Cost vs. benefit:** the fix was a manifest addition following an established, working pattern
already present in this exact file, verified against a real build's own manifest-merger output at
no meaningful cost. Even narrowed to the brute-force-only remaining path, closing a genuine,
zero-permission bypass of the application's core promise for this cost is not a close call.
**Recommendation: fix, not accept — implemented.**

---

### F2 — Deactivation-code comparison is not constant-time

**Severity: Low — accepted risk, effectively theoretical.**

**Affected component:** `isDeactivationCodeValid`, `lib/screens/scan_code/qr_scanner.dart:44-50`:

```dart
bool isDeactivationCodeValid(
    DeactivationCode? storedCode, String? scannedPayload) {
  if (storedCode == null) {
    return true;
  }
  return storedCode.payload == scannedPayload;
}
```

**Description:** Dart's `String.==` is not defined to run in constant time with respect to where
the first mismatching character occurs, so in principle this comparison could leak timing
information about the correct payload's prefix. Generation, by contrast, is sound:
`DeactivationCode.generateRandomHash` (`lib/models/scan_code/deactivation_code.dart:38-46`) uses
`Random.secure()` — a CSPRNG — over 16 bytes:

```dart
final random = Random.secure();
final bytes = List<int>.generate(16, (_) => random.nextInt(256));
final hash = base64Encode(bytes);
```

That is **128 bits of entropy**, base64-encoded to a 24-character string (22 meaningful base64
characters plus 2 `=` padding characters, since 16 mod 3 = 1) — cryptographically strong, not
brute-forceable by any realistic means.

**Why this is not a realistic risk here:** a timing side-channel requires the attacker to submit
many guesses and measure the *comparison's own wall-clock duration* with enough precision to
distinguish a difference on the order of nanoseconds-to-microseconds per character. In this
codebase, the comparison only ever runs inside `_validateDeactivationCode`
(`qr_scanner.dart:294-348`), reached exclusively by decoding a physical, camera-visible barcode —
each attempt requires presenting an actual printed/displayed code to the device's camera, gated by
a real decode pass (`scanDelay`/`scanDelaySuccess`, real image processing) and, for the injected
test-stream seam, explicitly test-only (`debugScanStreamOverride`, `@visibleForTesting`, not
reachable from production input). There is no IPC, log output, or other channel through which a
co-located process could observe *this specific comparison's* execution time; Android's process
isolation means another app cannot instrument or time WakeyWakey's own function calls without
already having a far stronger capability (root, a debugger attached to the target process) than
anything a timing side-channel would itself grant. In short: the precondition to exploit this
theoretical weakness is already "I can arbitrarily instrument the target app's process," at which
point reading the deactivation code out of memory or off disk (Section 5) is trivially easier than
timing a string comparison.

**Recommendation: accept.** Switching to a constant-time comparison (e.g. XOR-and-accumulate over
UTF-8 bytes) would cost a few lines and a small test, so this is not being rejected on cost grounds
— it is rejected because there is no channel through which the timing this comparison takes could
ever reach an attacker in this application's actual architecture, and "harden a channel that
provably does not exist" is exactly the kind of effort-for-no-benefit this review's own standard
argues against spending. Revisit only if the comparison is ever exposed to something that isn't a
physical camera scan (e.g. a debug/import API reachable from outside the app).

---

### F3 — `awesome_notifications`' `DartRefreshSchedulesReceiver` reachable via an unprotected broadcast action

**Severity: Low / Informational — accepted risk.**

**Affected component:** `.DartRefreshSchedulesReceiver`,
`~/.pub-cache/hosted/pub.dev/awesome_notifications-0.12.1/android/src/main/AndroidManifest.xml:17-30`:

```xml
<receiver
    android:name=".DartRefreshSchedulesReceiver"
    android:enabled="true"
    android:exported="true">
    <intent-filter>
        <category android:name="android.intent.category.DEFAULT"/>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
        <action android:name="android.intent.action.LOCKED_BOOT_COMPLETED"/>
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
        <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
        <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
        <action android:name="android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"/>
    </intent-filter>
</receiver>
```

**Description:** of the six actions in this filter, three are AOSP protected broadcasts, verified
directly against current AOSP source
(`https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/master/core/res/AndroidManifest.xml`,
fetched during this review — see Appendix for the exact lines): `BOOT_COMPLETED` (line 37),
`MY_PACKAGE_REPLACED` (line 41), `LOCKED_BOOT_COMPLETED` (line 522). **`android.intent.action.QUICKBOOT_POWERON`
and `com.htc.intent.action.QUICKBOOT_POWERON` are *not* present anywhere in that file** — they are
legacy vendor-era actions with no OS-level sender restriction, confirmed by their absence from the
protected-broadcast list rather than assumed. Any installed app, with no special permission, can
therefore send `android.intent.action.QUICKBOOT_POWERON` as an explicit or matching-implicit
broadcast and cause this receiver to run its reschedule logic on demand, at a time of the
attacker's choosing.

**Impact, precisely scoped:** this receiver belongs to `awesome_notifications`, which in this app
is used **only** for informational notifications (FR-6/9/12 warnings, the bedtime reminder, and
FR-16 Checkpoint 2's silent title/body-less notification — see `lib/utils/notifications.dart`).
`onActionReceivedMethod` — the only place a notification *action* could do anything — is a
deliberate no-op (`lib/utils/notifications.dart:58-59`: `Future<void> onActionReceivedMethod(...)
async {}`). The actual alarm-ringing engine is the separate `alarm` plugin (Finding F1), which has
its own, protected-broadcast-gated `BootReceiver`
(`~/.pub-cache/.../alarm-5.12.0/.../AndroidManifest.xml:16-23`, filtered on `BOOT_COMPLETED` only).
Forcing this receiver early can, at most, cause `awesome_notifications`' own schedule bookkeeping to
re-run and could, in principle, cause a duplicate or early-fired informational notification (e.g.
a spurious "Sleep time" reminder) or an extra run of FR-16 Checkpoint 2's
`onNotificationCreatedMethod` → `runTimezoneCheckpoint2()` — a function this project's own
architecture documents as idempotent-by-design (`checkpoint.dart`/`replan.dart` are "serialized
against itself"). No alarm data, no deactivation code, and no scheduling decision is reachable from
this path.

**Recommendation: accept.** This is a real, verified gap (unlike the already-closed
`DirectBootReceiver` finding, `QUICKBOOT_POWERON` genuinely is unprotected), but the worst
realistic outcome is a spurious or early informational notification, not a safety-relevant one. The
same manifest-override technique used for F1 could close it (`tools:replace="android:exported"` set
to `false`, or narrowing the `<intent-filter>` to drop the two `QUICKBOOT_POWERON` actions via
`tools:node="removeAll"` on those specific `<action>` elements), but given the impact ceiling here
is "an extra harmless notification," spending review/testing effort on it ahead of F1 would not be
a good use of the same budget. Worth revisiting only as low-priority cleanup, not before a release.

---

### F4 — Release build ships without R8/ProGuard minification or shrinking

**Severity: Low — optional hardening, not recommended as a priority.**

**Affected component:** `android/app/build.gradle.kts`, `buildTypes { release { ... } }`:

```kotlin
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
        proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
    }
}
```

**Description:** `proguardFiles(...)` only *supplies rule files* to R8; it does not itself enable
minification/shrinking. Neither `isMinifyEnabled` nor `isShrinkResources` is set anywhere in this
block (confirmed by `grep -rn "isMinifyEnabled\|isShrinkResources\|minifyEnabled" android/`
returning nothing), so AGP's default for a release build type applies: **both are `false`**. The
release APK's Kotlin/Java platform layer — `MainActivity`, `DirectBootReceiver`,
`DirectBootFallbackAlarmReceiver`, `DirectBootFallbackService`, and every merged plugin class named
above — ships with original class/method names intact and unshrunk, straightforwardly
decompilable with a standard tool (`jadx`, not available in this review environment but not needed
to reach this conclusion — the build configuration itself settles it).

**Why this is lower-value to fix than it might first look:** WakeyWakey's actual application logic
— the scheduling engine, the deactivation-code validation, the diagnostics logger — is written in
Dart and, for a release build, AOT-compiled to native ARM machine code by the Flutter toolchain.
That compilation step is entirely independent of `isMinifyEnabled` (which governs only the Android
Kotlin/Java side) and is already not meaningfully "readable" by decompiling — there is no bytecode
equivalent of a `.class` file to run `jadx` against for the Dart portion regardless of this
setting. What R8 minification would additionally obscure is only the thin native platform-glue
layer above, plus (via `isShrinkResources`) unused resources. Combined with this project's own
documented trajectory — the repository is intended to go public under GPLv3 at release
(`docs/licence-position.md`) — obfuscating that glue layer for intellectual-property reasons has a
shrinking payoff window regardless of whether this is turned on.

**Recommendation:** optional. If enabled, it would need `isMinifyEnabled = true` /
`isShrinkResources = true` plus keep rules verified against every plugin that uses reflection
(`device_calendar`'s existing `-keep class com.builttoroam.devicecalendar.** { *; }` in
`proguard-rules.pro` is a sign this has already bitten once; `awesome_notifications` and `alarm`
would need the same audit) and a full regression pass, since a missing keep rule fails silently at
runtime rather than at build time — a real, non-trivial cost for a benefit limited to a thin glue
layer in an app whose source is headed for a public repository anyway. **Not worth prioritizing**
ahead of F1; revisit only as routine hardening with slack in the schedule to do the keep-rule audit
properly, and treat it as APK-size/tamper-resistance hygiene rather than a confidentiality fix.

---

### F5 — Native barcode decoding (`flutter_zxing`/zxing-cpp) parses untrusted camera input

**Severity: Informational — accepted risk.**

**Affected component:** `flutter_zxing: 3.0.1` (`pubspec.yaml:87`), which vendors the zxing-cpp C++
core directly under `~/.pub-cache/hosted/pub.dev/flutter_zxing-3.0.1/src/zxing/core/` (confirmed
present in the package; no separate version marker file was found in the vendored tree, so the
exact upstream zxing-cpp commit this package snapshot corresponds to could not be pinned more
precisely than "as vendored in flutter_zxing 3.0.1").

**Description:** any native library that parses attacker-influenced binary/visual input (here:
whatever the camera sees, decoded by C++ code) is a plausible memory-safety attack surface in
principle. This review searched specifically for CVEs/security advisories against `zxing-cpp`
(the actively maintained C++ decoder `flutter_zxing` wraps, at `github.com/zxing-cpp/zxing-cpp`,
formerly `nu-book/zxing-cpp`) and against `flutter_zxing` itself, and found **no CVEs or published
security advisories against zxing-cpp's actual decoder core**. The buffer-overflow CVEs that do
turn up in a general search (CVE-2021-28021, CVE-2021-42715, CVE-2021-42716) belong to a
*different, unrelated* project — the original Java ZXing's C++ `stbi`-based image-*loader* utility
packaged separately by some Linux distributions — not the barcode-decoding core this app links.

**Impact, if a memory-safety bug existed and were triggered:** at worst, a crash of the process
hosting the decode (a DoS of the scanning screen, recoverable by the emergency-stop button
`qr_scanner.dart` already provides for exactly this class of "scanner stopped working" situation —
see `_cameraFailed`/`_maxScanDurationTimer`, `qr_scanner.dart:138-153`). Nothing in this review
suggests memory corruption beyond a crash is a *known*, exploitable risk at the pinned version —
this is stated as an absence of found evidence, not as a guarantee of absence. Realistic attacker
positioning is also limited: triggering this requires presenting a specific, malicious visual
pattern to the phone's own camera at close range while an alarm is ringing or a code is being
imported — a physical-proximity requirement that rules out any remote or purely-local-app vector.

**Recommendation: accept.** This project already made one licensing-driven vendor swap in this
exact area (`docs/TODO.md` T-33/T-05, away from proprietary Google ML Kit to `flutter_zxing`
specifically to satisfy GPLv3 compatibility); swapping again on the basis of an unconfirmed,
theoretical native-parsing risk with no CVE evidence and a narrow, physical-proximity-gated impact
ceiling would cost a real re-implementation for no demonstrated benefit. Worth a periodic check
(re-run this same CVE search when bumping the dependency) rather than any action now.

---

## 4. Cross-references and evidence not raised to a separate finding

### 4.1 `DirectBootReceiver` (T-160) — referenced, not re-opened

Already independently reviewed under this project's own security-researcher persona and accepted
into `.github/security-exceptions.json` (dated 2026-09-24) on the verified grounds that
`LOCKED_BOOT_COMPLETED` is an AOSP protected broadcast. This review re-derived the same AOSP fact
independently (Appendix) while checking F3's `QUICKBOOT_POWERON` claim, and it holds.

### 4.2 `allowBackup` and local data-at-rest

`android/app/src/main/AndroidManifest.xml:66`: `android:allowBackup="false"`. This disables both
`adb backup`/`adb restore` and Android's Auto Backup to the cloud for this app's data, closing off
what would otherwise be the most straightforward way to lift another app's private storage off a
stock, unrooted device. With this flag correctly set to `false`, the remaining protection on
WakeyWakey's `SharedPreferences` file (`shared_preferences`, storing among other things the
JSON-encoded deactivation code, per `lib/app_state.dart:452-455`) is standard Android per-UID Linux
DAC sandboxing: the file lives under `/data/data/com.wakeywakey.wakeywakey/shared_prefs/`, mode
`0700`-equivalent, owned by this app's own UID. **Reading it from another app requires either root,
or `run-as` against a `debuggable` build via `adb`** — and this app's release build type declares
no `debuggable` override (AGP's release default is `false`), so `run-as` is not available against
the shipped build either. This matches (and, generalized beyond just the direct-boot fallback,
independently corroborates) this project's own stated reasoning in `CLAUDE.md` about why
`DirectBootFallback`'s three components "cannot read the app's real alarm/settings data." No
finding here — this is the correct, currently-effective configuration.

### 4.3 Debug/logging leftovers

`lib/main.dart:48-52` was checked against its own doc-comment claim rather than trusted:

```dart
// Guarantee that no debug log messages are printed in release mode
if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
}
```

This genuinely reassigns the global `debugPrint` function reference to a no-op when
`kReleaseMode` is true — `kReleaseMode` is a Flutter compile-time constant that is `true` in a
`flutter build apk --release` output, so this claim holds. `lib/` contains 148 `debugPrint(...)`
call sites across 21 files, all of them consequently silent in the shipped release build. A
separate check for raw `print(...)` calls (which `kReleaseMode` gating does **not** cover) found
**zero** in `lib/` — every diagnostic call site in this codebase goes through the gated
`debugPrint`. Combined with this project's own structurally-enforced, source-guarded PII-free
`Diag` logger (`test/diag_log_api_test.dart`, `test/no_pii_in_logs_test.dart`, already treated as
verified per the review brief), no finding here.

### 4.4 `PendingIntent` mutability

`AlarmReceiver.kt:80-86` (the code path that actually rings an alarm) uses
`PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT` on Android 12+. Immutable
`PendingIntent`s close off the "foreign app fills in/modifies this app's pending action" class of
bug (mandatory since Android 12 for most cases, but confirmed explicitly set here rather than
assumed). No finding.

### 4.5 Cross-app `AlarmManager` interference — precisely scoped, and distinguished from F1

The review brief specifically asked whether another installed app could cancel or otherwise
interfere with WakeyWakey's scheduled platform alarms through Android's normal permission model.
Stated precisely: **a foreign app cannot call `AlarmManager.cancel()` (or an equivalent) against
WakeyWakey's own alarms**, because Android's `AlarmManager` matches and cancels alarms by the
identity of the `PendingIntent` that registered them, and a `PendingIntent`'s identity is scoped to
the creating application — a different app cannot construct an equivalent `PendingIntent` that
resolves to WakeyWakey's own registration. This is why F1 matters: it is not "AlarmManager itself
is insecure," it is a specific, narrower hole — an unauthenticated `BroadcastReceiver` that
implements its *own* stop/snooze protocol reachable independently of `AlarmManager`'s own
protections. Being precise about which mechanism is actually exploitable, and which merely sounds
like it should be, is the point of stating this separately rather than folding a vague "alarms
could be cancelled" claim into the executive summary.

### 4.6 Dependency vulnerabilities (Dart/Flutter side)

```
$ osv-scanner --lockfile=pubspec.lock
Scanned /home/dam0k1es/projects/wwmaster/pubspec.lock file and found 142 packages
No issues found
```

Clean. This mirrors (does not replace) CI's own `osv-scanner` runs — the reusable
`security-gate.yml` pass against the same `pubspec.lock`, and the separate, differently-scoped
native-Android SBOM pass in `ci.yml`/`release.yml` that already caught and force-fixed a real
transitive CVE (`gson` 2.8.8 → 2.8.9, GHSA-4jrv-ppp4-jm57/CVE-2022-25647,
`android/app/build.gradle.kts`'s `resolutionStrategy.force(...)`) — which this review's
Dart-lockfile-only scan cannot see and does not attempt to duplicate.

---

## 5. Areas examined with no material finding (summary)

For completeness, per this review's instruction not to omit areas that were genuinely checked:

- `MainActivity` — `exported="true"` but its only `<intent-filter>` is the standard
  `MAIN`/`LAUNCHER` pair every launchable Android activity requires; no data-carrying intent
  surface.
- `device_calendar` and `flutter_zxing`'s own Android manifests declare no components at all
  (confirmed by direct inspection — both files contain only an empty `<manifest>` root, or in
  `device_calendar`'s case, nothing beyond the package declaration).
- `camera_android_camerax`'s manifest declares only permissions (`CAMERA`, `RECORD_AUDIO`,
  scoped `WRITE_EXTERNAL_STORAGE`), no exported components.
- No `INTERNET` permission anywhere in the merged manifest; no network code in `lib/` (confirmed
  elsewhere in this project's own record and not contradicted by anything found here).
- No plaintext secrets, API keys, or credentials found via the source review that accompanied this
  assessment (this review did not re-run `trufflehog` itself, since CI's `security-gate.yml`
  already runs `trufflehog git --fail` against the full git history on every push to/PR into
  `master`, per `CLAUDE.md`).

---

## Appendix

### A. Commands actually run

```
$ cd ~/projects/wwmaster && git branch --show-current
dev

$ osv-scanner --version
osv-scanner version: 2.5.1
osv-scalibr version: 0.5.2
commit: c84fa4568f2526d0333e9a914ea8a0a5f74ad68b
built at: 2026-08-17T03:44:26Z

$ osv-scanner --lockfile=pubspec.lock
Scanned /home/dam0k1es/projects/wwmaster/pubspec.lock file and found 142 packages
No issues found

$ grep -rn "debugPrint(" lib/ | wc -l
148
$ grep -rln "debugPrint(" lib/ | wc -l
21
$ grep -rn "print(" lib/ | grep -v debugPrint
(no output)

$ grep -rn "isMinifyEnabled\|isShrinkResources\|minifyEnabled" android/
(no output)

$ curl -s "https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/master/core/res/AndroidManifest.xml" \
    | grep -n "QUICKBOOT_POWERON\|LOCKED_BOOT_COMPLETED\|MY_PACKAGE_REPLACED\|BOOT_COMPLETED"
36:    <protected-broadcast android:name="android.intent.action.PRE_BOOT_COMPLETED" />
37:    <protected-broadcast android:name="android.intent.action.BOOT_COMPLETED" />
41:    <protected-broadcast android:name="android.intent.action.MY_PACKAGE_REPLACED" />
522:    <protected-broadcast android:name="android.intent.action.LOCKED_BOOT_COMPLETED" />
(no match for either QUICKBOOT_POWERON action, anywhere in the file)
```

**Remediation-verification commands for F1** (run after the manifest override was added):

```
$ grep -n "stopButton\|snoozeButton" lib/models/alarms/ringing_alarm_settings.dart
(no output - confirms neither is ever set by this app)

$ grep -n "addAction\|stopButton\|androidSnoozeButton" \
    ~/.pub-cache/hosted/pub.dev/alarm-5.12.0/android/.../services/NotificationService.kt
            if (it.stopButton != null) {
                notificationBuilder.addAction(0, it.stopButton, stopPendingIntent)
            if (it.androidSnoozeButton != null && canSnooze) {
                notificationBuilder.addAction(0, it.androidSnoozeButton, snoozePendingIntent)
(confirms both actions - and their PendingIntents - are gated on fields this app never sets)

$ flutter build apk --release
✓ Built build/app/outputs/flutter-apk/app-release.apk

$ grep -A8 "gdelataillade.alarm.alarm.AlarmReceiver" \
    build/app/outputs/logs/manifest-merger-release-report.txt
receiver#com.gdelataillade.alarm.alarm.AlarmReceiver
    android:exported
        ADDED from .../android/app/src/main/AndroidManifest.xml:181:13-37
        REJECTED from [:alarm] .../build/alarm/intermediates/merged_manifest/release/.../AndroidManifest.xml:22:13-36

$ grep -A3 "AlarmReceiver\"" \
    build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml
            android:name="com.gdelataillade.alarm.alarm.AlarmReceiver"
            android:exported="false" />

$ flutter test test/alarm_receiver_not_exported_test.dart
00:00 +1: All tests passed!

$ git show HEAD~1:android/app/src/main/AndroidManifest.xml | grep -c "com.gdelataillade.alarm.alarm.AlarmReceiver"
0
(confirms the new regression test would have failed against the pre-fix manifest)
```

### B. Package versions relevant to this review

| Package | Version pinned | Role |
|---|---|---|
| `alarm` | 5.12.0 | Finding F1 |
| `awesome_notifications` | 0.12.1 | Finding F3 |
| `device_calendar` | 4.3.2 | examined, no finding |
| `camera_android_camerax` | 0.7.4+8 | examined, no finding |
| `flutter_zxing` | 3.0.1 | Finding F5 |

### C. References

- AOSP protected-broadcast declarations (fetched live during this review):
  `https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/master/core/res/AndroidManifest.xml`
- Android Developers, insecure broadcast receivers:
  `https://developer.android.com/privacy-and-security/risks/insecure-broadcast-receiver`
- Android Developers, `PendingIntent`:
  `https://developer.android.com/reference/android/app/PendingIntent`
- Android Developers, sender of pending intents (fetched during remediation, cited in F1's
  "Verification update"): `https://developer.android.com/privacy-and-security/risks/sender-of-pending-intents`
- `zxing-cpp` (upstream, actively maintained core `flutter_zxing` wraps):
  `https://github.com/zxing-cpp/zxing-cpp`
- This project's own prior, related review: `docs/TODO.md` T-160;
  `.github/security-exceptions.json`; `docs/REQUIREMENTS.md` R1.
