import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/screens/settings/page_alarmtones.dart';

// docs/TODO.md T-56: custom tones render as a growable list of named tiles,
// not a single replaceable slot. The file-picker half of importing a new
// one has no test seam (FilePicker is a platform-channel plugin with none
// exposed here, the same boundary this project already accepts for other
// plugins like the camera) - what's tested is what's reachable without it:
// rendering already-imported tones, and selecting one of them.

Future<AppState> _appStateWithCustomTones(Directory documentsDir) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final appState = AppState();
  await appState.initialized;

  Future<File> makeSourceFile(String name) async {
    final file = File('${documentsDir.path}/$name');
    await file.writeAsString('fake audio');
    return file;
  }

  final first = await makeSourceFile('one.mp3');
  final second = await makeSourceFile('two.wav');
  await appState.addCustomTone(first.path,
      name: 'Morning Bell', documentsDirectory: () async => documentsDir);
  await appState.addCustomTone(second.path,
      name: 'Second Alarm', documentsDirectory: () async => documentsDir);
  return appState;
}

void main() {
  late Directory documentsDir;

  setUp(() async {
    documentsDir = await Directory.systemTemp.createTemp('crescendo_alarm_docs_');
  });

  tearDown(() async {
    if (await documentsDir.exists()) {
      await documentsDir.delete(recursive: true);
    }
  });

  testWidgets(
      'every imported custom tone renders as its own named tile, plus an '
      'always-present "Add custom tone" tile', (tester) async {
    // Real dart:io calls (Directory/File) inside testWidgets' fake-async
    // zone can hang indefinitely unless run through `runAsync` - the same
    // escape hatch this project already uses for real platform-channel
    // futures elsewhere (e.g. qr_scanner_close_test.dart).
    late AppState appState;
    await tester.runAsync(() async {
      appState = await _appStateWithCustomTones(documentsDir);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: PageAlarmTones()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Morning Bell'), findsOneWidget);
    expect(find.text('Second Alarm'), findsOneWidget);
    expect(find.text('Add custom tone'), findsOneWidget);
  });

  testWidgets('tapping a custom tone\'s switch selects it', (tester) async {
    late AppState appState;
    await tester.runAsync(() async {
      appState = await _appStateWithCustomTones(documentsDir);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(home: PageAlarmTones()),
      ),
    );
    await tester.pump();
    await tester.pump();

    final secondTone = appState.customTones.firstWhere(
      (tone) => tone.name == 'Second Alarm',
    );
    expect(appState.selectedTone, isNot(secondTone.path));

    final switchFinder = find.descendant(
      of: find.ancestor(
        of: find.text('Second Alarm'),
        matching: find.byType(Card),
      ),
      matching: find.byType(Switch),
    );
    // The page scrolls; a tile below the default 600px test viewport
    // exists in the tree before it's actually reachable by a tap.
    await tester.ensureVisible(switchFinder);
    await tester.pump();
    await tester.tap(switchFinder);
    await tester.pump();

    expect(appState.selectedTone, secondTone.path);
  });
}
