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

import 'dart:io';

/// File extensions the alarm plugin's native player (`android.media.MediaPlayer`
/// on Android) can reliably play. Deliberately a small, well-tested set
/// rather than "whatever `file_picker` will hand back" - an alarm that fails
/// to play its tone is the app's worst possible failure mode.
const supportedCustomToneExtensions = {'mp3', 'wav', 'm4a', 'aac', 'ogg'};

/// Whether [path]'s extension is one [supportedCustomToneExtensions] covers.
bool isSupportedToneFile(String path) {
  final dot = path.lastIndexOf('.');
  if (dot == -1 || dot == path.length - 1) return false;
  final ext = path.substring(dot + 1).toLowerCase();
  return supportedCustomToneExtensions.contains(ext);
}

/// Copies the file at [sourcePath] into a `custom_tones/` subdirectory of
/// [documentsDirectory] and returns the path *relative to that directory*.
///
/// The copy, not a reference to [sourcePath], is what the app ever plays
/// from afterward: the source came from wherever the system file picker
/// pointed at (an SAF URI-backed location, a downloads folder, an SD card),
/// and any of those can disappear or have their access grant revoked
/// independently of the app. A file the app owns in its own sandbox cannot.
///
/// The returned path is relative (never starting with `/` or `assets/`)
/// because that is what `AlarmSettings.assetAudioPath` (package:alarm)
/// requires for an on-device file - its own doc comment, and
/// `AudioService.kt`'s `baseAppFlutterPath` resolution, both key an
/// unprefixed relative path against the app's Documents directory. An
/// absolute path would also break across an app update, per that same
/// contract.
///
/// docs/TODO.md T-56: tones grow as a list - importing a file keeps every
/// tone imported before it, under its own filename (the source file's own
/// name; a numeric suffix is added only if that name is already taken, so
/// two different files picked with the same name don't collide on disk).
///
/// Throws [UnsupportedToneFormatException] if [sourcePath]'s extension isn't
/// in [supportedCustomToneExtensions]. Propagates the underlying
/// [FileSystemException] if [sourcePath] can't be read.
Future<String> importCustomTone({
  required String sourcePath,
  required Directory documentsDirectory,
}) async {
  if (!isSupportedToneFile(sourcePath)) {
    throw UnsupportedToneFormatException(sourcePath);
  }

  final sourceFile = File(sourcePath);
  const subdirectory = 'custom_tones';
  final destinationDir = Directory('${documentsDirectory.path}/$subdirectory');
  final originalName = sourcePath.substring(sourcePath.lastIndexOf('/') + 1);

  // Read the source before touching the destination directory, so a missing
  // or unreadable source fails loudly instead of leaving a half-written file
  // in place.
  final bytes = await sourceFile.readAsBytes();

  await destinationDir.create(recursive: true);
  final destinationFile = await _uniqueFile(destinationDir, originalName);
  await destinationFile.writeAsBytes(bytes);

  return '$subdirectory/${destinationFile.uri.pathSegments.last}';
}

/// The first of `name`, `name (1)`, `name (2)`, … under [dir] that doesn't
/// already exist - so importing a second file that happens to share a name
/// with an earlier import gets its own distinct file instead of overwriting
/// it.
Future<File> _uniqueFile(Directory dir, String name) async {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';

  var candidate = File('${dir.path}/$name');
  var suffix = 1;
  while (await candidate.exists()) {
    candidate = File('${dir.path}/$stem ($suffix)$ext');
    suffix++;
  }
  return candidate;
}

/// Thrown by [importCustomTone] when the picked file's extension isn't one
/// the alarm plugin's native player can be relied on to play.
class UnsupportedToneFormatException implements Exception {
  UnsupportedToneFormatException(this.path);

  final String path;

  @override
  String toString() => 'Unsupported tone file format: $path';
}

/// docs/TODO.md T-56: one user-imported tone - a user-chosen [name] (the
/// dialog that creates one pre-fills it with the picked file's own name,
/// minus its extension, but the user can change it) paired with the
/// documents-relative [path] `importCustomTone` returned for it.
///
/// Plain data, immutable, JSON round-trippable: `AppState` persists a list
/// of these the same way it persists every other value, and `==`/`hashCode`
/// let a `ManualAlarm`'s stored `tone` (still a bare path string, unchanged)
/// be matched back to the [CustomTone] that owns it by comparing [path].
class CustomTone {
  const CustomTone({required this.name, required this.path});

  final String name;
  final String path;

  Map<String, dynamic> toJson() => {'name': name, 'path': path};

  factory CustomTone.fromJson(Map<String, dynamic> json) => CustomTone(
        name: json['name'] as String,
        path: json['path'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is CustomTone && other.name == name && other.path == path;

  @override
  int get hashCode => Object.hash(name, path);

  @override
  String toString() => 'CustomTone(name: $name, path: $path)';
}

/// The sensible starting point for a newly imported tone's display name: the
/// picked file's own name, without its extension - so the user only has to
/// change it if the filename isn't already a good enough label, rather than
/// type a name from scratch every time.
String defaultCustomToneName(String sourcePath) {
  final base = sourcePath.substring(sourcePath.lastIndexOf('/') + 1);
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}
