import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// docs/TODO.md T-176-b (independent audit finding 1.5, 2026-09-25): the
// 2026-09-25 rename (T-169) updated every other user-facing surface - app
// title, notification titles, About page, diagnostics export header,
// deactivation-code label - but missed assets/text/Privacy.md, which is the
// very first document a user is asked to read and accept (README.md,
// docs/USER_GUIDE.md). A privacy policy that misnames the product it
// describes fails its own accuracy requirement (docs/REQUIREMENTS.md R11)
// regardless of how minor the change looks. A source-reading test, matching
// licence_header_test.dart's own precedent for a convention with no
// behaviour to exercise, only a regression to keep from recurring silently
// on the next rename.
void main() {
  test('the Privacy Policy names the current product, not the old one', () {
    final content = File('assets/text/Privacy.md').readAsStringSync();

    expect(content, contains('Crescendo Alarm'),
        reason: 'the Privacy Policy must identify the app it actually '
            'describes');
    expect(content, isNot(contains('Wakey Wakey')),
        reason: 'stale pre-rename branding - the exact defect the '
            '2026-09-25 independent audit found');
    expect(content, isNot(contains('WakeyWakey')));
  });
}
