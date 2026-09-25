import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// docs/TODO.md T-160: MobSF flags DirectBootReceiver as an unprotected
// exported component. It has to be exported for the OS to deliver
// LOCKED_BOOT_COMPLETED at all, and that action is itself AOSP-protected (only
// system/platform-signed code can send it) - so the finding was accepted, not
// fixed. Independent-review finding on that acceptance: the accepted
// rationale rests on a real-code invariant ("the receiver reads no Intent
// data beyond the action string - the due time comes only from this app's own
// private storage") that nothing in the suite guarded going forward, unlike
// its sibling fix (`alarm_receiver_not_exported_test.dart`). A future change
// that started trusting Intent extras/data here would quietly reopen exactly
// the injection surface the acceptance argued does not exist, with no build
// failure or manifest diff to notice it - this is a source-reading test in
// the same shape, guarding the invariant itself rather than a value no build
// step re-checks.
void main() {
  final source = File(
          'android/app/src/main/kotlin/com/crescendoalarm/crescendoalarm/DirectBootReceiver.kt')
      .readAsStringSync();

  test('DirectBootReceiver.onReceive reads no Intent data beyond .action',
      () {
    final onReceiveMatch = RegExp(
      r'override fun onReceive\(context: Context, intent: Intent\) \{([\s\S]*?)\n    \}',
    ).firstMatch(source);

    expect(onReceiveMatch, isNotNull,
        reason: 'could not find onReceive\'s body in DirectBootReceiver.kt - '
            'has its signature changed? This test needs updating to match, '
            'not silently stop guarding the invariant.');

    final body = onReceiveMatch!.group(1)!;

    expect(body, contains('intent.action'),
        reason: 'the body must still read the action at all - otherwise '
            'this test would trivially pass against a body that reads '
            'nothing whatsoever, proving nothing about the actual '
            'accepted-risk claim');

    const forbiddenOnIntent = [
      'getStringExtra',
      'getIntExtra',
      'getLongExtra',
      'getBooleanExtra',
      'getDoubleExtra',
      'getFloatExtra',
      'getCharSequenceExtra',
      'getBundleExtra',
      'getParcelableExtra',
      'getSerializableExtra',
      'getExtras',
      'intent.data',
      'intent.extras',
    ];
    for (final forbidden in forbiddenOnIntent) {
      expect(body, isNot(contains(forbidden)),
          reason:
              'docs/TODO.md T-160\'s accepted-risk rationale is specifically '
              'that this receiver "reads no Intent data beyond the action '
              'string" - $forbidden would read Intent data beyond that, and '
              'the finding would need re-review (not a hardcoded accept) if '
              'it started doing so, since a forged LOCKED_BOOT_COMPLETED '
              'broadcast (blocked at the OS level today only because that '
              'action is itself AOSP-protected) is not the only remaining '
              'threat model to consider once this receiver trusts anything '
              'the Intent carries.');
    }
  });
}
