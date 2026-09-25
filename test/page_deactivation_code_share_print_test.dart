import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/scan_code/deactivation_code.dart';
import 'package:crescendo_alarm/screens/scan_code/page_deactivation_code.dart';

// docs/TODO.md T-182 (maintainer request): the "Share" button used to just
// show a "This is a future feature!" toast. It now exports the deactivation
// code as a PNG and hands it to the platform - `SharePlus.instance.share`
// (share_plus, the native Android ACTION_SEND chooser) for "Share", and
// `Printing.layoutPdf` (printing+pdf, android.print.PrintManager directly)
// for the new dedicated "Print" button. None of these have a platform
// channel in `flutter test`, so all three (the render step, the share call,
// the print call) are driven through injectable seams - the same
// `debugXxxOverride` shape as every other plugin call this project tests
// this way. `test/qr_export_test.dart` already covers the real PNG-rendering
// function (`renderQrCodePng`) in isolation; this file is only about the
// Share/Print button *wiring*, so it stands in a fast, deterministic fake
// for the render step rather than re-exercising the real `dart:ui` image
// rasterization pipeline, which never resolves when triggered from inside
// an active `testWidgets` binding via a real button tap.

/// The button row sits below the QR image in a `SingleChildScrollView` -
/// below the fold on the 800x600 test viewport, the same scroll trap other
/// dialogs/screens in this project already needed `ensureVisible()` for.
Future<void> _tapButton(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(OutlinedButton, label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  // A single pump, not pumpAndSettle: a failure shows a SnackBar, which
  // enters via an animation and auto-dismisses after its own duration -
  // settling would pump straight past it, the same gotcha
  // screen_sleephabits_help_test.dart's own help-button test already
  // documents.
  await tester.pump();
}

Future<AppState> _pumpScreen(WidgetTester tester,
    {String? description}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;
  // A code with no description at all triggers PageDeactivationCode's own
  // auto-prompt dialog (T-150) on the next frame, which then sits on top
  // and blocks every tap below it - none of these tests are about that
  // dialog, so a description is always supplied here unless a test wants
  // to check the "description shown instead of the QR image" case
  // specifically.
  appState.deactivationCode = DeactivationCode(
      payload: 'the-real-secret', description: description ?? 'unused');

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      // A bare Scaffold, matching how screen_scancode.dart actually embeds
      // this widget (`Scaffold(body: PageDeactivationCode())`) - without
      // it, displayToast's ScaffoldMessenger.of(context) has no ancestor
      // to find at all.
      child: const MaterialApp(
        home: Scaffold(body: PageDeactivationCode()),
      ),
    ),
  );
  await tester.pump();
  return appState;
}

/// A trivial, fast fake standing in for the real PNG rendering - what
/// matters to these tests is which PAYLOAD reached it, not that it produces
/// an actual image.
Future<Uint8List> _fakeRender(String payload) async =>
    Uint8List.fromList(payload.codeUnits);

void main() {
  setUp(() {
    PageDeactivationCode.debugRenderQrCodeOverride = _fakeRender;
  });

  tearDown(() {
    PageDeactivationCode.debugShareOverride = null;
    PageDeactivationCode.debugPrintOverride = null;
    PageDeactivationCode.debugRenderQrCodeOverride = null;
  });

  testWidgets('"Share" exports the real code and hands it off',
      (tester) async {
    List<int>? shared;
    PageDeactivationCode.debugShareOverride = (bytes) async {
      shared = bytes;
    };
    await _pumpScreen(tester);

    await _tapButton(tester, 'Share');

    expect(shared, isNotNull);
    expect(Uint8List.fromList(shared!), equals(await _fakeRender('the-real-secret')),
        reason: 'the shared image must be the actual code, not a '
            'placeholder or a different payload');
  });

  testWidgets('"Print" renders the real code and hands it to the print '
      'framework', (tester) async {
    List<int>? printed;
    PageDeactivationCode.debugPrintOverride = (bytes) async {
      printed = bytes;
    };
    await _pumpScreen(tester);

    await _tapButton(tester, 'Print');

    expect(printed, isNotNull);
    expect(Uint8List.fromList(printed!), equals(await _fakeRender('the-real-secret')));
  });

  testWidgets(
      'Share/Print use the underlying payload even while the description '
      'is shown instead of the QR image', (tester) async {
    // T-150: once a description exists, the screen shows THAT instead of
    // the re-rendered QR image - Share/Print must still act on the real
    // code, not on whatever happens to be visually on screen.
    List<int>? shared;
    PageDeactivationCode.debugShareOverride = (bytes) async {
      shared = bytes;
    };
    await _pumpScreen(tester, description: 'Sticker on the fridge');

    expect(find.text('Sticker on the fridge'), findsOneWidget);
    expect(find.textContaining('the-real-secret'), findsNothing,
        reason: 'the raw payload must never appear as visible text');

    await _tapButton(tester, 'Share');

    expect(shared, isNotNull);
    expect(Uint8List.fromList(shared!), equals(await _fakeRender('the-real-secret')));
  });

  testWidgets('a Share failure shows a toast instead of crashing',
      (tester) async {
    PageDeactivationCode.debugShareOverride =
        (bytes) async => throw StateError('platform gone');
    await _pumpScreen(tester);

    await _tapButton(tester, 'Share');

    expect(find.textContaining('Could not share'), findsOneWidget);
  });

  testWidgets('a Print failure shows a toast instead of crashing',
      (tester) async {
    PageDeactivationCode.debugPrintOverride =
        (bytes) async => throw StateError('platform gone');
    await _pumpScreen(tester);

    await _tapButton(tester, 'Print');

    expect(find.textContaining('Could not print'), findsOneWidget);
  });
}
