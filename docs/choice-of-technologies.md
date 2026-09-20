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
