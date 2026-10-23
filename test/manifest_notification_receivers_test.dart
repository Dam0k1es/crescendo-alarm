// Copyright (C) 2026 Dam0k1es, centron5961
//
// This file is part of Crescendo Alarm.
//
// Crescendo Alarm is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Crescendo Alarm is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Crescendo Alarm. If not, see <https://www.gnu.org/licenses/>.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Philipp's review (docs/TODO.md T-241): awesome_notifications 0.12.1 declares
// three receivers exported with no intent filter and no permission
// (DartNotificationActionReceiver, DartDismissedNotificationReceiver,
// DartScheduledNotificationReceiver). Any installed app could therefore make
// Crescendo Alarm post an arbitrary notification, with wake-screen and
// full-screen fields: a phishing and nuisance surface. The plugin reaches them
// only through explicit PendingIntents of its own app, so they do not need to
// be exported; the merged manifest makes them private.

const _receivers = [
  'me.carda.awesome_notifications.DartNotificationActionReceiver',
  'me.carda.awesome_notifications.DartDismissedNotificationReceiver',
  'me.carda.awesome_notifications.DartScheduledNotificationReceiver',
];

void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  for (final name in _receivers) {
    test('${name.split('.').last} is not exported', () {
      final decl = RegExp(
        '<receiver[^>]*android:name="${RegExp.escape(name)}"[^>]*>',
        dotAll: true,
      ).firstMatch(manifest)?.group(0);
      expect(decl, isNotNull, reason: 'the override is in the app manifest');
      expect(decl, contains('android:exported="false"'));
      expect(decl, contains('tools:replace="android:exported"'),
          reason: 'the plugin manifest says exported="true"; without '
              'tools:replace the merger fails or keeps its value');
    });
  }
}
