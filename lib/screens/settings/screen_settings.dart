import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/screens/settings/page_aboutpage.dart';
import 'package:wakeywakey/screens/settings/page_alarmtones.dart';
import 'package:wakeywakey/screens/settings/page_appearance.dart';
import 'package:wakeywakey/screens/settings/page_diagnostics.dart';

class ScreenSettings extends StatefulWidget {
  const ScreenSettings({super.key});

  @override
  State<ScreenSettings> createState() => _ScreenSettingsState();
}

class _ScreenSettingsState extends State<ScreenSettings>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Theme.of(context).colorScheme.surface,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.onSurface,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurface,
          indicatorColor: context.watch<AppState>().accentColor,
          tabs: [
            Tab(
              icon: Icon(Icons.notifications_active,
                  color: context.watch<AppState>().accentColor),
              text: 'Alarm Tones',
            ),
            Tab(
              icon: Icon(Icons.palette,
                  color: context.watch<AppState>().accentColor),
              text: 'Appearance',
            ),
            Tab(
              icon: Icon(Icons.info,
                  color: context.watch<AppState>().accentColor),
              text: 'About Page',
            ),
            // docs/TODO.md T-89: the view into the PII-free event log.
            // Visible, not hidden, because the user must be able to see
            // what they're passing on when they copy it.
            Tab(
              icon: Icon(Icons.bug_report,
                  color: context.watch<AppState>().accentColor),
              text: 'Diagnostics',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          PageAlarmTones(),
          PageAppearance(),
          PageAboutpage(),
          PageDiagnostics(),
        ],
      ),
    );
  }
}
