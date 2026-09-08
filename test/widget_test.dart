import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wakeywakey/app_state.dart';
import 'package:wakeywakey/main.dart';

void main() {
  testWidgets('App builds and shows the splash screen on first launch',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    await appState.initialized;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MyApp(),
      ),
    );

    // Permissions are only requested on Android/iOS (see
    // PermissionsManager.requestPermissions), so on the test host platform
    // the splash screen resolves immediately without needing further pumps.
    expect(find.text('Checking permissions...'), findsOneWidget);
  });
}
