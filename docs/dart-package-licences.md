# Licences of the Dart packages the app resolves (2026-10-23)

Snapshot of what `test/dart_package_licences_test.dart` found (audit L1-08): the LICENSE file of every
package in `pubspec.lock` was read and classified by its text. The test keeps failing on any package that
mentions GPL/LGPL/AGPL, "proprietary", "non-commercial" or Creative Commons, or whose text it cannot
classify, until a human has reviewed the package and listed it with a reason - so a dependency bump that
changes a licence stops there. This file is a dated record, not a source of truth; the test is.

Classes (a file can match several - a package that bundles third-party code; "BSD-3-Clause + BSD-2-Clause"
is simply a BSD-3 text, which also matches the shorter BSD-2 pattern):

| Class | Packages |
|---|---:|
| BSD-3-Clause + BSD-2-Clause | 92 |
| MIT | 43 |
| Apache-2.0 | 10 |
| BSD-3-Clause (Flutter SDK; test-only) | 3 |
| Apache-2.0 + BSD-3-Clause + BSD-2-Clause | 3 |
| BSD-2-Clause | 1 |
| MPL-2.0 | 1 |
| BSD-3-Clause (Flutter SDK; web-only) | 1 |
| BSD-3-Clause (Flutter SDK; tooling-only) | 1 |
| BSD-3-Clause AND bundled engine notices (Flutter SDK) | 1 |

Total: 156 packages (2026-10-24: `device_calendar` and `sprintf` out, the four `device_calendar_plus` packages in; counts adjusted by hand, the test is the source of truth). Nothing is copyleft except `dbus` (MPL-2.0, GPLv3-compatible through its
section 3.3; a Linux-only transitive dependency that is not part of the Android build).

| Package | Licence(s) found |
|---|---|
| `alarm` | MIT |
| `android_file_picker` | MIT |
| `archive` | MIT |
| `args` | BSD-3-Clause + BSD-2-Clause |
| `async` | BSD-3-Clause + BSD-2-Clause |
| `audioplayers` | MIT |
| `audioplayers_android` | MIT |
| `audioplayers_darwin` | MIT |
| `audioplayers_linux` | MIT |
| `audioplayers_platform_interface` | MIT |
| `audioplayers_web` | MIT |
| `audioplayers_windows` | MIT |
| `awesome_notifications` | Apache-2.0 |
| `barcode` | Apache-2.0 |
| `bidi` | MIT |
| `boolean_selector` | BSD-3-Clause + BSD-2-Clause |
| `calendar_view` | MIT |
| `camera` | BSD-3-Clause + BSD-2-Clause |
| `camera_android_camerax` | BSD-3-Clause + BSD-2-Clause |
| `camera_avfoundation` | BSD-3-Clause + BSD-2-Clause |
| `camera_platform_interface` | BSD-3-Clause + BSD-2-Clause |
| `camera_web` | BSD-3-Clause + BSD-2-Clause |
| `characters` | BSD-3-Clause + BSD-2-Clause |
| `checked_yaml` | BSD-3-Clause + BSD-2-Clause |
| `cli_util` | BSD-3-Clause + BSD-2-Clause |
| `clock` | Apache-2.0 |
| `code_assets` | BSD-3-Clause + BSD-2-Clause |
| `collection` | BSD-3-Clause + BSD-2-Clause |
| `cross_file` | BSD-3-Clause + BSD-2-Clause |
| `crypto` | BSD-3-Clause + BSD-2-Clause |
| `dbus` | MPL-2.0 |
| `device_calendar_plus` (and `_android`, `_ios`, `_platform_interface`) | MIT |
| `equatable` | MIT |
| `fake_async` | Apache-2.0 |
| `ffi` | BSD-3-Clause + BSD-2-Clause |
| `ffi_leak_tracker` | BSD-3-Clause + BSD-2-Clause |
| `file` | BSD-3-Clause + BSD-2-Clause |
| `file_picker` | MIT |
| `file_picker_darwin` | MIT |
| `file_picker_linux` | MIT |
| `file_picker_platform_interface` | MIT |
| `file_picker_web` | MIT |
| `file_selector_linux` | BSD-3-Clause + BSD-2-Clause |
| `file_selector_macos` | BSD-3-Clause + BSD-2-Clause |
| `file_selector_platform_interface` | BSD-3-Clause + BSD-2-Clause |
| `file_selector_windows` | BSD-3-Clause + BSD-2-Clause |
| `fixnum` | BSD-3-Clause + BSD-2-Clause |
| `flutter` | BSD-3-Clause + BSD-2-Clause |
| `flutter_colorpicker` | MIT |
| `flutter_driver` | BSD-3-Clause (Flutter SDK; test-only) |
| `flutter_fgbg` | MIT |
| `flutter_launcher_icons` | MIT |
| `flutter_lints` | BSD-3-Clause + BSD-2-Clause |
| `flutter_markdown_plus` | BSD-3-Clause + BSD-2-Clause |
| `flutter_plugin_android_lifecycle` | BSD-3-Clause + BSD-2-Clause |
| `flutter_test` | BSD-3-Clause (Flutter SDK; test-only) |
| `flutter_web_plugins` | BSD-3-Clause (Flutter SDK; web-only) |
| `flutter_zxing` | MIT |
| `fuchsia_remote_debug_protocol` | BSD-3-Clause (Flutter SDK; tooling-only) |
| `hooks` | BSD-3-Clause + BSD-2-Clause |
| `http` | BSD-3-Clause + BSD-2-Clause |
| `http_parser` | BSD-3-Clause + BSD-2-Clause |
| `image` | MIT |
| `image_picker` | Apache-2.0 + BSD-3-Clause + BSD-2-Clause |
| `image_picker_android` | Apache-2.0 + BSD-3-Clause + BSD-2-Clause |
| `image_picker_for_web` | BSD-3-Clause + BSD-2-Clause |
| `image_picker_ios` | Apache-2.0 + BSD-3-Clause + BSD-2-Clause |
| `image_picker_linux` | BSD-3-Clause + BSD-2-Clause |
| `image_picker_macos` | BSD-3-Clause + BSD-2-Clause |
| `image_picker_platform_interface` | BSD-3-Clause + BSD-2-Clause |
| `image_picker_windows` | BSD-3-Clause + BSD-2-Clause |
| `integration_test` | BSD-3-Clause (Flutter SDK; test-only) |
| `intl` | BSD-3-Clause + BSD-2-Clause |
| `jni` | BSD-3-Clause + BSD-2-Clause |
| `jni_flutter` | BSD-3-Clause + BSD-2-Clause |
| `jni_util` | BSD-3-Clause + BSD-2-Clause |
| `json_annotation` | BSD-3-Clause + BSD-2-Clause |
| `leak_tracker` | BSD-3-Clause + BSD-2-Clause |
| `leak_tracker_flutter_testing` | BSD-3-Clause + BSD-2-Clause |
| `leak_tracker_testing` | BSD-3-Clause + BSD-2-Clause |
| `lints` | BSD-3-Clause + BSD-2-Clause |
| `logging` | BSD-3-Clause + BSD-2-Clause |
| `markdown` | BSD-3-Clause + BSD-2-Clause |
| `matcher` | BSD-3-Clause + BSD-2-Clause |
| `material_color_utilities` | Apache-2.0 |
| `meta` | BSD-3-Clause + BSD-2-Clause |
| `mime` | BSD-3-Clause + BSD-2-Clause |
| `nested` | MIT |
| `objective_c` | BSD-3-Clause + BSD-2-Clause |
| `package_config` | BSD-3-Clause + BSD-2-Clause |
| `path` | BSD-3-Clause + BSD-2-Clause |
| `path_parsing` | MIT |
| `path_provider` | BSD-3-Clause + BSD-2-Clause |
| `path_provider_android` | BSD-3-Clause + BSD-2-Clause |
| `path_provider_foundation` | BSD-3-Clause + BSD-2-Clause |
| `path_provider_linux` | BSD-3-Clause + BSD-2-Clause |
| `path_provider_platform_interface` | BSD-3-Clause + BSD-2-Clause |
| `path_provider_windows` | BSD-3-Clause + BSD-2-Clause |
| `pdf` | Apache-2.0 |
| `pdf_widget_wrapper` | Apache-2.0 |
| `permission_handler` | MIT |
| `permission_handler_android` | MIT |
| `permission_handler_apple` | MIT |
| `permission_handler_html` | MIT |
| `permission_handler_platform_interface` | MIT |
| `permission_handler_windows` | MIT |
| `petitparser` | MIT |
| `platform` | BSD-3-Clause + BSD-2-Clause |
| `plugin_platform_interface` | BSD-3-Clause + BSD-2-Clause |
| `posix` | MIT |
| `printing` | Apache-2.0 |
| `process` | BSD-3-Clause + BSD-2-Clause |
| `provider` | MIT |
| `pub_semver` | BSD-3-Clause + BSD-2-Clause |
| `qr` | BSD-3-Clause + BSD-2-Clause |
| `qr_flutter` | BSD-3-Clause + BSD-2-Clause |
| `record_use` | BSD-3-Clause + BSD-2-Clause |
| `rxdart` | Apache-2.0 |
| `share_plus` | BSD-3-Clause + BSD-2-Clause |
| `share_plus_platform_interface` | BSD-3-Clause + BSD-2-Clause |
| `shared_preferences` | BSD-3-Clause + BSD-2-Clause |
| `shared_preferences_android` | BSD-3-Clause + BSD-2-Clause |
| `shared_preferences_foundation` | BSD-3-Clause + BSD-2-Clause |
| `shared_preferences_linux` | BSD-3-Clause + BSD-2-Clause |
| `shared_preferences_platform_interface` | BSD-3-Clause + BSD-2-Clause |
| `shared_preferences_web` | BSD-3-Clause + BSD-2-Clause |
| `shared_preferences_windows` | BSD-3-Clause + BSD-2-Clause |
| `sky_engine` | BSD-3-Clause AND bundled engine notices (Flutter SDK) |
| `source_span` | BSD-3-Clause + BSD-2-Clause |
| `stack_trace` | BSD-3-Clause + BSD-2-Clause |
| `stream_channel` | BSD-3-Clause + BSD-2-Clause |
| `stream_transform` | BSD-3-Clause + BSD-2-Clause |
| `string_scanner` | BSD-3-Clause + BSD-2-Clause |
| `sync_http` | BSD-3-Clause + BSD-2-Clause |
| `synchronized` | MIT |
| `term_glyph` | BSD-3-Clause + BSD-2-Clause |
| `test_api` | BSD-3-Clause + BSD-2-Clause |
| `timezone` | BSD-2-Clause |
| `typed_data` | BSD-3-Clause + BSD-2-Clause |
| `url_launcher_linux` | BSD-3-Clause + BSD-2-Clause |
| `url_launcher_platform_interface` | BSD-3-Clause + BSD-2-Clause |
| `url_launcher_web` | BSD-3-Clause + BSD-2-Clause |
| `url_launcher_windows` | BSD-3-Clause + BSD-2-Clause |
| `uuid` | MIT |
| `vector_math` | BSD-3-Clause + BSD-2-Clause |
| `vm_service` | BSD-3-Clause + BSD-2-Clause |
| `web` | BSD-3-Clause + BSD-2-Clause |
| `webdriver` | Apache-2.0 |
| `win32` | BSD-3-Clause + BSD-2-Clause |
| `windows_file_picker` | MIT |
| `xdg_directories` | BSD-3-Clause + BSD-2-Clause |
| `xml` | MIT |
| `yaml` | MIT |
