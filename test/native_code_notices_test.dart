import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// docs/TODO.md T-213 (G5): assets/text/NativeCodeNotices.txt is written by
// hand, and that is how libzueci (BSD-3-Clause) and Bjoern Hoehrmann's UTF-8
// decoder (MIT) went missing from it while both were compiled into
// libflutter_zxing.so (audit findings N1/N2). This test reads what the
// resolved flutter_zxing's CMake actually compiles - located through
// .dart_tool/package_config.json, so a version bump is followed
// automatically - and checks the notices against it:
//
//   * every vendored third-party library directory (`src/lib*`) is named;
//   * every copyright holder found in a compiled source file, or in a header
//     it includes, is named.
//
// The second rule is what catches code embedded inside another library's
// files (Hoehrmann's decoder inside zueci.c and Utf.cpp, Project Nayuki's
// MIT code inside zint's qr.c, the Arimo/OCR-B font data inside zint's
// fonts/*.h), which no directory listing shows.

Uri _packageRoot(String name) {
  final config = jsonDecode(
          File('.dart_tool/package_config.json').readAsStringSync())
      as Map<String, dynamic>;
  final entry = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((p) => p['name'] == name);
  final root = entry['rootUri'] as String;
  final base = Uri.file('${Directory.current.path}/.dart_tool/');
  final resolved = base.resolve(root.endsWith('/') ? root : '$root/');
  return resolved;
}

String _notices() =>
    File('assets/text/NativeCodeNotices.txt').readAsStringSync();

/// flutter_zxing's own CMakeLists adds zxing-cpp's core with
/// `add_subdirectory(<dir>)`; that core CMakeLists lists every compiled file.
Directory _coreDir() {
  final src = Directory.fromUri(_packageRoot('flutter_zxing').resolve('src/'));
  final top = File('${src.path}/CMakeLists.txt').readAsStringSync();
  final sub = RegExp(r'add_subdirectory\s*\(\s*([^\s)]+)').firstMatch(top);
  expect(sub, isNotNull, reason: 'flutter_zxing no longer adds zxing-cpp');
  return Directory('${src.path}/${sub!.group(1)}');
}

Set<String> _cmakeSourceFiles(Directory core) {
  final cmake = File('${core.path}/CMakeLists.txt').readAsStringSync();
  return RegExp(r'(src/[A-Za-z0-9_./-]+\.(?:c|cpp|h))')
      .allMatches(cmake)
      .map((m) => m.group(1)!)
      .toSet();
}

/// Every compiled file plus every local header it includes, transitively.
/// zxing-cpp's libzint/ files are thin wrappers that `#include` the real
/// zint sources from `../../../zint/backend/`, so following includes is what
/// reaches zint's actual code and its embedded font data.
Set<String> _compiledFilesWithIncludes(Directory core) {
  final includeDirs = ['${core.path}/src', '${core.path}/src/libzint'];
  final seen = <String>{};
  final todo = _cmakeSourceFiles(core)
      .map((f) => File('${core.path}/$f').absolute.path)
      .toList();
  final include = RegExp(r'#\s*include\s+"([^"]+)"');
  while (todo.isNotEmpty) {
    final path = File(todo.removeLast()).absolute.uri.normalizePath().path;
    if (seen.contains(path) || !File(path).existsSync()) continue;
    seen.add(path);
    final text = File(path).readAsStringSync(encoding: latin1);
    for (final m in include.allMatches(text)) {
      for (final dir in [File(path).parent.path, ...includeDirs]) {
        final candidate = File('$dir/${m.group(1)}');
        if (candidate.existsSync()) {
          todo.add(candidate.absolute.uri.normalizePath().path);
          break;
        }
      }
    }
  }
  return seen;
}

/// The holder named on a `Copyright ...` line, without years, e-mail
/// addresses, "(c)" and trailing punctuation.
String? _holder(String line) {
  final m = RegExp(r'^[\s/*#"]*(?:Portions\s+)?Copyright\s+(?:\(c\)\s*)?(.*)$',
          caseSensitive: false)
      .firstMatch(line);
  if (m == null) return null;
  var h = m.group(1)!;
  h = h.replaceAll(RegExp(r'<[^>]*>'), '');
  h = h.replaceAll(RegExp(r'\(MIT License\)'), '');
  h = h.replaceAll(RegExp(r'\(?\b\d{4}\b(\s*-\s*\d{4})?\)?[,;]?'), '');
  h = h.replaceAll(RegExp(r'\s+'), ' ').trim();
  h = h.replaceAll(RegExp(r'^[.;,\s]+|[.;,\s]+$'), '');
  // "subsists in all BSI publications" and similar prose are not holders.
  if (h.isEmpty || h.toLowerCase().startsWith('subsists')) return null;
  return h;
}

void main() {
  late Directory core;
  late Set<String> compiled;

  setUpAll(() {
    core = _coreDir();
    compiled = _compiledFilesWithIncludes(core);
  });

  test('the CMake parser sees what flutter_zxing really compiles', () {
    // Counter-test: an empty parse would make every rule below pass.
    expect(compiled.length, greaterThan(100));
    expect(compiled.any((p) => p.endsWith('/libzueci/zueci.c')), isTrue);
    expect(compiled.any((p) => p.endsWith('/zint/backend/qr.c')), isTrue,
        reason: 'the libzint wrappers were not followed into zint/backend');
    expect(_holder('    Copyright (C) 2009-2025 Robin Stuart <r@x.com>'),
        'Robin Stuart');
    expect(_holder('        Copyright (c) 2008-2009 Bjoern Hoehrmann <b@h>'),
        'Bjoern Hoehrmann');
    expect(_holder(' * Copyright (c) Project Nayuki. (MIT License)'),
        'Project Nayuki');
    expect(_holder('    2. Redistributions ... the above copyright'), isNull);
  });

  test('every vendored third-party library CMake compiles is named', () {
    final libraries = _cmakeSourceFiles(core)
        .map((f) => f.split('/')[1])
        .where((segment) => segment.startsWith('lib'))
        .toSet();
    expect(libraries, isNotEmpty);
    final notices = _notices();
    final missing = libraries.where((l) => !notices.contains(l)).toList();
    expect(missing, isEmpty,
        reason: 'compiled into libflutter_zxing.so but not named in '
            'assets/text/NativeCodeNotices.txt: $missing');
  });

  test('every copyright holder in the compiled sources is named', () {
    final notices = _notices();
    final missing = <String, String>{};
    for (final path in compiled) {
      for (final line
          in File(path).readAsLinesSync(encoding: latin1)) {
        final holder = _holder(line);
        if (holder == null) continue;
        // "Matthew Skala; based on code by Norbert Schwarz" names two.
        for (final name in holder.split(RegExp(r'\s*based on code by\s*'))) {
          final utf8Name = _tryUtf8(name);
          if (!notices.contains(utf8Name)) {
            missing[utf8Name] = path.substring(core.parent.path.length);
          }
        }
      }
    }
    expect(missing, isEmpty,
        reason: 'copyright holders in compiled flutter_zxing sources that '
            'assets/text/NativeCodeNotices.txt does not name: $missing');
  });
}

/// Source files are read as Latin-1 so a stray byte cannot throw; a holder
/// like "Antoine Mérino" is UTF-8 in the file, so decode it back for the
/// comparison against the (UTF-8) notices asset.
String _tryUtf8(String latin1Text) {
  try {
    return utf8.decode(latin1.encode(latin1Text));
  } on FormatException {
    return latin1Text;
  }
}
