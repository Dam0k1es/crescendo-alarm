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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:crescendo_alarm/utils/media_credits.dart';

/// docs/TODO.md T-213: licence notices that Flutter's own collector cannot
/// find, registered with [LicenseRegistry] so they appear in the one list
/// the About page's "Third-Party Licenses" already shows.
///
/// Flutter's collector reads only each Dart package's root LICENSE file. It
/// misses: the C/C++ that flutter_zxing compiles into the app (T-142); the
/// Material Icons font, which Flutter bundles under CC-BY-4.0; the
/// Java/Kotlin libraries Gradle adds (AndroidX, Kotlin, desugar_jdk_libs,
/// ...); the extra notices `archive`, `image` and `mime` keep outside their
/// LICENSE file although that code ships (their codecs and mime table
/// survive tree-shaking in the release `libapp.so`); and the credits of the
/// app's own media (assets/icons/, assets/sounds/).
///
/// Every text is a bundled asset (pubspec.yaml), loaded lazily: the
/// collector runs only when the licence page is opened. One asset that
/// fails to load is skipped instead of breaking the whole licence page;
/// test/licence_notices_test.dart checks that every entry is present.
void registerAppLicences() {
  LicenseRegistry.addLicense(() => _collect(rootBundle));
}

const _materialIconsPreface =
    'The Material Icons font (MaterialIcons-Regular.otf) by Google, bundled '
    'by Flutter, is licensed under the Creative Commons Attribution 4.0 '
    'International licence (CC BY 4.0), '
    'https://creativecommons.org/licenses/by/4.0/. Changes: at build time '
    'the font is reduced to the icons this app uses. The licence text '
    'follows.';

const _desugarPreface =
    'desugar_jdk_libs (com.android.tools:desugar_jdk_libs) - a subset of '
    'the OpenJDK class library, compiled into this app to provide java.time '
    'and related classes on older Android versions. Licensed under the GNU '
    'General Public License, version 2, with the Classpath Exception. The '
    'source code is published at https://github.com/google/desugar_jdk_libs '
    '(the version is listed under "Android libraries (Java/Kotlin)"). The '
    'licence text follows, as shipped with OpenJDK.';

const _protobufPreface =
    'Protocol Buffers runtime, repackaged by AndroidX as '
    'androidx.datastore:datastore-preferences-external-protobuf. Licensed '
    'under the 3-clause BSD licence:';

const _otherPreface = 'Additional notices for code this package derived '
    'from other projects (kept outside its LICENSE file):';

/// (packages, asset, preface). A package name equal to a Dart package's
/// name (flutter_zxing, archive, image, mime) adds to that package's entry
/// in the list instead of creating a new one.
const _textNotices = <(List<String>, String, String?)>[
  (['flutter_zxing'], 'assets/text/NativeCodeNotices.txt', null),
  (
    ['Material Icons'],
    'assets/text/licences/MaterialIcons_LICENSE.txt',
    _materialIconsPreface
  ),
  (
    ['Android libraries (Java/Kotlin)'],
    'assets/text/licences/AndroidLibraries.txt',
    null
  ),
  (
    ['desugar_jdk_libs'],
    'assets/text/licences/GPL-2.0-with-classpath-exception.txt',
    _desugarPreface
  ),
  (
    ['Protocol Buffers'],
    'assets/text/licences/protobuf_LICENSE.txt',
    _protobufPreface
  ),
  (['archive'], 'assets/text/licences/archive_LICENSE-other.md', _otherPreface),
  (['image'], 'assets/text/licences/image_LICENSE-other.md', _otherPreface),
  (
    ['mime'],
    'assets/text/licences/mime_httpd_LICENSE.txt',
    'The mime type table is derived from the Apache httpd project '
        '(https://github.com/apache/httpd), licensed under the Apache '
        'License 2.0:'
  ),
];

const _mediaNotices = <(String, String)>[
  ('Crescendo Alarm app icon', 'assets/icons/CREDITS.md'),
  ('Crescendo Alarm alarm tones', 'assets/sounds/CREDITS.md'),
];

Stream<LicenseEntry> _collect(AssetBundle bundle) async* {
  for (final (packages, asset, preface) in _textNotices) {
    final text = await _load(bundle, asset);
    if (text == null) continue;
    yield LicenseEntryWithLineBreaks(
        packages, preface == null ? text : '$preface\n\n$text');
  }
  for (final (package, asset) in _mediaNotices) {
    final markdown = await _load(bundle, asset);
    if (markdown == null) continue;
    yield LicenseEntryWithLineBreaks([package], mediaCreditsText(markdown));
  }
}

Future<String?> _load(AssetBundle bundle, String asset) async {
  try {
    // cache: false - licence texts are read once, when the page opens.
    return (await bundle.loadString(asset, cache: false))
        .replaceAll('\r\n', '\n');
  } on Object {
    return null;
  }
}

/// A CREDITS.md as plain-text notice paragraphs: one per credited file,
/// with the licence's URL. Falls back to the raw file when it has no
/// credits table yet (or a malformed one), so nothing is hidden.
@visibleForTesting
String mediaCreditsText(String markdown) {
  List<MediaCredit> rows;
  try {
    rows = parseMediaCredits(markdown);
  } on FormatException {
    rows = const [];
  }
  if (rows.isEmpty) return markdown;
  return rows.map((r) {
    final url = mediaLicenceUrl(r.licence);
    final licence = url == null ? r.licence : '${r.licence} ($url)';
    final changes =
        r.changes.isEmpty || r.changes == '-' ? 'none' : r.changes;
    return '${r.file}: "${r.title}" by ${r.author}. Source: ${r.source}. '
        'Licence: $licence. Changes: $changes.';
  }).join('\n\n');
}
