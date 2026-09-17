import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// docs/TODO.md T-05, T-33: the app is distributed under GPLv3, so every
// dependency that ships inside the APK has to be licensed compatibly.
//
// Two dependencies were not, and both are now gone (see docs/licence-position.md):
//
//   * the Syncfusion calendar packages, whose licence states outright that the
//     product may not be used without a community or commercial licence, and
//   * `mobile_scanner`, which is itself BSD-licensed but links Google's
//     proprietary ML Kit barcode binaries - and that sat directly under the
//     app's headline feature, so no calendar swap could have resolved it.
//
// This test guards the *dependency list*, not a behaviour, because that is
// where the regression would happen: a future `flutter pub add` of a convenient
// widget library re-creates the conflict silently, and nothing else in the
// suite would notice. The same reasoning as test/diag_log_api_test.dart - forbid
// the channel, not the symptom.
//
// Adding a name here is a licence decision, so each entry says WHY.

const _forbidden = <String, String>{
  'syncfusion_flutter_calendar':
      'Syncfusion Essential Studio licence - "under no circumstances can you '
          'use this product without (1) either a Community License or a '
          'commercial license". Replaced by calendar_view (MIT).',
  'syncfusion_flutter_core': 'see syncfusion_flutter_calendar',
  'syncfusion_flutter_datepicker': 'see syncfusion_flutter_calendar',
  'syncfusion_localizations': 'see syncfusion_flutter_calendar',
  'mobile_scanner':
      'links com.google.mlkit:barcode-scanning (bundled) or '
          'play-services-mlkit-barcode-scanning - proprietary Google binaries '
          'inside a GPLv3 APK. Replaced by flutter_zxing (MIT, zxing-cpp '
          'under Apache-2.0).',
};

String _pubspec() => File('pubspec.yaml').readAsStringSync();

/// The dependency names actually declared, ignoring comments - a package
/// mentioned in an explanatory comment must not fail this test, and the
/// explanations above are exactly such mentions.
Set<String> _declaredDependencies() {
  final names = <String>{};
  for (final line in _pubspec().split('\n')) {
    if (line.trimLeft().startsWith('#')) continue;
    final match = RegExp(r'^\s{2}([a-z0-9_]+):').firstMatch(line);
    if (match != null) names.add(match.group(1)!);
  }
  return names;
}

void main() {
  group('GPLv3 compatibility of the shipped dependencies', () {
    test('no dependency with a licence that conflicts with GPLv3', () {
      final declared = _declaredDependencies();
      final offenders = <String>[];
      for (final entry in _forbidden.entries) {
        if (declared.contains(entry.key)) {
          offenders.add('${entry.key}: ${entry.value}');
        }
      }

      expect(offenders, isEmpty,
          reason: 'These dependencies cannot be distributed inside a GPLv3 '
              'APK:\n${offenders.join('\n\n')}');
    });

    test('nothing in lib/ imports one of them either', () {
      // A `dependency_overrides` entry or a transitive path could bring a
      // package back without a line in `dependencies:`. An import is the proof
      // that it is actually being used.
      final offenders = <String>[];
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        for (final name in _forbidden.keys) {
          if (source.contains("package:$name/")) {
            offenders.add('${file.path} imports $name');
          }
        }
      }

      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('the guard would actually catch something', () {
      // Counter-test: without it, the two tests above would also pass if the
      // matching had quietly stopped working - which is how a source-reading
      // guard usually fails.
      expect(_declaredDependencies(), contains('flutter'),
          reason: 'the dependency parser reads nothing at all');
      expect(_declaredDependencies(), contains('alarm'));
    });
  });
}
