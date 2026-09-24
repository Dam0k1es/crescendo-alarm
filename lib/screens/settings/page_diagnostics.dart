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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';

/// The view for the PII-free event log (`docs/TODO.md` T-89).
///
/// Why this page exists: nothing at all used to come back from an installed
/// release build - every diagnostic went through `debugPrint`, and
/// `lib/main.dart` replaces that with an empty function in release. A device
/// test could therefore only show THAT something went wrong, never why.
///
/// Why display + clipboard instead of a share dialog: the app deliberately
/// makes not a single network call, and a share dialog would be a new
/// dependency requiring a licence check (`share_plus`). But above all, this
/// form is more honest - the user reads exactly what they're passing on,
/// instead of consenting to a black box.
class PageDiagnostics extends StatefulWidget {
  const PageDiagnostics({super.key});

  @override
  State<PageDiagnostics> createState() => _PageDiagnosticsState();
}

class _PageDiagnosticsState extends State<PageDiagnostics> {
  String _text = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    String text;
    try {
      // Reads both sinks - FR-16 checkpoint 2's background isolate writes
      // to its own key and has its own ring buffer (the same trap as T-69,
      // just one level deeper).
      text = Diag.render(await Diag.readAll());
    } catch (e) {
      text = 'Could not read the diagnostics log (${e.runtimeType}).';
    }
    if (!mounted) return;
    setState(() {
      _text = text;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Diagnostics log',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A local record of what the alarm scheduler did, kept on '
                    'this device only. By default it contains no wake-up '
                    'times, no calendar content (never a title, description, '
                    'attendee or location - not even with the switch below '
                    'on) and no deactivation code - by construction, not by '
                    'promise: the recording code has no way to store text at '
                    'all. Nothing is ever sent anywhere; copying it below is '
                    'the only way it leaves the device.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Record diagnostics'),
                    value: appState.diagnosticsEnabled,
                    activeThumbColor: appState.accentColor,
                    onChanged: (value) {
                      appState.diagnosticsEnabled = value;
                    },
                  ),
                  // docs/TODO.md T-135, extended by T-163. Deliberately a
                  // SECOND switch, not part of the first: it lifts exactly
                  // the property that makes the paragraph above true.
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Also record wake and appointment times'),
                    subtitle: const Text(
                      'Off by default. Adds each day\'s planned wake time, '
                      'plus the start and end time of every calendar event '
                      'that day (still never its title, description, '
                      'attendees or location), so a week\'s plan can be '
                      'checked against what the calendar actually held. '
                      'These are clock times: together they are a sleep '
                      'pattern and a daily routine. Turn it on while '
                      'investigating a scheduling problem - and remember it '
                      'is then in anything you share.',
                      style: TextStyle(fontSize: 12),
                    ),
                    isThreeLine: true,
                    value: appState.diagnosticsIncludeClockTimes,
                    activeThumbColor: appState.accentColor,
                    onChanged: appState.diagnosticsEnabled
                        ? (value) {
                            appState.diagnosticsIncludeClockTimes = value;
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _loading ? null : _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _loading || _text.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: _text));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Diagnostics copied to clipboard'),
                          ),
                        );
                      },
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () async {
                        await Diag.clear();
                        await _reload();
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: _loading
                  ? const Center(child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(),
                    ))
                  : SelectableText(
                      _text.isEmpty ? 'No events recorded yet.' : _text,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
