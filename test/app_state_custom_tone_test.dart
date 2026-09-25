import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/models/alarms/custom_tone.dart';

// AppState.addCustomTone wires the pure logic in custom_tone_test.dart to
// persistence and to path_provider - the latter via an injected
// [documentsDirectory] callback (the same pattern as this class's other
// plugin boundaries, e.g. `fetchEvents`/`now`), so these tests never touch a
// real platform channel.
//
// docs/TODO.md T-56: customTones is a growable list, not a single
// replaceable slot - each entry carries the user-chosen [CustomTone.name]
// alongside the file path.

void main() {
  Future<AppState> freshAppState() async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;
    return appState;
  }

  Future<File> makeSourceFile(Directory dir, String name,
      [String contents = 'fake audio bytes']) async {
    final file = File('${dir.path}/$name');
    await file.writeAsString(contents);
    return file;
  }

  late Directory documentsDir;

  setUp(() async {
    documentsDir = await Directory.systemTemp.createTemp('crescendo_alarm_docs_');
  });

  tearDown(() async {
    if (await documentsDir.exists()) {
      await documentsDir.delete(recursive: true);
    }
  });

  test('customTones is empty before anything is imported', () async {
    final appState = await freshAppState();
    expect(appState.customTones, isEmpty);
  });

  test('importing a supported file adds it to customTones and notifies',
      () async {
    final appState = await freshAppState();
    final source = await makeSourceFile(documentsDir, 'ringtone.mp3');
    var notified = false;
    appState.addListener(() => notified = true);

    await appState.addCustomTone(
      source.path,
      name: 'My Ringtone',
      documentsDirectory: () async => documentsDir,
    );

    expect(appState.customTones, hasLength(1));
    expect(appState.customTones.single.name, 'My Ringtone');
    expect(appState.customTones.single.path, 'custom_tones/ringtone.mp3');
    expect(notified, isTrue);
  });

  test('importing a second file keeps the first one, both named', () async {
    final appState = await freshAppState();
    final first = await makeSourceFile(documentsDir, 'one.mp3');
    final second = await makeSourceFile(documentsDir, 'two.wav');

    await appState.addCustomTone(first.path,
        name: 'First', documentsDirectory: () async => documentsDir);
    await appState.addCustomTone(second.path,
        name: 'Second', documentsDirectory: () async => documentsDir);

    expect(appState.customTones, hasLength(2));
    expect(appState.customTones.map((t) => t.name), ['First', 'Second']);
  });

  test('customTones survives an app restart (persistence round trip)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final first = AppState();
    await first.initialized;
    final source = await makeSourceFile(documentsDir, 'ringtone.wav');

    await first.addCustomTone(
      source.path,
      name: 'Restart Test',
      documentsDirectory: () async => documentsDir,
    );

    final second = AppState();
    await second.initialized;
    expect(second.customTones, hasLength(1));
    expect(second.customTones.single.name, 'Restart Test');
    expect(second.customTones.single.path, 'custom_tones/ringtone.wav');
  });

  test('an unsupported file type propagates and adds nothing', () async {
    final appState = await freshAppState();
    final source = await makeSourceFile(documentsDir, 'not_audio.txt');

    await expectLater(
      appState.addCustomTone(
        source.path,
        name: 'Whatever',
        documentsDirectory: () async => documentsDir,
      ),
      throwsA(isA<UnsupportedToneFormatException>()),
    );

    expect(appState.customTones, isEmpty);
  });
}
