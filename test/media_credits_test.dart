import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/utils/media_credits.dart';

// docs/TODO.md T-213 (G4): media licences were prose nobody checked - which
// is how six non-free Mixkit tones passed as "free" (T-212). Each media
// directory's CREDITS.md now carries one table with a fixed header and an
// SPDX licence id per file; the app shows those rows as licence notices
// (lib/utils/licence_notices.dart), and this test makes the table complete.

const _fixture = '''
# Sound credits

Some prose that must be ignored, including a | pipe |.

| File | Title | Author | Source | Licence | Changes |
|---|---|---|---|---|---|
| `wake_up.mp3` | Morning bell | Jane Example | [freesound #1](https://freesound.org/s/1/) | CC-BY-4.0 | trimmed to 20 s |
| `rooster.mp3` | Rooster | <https://example.org/u> | https://example.org/r | CC0-1.0 | - |

## Afterwards

| Other | table |
|---|---|
| `ignored.mp3` | x |
''';

void main() {
  group('parseMediaCredits', () {
    test('reads the rows under the exact header, and only those', () {
      final rows = parseMediaCredits(_fixture);
      expect(rows.map((r) => r.file), ['wake_up.mp3', 'rooster.mp3']);
      final first = rows.first;
      expect(first.title, 'Morning bell');
      expect(first.author, 'Jane Example');
      expect(first.source, 'freesound #1 (https://freesound.org/s/1/)');
      expect(first.licence, 'CC-BY-4.0');
      expect(first.changes, 'trimmed to 20 s');
      expect(rows.last.author, 'https://example.org/u');
    });

    test('a file without the header yields no rows', () {
      expect(parseMediaCredits('| File | Title |\n|---|---|\n| a | b |'),
          isEmpty);
    });

    test('a malformed row is an error, not silently dropped', () {
      expect(
          () => parseMediaCredits('$mediaCreditsHeader\n|---|---|---|---|---|'
              '---|\n| `a.mp3` | t | a | s | CC0-1.0 |'),
          throwsFormatException);
    });

    test('every allowed licence has a canonical URL', () {
      for (final id in allowedMediaLicences) {
        expect(mediaLicenceUrl(id), startsWith('https://'), reason: id);
      }
      expect(mediaLicenceUrl('Mixkit'), isNull);
    });
  });

  for (final dir in ['assets/sounds', 'assets/icons']) {
    test('$dir/CREDITS.md has exactly one row with a free licence per file',
        () {
      final credits = File('$dir/CREDITS.md');
      expect(credits.existsSync(), isTrue, reason: '$dir has no CREDITS.md');
      final rows = parseMediaCredits(credits.readAsStringSync());
      final files = Directory(dir)
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((name) => name != 'CREDITS.md')
          .toList()
        ..sort();
      expect(files, isNotEmpty);

      final problems = <String>[];
      for (final file in files) {
        final matching = rows.where((r) => r.file == file).toList();
        if (matching.length != 1) {
          problems.add('$file: ${matching.length} rows (need exactly 1)');
        } else if (!allowedMediaLicences.contains(matching.single.licence)) {
          problems.add('$file: licence "${matching.single.licence}" is not '
              'one of $allowedMediaLicences');
        }
      }
      for (final row in rows) {
        if (!files.contains(row.file)) {
          problems.add('${row.file}: credited, but no such file in $dir');
        }
      }
      expect(problems, isEmpty,
          reason: '$dir/CREDITS.md (header must be exactly '
              '"$mediaCreditsHeader"):\n${problems.join('\n')}');
    });
  }
}
