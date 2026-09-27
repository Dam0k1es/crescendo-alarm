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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _sourceFiles(String root, String extension) =>
    Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith(extension));

void main() {
  test('the manifest no longer requests ACCESS_NOTIFICATION_POLICY', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, isNot(contains('ACCESS_NOTIFICATION_POLICY')));
  });

  test('no Dart or Kotlin source touches the interruption filter', () {
    final offenders = [
      ..._sourceFiles('lib', '.dart'),
      ..._sourceFiles('android/app/src', '.kt'),
    ].where((f) {
      final source = f.readAsStringSync();
      return source.contains('InterruptionFilter') ||
          source.contains('isNotificationPolicyAccessGranted');
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
