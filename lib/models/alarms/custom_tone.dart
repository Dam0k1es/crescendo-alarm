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
/// Only one custom tone is kept at a time: re-importing removes whatever
/// `custom_tones/` held before, so a user swapping their tone doesn't leave
/// dead files behind indefinitely.
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
  final ext = sourcePath.substring(sourcePath.lastIndexOf('.') + 1).toLowerCase();
  const subdirectory = 'custom_tones';
  final destinationDir = Directory('${documentsDirectory.path}/$subdirectory');
  final destinationFile = File('${destinationDir.path}/custom_tone.$ext');

  // Read the source before touching the destination directory, so a missing
  // or unreadable source fails loudly instead of leaving a half-replaced
  // custom tone in place.
  final bytes = await sourceFile.readAsBytes();

  if (await destinationDir.exists()) {
    await destinationDir.delete(recursive: true);
  }
  await destinationDir.create(recursive: true);
  await destinationFile.writeAsBytes(bytes);

  return '$subdirectory/custom_tone.$ext';
}

/// Thrown by [importCustomTone] when the picked file's extension isn't one
/// the alarm plugin's native player can be relied on to play.
class UnsupportedToneFormatException implements Exception {
  UnsupportedToneFormatException(this.path);

  final String path;

  @override
  String toString() => 'Unsupported tone file format: $path';
}
