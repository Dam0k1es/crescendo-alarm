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

/// docs/TODO.md T-213: the credits of the bundled media (assets/icons/,
/// assets/sounds/), read from each directory's CREDITS.md.
///
/// Each CREDITS.md carries one Markdown table with exactly
/// [mediaCreditsHeader] as its header and one row per file, whose Licence
/// cell is an SPDX id from [allowedMediaLicences]. The same parser serves the
/// app (the rows become licence notices, lib/utils/licence_notices.dart) and
/// test/media_credits_test.dart, which requires one valid row per file - so
/// what the About page shows and what the check verifies cannot diverge.
library;

const mediaCreditsHeader =
    '| File | Title | Author | Source | Licence | Changes |';

/// Free-culture licences acceptable for media inside a GPLv3 app
/// (docs/licence-position.md). Each has an entry in [_licenceUrls].
const allowedMediaLicences = <String>{
  'CC0-1.0',
  'CC-BY-3.0',
  'CC-BY-4.0',
  'CC-BY-SA-3.0',
  'CC-BY-SA-4.0',
  'GPL-3.0-or-later',
  'LicenseRef-PublicDomain',
};

const _licenceUrls = <String, String>{
  'CC0-1.0': 'https://creativecommons.org/publicdomain/zero/1.0/',
  'CC-BY-3.0': 'https://creativecommons.org/licenses/by/3.0/',
  'CC-BY-4.0': 'https://creativecommons.org/licenses/by/4.0/',
  'CC-BY-SA-3.0': 'https://creativecommons.org/licenses/by-sa/3.0/',
  'CC-BY-SA-4.0': 'https://creativecommons.org/licenses/by-sa/4.0/',
  'GPL-3.0-or-later': 'https://www.gnu.org/licenses/gpl-3.0.html',
  'LicenseRef-PublicDomain':
      'https://creativecommons.org/publicdomain/mark/1.0/',
};

/// The canonical URL of an allowed licence, or null for any other id.
String? mediaLicenceUrl(String spdxId) => _licenceUrls[spdxId];

class MediaCredit {
  const MediaCredit(this.file, this.title, this.author, this.source,
      this.licence, this.changes);

  /// The file name inside the media directory, without backticks.
  final String file;
  final String title;
  final String author;
  final String source;

  /// An SPDX licence id (not validated here - see [allowedMediaLicences]).
  final String licence;
  final String changes;
}

/// The rows of the table headed by [mediaCreditsHeader], with Markdown code
/// spans and links reduced to plain text. Other tables and prose are
/// ignored; a file without that header yields no rows. A row with the wrong
/// number of cells throws a [FormatException] rather than being dropped.
List<MediaCredit> parseMediaCredits(String markdown) {
  final lines = markdown.split('\n').map((l) => l.trimRight()).toList();
  final header = lines.indexOf(mediaCreditsHeader);
  if (header < 0) return const [];

  final rows = <MediaCredit>[];
  // header + 1 is the |---|---| separator line.
  for (var i = header + 2; i < lines.length; i++) {
    final line = lines[i].trim();
    if (!line.startsWith('|')) break;
    final cells = line
        .substring(1, line.endsWith('|') ? line.length - 1 : line.length)
        .split('|')
        .map((c) => _plain(c.trim()))
        .toList();
    if (cells.length != 6) {
      throw FormatException(
          'CREDITS.md line ${i + 1} has ${cells.length} cells, expected 6');
    }
    rows.add(MediaCredit(
        cells[0], cells[1], cells[2], cells[3], cells[4], cells[5]));
  }
  return rows;
}

String _plain(String cell) => cell
    .replaceAll('`', '')
    .replaceAllMapped(
        RegExp(r'\[([^\]]*)\]\(([^)]*)\)'), (m) => '${m[1]} (${m[2]})')
    .replaceAllMapped(RegExp(r'<(https?://[^>]*)>'), (m) => m[1]!);
