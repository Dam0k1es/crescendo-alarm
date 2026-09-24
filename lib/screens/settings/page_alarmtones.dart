// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of WakeyWakey.
//
// WakeyWakey is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// WakeyWakey is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with WakeyWakey. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/alarms/custom_tone.dart';
import 'package:wakeywakey/models/scheduling/checkpoint.dart';
import 'package:wakeywakey/utils/utils.dart';

class PageAlarmTones extends StatefulWidget {
  const PageAlarmTones({super.key});

  @override
  State<PageAlarmTones> createState() => _PageAlarmTonesState();
}

class _PageAlarmTonesState extends State<PageAlarmTones> {
  AudioPlayer? _audioPlayer;
  Timer? _timer;
  String? _currentlyPlaying;
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = Provider.of<AppState>(context, listen: false);
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _playOrStopAudio(String path) async {
    if (_currentlyPlaying == path) {
      _stopAudio();
    } else {
      await _stopAudio();
      _audioPlayer = AudioPlayer();
      try {
        // Not really system volume, but saves us a library
        _audioPlayer?.setVolume(_appState.selectedVolume);
        await _audioPlayer!.setSource(await _sourceFor(path));
        await _audioPlayer!.resume();
        _currentlyPlaying = path;
        _timer = Timer(const Duration(seconds: 10), () {
          _stopAudio();
        });
      } catch (e) {
        debugPrint("Error playing audio: ${e.runtimeType}");
      }
    }
  }

  /// Bundled tones are Flutter assets; an imported custom tone is a real
  /// file the app copied into its own Documents directory (see
  /// `custom_tone.dart`) - `audioplayers` needs a different `Source` for
  /// each, unlike the alarm plugin, which resolves both forms of [path]
  /// itself (see `AppState._setAlarm`'s doc comment on `assetAudioPath`).
  Future<Source> _sourceFor(String path) async {
    if (path.startsWith('assets/')) {
      return AssetSource(path.replaceFirst('assets/', ''));
    }
    final documentsDir = await getApplicationDocumentsDirectory();
    return DeviceFileSource('${documentsDir.path}/$path');
  }

  Future<void> _stopAudio() async {
    await _audioPlayer?.stop();
    _audioPlayer?.dispose();
    _audioPlayer = null;
    _timer?.cancel();
    setState(() {
      _currentlyPlaying = null;
    });
  }

  /// Opens the system file picker (Storage Access Framework on Android - no
  /// declared permission needed, and none is requested until the user
  /// actually taps this) restricted to [supportedCustomToneExtensions], asks
  /// the user to name it (docs/TODO.md T-56), then imports whatever was
  /// picked under that name.
  Future<void> _pickCustomTone() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: supportedCustomToneExtensions.toList(),
    );
    final pickedPath = picked?.path;
    if (pickedPath == null) return; // user cancelled

    if (!mounted) return;
    final name = await _promptForToneName(defaultCustomToneName(pickedPath));
    if (name == null) return; // user cancelled the naming dialog

    if (!mounted) return;
    try {
      await _appState.addCustomTone(pickedPath, name: name);
      if (!mounted) return;
      displayToast(context, 'Custom tone imported.');
    } on UnsupportedToneFormatException {
      if (!mounted) return;
      displayToast(context, 'Unsupported file type.');
    } catch (e) {
      debugPrint("Error importing custom tone: ${e.runtimeType}");
      if (!mounted) return;
      displayToast(context, 'Could not import that file.');
    }
  }

  /// Pre-filled with [defaultName] (the picked file's own name, minus its
  /// extension) so most imports need no typing at all - the user only has
  /// to change it if that name isn't already a good enough label. Returns
  /// `null` on Cancel, which [_pickCustomTone] takes as "import nothing"
  /// rather than adding an unnamed entry.
  Future<String?> _promptForToneName(String defaultName) async {
    final controller = TextEditingController(text: defaultName);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name this tone'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(
                controller.text.trim().isEmpty
                    ? defaultName
                    : controller.text.trim()),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Alarm Tones',
          style: TextStyle(fontSize: 24),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildToggle(context, 'Annoying Alarm',
                  'assets/sounds/annoying_alarm.mp3'),
              const SizedBox(height: 16.0),
              _buildToggle(context, 'LolliPop', 'assets/sounds/lollipop.mp3'),
              const SizedBox(height: 16.0),
              _buildToggle(context, 'Old Telephone',
                  'assets/sounds/old_telephone_ring.mp3'),
              const SizedBox(height: 16.0),
              _buildToggle(context, 'Wake UP', 'assets/sounds/wake_up.mp3'),
              const SizedBox(height: 16.0),
              _buildToggle(
                  context, 'WakeyWakey', 'assets/sounds/wakeywakey.mp3'),
              const SizedBox(height: 16.0),
              _buildToggle(
                  context, 'WakeyWakey 2', 'assets/sounds/wakeywakey2.mp3'),
              const SizedBox(height: 16.0),
              _buildCustomToneSection(context),
              const SizedBox(height: 32.0),
              _buildVolumeSlider(context),
              const SizedBox(height: 16.0),
              _buildVibrationToggle(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggle(BuildContext context, String tone, String path) {
    return GestureDetector(
      onTap: () {
        _playOrStopAudio(path);
      },
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tone,
                style: const TextStyle(
                  fontSize: 18.0,
                ),
              ),
              Switch(
                value: _appState.selectedTone == path,
                onChanged: (value) {
                  if (value) {
                    _appState.selectedTone = path;
                    // docs/TODO.md T-84: planned alarms carry the tone as
                    // their own property - without a checkpoint the change
                    // would only take effect once a day gets replanned
                    // anyway (so possibly never).
                    runCheckpointSafely(_appState,
                        trigger: CheckpointTrigger.settingsChanged);
                  }
                },
                activeThumbColor: context
                    .watch<AppState>()
                    .accentColor
                    .withValues(alpha: 0.05),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// docs/TODO.md T-56: every imported tone gets its own tile (named,
  /// selectable, previewable - the same shape as a bundled tone's
  /// [_buildToggle]), followed by a permanently-available tile to import
  /// another. Growable, not a single replaceable slot.
  Widget _buildCustomToneSection(BuildContext context) {
    final tones = context.watch<AppState>().customTones;
    return Column(
      children: [
        for (final tone in tones) ...[
          _buildCustomToneTile(context, tone),
          const SizedBox(height: 16.0),
        ],
        _buildAddCustomToneTile(context),
      ],
    );
  }

  Widget _buildCustomToneTile(BuildContext context, CustomTone tone) {
    return GestureDetector(
      onTap: () => _playOrStopAudio(tone.path),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  tone.name,
                  style: const TextStyle(fontSize: 18.0),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Switch(
                value: _appState.selectedTone == tone.path,
                onChanged: (value) {
                  if (value) {
                    _appState.selectedTone = tone.path;
                    // docs/TODO.md T-84: see the built-in tones' toggle
                    // above - a checkpoint is needed for the change to
                    // reach already-planned alarms.
                    runCheckpointSafely(_appState,
                        trigger: CheckpointTrigger.settingsChanged);
                  }
                },
                activeThumbColor: context
                    .watch<AppState>()
                    .accentColor
                    .withValues(alpha: 0.05),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Always present, regardless of how many custom tones already exist -
  /// this is what makes the list "grow", rather than a slot that's either
  /// empty or full.
  Widget _buildAddCustomToneTile(BuildContext context) {
    return GestureDetector(
      onTap: _pickCustomTone,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, color: _appState.accentColor),
              const SizedBox(width: 8.0),
              Text(
                'Add custom tone',
                style:
                    TextStyle(fontSize: 18.0, color: _appState.accentColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeSlider(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Volume',
              style: TextStyle(
                fontSize: 18.0,
              ),
            ),
            Slider(
              value: _appState.selectedVolume,
              onChanged: (value) {
                _appState.selectedVolume = value;
              },
              // Only replan on release, not on every step of the drag
              // (docs/TODO.md T-84).
              onChangeEnd: (value) {
                runCheckpointSafely(_appState,
                    trigger: CheckpointTrigger.settingsChanged);
              },
              min: 0.0,
              max: 1.0,
              divisions: 10,
              activeColor: _appState.accentColor,
              label: '${(_appState.selectedVolume * 100).round()}%',
            ),
          ],
        ),
      ),
    );
  }

  // docs/TODO.md T-50: there was no vibration setting anywhere in the app
  // before this - every alarm always vibrated regardless of anything the
  // user could do.
  Widget _buildVibrationToggle(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Vibration',
              style: TextStyle(fontSize: 18.0),
            ),
            Switch(
              value: context.watch<AppState>().vibrationEnabled,
              onChanged: (value) {
                _appState.vibrationEnabled = value;
                // The setting belongs to already-armed alarms too (T-84's
                // lesson) - without a checkpoint it would only reach a day
                // that gets replanned anyway.
                runCheckpointSafely(_appState,
                    trigger: CheckpointTrigger.settingsChanged);
              },
              activeThumbColor:
                  context.watch<AppState>().accentColor.withValues(alpha: 0.05),
            ),
          ],
        ),
      ),
    );
  }
}
