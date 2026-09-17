import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/utils/utils.dart';

// docs/TODO.md T-136: messages like "Can not edit scheduled alarms!" stayed
// on screen until the user tapped them away - even though `displayToast` has
// set `duration: Duration(seconds: 5)` since its very first commit.
//
// The cause is in the framework, not in the call site: `SnackBar` defaults
// `persist` to `persist ?? action != null`, and `ScaffoldMessenger` aborts
// its timer with `if (snackBar.persist) return;`. A SnackBar WITH an action
// therefore ignores its own duration - and `displayToast` supplies a
// "Dismiss" button.

const _message = 'Can not edit scheduled alarms!';

Widget _host() => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => displayToast(context, _message),
            child: const Text('trigger'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('the message disappears on its own after 5 seconds',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('trigger'));
    await tester.pump();
    // Wait out the fade-in animation: `ScaffoldMessenger` only starts its
    // fade-out timer once it has completed (`isCompleted` in its
    // `build`). Pumping too little here doesn't measure the timer at all.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(_message), findsOneWidget);

    // Shortly before it expires it is still there.
    await tester.pump(const Duration(seconds: 4));
    expect(find.text(_message), findsOneWidget,
        reason: 'it stays visible before the 5 seconds are up');

    // After expiry it disappears with no interaction at all - including
    // the fade-out animation.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text(_message), findsNothing,
        reason: 'gone after 5 seconds without a single tap');
  });

  testWidgets('the Dismiss button is still there', (tester) async {
    // Counter-check: the automatic dismissal must not replace the manual
    // one - anyone who has read the message should be able to tap it away
    // immediately.
    await tester.pumpWidget(_host());
    await tester.tap(find.text('trigger'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Dismiss'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text(_message), findsNothing);
  });
}
