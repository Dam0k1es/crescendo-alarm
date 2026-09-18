import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import 'package:wakeywakey/app_state.dart';

class PageAppearance extends StatefulWidget {
  const PageAppearance({super.key});

  @override
  State<PageAppearance> createState() => _PageAppearanceState();
}

class _PageAppearanceState extends State<PageAppearance> {
  late final AppState _appState;
  late Color _pickedColor;

  @override
  void initState() {
    super.initState();
    _appState = Provider.of<AppState>(context, listen: false);
    _pickedColor = _appState.accentColor;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Appearance',
          style: TextStyle(fontSize: 24),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          children: [
            _buildFollowSystemThemeToggle(),
            const SizedBox(height: 16.0),
            _buildDarkModeToggle(),
            const SizedBox(height: 16.0),
            _buildAccentColorPicker(),
          ],
        ),
      ),
    );
  }

  // docs/TODO.md T-51: "Follow System Theme" - drives AppState.themeMode
  // to ThemeMode.system instead of the manual darkMode value. Placed above
  // the Dark Mode toggle it overrides, since it grays that one out while on.
  Widget _buildFollowSystemThemeToggle() {
    final appState = context.watch<AppState>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Follow System Theme',
              style: TextStyle(
                fontSize: 18.0,
              ),
            ),
            Switch(
              key: const Key('followSystemThemeSwitch'),
              value: appState.followSystemTheme,
              onChanged: (value) {
                _appState.followSystemTheme = value;
              },
              activeThumbColor: appState.accentColor.withValues(alpha: 0.05),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDarkModeToggle() {
    final appState = context.watch<AppState>();
    final followingSystem = appState.followSystemTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Dark Mode',
              style: TextStyle(
                fontSize: 18.0,
                // Greyed out to match the switch's own disabled look, so the
                // label doesn't claim a control the user can't actually use.
                color: followingSystem
                    ? Theme.of(context).disabledColor
                    : null,
              ),
            ),
            Switch(
              key: const Key('darkModeSwitch'),
              value: appState.darkMode,
              // null, not a no-op callback: that's what makes Switch render
              // itself as disabled/greyed out, per the spec ("die manuelle
              // Option ausgrauen").
              onChanged: followingSystem
                  ? null
                  : (value) {
                      _appState.darkMode = value;
                    },
              activeThumbColor: appState.accentColor.withValues(alpha: 0.05),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccentColorPicker() {
    return GestureDetector(
      onTap: _showColorPickerOverlay,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Accent Color',
                style: TextStyle(
                  fontSize: 18.0,
                ),
              ),
              TextButton(
                onPressed: _showColorPickerOverlay,
                child: Icon(Icons.color_lens, color: _appState.accentColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showColorPickerOverlay() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pick an Accent Color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: _appState.accentColor,
              onColorChanged: (color) {
                _pickedColor = color;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                _appState.accentColor = _pickedColor;
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
