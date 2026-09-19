import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scan_code/deactivation_code.dart';
import 'package:wakeywakey/screens/scan_code/page_deactivation_code.dart';

// User request: a QR code re-rendered from a scanned-in payload doesn't
// look anything like the code that was actually scanned, so it's useless
// as a reminder of what to scan next time. A user-entered description
// should be shown instead, and the app should prompt for one as soon as a
// code with none exists.
Future<AppState> _pumpScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: const MaterialApp(home: PageDeactivationCode()),
    ),
  );
  await tester.pump();
  return appState;
}

void main() {
  testWidgets(
      'a code with no description prompts for one, and saving it replaces the QR image',
      (tester) async {
    final appState = await _pumpScreen(tester);
    appState.deactivationCode = DeactivationCode(payload: 'scanned-payload');
    await tester.pumpAndSettle();

    expect(find.text('What do you need to scan?'), findsOneWidget,
        reason: 'a fresh code with no description must prompt immediately');
    expect(find.byType(QrImageView), findsOneWidget,
        reason: 'until a description exists, the QR image is still shown '
            'as the fallback');

    await tester.enterText(
        find.byType(TextField), 'Barcode on the milk carton');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Barcode on the milk carton'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing,
        reason: 'the meaningless re-rendered QR image must be replaced by '
            'the description, not shown alongside it');
    expect(appState.deactivationCode?.description,
        'Barcode on the milk carton');
  });

  testWidgets('skipping the prompt leaves the QR image showing',
      (tester) async {
    final appState = await _pumpScreen(tester);
    appState.deactivationCode = DeactivationCode(payload: 'scanned-payload');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(appState.deactivationCode?.description, isNull);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Add a description'), findsOneWidget);
  });

  testWidgets('the prompt does not reappear on every rebuild of the same code',
      (tester) async {
    final appState = await _pumpScreen(tester);
    appState.deactivationCode = DeactivationCode(payload: 'scanned-payload');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // Something unrelated triggers a rebuild (accentColor is read all over
    // this screen, so any AppState change does).
    appState.accentColor = Colors.purple;
    await tester.pump();
    await tester.pump();

    expect(find.text('What do you need to scan?'), findsNothing,
        reason: 'the same code must not be prompted for twice');
  });

  testWidgets('a new code (after Remove) is prompted for again',
      (tester) async {
    final appState = await _pumpScreen(tester);
    appState.deactivationCode = DeactivationCode(payload: 'first');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    appState.deactivationCode = null;
    await tester.pump();
    appState.deactivationCode = DeactivationCode(payload: 'second');
    await tester.pumpAndSettle();

    expect(find.text('What do you need to scan?'), findsOneWidget,
        reason: 'a genuinely new code deserves its own prompt');
  });

  testWidgets('"Edit description" reopens the dialog for an existing description',
      (tester) async {
    final appState = await _pumpScreen(tester);
    appState.deactivationCode = DeactivationCode(
        payload: 'scanned-payload', description: 'Old description');
    await tester.pump();

    // Already has a description, so no auto-prompt this time.
    expect(find.text('What do you need to scan?'), findsNothing);
    expect(find.text('Old description'), findsOneWidget);

    await tester.tap(find.text('Edit description'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Old description'), findsOneWidget);
  });
}
