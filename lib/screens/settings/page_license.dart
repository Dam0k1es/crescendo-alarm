import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// docs/TODO.md T-36: the app's own GPLv3 licence, readable from inside the
/// app rather than only linked from a README a user of the shipped product
/// never sees. Reads the real root `LICENSE` file (bundled directly via
/// `pubspec.yaml`, not a copy) so there is exactly one copy to keep in sync.
///
/// Plain text, not Markdown: the GPLv3's specific indentation and line
/// breaks are part of the document, and a Markdown renderer reflowing a
/// licence text is exactly the kind of subtle corruption this page exists
/// to avoid.
class PageLicense extends StatelessWidget {
  const PageLicense({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'License',
          style: TextStyle(fontSize: 24),
        ),
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString('LICENSE'),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: SelectableText(
                snapshot.data!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            );
          } else if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          } else {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
        },
      ),
    );
  }
}
