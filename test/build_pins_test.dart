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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// F-Droid builds this app from source with a toolchain it fetches itself
// (docs/TODO.md, F-Droid readiness): the Flutter SDK named in a file of the
// repository, and the Gradle distribution the wrapper downloads. Both must be
// pinned and the pins must agree with each other and with CI, or a silent
// toolchain change would change what ships (and what F-Droid can verify).
// Bumping any of them is a reviewed decision: these tests then fail and say
// where else the number lives.

/// Official checksums from services.gradle.org (2026-10-23), for Gradle 9.8.0.
const _gradleVersion = '9.8.0';
const _distributionSha256 =
    '46ac66d47f30f3dacfdf306e0b714a91a34fb94a22ba0a744b280933f47bc0cf';
const _wrapperJarSha256 =
    '238e777fcddd7e34f9708186085def2abd6e08e658505b38718d79d74c21abd5';

void main() {
  group('Gradle wrapper', () {
    final props =
        File('android/gradle/wrapper/gradle-wrapper.properties').readAsStringSync();

    test('the distribution is the pinned version and carries its checksum', () {
      expect(props, contains('gradle-$_gradleVersion-all.zip'));
      expect(props, contains('distributionSha256Sum=$_distributionSha256'),
          reason: 'without distributionSha256Sum the wrapper downloads and runs '
              'whatever the server sends');
    });

    test('the tracked wrapper jar is the official one for that version', () {
      final result = Process.runSync(
          'sha256sum', ['android/gradle/wrapper/gradle-wrapper.jar']);
      expect(result.exitCode, 0);
      expect((result.stdout as String).split(' ').first, _wrapperJarSha256,
          reason: 'a changed gradle-wrapper.jar (a dependency-bot bump, a '
              'tampered file) must be checked against '
              'https://gradle.org/release-checksums/ before it is trusted');
    }, skip: Platform.isLinux ? false : 'needs sha256sum');
  });

  group('Flutter pin', () {
    String? match(String text, RegExp re) => re.firstMatch(text)?.group(1);

    final fvm = File('.fvmrc').readAsStringSync();
    final pin = match(fvm, RegExp(r'"flutter"\s*:\s*"([^"]+)"'));

    test('.fvmrc names an exact version', () {
      expect(pin, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    });

    test('every workflow builds with the pinned version', () {
      for (final f in Directory('.github/workflows').listSync().whereType<File>()) {
        final text = f.readAsStringSync();
        final v = match(text, RegExp(r'FLUTTER_VERSION:\s*"([^"]+)"'));
        if (v == null) continue; // a workflow that does not build Flutter
        expect(v, pin, reason: '${f.path} builds with another Flutter version');
      }
    });

    test('pubspec.yaml admits the pinned version and no other', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final constraint =
          match(pubspec, RegExp(r"^  flutter:\s*'([^']+)'", multiLine: true));
      expect(constraint, isNotNull, reason: 'environment: flutter: is missing');
      final bounds = RegExp(r'>=(\d+\.\d+\.\d+)\s+<(\d+\.\d+)\.0').firstMatch(constraint!);
      expect(bounds, isNotNull, reason: 'expected ">=X.Y.Z <X.(Y+1).0"');
      expect(bounds!.group(1), pin);
      final lower = pin!.split('.').map(int.parse).toList();
      expect(bounds.group(2), '${lower[0]}.${lower[1] + 1}');
    });
  });

  group('release signing', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    // A release build without key.properties failed in `validateSigningRelease`
    // ("Keystore file not set for signing config release") - found by an
    // unsigned trial build for F-Droid (2026-10-23), whose builder has no key.
    // F-Droid re-signs with its own key, so the build must be allowed to fall
    // back to the debug key - but ONLY on an explicit request, never silently:
    // a CI release build that lost its key must stay red, not publish a
    // debug-signed APK.
    test('the debug-key fallback is opt-in through one environment variable',
        () {
      expect(gradle, contains('CRESCENDO_ALLOW_DEBUG_SIGNED_RELEASE'));
      expect(gradle, contains('signingConfigs.getByName("debug")'));
      // The environment variable guards the fallback; the default branch is
      // still the release config, which fails loudly without a key.
      expect(
          RegExp(r'System\.getenv\("CRESCENDO_ALLOW_DEBUG_SIGNED_RELEASE"\) == "1"')
              .hasMatch(gradle),
          isTrue);
    });

    test('no workflow sets the fallback - only the F-Droid recipe does', () {
      for (final f in Directory('.github/workflows').listSync().whereType<File>()) {
        expect(f.readAsStringSync(), isNot(contains('CRESCENDO_ALLOW_DEBUG_SIGNED_RELEASE')),
            reason: '\${f.path} would let a release build fall back to the debug key');
      }
      expect(File('docs/fdroid-recipe-draft.yml').readAsStringSync(),
          contains('CRESCENDO_ALLOW_DEBUG_SIGNED_RELEASE=1'));
    });
  });
}
