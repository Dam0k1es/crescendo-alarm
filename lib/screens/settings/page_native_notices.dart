import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakeywakey/screens/settings/page_license.dart';

/// docs/TODO.md T-142: `flutter_zxing` compiles third-party C/C++ (zxing-cpp,
/// including its bundled "librscpp", plus zint) into the app at build time -
/// invisible to Flutter's own licence collector (`showLicensePage`, reachable
/// from the About page), which only reads package-root `LICENSE` files, not
/// CMake-compiled native code. This page reproduces those notices by hand
/// from `assets/text/NativeCodeNotices.txt`, the same way [PageLicense]
/// reproduces this app's own GPLv3 licence.
///
/// Plain text, not Markdown, for the same reason as [PageLicense]: a licence
/// text's own indentation and line breaks are part of the document.
class PageNativeNotices extends StatelessWidget {
  const PageNativeNotices({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Native Code Notices',
          style: TextStyle(fontSize: 24),
        ),
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString('assets/text/NativeCodeNotices.txt'),
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
