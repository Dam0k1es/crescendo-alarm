import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/utils/media_credits.dart';

// docs/TODO.md T-213 (G4): media licences were prose nobody checked - which
// is how six non-free Mixkit tones passed as "free" (T-212). Each media
// directory's CREDITS.md now carries one table with a fixed header and an
// SPDX licence id per file; the app shows those rows as licence notices
// (lib/utils/licence_notices.dart), and this test makes the table complete.
//
// A credit row names a file, not its content: a different MP3 under the same
// name would pass a name-only check (audit of 2026-10-05). Each CREDITS.md
// therefore also carries a `| File | SHA-256 |` table, and the test compares
// every file's actual hash with it - replacing a file means re-checking its
// credit row and recording the new hash. (`scripts/gen_tones.py` regenerates
// `lollipop.mp3` byte-identically, so its hash is stable.)

const _hashHeader = '| File | SHA-256 |';

/// FIPS 180-4 SHA-256, here so the test needs no package beyond the SDK
/// (`package:crypto` is only a transitive dependency). Checked against the
/// standard test vectors below.
String _sha256Hex(List<int> message) {
  const k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
  final h = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  final bitLength = message.length * 8;
  final padded = BytesBuilder(copy: false)
    ..add(message)
    ..addByte(0x80);
  while ((padded.length + 8) % 64 != 0) {
    padded.addByte(0);
  }
  final lengthBytes = ByteData(8)..setUint64(0, bitLength);
  padded.add(lengthBytes.buffer.asUint8List());
  final data = ByteData.sublistView(padded.toBytes());

  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;
  final w = List<int>.filled(64, 0);
  for (var chunk = 0; chunk < data.lengthInBytes; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = data.getUint32(chunk + i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ (~e & 0xffffffff & g);
      final t1 = (hh + s1 + ch + k[i] + w[i]) & 0xffffffff;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    h[0] = (h[0] + a) & 0xffffffff;
    h[1] = (h[1] + b) & 0xffffffff;
    h[2] = (h[2] + c) & 0xffffffff;
    h[3] = (h[3] + d) & 0xffffffff;
    h[4] = (h[4] + e) & 0xffffffff;
    h[5] = (h[5] + f) & 0xffffffff;
    h[6] = (h[6] + g) & 0xffffffff;
    h[7] = (h[7] + hh) & 0xffffffff;
  }
  return h.map((v) => v.toRadixString(16).padLeft(8, '0')).join();
}

/// The `file -> sha256` rows of the `| File | SHA-256 |` table in [text].
/// Throws on a malformed row instead of skipping it.
Map<String, String> _parseHashTable(String text) {
  final lines = text.split('\n');
  final start = lines.indexWhere((l) => l.trim() == _hashHeader);
  if (start < 0) return {};
  final hashes = <String, String>{};
  for (final line in lines.skip(start + 2)) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('|')) break;
    final cells = trimmed
        .substring(1, trimmed.length - 1)
        .split('|')
        .map((c) => c.trim().replaceAll('`', ''))
        .toList();
    if (cells.length != 2 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(cells[1])) {
      throw FormatException('malformed SHA-256 row: $line');
    }
    if (hashes.containsKey(cells[0])) {
      throw FormatException('duplicate SHA-256 row for ${cells[0]}');
    }
    hashes[cells[0]] = cells[1];
  }
  return hashes;
}

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
      expect(
          parseMediaCredits('| File | Title |\n|---|---|\n| a | b |'), isEmpty);
    });

    test('a malformed row is an error, not silently dropped', () {
      expect(
          () => parseMediaCredits('$mediaCreditsHeader\n|---|---|---|---|---|'
              '---|\n| `a.mp3` | t | a | s | CC0-1.0 |'),
          throwsFormatException);
    });

    test('the SHA-256 helper matches the FIPS 180-4 test vectors', () {
      expect(_sha256Hex([]),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(_sha256Hex('abc'.codeUnits),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(
          _sha256Hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'
              .codeUnits),
          '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
      expect(_sha256Hex(List<int>.filled(1000000, 0x61)),
          'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
    });

    test('the SHA-256 table is read, and a malformed hash is an error', () {
      final table = '$_hashHeader\n|---|---|\n'
          '| `a.mp3` | `${'0' * 64}` |\n| `b.png` | `${'f' * 64}` |\n\nprose';
      expect(_parseHashTable(table), {'a.mp3': '0' * 64, 'b.png': 'f' * 64});
      expect(
          () => _parseHashTable('$_hashHeader\n|---|---|\n| `a.mp3` | abc |'),
          throwsFormatException);
      expect(
          _parseHashTable('| File | Title |\n|---|---|\n| a | b |'), isEmpty);
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

    test('$dir/CREDITS.md records the SHA-256 of exactly the files shipped',
        () {
      final hashes =
          _parseHashTable(File('$dir/CREDITS.md').readAsStringSync());
      final files = Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last != 'CREDITS.md')
          .toList();
      expect(files, isNotEmpty);

      final problems = <String>[];
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        final actual = _sha256Hex(f.readAsBytesSync());
        final recorded = hashes[name];
        if (recorded == null) {
          problems.add('$name: no SHA-256 row (actual $actual)');
        } else if (recorded != actual) {
          problems.add('$name: recorded $recorded, actual $actual - the file '
              'changed; re-check its credit row, then record the new hash');
        }
      }
      final names = files.map((f) => f.uri.pathSegments.last).toSet();
      for (final name in hashes.keys) {
        if (!names.contains(name)) {
          problems.add('$name: hash recorded, but no such file in $dir');
        }
      }
      expect(problems, isEmpty,
          reason: '$dir/CREDITS.md ("$_hashHeader" table):\n'
              '${problems.join('\n')}');
    });
  }
}
