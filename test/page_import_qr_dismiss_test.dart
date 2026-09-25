import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/scan_code/page_import_qr.dart';

// docs/TODO.md T-183. Maintainer report: the Import Code screen (opened via `showFullScreenOverlay`,
// which pushes it as `fullscreenDialog: true`) showed TWO ways to back out -
// Flutter's own auto-generated AppBar close ("X") button, and QrScanner's own
// bottom "Cancel" button - and the X did not work at all.
//
// Root cause: QrScanner wraps its whole Scaffold in `PopScope(canPop: false)`
// (deliberately, so the "guaranteed wake-up" gate cannot be dismissed by a
// system back gesture/button). A `fullscreenDialog: true` route's default
// AppBar leading widget is a plain `CloseButton`, which only ever calls
// `Navigator.maybePop(context)` - exactly what that `PopScope` exists to
// block, so the X silently did nothing. The bottom "Cancel" button, by
// contrast, calls `_closeView()` directly, which pops explicitly rather than
// going through `maybePop`, so it already worked correctly. Fixed by turning
// off the AppBar's automatic leading button, leaving only the one control
// that actually works.

Future<void> _pumpAsFullscreenDialog(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PageImportQr(),
                fullscreenDialog: true,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows only one dismiss control, not an AppBar close button too',
      (tester) async {
    await _pumpAsFullscreenDialog(tester);

    expect(find.byType(PageImportQr), findsOneWidget);
    expect(find.byType(CloseButton), findsNothing,
        reason: 'a fullscreenDialog route\'s auto-generated AppBar close '
            'button only ever calls Navigator.maybePop, which QrScanner\'s '
            'own PopScope(canPop: false) blocks - it must not be shown '
            'alongside the "Cancel" button that already works');
    expect(find.widgetWithText(ElevatedButton, 'Cancel'), findsOneWidget);
  });

  testWidgets('the remaining "Cancel" button actually closes the screen',
      (tester) async {
    await _pumpAsFullscreenDialog(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(PageImportQr), findsNothing,
        reason: 'the one remaining dismiss control must actually dismiss '
            'the screen');
  });
}
