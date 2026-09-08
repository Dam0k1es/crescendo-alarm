import 'package:flutter/material.dart';
import 'package:wakeywakey/screens/scan_code/qr_scanner.dart';

class PageImportQr extends StatefulWidget {
  const PageImportQr({super.key});

  @override
  State<PageImportQr> createState() => _PageImportQrState();
}

class _PageImportQrState extends State<PageImportQr> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Theme.of(context).colorScheme.surface,
        title: const Text(
          'Import QR Code',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: null,
      ),
      body: const QrScanner(displayExitButton: true),
    );
  }
}
