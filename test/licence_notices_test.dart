import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/utils/licence_notices.dart';

// docs/TODO.md T-213: notices that Flutter's licence collector cannot find on
// its own (it reads only Dart packages' LICENSE files) are registered with
// LicenseRegistry, so they appear under About > "Third-Party Licenses":
// the native code compiled by flutter_zxing (N1/N2), the Material Icons font
// (CC-BY-4.0, N3), the Android Java/Kotlin libraries (N4), the extra notices
// of `archive`, `image` and `mime` whose code ships but whose
// LICENSE-other files the collector skips (N5), and the media credits for
// the app icon and the alarm tones.

Future<Map<String, String>> _registeredTextByPackage() async {
  final byPackage = <String, String>{};
  await for (final entry in LicenseRegistry.licenses) {
    final text = entry.paragraphs.map((p) => p.text).join('\n');
    for (final package in entry.packages) {
      byPackage[package] = '${byPackage[package] ?? ''}\n$text';
    }
  }
  return byPackage;
}

Uri _packageRoot(String name) {
  final config = jsonDecode(
          File('.dart_tool/package_config.json').readAsStringSync())
      as Map<String, dynamic>;
  final root = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((p) => p['name'] == name)['rootUri'] as String;
  return Uri.file('${Directory.current.path}/.dart_tool/')
      .resolve(root.endsWith('/') ? root : '$root/');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('registerAppLicences', () {
    late Map<String, String> byPackage;

    setUpAll(() async {
      LicenseRegistry.reset();
      registerAppLicences();
      byPackage = await _registeredTextByPackage();
    });

    // package name in the list -> text that must appear in its entry.
    const expected = <String, List<String>>{
      'flutter_zxing': ['libzueci', 'Bjoern Hoehrmann', 'Steve Matteson'],
      'Material Icons': [
        'Material Icons',
        'Google',
        'https://creativecommons.org/licenses/by/4.0/',
        'Attribution 4.0 International',
      ],
      'Android libraries (Java/Kotlin)': [
        'androidx.core:core',
        'com.android.tools:desugar_jdk_libs',
      ],
      'desugar_jdk_libs': [
        'GNU General Public License',
        '"CLASSPATH" EXCEPTION TO THE GPL',
        'https://github.com/google/desugar_jdk_libs',
      ],
      'Protocol Buffers': ['Copyright 2008 Google Inc.'],
      'archive': ['JZLib', 'zlib.js'],
      'image': ['libwebp', 'OpenEXR', 'QuickPVR'],
      'mime': ['Apache License', 'httpd'],
      'Crescendo Alarm app icon': ['icon.png', 'Dam0k1es', 'CC-BY-SA-4.0'],
      'Crescendo Alarm alarm tones': ['.mp3'],
    };

    for (final MapEntry(key: package, value: markers) in expected.entries) {
      test('lists "$package"', () {
        expect(byPackage.keys, contains(package));
        for (final marker in markers) {
          expect(byPackage[package], contains(marker),
              reason: '"$package" entry lacks "$marker"');
        }
      });
    }

    test('the icon credits name the CC licence URL, not only its id', () {
      expect(byPackage['Crescendo Alarm app icon'],
          contains('https://creativecommons.org/licenses/by-sa/4.0/'));
    });
  });

  test('main() registers the notices before the app starts', () {
    final main = File('lib/main.dart').readAsStringSync();
    final register = main.indexOf('registerAppLicences()');
    expect(register, greaterThan(0),
        reason: 'lib/main.dart never calls registerAppLicences()');
    expect(register, lessThan(main.indexOf('runApp(')));
  });

  group('bundled copies of upstream licence files are unchanged', () {
    // A copy is only as good as its source: these compare the committed
    // asset against the file in the resolved package / Flutter SDK, so a
    // dependency bump that changes a notice fails here instead of shipping a
    // stale one.
    final flutterSdk = _packageRoot('flutter').resolve('../../');
    final copies = <String, Uri>{
      'assets/text/licences/MaterialIcons_LICENSE.txt': flutterSdk
          .resolve('bin/cache/artifacts/material_fonts/'
              'MaterialIcons_LICENSE.txt'),
      'assets/text/licences/archive_LICENSE-other.md':
          _packageRoot('archive').resolve('LICENSE-other.md'),
      'assets/text/licences/image_LICENSE-other.md':
          _packageRoot('image').resolve('LICENSE-other.md'),
      'assets/text/licences/mime_httpd_LICENSE.txt':
          _packageRoot('mime').resolve('third_party/httpd/LICENSE'),
    };
    for (final MapEntry(key: asset, value: upstream) in copies.entries) {
      test(asset, () {
        final source = File.fromUri(upstream);
        expect(source.existsSync(), isTrue, reason: 'missing $upstream');
        // Line endings normalised: archive's and image's files are CRLF
        // upstream, and git may check the copy out either way.
        String normalised(File f) =>
            f.readAsStringSync().replaceAll('\r\n', '\n');
        expect(normalised(File(asset)), normalised(source),
            reason: '$asset differs from $upstream - copy it again');
      });
    }
  });
}
