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
