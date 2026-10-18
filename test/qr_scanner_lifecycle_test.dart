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

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_alarm/screens/scan_code/qr_scanner.dart';

// docs/TODO.md T-231 (real phone, 2026-10-19): swiping the app out of Recents
// while the QR scanner was shown crashed the whole process - a camera preview
// frame reached Flutter's texture after the engine was detached
// ("FlutterJNI is not attached to native" in
// `FlutterRenderer$ImageReaderSurfaceProducer.onImage`) - and `AlarmService`,
// in the same process, died with it: the ring ended without the code.
// flutter_zxing's ReaderWidget only stops its image stream when the app leaves
// the foreground; the preview runs until the widget is disposed. So the
// scanner itself must drop the live preview whenever the app is not in the
// foreground.
void main() {
  group('shouldBuildLivePreview', () {
    test('builds the preview while the app is in the foreground', () {
      expect(
          shouldBuildLivePreview(
              testStreamInjected: false, lifecycle: AppLifecycleState.resumed),
          isTrue);
    });

    test('builds it before any lifecycle state is known', () {
      expect(
          shouldBuildLivePreview(testStreamInjected: false, lifecycle: null),
          isTrue);
    });

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      test('drops it when the app is $state', () {
        expect(
            shouldBuildLivePreview(testStreamInjected: false, lifecycle: state),
            isFalse);
      });
    }

    test('never builds it when a test stream is injected', () {
      expect(
          shouldBuildLivePreview(
              testStreamInjected: true, lifecycle: AppLifecycleState.resumed),
          isFalse);
    });
  });

  test('the scanner follows the app lifecycle and builds ReaderWidget only '
      'through shouldBuildLivePreview', () {
    final source =
        File('lib/screens/scan_code/qr_scanner.dart').readAsStringSync();
    expect(source, contains('with WidgetsBindingObserver'));
    expect(source, contains('didChangeAppLifecycleState'));
    expect(source, contains('if (shouldBuildLivePreview('));
    expect(source, isNot(contains('if (QrScanner.debugScanStreamOverride == null)')),
        reason: 'the preview must not be gated on the test stream alone');
  });
}
