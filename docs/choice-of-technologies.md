# Choice of Technologies

> Note (2026-09): this document reflects the original technology planning. The
> line marked "not used" below was an early consideration that didn't make it
> into the shipped app - see `CLAUDE.md` for what's actually in use today.
> This document also doesn't mention two later, licence-driven swaps that
> happened after the original planning: `syncfusion_flutter_calendar`
> (replaced by `calendar_view`, MIT) and `mobile_scanner` (replaced by
> `flutter_zxing`, MIT) - both non-GPLv3-compatible dependencies. See
> `docs/licence-position.md` and `docs/TODO.md` T-05/T-33 for why.

# Flutter (Frontend)
- Flutter is used to develop the app's frontend.
- Flutter makes it possible to build an appealing and consistent user interface that runs smoothly across various devices and platforms. Flutter's cross-platform approach saves time and resources by allowing a single codebase to be used for iOS and Android.

> **Note (2026-09):** The iOS part of this reasoning is unverified - iOS has the project
> scaffolding, but has never been built or run (no Mac/Xcode available in this environment),
> see `CLAUDE.md`, "Supported platforms". The cross-platform saving is so far demonstrated
> only for Android and the local Linux debug loop.

# Firebase (Backend Services) - **not used**
- Originally considered for backend services (user accounts, settings sync, alarm storage). What was actually implemented instead is a fully local, offline-capable app with no network communication at all (see `CLAUDE.md`) - Firebase is not used anywhere.

# The actual "backend": on-device persistence and platform integration
> **Note (2026-09):** there is no server, no user account, and no data ever leaves the
> device - "backend" here means whatever plays that role locally. Listed because the
> original planning above never anticipated it, not because any of this was a later
> substitute for Firebase specifically.

- **`shared_preferences`** is the only persistence layer: every piece of app state -
  settings, the scheduled/manual alarm lists, the deactivation code, the diagnostics
  log's ring buffer - is stored as on-device key-value pairs, read back through
  `AppState`. No SQL/NoSQL database, no ORM, no schema migrations.
- **The `alarm` plugin** (a thin wrapper around Android's own `AlarmManager`) is what
  actually "stores and serves" a wake-up: registering a real platform alarm that
  survives reboot and force-stop (R3), not an app-level timer.
- **`awesome_notifications`** schedules the background-isolate hooks this app relies on
  (FR-16's Checkpoint 2, the bedtime reminder, and - since T-184 - the Do Not Disturb
  activation trigger) via Android's own local notification/alarm subsystem. No push
  service, no FCM/APNs, no external server ever involved in triggering one.
- **Two small custom Kotlin platform channels**, not pub.dev plugins, where a suitable
  one didn't exist or wasn't worth the dependency for a handful of framework calls:
  `DirectBootFallback` (the `LOCKED_BOOT_COMPLETED` broadcast) and `DoNotDisturbChannel`
  (`NotificationManager`'s `getCurrentInterruptionFilter`/`setInterruptionFilter`, T-184)
  - see `CLAUDE.md`'s architecture notes for both.
- **`device_calendar`** is the only external data source the app reads from at all, and
  it's still entirely on-device: the phone's own local calendar provider, not a calendar
  server or API.
