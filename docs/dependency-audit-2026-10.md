# Dependency supply-chain audit - infostealers, loaders and other hostile code

**Date:** 2026-10-28. **Target:** every dependency of Crescendo Alarm in its current state (`dev` at `adc954b`) **and in every
version that ever appeared in the git history** (338 commits over all refs, 14 revisions of `pubspec.lock`, seven release tags
`v1.0.0` ... `v1.7.0`, 22 remote dependabot branches). **Requested by:** the maintainer, "as if it were enterprise data".

**Result in one sentence:** no indicator of an infostealer, loader, backdoor or any other hostile behaviour in any dependency
version that was ever part of the project (0 blockers); what the audit did find are *weaknesses in how things are fetched and
built* (section 4), none of which has been exploited as far as any available evidence shows, and one behaviour change that
arrived with a dependency bump and needs a decision (A-1).

How far "no indicator" reaches is stated in section 6 - read it before relying on this document.

## 1. Scope and method

| Layer | What was examined | How |
|---|---|---|
| pub.dev packages | 164 (package, version) pairs, 159 packages, all hosted at pub.dev, no `git:`/`path:` source ever | extracted every archive; sha256 against the lock files; pub.dev metadata; OSV; static scan; four independent reviews |
| Maven / Gradle | the resolved Android dependency tree (SBOM of the last `master` build, 164 components) and every artifact in the dev VM's Gradle cache (1845 files) | checksum of each file against Google Maven / Maven Central / `download.flutter.io` |
| Shipped binaries | the seven release APKs | signature, permissions, components, native libraries compared with their sources, strings, dex packages |
| Build and CI | workflows, scripts, Gradle/CMake/Podfile files, the Flutter SDK, Docker images, third-party actions - across the whole history | independent review of all history and of the real Actions run logs |

The four reviews were done by independent agents with the "Philipp" persona of `CLAUDE.md` (Android code, Dart code, native and
build code, CI) plus a provenance reviewer (published archive versus public source repository). The agent reports are model
output; every claim that this document relies on was either re-checked by the author of this document or is marked as an agent
finding. Detailed reports and the raw evidence are kept outside the repository (they contain machine paths).

## 2. What was verified, with evidence

1. **Registry integrity.** All 164 archives, re-downloaded today, hash to the `sha256` recorded in the lock files; no
   (package, version) ever had two different hashes across the 14 lock revisions; no version is retracted or discontinued.
2. **Known vulnerabilities.** `osv-scanner` on each of the 14 historical lock files: no issues. pub.dev lists four advisories for
   `archive`, `http` and `shared_preferences_android`; none affects the versions used (checked per version list).
3. **Provenance.** 104 of the 164 pairs were diffed against the public repository at the matching tag or commit: every file in
   every archive is byte-identical or the difference is explained from primary sources. The four packages without a verified
   pub.dev publisher (`flutter_zxing`, `flutter_colorpicker`, `flutter_fgbg`, `sprintf`) match their repositories. `flutter_zxing`
   bundles ~320 k lines of C/C++: its zxing-cpp core is byte-identical to upstream tag `v3.1.1` (commit `287c85df`), its zint
   backend to zint 2.16.0, and its own 1070 lines of glue were read in full (decode and encode only).
4. **No binaries in packages.** None of the 164 archives contains an ELF/PE/Mach-O file, a keystore, a key, a symlink or a hard
   link. The only binaries are three `gradle-wrapper.jar` files, all equal to Gradle's published wrapper checksums, and two
   prebuilt Flutter-web DevTools bundles (`provider`, `shared_preferences`) that are not part of an app build.
5. **Network, process and loader code.** No package contains data exfiltration, `Process` spawning at run time, dynamic code
   loading (`DexClassLoader`, `System.load` of non-APK paths, `Isolate.spawnUri`), clipboard or account access, or reads of
   credential files. The code that can reach a network exists only as caller-driven or opt-in APIs the app never calls
   (`flutter_zxing.readBarcodeImageUrl`, `printing`'s font and image fetch, audio URL sources, an HTTP bitmap fetch in the
   `AndroidAwnCore` AAR) and is inert because **no release ever declared `INTERNET`** (checked in all seven APKs).
6. **Build hooks.** The only Dart native-assets hook that can run in a consumer's build is `objective_c-9.6.0/hook/build.dart`,
   read in full: it does nothing unless the target is iOS or macOS.
7. **Maven artifacts.** All 1845 files in the Gradle cache have the checksum their registry publishes (the apparent mismatches
   were Gradle dropping leading zeros in directory names, and one artifact that exists in two registries with different content,
   `transform-api:2.0.0-deprecated-use-gradle-api`, which is the Google Maven copy Gradle resolved). The Flutter engine
   artifacts match the md5 that `download.flutter.io` publishes.
8. **What actually shipped.** In all seven releases `libflutter.so` (3 ABIs) is byte-identical to the official engine
   `a804b261...` (Flutter 3.47.2) after `llvm-strip --strip-unneeded` (what AGP does to release libraries); the three AndroidX native
   libraries equal the ones in their registry-verified AARs; `libdartjni.so` and `libflutter_zxing.so` import no socket, exec,
   `dlopen` or `getenv` symbol and link only `liblog`, `libm`, `libdl`, `libc`; the dex files contain only the expected library
   packages; the signer certificate is the same in all releases (`f8a3a0c8...`). The two v1.0.0 assets differ only in AGP's
   encrypted dependency-metadata block (same zip entries, same signature).
9. **Tooling.** The Flutter SDK checkout is exactly the commit of tag `3.47.2`; all `distributionSha256Sum` values in history equal
   Gradle's published checksums (the pin exists only since v1.7.0).

Things that changed over the history and are explained: v1.0.0-v1.4.0 declared launcher-badge permissions (ShortcutBadger via
`awesome_notifications`, removed from v1.5.0), carried a disabled GMS `ModuleDependencies` stub (from `image_picker_android`,
no GMS code ships) and core-library desugaring (`j$.*`, gone since minSdk 26).

## 3. Per-reviewer outcome

| Reviewer | Scope | Blocker | Suspicious | Notes |
|---|---|---|---|---|
| A | Android code of the plugins touching calendar, notifications, alarms, files, permissions (20 versions) | 0 | 0 | 12 clean, 8 notes |
| B | the other Android plugins, `printing`, `mobile_scanner`, `jni`, `flutter_zxing` Dart side (~50 versions) | 0 | 1 (`printing` desktop download, see 4.1) | ~28 clean, ~20 notes |
| C | Dart code of all 164 versions, hooks, archive hygiene, obfuscation | 0 | 0 | 140 clean, 24 notes |
| D | native code and build-time scripts, provenance of the bundled C/C++ | 0 | 1 (same item as B) | rest clean |
| E | published archive versus public repository (104 pairs) | 0 | 0 | five notes, all benign |
| F | build, CI and tooling across the history | 0 | 2 (4.2, 4.3) | 12 notes, 5 clean |

## 4. Findings

None of these is a sign of malicious code. They are the places where a future compromise of someone else's account or release
would reach this project, or where a dependency does more than the app needs.

### 4.1 `printing`: unpinned prebuilt pdfium download on Linux and Windows desktop builds (suspicious as a weakness)

`printing-5.15.1/linux/CMakeLists.txt:19-46` (and the Windows twin) download
`https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/5200/pdfium-<os>-<arch>.tgz` at CMake configure time, with
no hash, and `include()` the `PDFiumConfig.cmake` from the archive. The result is linked into the Linux app and runs. It reaches
**only** the maintainer's `flutter build linux` dev loop; the Android APK and CI are unaffected, and the app never calls
`Printing.raster`. Checked today: the asset has been unchanged since 2022-07-25, `libpdfium.so` has no network or exec imports.
sha256 of the archives as served on 2026-10-28: `linux-x64` `0e68e7f0c7619a5b4a91431fad516d665cc52f0c341d701b21aad71a6c6d41d9`,
`linux-arm64` `2a888b49c5474c436da465b223fca1311cf25e542a8070df3d4096f8d6b2df4d`, `win-x64`
`8e900c3e5103ae9a3aa7800653e804575c687d132fcfb4deda7bb2ce04aca8d2`. Options: build the Linux target only in a throw-away VM
without keys; pre-seed the download directory with a verified tarball; or stop building the Linux target.

### 4.2 CI: `osv-scanner` is fetched from `releases/latest` without a hash and runs while the release keystore is on disk (suspicious as a weakness)

`ci.yml:294-298`, `release.yml:71-75`, `security-gate.yml:43-47`. In the real v1.7.0 release run the tool executes between "Decode
signing key" and "Clean up signing key", with a `contents: write` token and the passwords present (and `persist-credentials` left
on). Pinning a version and its sha256 costs three lines; moving the verdict tools into a job without the key removes the window.

### 4.3 CI: `curl .../trufflehog/main/scripts/install.sh | sh`

`security-gate.yml:50`. A remote script from a mutable branch; the script only checks a checksum from the same origin. The job has
no secrets (a read-only token stays in `.git/config`). Pin the release and its sha256.

### 4.4 Other build-chain weaknesses (notes)

No action is pinned to a commit SHA (`subosito/flutter-action@v2`, `reactivecircus/android-emulator-runner@v2`,
`softprops/action-gh-release@v3`, the first-party `actions/*` by tag); `pip install mobsfscan` pulls ~80 unhashed packages; the
MobSF image is `:latest`; `subosito/flutter-action` never verifies the Flutter archive's manifest hash; Gradle has no dependency
verification or lock file (the audit had to reconstruct that from registry checksums); the Flutter Gradle plugin injects the
`download.flutter.io` repository; the cyclonedx plugin and all plugin build scripts run while the release key is on disk; GitHub
secret scanning and push protection are disabled for the repository; the dev keystore is the update identity of the
maintainer's real phone while its comments call it "not a secret".

### 4.5 `alarm` 5.15.0 arms alarms with `setAlarmClock` by default (behaviour change, needs a decision)

`alarm` 5.15.0 (on `dev` since the dependabot bump `eb7e424`, not in any release) added `AlarmSettings.androidAlarmClock`,
default `true`: every alarm is armed with `AlarmManager.setAlarmClock`. Effects: the next wake time becomes readable by every app
(`AlarmManager.getNextAlarmClock`) and shows as the system's next alarm. The app sets the flag nowhere
(`grep -rn androidAlarmClock lib test android` finds nothing). A privacy-minded app should decide this consciously: either pass
`androidAlarmClock: false`, or accept it (it also exempts the ring from Doze and OEM battery savers, which is a benefit).

### 4.6 Capability the app does not use but that is present (notes)

`device_calendar_plus_android` returns more than the app needs (descriptions, locations, organizer, attendee e-mails, account
name) and can create and delete events (the app holds `WRITE_CALENDAR` only because `permission_handler_android` 13.0.1 refuses the
calendar request unless both calendar permissions are declared - see the manifest comment and T-244 - so nothing in the app
writes, but the permission is there); `jni`/`jni_flutter` give any Dart code arbitrary Java reflection by design (only
`path_provider_android` uses them, touching `Context`, `File`, `Environment`); `me.leolin:ShortcutBadger` contains hidden-API
reflection and vendor broadcasts, reachable only through a notification feature the app never triggers; `share_plus` leaves the
deactivation QR PNG in the app's private cache; `permission_handler` and `awesome_notifications` ship stale helper scripts and an
upstream crash log that no build executes. `mobile_scanner` (never released) would have pulled the datatransport/CCT stack with
`INTERNET` and Firebase logging endpoints in its manifests - the reason the release permission guard
(`scripts/check_manifest_permissions.py`) matters.

### 4.7 Provenance notes

- `file_picker` moved from its original author's GitHub account to its main committer's account at 12.2.0 (2026-09-02): the same
  GitHub repository (id 138361535, full history; the new owner has been the main committer since 2024-12-30). Who initiated the transfer and when the pub.dev publisher
  changed is not visible through public APIs.
- `awesome_notifications` ships no Android code itself; it pulls `me.carda:AndroidAwnCore:0.12.1` from Maven Central (sources
  identical to the git tag, GPG-signed, one person controls the pub package and the Maven group; the AAR itself was not rebuilt).
- The git history was rewritten once (T-29, removing six relicensed `assets/sounds/*.mp3`): 77 CI-run commit SHAs are no longer
  reachable in the repository but are still fetchable from GitHub; 71 of them were compared tree-for-tree with their rewritten twins
  and differ only in those six files, the other six are superseded dependabot heads.
- `xml-7.0.1` and `petitparser-7.0.2` ship `AGENTS.md`/`GEMINI.md` style guides for coding assistants; read, inert, nothing aimed at
  reviewers.
- Packages published very shortly before adoption (2-4 days): the `file_picker` family (a new split into `android_file_picker`
  etc., first published 2026-08-14) and `device_calendar_plus` (a young package, 2025-11). Both match their public tags.

## 5. Recommended actions (all open; see `docs/TODO.md` T-246)

1. Decide `androidAlarmClock` for `alarm` 5.15.0 (4.5) before the next release.
2. Do not build the Linux desktop target on a machine that holds keys, or pin the pdfium tarball (4.1).
3. Pin `osv-scanner` and trufflehog by version and sha256; take them out of the job that holds the release key (4.2, 4.3).
4. Pin third-party actions by commit SHA (dependabot's `github-actions` ecosystem keeps SHA pins current) and pin the MobSF
   image by digest (4.4).
5. Consider Gradle dependency verification (`gradle/verification-metadata.xml`), which would turn this audit's one-off checksum
   run into a standing check.
6. Consider enabling GitHub secret scanning and push protection (a repository setting, the maintainer's call).

## 6. What this audit does not establish

- It is static analysis and provenance comparison. Nothing from the packages was built or executed, and no app run was traced
  at the network or syscall level. "No indicator" is not a proof of absence, in particular for code that depends on a trigger
  (date, locale, device model) that a reader would not see.
- 60 of the 164 package versions (first-party Google and Dart-team packages) were not diffed against their repositories
  individually, only spot-checked per monorepo; their Dart and native code was pattern-reviewed and read where sensitive.
- `libdartjni.so` and `libflutter_zxing.so` were checked by symbol table and by the equality of their sources with upstream, not by
  a bit-exact rebuild; `libapp.so` (the compiled Dart) was only string-scanned.
- Not examined: the compiled Flutter-web DevTools bundles (not part of any app build), the proprietary ML Kit binaries of
  `mobile_scanner` (never released), the Syncfusion packages beyond their public drop (never released; pure Dart), the
  source of the third-party actions and CI tools, and the Flutter, JDK and Gradle archives that CI downloaded.
- 85 of the 383 recorded Actions runs have no retrievable log; the 298 that have one were read for the steps in 4.2-4.4.
- A registry or maintainer account that was malicious *at publication time and still is* would pass every integrity check here;
  the provenance comparison (3.) is the control against that, and it covers the packages with native or sensitive code.
