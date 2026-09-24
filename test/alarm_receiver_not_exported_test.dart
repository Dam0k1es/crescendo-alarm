import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// docs/TODO.md T-165, docs/security-assessment-2026-09.md Finding F1: the
// `alarm` plugin (5.12.0) declares its own AlarmReceiver as
// `android:exported="true"` with no `android:permission` - reachable by any
// other installed app via an explicit broadcast naming the component
// directly, whose ACTION_STOP handler fully silences a ringing alarm with
// no check of any kind, bypassing the QR-scan "guaranteed wake-up" gate
// entirely (that gate lives in the Dart layer and this native receiver
// never consults it).
//
// A source-reading test, in the same shape as
// `test/no_proprietary_dependencies_test.dart`/`test/diag_log_api_test.dart`:
// the manifest is what actually ships, so this guards the override against
// ever being silently dropped (e.g. by a future manifest edit that removes
// or reorders the <application> block) rather than asserting a value no
// build step re-checks.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test(
      'AndroidManifest.xml overrides the alarm plugin\'s AlarmReceiver to '
      'exported=false', () {
    final receiverMatch = RegExp(
      r'<receiver\s+android:name="com\.gdelataillade\.alarm\.alarm\.AlarmReceiver"'
      r'([\s\S]*?)/>',
    ).firstMatch(manifest);

    expect(receiverMatch, isNotNull,
        reason: 'no <receiver> override for com.gdelataillade.alarm.alarm.'
            'AlarmReceiver found in the app\'s own AndroidManifest.xml - '
            'without it, the plugin\'s own exported="true", no-permission '
            'declaration ships unmodified and any installed app can '
            'silence a ringing "guaranteed wake-up" alarm via an explicit '
            'broadcast (docs/TODO.md T-165).');

    final attrs = receiverMatch!.group(1)!;
    expect(attrs, contains('android:exported="false"'),
        reason: 'the override must actually set exported=false, not just '
            'reference the component');
    expect(attrs, contains('tools:replace="android:exported"'),
        reason: 'without tools:replace, the manifest merger keeps the '
            'plugin\'s own exported="true" and silently drops this '
            'override - the app would ship unprotected with no build '
            'failure to notice it (verified against a real Gradle build: '
            'this exact override was independently confirmed via '
            'build/app/outputs/logs/manifest-merger-release-report.txt, '
            'which shows android:exported ADDED from the app manifest and '
            'REJECTED from the alarm plugin\'s own).');
  });
}
