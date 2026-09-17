import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wakeywakey/models/alarms/custom_tone.dart';

// A user-supplied alarm tone (docs/TODO.md T-29 follow-up: the six bundled
// tones turned out to include an unlicensed rip, and letting the user bring
// their own file sidesteps that class of problem entirely - the app then
// isn't distributing anything, the user is).
//
// Two requirements drive this file's shape:
//
// - The imported tone must keep working even after the file the user picked
//   it from is gone (moved, deleted, or the picker only ever granted a
//   transient URI-scoped permission) - so the picked file is copied into the
//   app's own persistent storage immediately, never referenced by its
//   original location.
// - `AlarmSettings.assetAudioPath` (package:alarm) resolves a path that
//   doesn't start with `assets/` or `/` against the app's Documents
//   directory on the native side (see the package's own doc comment and
//   `AudioService.kt`'s `baseAppFlutterPath`) - so the path stored and
//   handed back must be *relative to that directory*, not absolute. An
//   absolute path would also break across an app update, which is exactly
//   what that native-side contract warns against.
void main() {
  late Directory documentsDir;

  setUp(() async {
    documentsDir = await Directory.systemTemp.createTemp('wakeywakey_docs_');
  });

  tearDown(() async {
    if (await documentsDir.exists()) {
      await documentsDir.delete(recursive: true);
    }
  });

  group('isSupportedToneFile', () {
    for (final ext in ['mp3', 'wav', 'm4a', 'aac', 'ogg']) {
      test('accepts .$ext', () {
        expect(isSupportedToneFile('whatever.$ext'), isTrue);
      });

      test('accepts .${ext.toUpperCase()} (case-insensitive)', () {
        expect(isSupportedToneFile('whatever.${ext.toUpperCase()}'), isTrue);
      });
    }

    test('rejects an unsupported extension', () {
      expect(isSupportedToneFile('whatever.txt'), isFalse);
      expect(isSupportedToneFile('whatever.pdf'), isFalse);
      expect(isSupportedToneFile('whatever.exe'), isFalse);
    });

    test('rejects a file with no extension at all', () {
      expect(isSupportedToneFile('whatever'), isFalse);
    });
  });

  group('importCustomTone', () {
    Future<File> makeSourceFile(String name, [String contents = 'fake audio bytes']) async {
      final dir = await Directory.systemTemp.createTemp('wakeywakey_src_');
      final file = File('${dir.path}/$name');
      await file.writeAsString(contents);
      return file;
    }

    test('copies a supported file and returns a documents-relative path',
        () async {
      final source = await makeSourceFile('my_tone.mp3', 'hello world');

      final relativePath = await importCustomTone(
        sourcePath: source.path,
        documentsDirectory: documentsDir,
      );

      expect(relativePath, 'custom_tones/custom_tone.mp3');
      // Not absolute, not asset-prefixed - exactly what
      // AlarmSettings.assetAudioPath needs for an on-device file.
      expect(relativePath.startsWith('/'), isFalse);
      expect(relativePath.startsWith('assets/'), isFalse);

      final copied = File('${documentsDir.path}/$relativePath');
      expect(await copied.exists(), isTrue);
      expect(await copied.readAsString(), 'hello world');
    });

    test('the imported copy survives the original source file being deleted',
        () async {
      final source = await makeSourceFile('my_tone.wav', 'some audio data');

      final relativePath = await importCustomTone(
        sourcePath: source.path,
        documentsDirectory: documentsDir,
      );

      await source.delete();
      expect(await source.exists(), isFalse);

      final copied = File('${documentsDir.path}/$relativePath');
      expect(await copied.exists(), isTrue,
          reason: 'the copy must be independent of the original file');
      expect(await copied.readAsString(), 'some audio data');
    });

    test('rejects an unsupported file type and copies nothing', () async {
      final source = await makeSourceFile('not_audio.txt', 'not audio');

      expect(
        () => importCustomTone(
          sourcePath: source.path,
          documentsDirectory: documentsDir,
        ),
        throwsA(isA<UnsupportedToneFormatException>()),
      );

      final customTonesDir = Directory('${documentsDir.path}/custom_tones');
      expect(await customTonesDir.exists(), isFalse);
    });

    test('re-importing with a different extension removes the previous file',
        () async {
      final firstSource = await makeSourceFile('first.mp3', 'first');
      await importCustomTone(
        sourcePath: firstSource.path,
        documentsDirectory: documentsDir,
      );

      final secondSource = await makeSourceFile('second.wav', 'second');
      final relativePath = await importCustomTone(
        sourcePath: secondSource.path,
        documentsDirectory: documentsDir,
      );

      expect(relativePath, 'custom_tones/custom_tone.wav');
      final customTonesDir = Directory('${documentsDir.path}/custom_tones');
      final remaining = await customTonesDir.list().toList();
      expect(remaining.map((e) => e.path.split('/').last), ['custom_tone.wav'],
          reason: 'no leftover custom_tone.mp3 from the earlier import');
    });

    test('re-importing with the same extension replaces the old content',
        () async {
      final firstSource = await makeSourceFile('first.mp3', 'old content');
      await importCustomTone(
        sourcePath: firstSource.path,
        documentsDirectory: documentsDir,
      );

      final secondSource = await makeSourceFile('second.mp3', 'new content');
      final relativePath = await importCustomTone(
        sourcePath: secondSource.path,
        documentsDirectory: documentsDir,
      );

      final copied = File('${documentsDir.path}/$relativePath');
      expect(await copied.readAsString(), 'new content');
    });

    test('a missing source file propagates a clear filesystem error',
        () async {
      expect(
        () => importCustomTone(
          sourcePath: '/definitely/does/not/exist.mp3',
          documentsDirectory: documentsDir,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
