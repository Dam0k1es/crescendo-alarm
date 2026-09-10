import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/utils/diag/diag_log.dart';

/// Die Ansicht des PII-freien Ereignis-Logs (`docs/TODO.md` T-89).
///
/// Warum es diese Seite gibt: aus einem installierten Release-Build kam bisher
/// gar nichts zurueck - alle Diagnosen liefen ueber `debugPrint`, und
/// `lib/main.dart` ersetzt das im Release durch eine leere Funktion. Ein
/// Geraetetest konnte damit nur zeigen, DASS etwas schiefging, nie warum.
///
/// Warum Anzeigen und Zwischenablage statt Teilen-Dialog: die App macht
/// bewusst keinen einzigen Netzaufruf, und ein Teilen-Dialog waere eine neue,
/// lizenzpruefungspflichtige Abhaengigkeit (`share_plus`). Vor allem aber ist
/// diese Form ehrlicher - der Nutzer liest genau das, was er weitergibt,
/// statt einer Blackbox zuzustimmen.
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
      // Liest beide Senken - der Hintergrund-Isolate von FR-16s Checkpoint 2
      // schreibt in einen eigenen Schluessel und hat seinen eigenen
      // Ringpuffer (dieselbe Falle wie T-69, nur eine Ebene tiefer).
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
                    'this device only. It contains no wake-up times, no dates, '
                    'no calendar entries and no deactivation code - by '
                    'construction, not by promise: the recording code has no '
                    'way to store text at all. Nothing is ever sent anywhere; '
                    'copying it below is the only way it leaves the device.',
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
