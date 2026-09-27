// docs/TODO.md T-197 (maintainer request, 2026-09-27): the Do Not Disturb
// feature (T-184 … T-191) still misbehaved in live testing on a real phone -
// switching the toggle on activated Do Not Disturb immediately, against the
// bedtime-window logic, and ringing the alarm did not deactivate it again.
// Verbatim: "bitte entferne erstmal die funktion vollständig, bevor wir sie
// danach versuchen neu zu implementieren - erst nach meiner aufforderung".
//
// "Vollständig" is what this file pins down: no leftover path through which
// the app could still read or change the phone's interruption filter, and no
// permission that would keep it listed under Android's "Do Not Disturb
// access". Delete this file when the maintainer asks for a re-implementation.
//
// A tripwire, not a proof: the actual evidence that the removal is complete
// is that every file the feature touched is byte-identical to its pre-T-184
// state again (Günther's review of 967f98f). This file keeps it that way.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _sourceFiles(String root, String extension) =>
    Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith(extension));

void main() {
  test('ACCESS_NOTIFICATION_POLICY is stripped from the merged manifest', () {
    // Deleting the app's own declaration is not enough: the `alarm` plugin
    // declares the permission in its own manifest (without ever using it),
    // and manifest merging puts it back into the APK - Günther's review of
    // 967f98f found exactly that. Only an explicit tools:node="remove" keeps
    // it out, the same way the other unused plugin permissions are stripped.
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final declarations = RegExp(
            r'<uses-permission[^>]*ACCESS_NOTIFICATION_POLICY[^>]*>')
        .allMatches(manifest)
        .map((m) => m.group(0)!)
        .toList();
    expect(declarations, isNotEmpty,
        reason: 'without an explicit removal, the alarm plugin\'s own '
            'declaration is merged into the APK');
    for (final declaration in declarations) {
      expect(declaration, contains('tools:node="remove"'));
    }
  });

  test('no Dart or Kotlin source touches the interruption filter', () {
    final offenders = [
      ..._sourceFiles('lib', '.dart'),
      ..._sourceFiles('android/app/src', '.kt'),
      ..._sourceFiles('android/app/src', '.java'),
    ].where((f) {
      final source = f.readAsStringSync();
      return const [
        'InterruptionFilter',
        'isNotificationPolicyAccessGranted',
        'accessNotificationPolicy',
        'ZenRule',
        'setZenMode',
        'NotificationManager.Policy',
      ].any(source.contains);
    }).map((f) => f.path);
    expect(offenders, isEmpty);
  });

  test('no Dart source refers to a Do Not Disturb setting', () {
    final offenders = _sourceFiles('lib', '.dart')
        .where((f) => RegExp(r'doNotDisturb|DoNotDisturb|do_not_disturb')
            .hasMatch(f.readAsStringSync()))
        .map((f) => f.path);
    expect(offenders, isEmpty);
  });
}
