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
import 'package:crescendo_alarm/utils/alarm_screen_access.dart' as access;

/// Settings > Alarm Screen (`docs/TODO.md` T-240): can the alarm screen open
/// by itself, and where to change it. Android shows an alarm's full-screen
/// notification as a mere heads-up on a phone in use, and as a plain
/// notification everywhere if the user withdrew the full-screen-intent
/// access (Android 14+), so the user has to be told - and sent to the right
/// system screen - rather than left with a ringing phone and no screen.
class PageAlarmScreen extends StatefulWidget {
  const PageAlarmScreen({super.key});

  @override
  State<PageAlarmScreen> createState() => _PageAlarmScreenState();
}

class _PageAlarmScreenState extends State<PageAlarmScreen>
    with WidgetsBindingObserver {
  access.AlarmScreenAccess? _status;

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

  /// Back from a system screen: the grant may just have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final status = await access.readAlarmScreenAccess();
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!status.available) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'The alarm screen settings are not available on this device.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AccessCard(
          title: 'Over the lock screen',
          allowed: status.fullScreenIntent ?? true,
          text: switch (status.fullScreenIntent) {
            true => 'Allowed - the alarm screen opens over the lock screen.',
            null => 'Not needed on this Android version - the alarm screen '
                'opens over the lock screen.',
            false => 'Not allowed - the alarm shows only as a notification, '
                'also on the lock screen. Allow full-screen notifications '
                'for this app.',
          },
          actionLabel: 'Open settings',
          onAction: access.openFullScreenIntentSettings,
        ),
        const SizedBox(height: 12),
        _AccessCard(
          title: 'On an unlocked phone',
          allowed: status.overlay,
          text: status.overlay
              ? 'Allowed - the alarm screen opens by itself while you use the '
                  'phone.'
              : 'Not allowed - while you use the phone an alarm shows only as '
                  'a notification at the top of the screen; tap it to open '
                  'the alarm screen. Allow "Display over other apps" to have '
                  'it open by itself. The app draws nothing with it.',
          actionLabel: 'Allow',
          onAction: access.openOverlaySettings,
        ),
      ],
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({
    required this.title,
    required this.allowed,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final bool allowed;
  final String text;
  final String actionLabel;
  final Future<bool> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(allowed ? Icons.check_circle : Icons.warning_amber,
                  color: allowed ? Colors.green : Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ]),
            const SizedBox(height: 8),
            Text(text),
            if (!allowed) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => onAction(),
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
