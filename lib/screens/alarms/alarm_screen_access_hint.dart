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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:crescendo_alarm/app_state.dart';
import 'package:crescendo_alarm/utils/alarm_screen_access.dart' as access;

/// The top of the Alarms screen (`docs/TODO.md` T-240, Lea's review): nobody
/// would otherwise be told that an alarm shows only as a notification on the
/// lock screen because the full-screen-intent access (Android 14+) is off,
/// and nobody would be offered "Display over other apps" unless they happen
/// to open Settings > Alarm Screen.
///
/// - a persistent warning with a button while the full-screen-intent access is
///   off - re-read on every resume, so it disappears once granted;
/// - a one-time dialog offering the overlay access (which makes the alarm
///   screen open by itself on an unlocked phone). Shown once, whatever the
///   answer, and only where the native side exists.
class AlarmScreenAccessHint extends StatefulWidget {
  const AlarmScreenAccessHint({super.key});

  @override
  State<AlarmScreenAccessHint> createState() => _AlarmScreenAccessHintState();
}

class _AlarmScreenAccessHintState extends State<AlarmScreenAccessHint>
    with WidgetsBindingObserver {
  access.AlarmScreenAccess? _status;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final status = await access.readAlarmScreenAccess();
    if (!mounted) return;
    setState(() => _status = status);
    _maybeOffer(status);
  }

  void _maybeOffer(access.AlarmScreenAccess status) {
    final appState = context.read<AppState>();
    if (_dialogOpen ||
        !status.available ||
        status.overlay ||
        appState.alarmScreenPromptShown) {
      return;
    }
    _dialogOpen = true;
    appState.markAlarmScreenPromptShown();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open the alarm screen by itself?'),
        content: const Text(
          'While you use the phone, Android shows a ringing alarm only as a '
          'notification at the top of the screen. To let the app open the '
          'alarm screen by itself, allow "Display over other apps" (Android\'s '
          'name for letting an app bring its own screen to the front). The '
          'app draws nothing over other apps. You can change this any time '
          'under Settings > Alarm Screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              access.openOverlaySettings();
            },
            child: const Text('Allow'),
          ),
        ],
      ),
    ).whenComplete(() => _dialogOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null || !status.available || status.fullScreenIntent != false) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          const Icon(Icons.warning_amber),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Alarms show only as a notification on the lock screen: '
              'full-screen notifications are not allowed for this app.',
            ),
          ),
          TextButton(
            onPressed: () => access.openFullScreenIntentSettings(),
            child: const Text('Open settings'),
          ),
        ]),
      ),
    );
  }
}
