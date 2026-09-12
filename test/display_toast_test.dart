import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/utils/utils.dart';

// docs/TODO.md T-136: Meldungen wie "Can not edit scheduled alarms!" blieben
// stehen, bis der Nutzer sie wegtippte - obwohl `displayToast` seit dem ersten
// Commit `duration: Duration(seconds: 5)` setzt.
//
// Ursache im Framework, nicht im Aufruf: `SnackBar` belegt `persist` mit
// `persist ?? action != null` vor, und `ScaffoldMessenger` bricht seinen
// Timer mit `if (snackBar.persist) return;` ab. Ein SnackBar MIT Aktion
// ignoriert seine eigene Dauer also - und `displayToast` gibt einen
// "Dismiss"-Knopf mit.

const _message = 'Can not edit scheduled alarms!';

Widget _host() => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => displayToast(context, _message),
            child: const Text('ausloesen'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('die Meldung verschwindet nach 5 Sekunden von selbst',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('ausloesen'));
    await tester.pump();
    // Einblend-Animation abwarten: `ScaffoldMessenger` legt seinen
    // Ausblend-Timer erst an, wenn sie durch ist (`isCompleted` in dessen
    // `build`). Wer hier zu knapp pumpt, misst den Timer gar nicht.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(_message), findsOneWidget);

    // Kurz vor Ablauf steht sie noch.
    await tester.pump(const Duration(seconds: 4));
    expect(find.text(_message), findsOneWidget,
        reason: 'vor Ablauf der 5 Sekunden bleibt sie sichtbar');

    // Nach Ablauf verschwindet sie ohne jedes Zutun - samt Ausblend-Animation.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text(_message), findsNothing,
        reason: 'nach 5 Sekunden ohne einen einzigen Tipp weg');
  });

  testWidgets('der Dismiss-Knopf bleibt erhalten', (tester) async {
    // Gegenprobe: die automatische Abschaltung darf die manuelle nicht
    // ersetzen - wer die Meldung gelesen hat, soll sie sofort wegtippen
    // koennen.
    await tester.pumpWidget(_host());
    await tester.tap(find.text('ausloesen'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Dismiss'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text(_message), findsNothing);
  });
}
