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
            _buildDarkModeToggle(),
            const SizedBox(height: 16.0),
            _buildAccentColorPicker(),
          ],
        ),
      ),
    );
  }

  Widget _buildDarkModeToggle() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Dark Mode',
              style: TextStyle(
                fontSize: 18.0,
              ),
            ),
            Switch(
              value: _appState.darkMode,
              onChanged: (value) {
                _appState.darkMode = value;
              },
              activeThumbColor:
                  context.watch<AppState>().accentColor.withValues(alpha: 0.05),
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
