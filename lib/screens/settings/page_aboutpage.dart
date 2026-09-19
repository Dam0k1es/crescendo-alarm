import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:wakeywakey/screens/settings/page_license.dart';
import 'package:wakeywakey/screens/settings/page_native_notices.dart';

class PageAboutpage extends StatelessWidget {
  const PageAboutpage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'About WakeyWakey',
          style: TextStyle(fontSize: 24),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<String>(
              future: loadMarkdownFile('text/Privacy.md'),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Markdown(
                    data: snapshot.data!,
                    selectable: true,
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
          ),
          // docs/TODO.md T-36: the licence text has to be reachable from
          // inside the running app, not only linked from a README - both
          // this app's own GPLv3 and the third-party notices Flutter
          // already collects at build time but never displayed anywhere.
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const PageLicense(),
                      ),
                    );
                  },
                  child: const Text('License'),
                ),
                TextButton(
                  onPressed: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'WakeyWakey',
                      applicationLegalese:
                          'Copyright (C) 2026 Dam0k1es. Licensed under the '
                          'GNU General Public License v3.0.',
                    );
                  },
                  child: const Text('Third-Party Licenses'),
                ),
                // docs/TODO.md T-142: the QR scanner compiles third-party
                // C/C++ into the app - invisible to showLicensePage above,
                // which only ever reads package-root LICENSE files.
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const PageNativeNotices(),
                      ),
                    );
                  },
                  child: const Text('Native Code Notices'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<String> loadMarkdownFile(String fileName) async {
  final markdownFile = await rootBundle.loadString('assets/$fileName');
  return markdownFile;
}
