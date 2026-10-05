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

- **`shared_preferences`** is the app's main persistence layer: every piece of Dart-side app
  state - settings, the scheduled/manual alarm lists, the deactivation code, the diagnostics
  log's ring buffers - is stored as on-device key-value pairs, read back through
  `AppState`. No SQL/NoSQL database, no ORM, no schema migrations. Three exceptions:
  imported custom alarm tones are copied as files into the app's own documents directory
  (`docs/TODO.md` T-146); the two native Kotlin channels below keep their own Android
  `SharedPreferences` in **device-protected storage** (`direct_boot_fallback` - the next
  alarm's due time for the locked-after-reboot fallback, T-158; `sleep_time_dnd` - the Do Not
  Disturb window, T-198), which is readable before the device's first unlock by design;
  and the `alarm`/`awesome_notifications` plugins persist their own scheduled entries.
- **The `alarm` plugin** (a thin wrapper around Android's own `AlarmManager`) is what
  actually "stores and serves" a wake-up: registering a real platform alarm that
  survives a reboot, not an app-level timer (R3 - whether it survives a force-stop is still
  unresolved there).
- **`awesome_notifications`** schedules the bedtime reminder (and the silent notification
  FR-16's Checkpoint 2 hangs off - but see docs/TODO.md T-199: its `onNotificationCreatedMethod`
  fires when a notification is scheduled, not when it comes due) via Android's own local
  notification/alarm subsystem. No push
  service, no FCM/APNs, no external server ever involved in triggering one.
- **Two small custom Kotlin platform channels**, not pub.dev plugins, where a suitable
  one didn't exist or wasn't worth the dependency for a handful of framework calls:
  `DirectBootFallback` (the `LOCKED_BOOT_COMPLETED` broadcast), and `SleepTimeDnd`
  (docs/TODO.md T-198, the Sleep Habits Do Not Disturb trigger). The latter is more
  than a call-through: Dart only pushes the sleep-time window, and the native side arms
  two exact `AlarmManager` alarms and switches `NotificationManager`'s interruption
  filter from its own `BroadcastReceiver` (`SleepTimeDndReceiver`) when they fire - so it
  works with no Flutter engine running, which neither an `awesome_notifications` callback
  nor the `alarm` plugin's ring callback can guarantee (T-198's H1/H3 findings). The only
  pub.dev candidate (`do_not_disturb`, MPL-2.0, unmaintained) was rejected already in
  T-184. (T-184's own `DoNotDisturbChannel` existed until that feature was removed in
  T-197; `SleepTimeDnd` is a new design, not a restoration of it.)
- **`device_calendar`** is the only external data source the app reads from at all, and
  it's still entirely on-device: the phone's own local calendar provider, not a calendar
  server or API.
