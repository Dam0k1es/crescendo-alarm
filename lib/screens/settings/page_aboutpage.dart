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
                          'Copyright (C) 2026 Dam0k1es, centron5961. Licensed '
                          'under the GNU General Public License v3.0.',
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
