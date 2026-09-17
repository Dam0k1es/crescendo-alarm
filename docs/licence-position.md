# Licence position

WakeyWakey is distributed under the **GNU GPLv3** (`LICENSE`), with Dam0k1es as the sole copyright
holder. This document is the tracked decision the requirements R8 and R9 ask for: what the shipped
dependency set is licensed under, and how the obligations that come with conveying a GPLv3 binary
are met. It is the acceptance criterion of `docs/TODO.md` T-05, T-33 and T-34.

It is a **statement of the project's position**, written by its maintainer with the help of an
assistant, not legal advice.

## The rule this project follows

**A dependency whose licence conflicts with GPLv3 gets replaced, not excepted.**

As sole copyright holder, the maintainer could instead grant an additional permission under
GPLv3 §7 allowing the program to be linked with a named proprietary library - the well-known
OpenSSL exception has that shape, it takes a few lines, and it would have kept both dependencies
below in place. That was considered and deliberately rejected. An exception makes the licence of
the whole harder to reason about for anyone who receives the binary, and it preserves a dependency
the project would rather not have. Replacing costs more once; excepting costs a little forever.

Two dependencies were replaced under this rule:

| Removed | Why it could not stay | Replacement |
|---|---|---|
| `syncfusion_flutter_calendar` (+ `_core`, `_datepicker`, `syncfusion_localizations`, transitively) | Syncfusion Essential Studio licence: *"Under no circumstances can you use this product without (1) either a Community License or a commercial license."* Not an open-source licence, and not compatible with conveying it inside a GPLv3 APK. | `calendar_view` (MIT) |
| `mobile_scanner` | The package itself is BSD-3, but its Android build links Google's ML Kit barcode scanning - `com.google.mlkit:barcode-scanning` bundled into the APK by default, `play-services-mlkit-barcode-scanning` with the `useUnbundled` flag. Both are proprietary Google binaries, and this one sat directly under the app's headline feature, so no calendar swap could have resolved it. | `flutter_zxing` (MIT), wrapping `zxing-cpp` (Apache-2.0) |

`test/no_proprietary_dependencies_test.dart` enforces this against `pubspec.yaml` and every import
in `lib/`, so a convenient widget library cannot re-create the conflict quietly some months from
now. Adding a name to that test's list is a licence decision and the list says why for each entry.

## The rest of the shipped set

The remaining direct dependencies are BSD-3, MIT or Apache-2.0 - the permissive licences GPLv3
absorbs without further conditions. That includes the Flutter SDK and first-party plugins
(`camera`, `shared_preferences`, `permission_handler`, `image_picker`), `alarm`, `audioplayers`,
`device_calendar`, `awesome_notifications`, `provider`, `timezone`, `intl`, `qr_flutter`, `uuid`,
`flutter_colorpicker` and `flutter_markdown_plus`.

What this document does **not** claim: that every transitive dependency has been individually
audited. R8 scopes that out deliberately. The claim is narrower and checkable - no dependency in
the resolved tree is known to carry a licence that conflicts with GPLv3, and the two that did are
gone.

## Corresponding Source (GPLv3 §6)

Anyone who receives the APK is entitled to the source it was built from.

**The decision: the repository is public at the first public release.** That discharges the
obligation directly, without the alternative's bookkeeping - a written offer under §6(b) would bind
the maintainer to fulfil requests for three years and would need a contact address, which sits
badly with this project's policy of keeping real personal details out of tracked files.

Until then, nothing is conveyed to third parties: builds go to the maintainer's own test devices
only, which is not distribution. The condition to be met **before the first release to anyone
else** is therefore simply that the repository is public, and the release then points at the tag it
was built from.

Two further pieces of the same obligation, tracked separately because they are real work rather
than decisions: the app still has no in-app licence/notice surface for its dependencies
(`docs/TODO.md` T-36), and the per-file licence headers question is open (T-48).

## Bundled assets

Separate from code licensing and still open: the provenance of `assets/sounds/*.mp3` and the icon
assets is not recorded (`docs/TODO.md` T-29, requirement R10). Nothing here asserts they are
cleared.
