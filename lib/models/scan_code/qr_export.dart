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

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Renders [payload] as a QR code PNG image (docs/TODO.md T-182) - the
/// format `PageDeactivationCode`'s Share/Print actions both hand to the
/// platform, independent of whichever `page_deactivation_code.dart` widget
/// (the re-rendered QR image, or the user's own description) happens to be
/// on screen right now.
///
/// A white background is painted explicitly before the QR modules:
/// `QrPainter.paint`/`toPicture` draws only the modules themselves, with no
/// background fill of its own, so calling its own `toImageData()` directly
/// would produce a transparent-background PNG - fine on screen (where
/// `QrImageView` wraps it in an opaque `Container`), but unpredictable once
/// exported to a file some other app or a printer opens on its own.
Future<Uint8List> renderQrCodePng(String payload, {double size = 600}) async {
  final painter = QrPainter(
    data: payload,
    version: QrVersions.auto,
    gapless: false,
  );

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size, size),
    Paint()..color = Colors.white,
  );
  painter.paint(canvas, Size(size, size));

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.round(), size.round());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
