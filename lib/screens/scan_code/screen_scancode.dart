import 'package:flutter/material.dart';
import 'package:wakeywakey/screens/scan_code/page_deactivation_code.dart';

class ScreenScancode extends StatefulWidget {
  const ScreenScancode({super.key});

  @override
  State<ScreenScancode> createState() => _ScreenScancodeState();
}

class _ScreenScancodeState extends State<ScreenScancode> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Theme.of(context).colorScheme.surface,
        title: const Text(
          'Scan Code',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: const PageDeactivationCode(),
    );
  }
}
