# Licence position

Crescendo Alarm is distributed under the **GNU GPLv3** (`LICENSE`). The project grew out of a university
project with three original developers. All three have now given explicit consent (2026-09-20) to
this GPLv3 licensing; two, Dam0k1es and centron5961, also consented to being named as copyright
holders. The third consented to the licence only, not to being named - a deliberate choice by that
developer, not an open item - so no third name is added anywhere in this repository. See
`CLAUDE.md`'s own licence line for the current, authoritative state of this. This document is the
tracked decision the requirements R8 and R9 ask for: what the shipped dependency set is licensed
under, and how the obligations that come with conveying a GPLv3 binary are met. It is the
acceptance criterion of `docs/TODO.md` T-05, T-33 and T-34.

It is a **statement of the project's position**, written by its maintainer with the help of an
assistant, not legal advice.

## The rule this project follows

**A dependency whose licence conflicts with GPLv3 gets replaced, not excepted.**

As copyright holders, the maintainer and centron5961 together could instead grant an additional
permission under GPLv3 §7 allowing the program to be linked with a named proprietary library - the
well-known
OpenSSL exception has that shape, it takes a few lines, and it would have kept both dependencies
below in place. That was considered and deliberately rejected. An exception makes the licence of
the whole harder to reason about for anyone who receives the binary, and it preserves a dependency
the project would rather not have. Replacing costs more once; excepting costs a little forever.

Two dependencies were replaced under this rule:

| Removed | Why it could not stay | Replacement |
|---|---|---|
| `syncfusion_flutter_calendar` (+ `_core`, `_datepicker`, `syncfusion_localizations`, transitively) | Syncfusion Essential Studio licence: *"Under no circumstances can you use this product without (1) either a Community License or a commercial license."* Not an open-source licence, and not compatible with conveying it inside a GPLv3 APK. | `calendar_view` (MIT) |
| `mobile_scanner` | The package itself is BSD-3, but its Android build links Google's ML Kit barcode scanning - `com.google.mlkit:barcode-scanning` bundled into the APK by default, `play-services-mlkit-barcode-scanning` with the `useUnbundled` flag. Both are proprietary Google binaries, and this one sat directly under the app's headline feature, so no calendar swap could have resolved it. | `flutter_zxing` (MIT), wrapping `zxing-cpp` (Apache-2.0) |

`test/no_proprietary_dependencies_test.dart` enforces this against `pubspec.yaml`, `pubspec.lock`
(since 2026-09-24, `docs/TODO.md` T-144 - a transitive return with no direct `pubspec.yaml` line
used to be invisible) and every import in `lib/`, so a convenient widget library cannot re-create
the conflict quietly some months from now. `scripts/check_proprietary_native_deps.py` (same item)
covers the one channel that guard structurally cannot see - a proprietary Android artifact arriving
through a plugin's own `build.gradle` rather than anything in the Dart dependency graph, exactly how
`mobile_scanner` brought in ML Kit. Adding a name to either list is a licence decision and each
entry says why.

## The rest of the shipped set

The remaining direct dependencies are BSD-3, MIT or Apache-2.0 - the permissive licences GPLv3
absorbs without further conditions. That includes the Flutter SDK and first-party plugins
(`shared_preferences`, `permission_handler`), `alarm`, `audioplayers`, `device_calendar`,
`awesome_notifications`, `provider`, `timezone`, `intl`, `qr_flutter`, `uuid`,
`flutter_colorpicker`, `flutter_markdown_plus`, and the two replacements themselves,
`calendar_view` and `flutter_zxing`. (`camera` and `image_picker` are no longer declared directly -
they arrive with `flutter_zxing`. The two permissions stripped from the manifest both come from
`camera_android_camerax`, not from `image_picker`; see `docs/TODO.md` T-49.)

`flutter_zxing` additionally compiles third-party C/C++ into the app - zxing-cpp (including its
bundled "librscpp" Reed-Solomon implementation) under Apache-2.0, and zint under BSD-3. All
GPLv3-compatible, so the claim above holds for them too. (An earlier pass through this document
also listed "libzueci" as a fourth, separately-vendored body under BSD-3 - re-checked against
`flutter_zxing` 3.0.1's actual vendored source for T-142 and found to be a misreading: zint's own
BSD-3 files reference "zueci-compatible" data tables in a comment, but no separate zueci source
or build target is vendored at all. Two bodies, not four.)

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

**Met (2026-09-20, `docs/TODO.md` T-34):** the repository is public, and `v1.0.0` was published as a
GitHub Release the same day - a signed, `apksigner`-verified production APK (the real production
key, not the debug key), built from the tagged commit. Before that, nothing had been conveyed to
third parties: builds went only to the maintainer's own test devices, which is not distribution.

Three further pieces of the same obligation, tracked separately because they are real work rather
than decisions: the app still has no in-app licence/notice surface for its dependencies
(`docs/TODO.md` T-36), the per-file licence headers question is open (T-48), and the notices for
the statically linked native code (`docs/TODO.md` T-142) - **fixed 2026-09-19**. Flutter's licence
collector reads package-root `LICENSE` files and cannot see C++ compiled by CMake, so this needed
its own surface: `assets/text/NativeCodeNotices.txt`, hand-assembled from the vendored source's own
SPDX headers and licence files, reproducing the full Apache-2.0 text (zxing-cpp/librscpp) and the
full BSD-3 text with its copyright notice (zint) - reachable from the About page's new "Native Code
Notices" button, the same pattern T-36 established for this app's own GPLv3 text.

## Bundled assets

Separate from code licensing and still open: the provenance of `assets/sounds/*.mp3` and the icon
assets is not recorded (`docs/TODO.md` T-29, requirement R10). Nothing here asserts they are
cleared.
