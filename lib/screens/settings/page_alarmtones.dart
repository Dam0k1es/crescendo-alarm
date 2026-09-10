import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/models/scheduling/checkpoint.dart';

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
    debugPrint(
        "Attempting to play audio from path: $path"); // Debug-Befehl hinzugefügt
    if (_currentlyPlaying == path) {
      _stopAudio();
    } else {
      await _stopAudio();
      _audioPlayer = AudioPlayer();
      try {
        // Not really system volume, but saves us a library
        _audioPlayer?.setVolume(_appState.selectedVolume);
        String correctedPath = path.replaceFirst('assets/', '');
        await _audioPlayer!.setSource(AssetSource(correctedPath));
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

  Future<void> _stopAudio() async {
    await _audioPlayer?.stop();
    _audioPlayer?.dispose();
    _audioPlayer = null;
    _timer?.cancel();
    setState(() {
      _currentlyPlaying = null;
    });
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
              const SizedBox(height: 32.0),
              _buildVolumeSlider(context),
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
                    // docs/TODO.md T-84: die geplanten Alarme tragen den Ton
                    // als eigene Eigenschaft - ohne Checkpoint würde die
                    // Änderung erst greifen, wenn ein Tag ohnehin neu geplant
                    // wird (also unter Umständen nie).
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
              // Erst beim Loslassen neu planen, nicht bei jedem Rasterschritt
              // während des Ziehens (docs/TODO.md T-84).
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
}
