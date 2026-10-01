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
  'mobile_scanner': 'links com.google.mlkit:barcode-scanning (bundled) or '
      'play-services-mlkit-barcode-scanning - proprietary Google binaries '
      'inside a GPLv3 APK. Replaced by flutter_zxing (MIT, zxing-cpp '
      'under Apache-2.0).',
};

// docs/TODO.md T-213 (G1): whole families, by package-name prefix. Each of
// these either is proprietary itself or exists to link a proprietary Android
// SDK (Google Play Services, Firebase, Play Core/Billing, ML Kit, Huawei
// Mobile Services, a closed ads/attribution/social SDK) into the APK - the
// same channel as mobile_scanner/ML Kit. A prefix, not a name: the next
// `syncfusion_flutter_pdf` or `firebase_messaging` must fail without someone
// first remembering to list it. Keep each prefix specific (`google_mlkit_`,
// never `google_`): google_fonts or googleapis_auth are free.
const _forbiddenPrefixes = <String, String>{
  'syncfusion_': 'see syncfusion_flutter_calendar - every Syncfusion Flutter '
      'package ships under the same Essential Studio licence.',
  'firebase_': 'FlutterFire plugins link the Firebase Android SDK, which '
      'depends on proprietary Google Play Services.',
  'cloud_firestore': 'see firebase_',
  'cloud_functions': 'see firebase_',
  'google_mlkit_': 'Google ML Kit - proprietary binaries (the T-33 case).',
  'google_mobile_ads': 'Google Mobile Ads SDK - proprietary, Play Services.',
  'google_maps_flutter': 'links com.google.android.gms:play-services-maps.',
  'google_sign_in': 'links com.google.android.gms:play-services-auth.',
  'in_app_review': 'links Google Play Core (com.google.android.play), '
      'proprietary.',
  'in_app_update': 'see in_app_review',
  'in_app_purchase': 'links the proprietary Google Play Billing library.',
  'huawei_': 'Huawei Mobile Services (com.huawei.hms) - proprietary.',
  'agconnect_': 'Huawei AppGallery Connect - proprietary.',
  'onesignal_flutter': 'OneSignal SDK - pulls in Firebase Cloud Messaging.',
  'appsflyer_sdk': 'AppsFlyer attribution SDK - proprietary.',
  'facebook_': 'Facebook/Meta SDK - Facebook Platform licence, not free.',
  'flutter_facebook_': 'see facebook_',
};

/// Every name in [names] that [_forbidden] or [_forbiddenPrefixes] rules
/// out, with the reason.
List<String> _offenders(Iterable<String> names) {
  final offenders = <String>[];
  for (final name in names) {
    final reason = _forbidden[name] ??
        _forbiddenPrefixes.entries
            .where((e) => name.startsWith(e.key))
            .map((e) => e.value)
            .firstOrNull;
    if (reason != null) offenders.add('$name: $reason');
  }
  return offenders;
}

String _pubspec() => File('pubspec.yaml').readAsStringSync();

/// docs/TODO.md T-144: pubspec.yaml alone can't see a forbidden package that
/// comes back transitively - it never gets its own top-level `dependencies:`
/// line, only a `dependency: transitive` entry in the lockfile. This reads
/// `pubspec.lock`'s actually-resolved tree instead: every package, direct or
/// not, is a top-level key at 2-space indent under `packages:`
/// (`  some_package:`).
Set<String> _resolvedPackages() {
  final names = <String>{};
  for (final line in File('pubspec.lock').readAsLinesSync()) {
    final match = RegExp(r'^  ([a-z0-9_]+):$').firstMatch(line);
    if (match != null) names.add(match.group(1)!);
  }
  return names;
}

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
      final offenders = _offenders(_declaredDependencies());

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
        final imported = RegExp(r'''package:([a-z0-9_]+)/''')
            .allMatches(file.readAsStringSync())
            .map((m) => m.group(1)!);
        for (final offense in _offenders(imported.toSet())) {
          offenders.add('${file.path} imports $offense');
        }
      }

      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    // docs/TODO.md T-144: pubspec.yaml only lists direct dependencies, so a
    // forbidden package returning transitively (pulled in by some other
    // package, with no dependency_overrides line either) was invisible to
    // the first test above. pubspec.lock is what actually got resolved.
    test('no forbidden name in the resolved dependency tree (pubspec.lock)',
        () {
      final offenders = _offenders(_resolvedPackages());

      expect(offenders, isEmpty,
          reason: 'These dependencies resolved transitively even though '
              'pubspec.yaml itself does not declare them - still cannot be '
              'distributed inside a GPLv3 APK:\n${offenders.join('\n\n')}');
    });

    // docs/TODO.md T-213 (G1): exact names only caught the two historical
    // offenders - `syncfusion_flutter_pdf`, any `firebase_*` plugin or an ads
    // SDK would have passed. This fixture is a list of real pub.dev package
    // names from those families.
    test('the rules cover whole proprietary SDK families, not two names', () {
      const proprietary = [
        'syncfusion_flutter_pdf',
        'syncfusion_flutter_charts',
        'firebase_core',
        'firebase_crashlytics',
        'firebase_analytics',
        'cloud_firestore',
        'google_mlkit_barcode_scanning',
        'google_mlkit_text_recognition',
        'google_mobile_ads',
        'google_maps_flutter',
        'google_sign_in',
        'in_app_review',
        'in_app_update',
        'in_app_purchase',
        'huawei_push',
        'agconnect_core',
        'onesignal_flutter',
        'appsflyer_sdk',
        'facebook_app_events',
        'flutter_facebook_auth',
        'mobile_scanner',
      ];
      const free = [
        'calendar_view',
        'flutter_zxing',
        'google_fonts',
        'googleapis_auth',
        'in_app_notification',
        'cloud_storage_free_example',
        'flutter',
        'alarm',
      ];
      final flagged = _offenders(proprietary).map((o) => o.split(':').first);
      expect(proprietary.where((n) => !flagged.contains(n)), isEmpty,
          reason: 'proprietary SDK packages the guard lets through');
      expect(_offenders(free), isEmpty,
          reason: 'the rules are too broad - they flag free packages');
    });

    test('the guard would actually catch something', () {
      // Counter-test: without it, the two tests above would also pass if the
      // matching had quietly stopped working - which is how a source-reading
      // guard usually fails.
      expect(_declaredDependencies(), contains('flutter'),
          reason: 'the dependency parser reads nothing at all');
      expect(_declaredDependencies(), contains('alarm'));
      expect(_resolvedPackages(), contains('flutter'),
          reason: 'the lockfile parser reads nothing at all');
      expect(_resolvedPackages(), contains('alarm'));
    });
  });
}
