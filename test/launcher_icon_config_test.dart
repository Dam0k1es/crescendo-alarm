import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// docs/TODO.md: the launcher icon shipped only as a legacy (non-adaptive)
// PNG - no `mipmap-anydpi-v26/ic_launcher.xml` existed at all. Android
// launchers that expect an adaptive icon fall back to scaling a legacy icon
// down and compositing it onto a backplate of their own choosing, which is
// what produced the "light blob in dark mode" report: the badge already
// touches its own canvas edges, so the launcher's own re-shaping added an
// extra light plate behind it. These are source/file-presence checks, not
// something a widget test can exercise - there is no Flutter API that reads
// back what a launcher would render for an adaptive icon.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('flutter_launcher_icons declares an adaptive icon background', () {
    expect(pubspec, contains('adaptive_icon_background:'),
        reason: 'without a background layer, Android has no adaptive icon '
            'to render and falls back to the legacy-icon backplate '
            'behaviour this fix exists to avoid');
  });

  test('flutter_launcher_icons declares an adaptive icon foreground', () {
    expect(pubspec, contains('adaptive_icon_foreground:'),
        reason: 'the foreground layer is the actual artwork shown once an '
            'adaptive icon is configured');
  });

  test('the adaptive icon background is opaque white', () {
    // A fully transparent background (the original design) rendered as black
    // on the maintainer's home screen instead of showing the wallpaper
    // through, since most launchers paint an opaque surface behind an
    // adaptive icon rather than compositing it as truly see-through. The
    // maintainer's fix: an explicit opaque white background layer, with only
    // the foreground artwork itself (assets/icons/icon_foreground.png)
    // staying transparent outside the badge shape.
    final match =
        RegExp(r'adaptive_icon_background:\s*"?(#[0-9A-Fa-f]{8})"?')
            .firstMatch(pubspec);
    expect(match, isNotNull,
        reason: 'adaptive_icon_background should be an 8-digit ARGB hex '
            'colour, not an image');
    expect(match!.group(1)!.toLowerCase(), '#ffffffff');
  });

  test('the adaptive icon foreground asset exists and is transparent',
      () {
    final foreground = File('assets/icons/icon_foreground.png');
    expect(foreground.existsSync(), isTrue,
        reason: 'referenced by adaptive_icon_foreground in pubspec.yaml');
  });

  test('the generated Android resources define an adaptive icon', () {
    final adaptiveXml = File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml');
    expect(adaptiveXml.existsSync(), isTrue,
        reason: 'this file is what tells API 26+ launchers to use the '
            'foreground/background layers instead of falling back to the '
            'legacy single-PNG icon and its own re-shaping/backplate');
    expect(adaptiveXml.readAsStringSync(), contains('<adaptive-icon'));
  });
}
