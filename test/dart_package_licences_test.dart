// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of Crescendo Alarm.
//
// Crescendo Alarm is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Crescendo Alarm is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Crescendo Alarm. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Audit L1-08: test/no_proprietary_dependencies_test.dart is a name blocklist -
// it cannot tell that a NEW package arrives under a licence GPLv3 cannot
// absorb. This reads the LICENSE file of every Dart package the app resolves,
// classifies its text, and fails on copyleft that is not GPLv3-compatible
// or on anything it cannot classify, until a human has reviewed that package
// and entered it below with its SPDX id. A dependency bump that changes a
// licence therefore stops here instead of shipping.

/// Text signatures, most specific first. A file can match several (a package
/// bundling third-party code); every match must be permissive.
final _signatures = <String, RegExp>{
  'Apache-2.0': RegExp(r'Apache License\s+Version 2\.0', caseSensitive: false),
  'MPL-2.0': RegExp(r'Mozilla Public License,? (Version|v\.?) ?2\.0', caseSensitive: false),
  'MIT': RegExp(r'Permission is hereby granted, free of charge'),
  'BSD-3-Clause': RegExp(r'Redistribution and use in source and binary forms[\s\S]{0,1200}Neither the name', caseSensitive: false),
  'BSD-2-Clause': RegExp(r'Redistribution and use in source and binary forms', caseSensitive: false),
  'ISC': RegExp(r'Permission to use, copy, modify, and(/or)? distribute this software for any purpose', caseSensitive: false),
  'Zlib': RegExp(r'This software is provided .as-is.[\s\S]{0,400}altered source versions', caseSensitive: false),
  'Unlicense': RegExp(r'This is free and unencumbered software released into the public domain', caseSensitive: false),
};

/// Not permissive: needs a human decision whatever else the file says.
final _flagged = <String, RegExp>{
  'GPL/LGPL/AGPL': RegExp(r'GNU (Affero |Lesser |Library )?General Public License', caseSensitive: false),
  'proprietary/commercial': RegExp(r'\b(proprietary|commercial licen[cs]e|all rights reserved\.? no)', caseSensitive: false),
  'non-commercial': RegExp(r'non-?commercial|NonCommercial', caseSensitive: false),
  'Creative Commons': RegExp(r'Creative Commons', caseSensitive: false),
};

/// Reviewed by hand: package -> SPDX expression and why. Only for what the
/// signatures above cannot classify.
const _reviewed = <String, String>{
  // Flutter SDK packages: licensed like Flutter itself (BSD-3-Clause, the
  // LICENSE at the SDK root, reproduced by Flutter's own licence page under
  // About > Third-Party Licenses). Test/driver/web-only ones ship nothing in
  // the Android APK.
  'flutter_driver': 'BSD-3-Clause (Flutter SDK; test-only)',
  'flutter_test': 'BSD-3-Clause (Flutter SDK; test-only)',
  'flutter_web_plugins': 'BSD-3-Clause (Flutter SDK; web-only)',
  'fuchsia_remote_debug_protocol': 'BSD-3-Clause (Flutter SDK; tooling-only)',
  'integration_test': 'BSD-3-Clause (Flutter SDK; test-only)',
  // The Flutter engine's own package: its LICENSE is the engine's bundle of
  // third-party notices (FreeType, BSD/MIT code, the CC0 Ahem test font, ...),
  // which Flutter's licence page reproduces for the app.
  'sky_engine': 'BSD-3-Clause AND bundled engine notices (Flutter SDK)',
};

const _licenceFiles = [
  'LICENSE', 'LICENSE.md', 'LICENSE.txt', 'LICENCE', 'LICENCE.md', 'COPYING',
  'license', 'License', 'license.md', 'LICENSE-MIT', 'LICENSE.rst',
];

String? _licenceText(Directory root) {
  for (final name in _licenceFiles) {
    final f = File('${root.path}/$name');
    if (f.existsSync()) return f.readAsStringSync();
  }
  return null;
}

void main() {
  test('every resolved Dart package has a licence GPLv3 can absorb', () {
    final config = jsonDecode(
            File('.dart_tool/package_config.json').readAsStringSync())
        as Map<String, dynamic>;
    final lock = File('pubspec.lock').readAsStringSync();
    // Packages that are really resolved (not the flutter SDK's own).
    final names = RegExp(r'^  (\w+):$', multiLine: true)
        .allMatches(lock)
        .map((m) => m.group(1)!)
        .toSet();

    final problems = <String>[];
    final table = <String, String>{};
    for (final p in (config['packages'] as List).cast<Map<String, dynamic>>()) {
      final name = p['name'] as String;
      if (!names.contains(name)) continue;
      final root = Directory.fromUri(
          Uri.file('${Directory.current.path}/.dart_tool/')
              .resolve((p['rootUri'] as String).endsWith('/')
                  ? p['rootUri'] as String
                  : '${p['rootUri']}/'));
      final text = _licenceText(root);
      if (_reviewed.containsKey(name)) {
        table[name] = _reviewed[name]!;
        continue;
      }
      if (text == null) {
        problems.add('$name: no licence file found');
        continue;
      }
      final ids = _signatures.entries.where((e) => e.value.hasMatch(text)).map((e) => e.key).toList();
      final flags = _flagged.entries
          .where((e) => e.value.hasMatch(text))
          // MPL-2.0 (GPLv3-compatible, section 3.3) defines "Secondary
          // License" as the GPL family - that mention is its own text.
          .where((e) => !(ids.contains('MPL-2.0') && e.key == 'GPL/LGPL/AGPL'))
          .map((e) => e.key);
      if (flags.isNotEmpty) {
        problems.add('$name: mentions ${flags.join(", ")} - review and list it');
        continue;
      }
      if (ids.isEmpty) {
        problems.add('$name: licence text not recognised - review and list it');
        continue;
      }
      table[name] = ids.join(' + ');
    }

    expect(table.length, greaterThan(100),
        reason: 'expected to inspect the whole dependency tree');
    expect(problems, isEmpty,
        reason: 'review these licences against GPLv3 (docs/licence-position.md):\n${problems.join('\n')}');
    // The table is the evidence; print it for the audit record.
    // ignore: avoid_print
    print(table.entries.map((e) => '${e.key}: ${e.value}').join('\n'));
  });
}
