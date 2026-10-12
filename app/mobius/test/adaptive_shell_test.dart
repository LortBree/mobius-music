import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/adaptive_shell.dart';
import 'package:mobius/app/mobile_shell.dart';
import 'package:mobius/app/mobius_shell.dart';
import 'package:mobius/app/mobius_app.dart' show ThemeModeController;
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/features/library/data/ffi_library_repository.dart';
import 'package:mobius/playback/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_offline_player.dart';

Widget _app(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final player = FakeOfflinePlayer();
  final repository = FfiLibraryRepository(player);
  final controller = PlayerController(player);
  addTearDown(controller.dispose);

  return MaterialApp(
    theme: MobiusTheme.dark(),
    home: AdaptiveShell(
      repository: repository,
      playerController: controller,
      themeController: ThemeModeController(
        mode: ThemeMode.dark,
        setMode: (_) {},
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('narrow (< 900) renders the mobile shell with a NavigationBar', (
    tester,
  ) async {
    await tester.pumpWidget(_app(tester, const Size(400, 800)));
    await tester.pump();

    expect(find.byType(MobileShell), findsOneWidget);
    expect(find.byType(MobiusShell), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    // Four bottom-nav destinations: Home, Library, Search, Settings.
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Search'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    // Albums/Artists are Library text-tabs, not bottom-nav destinations.
    final navBar = find.byType(NavigationBar);
    expect(
      find.descendant(of: navBar, matching: find.text('Albums')),
      findsNothing,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('Artists')),
      findsNothing,
    );
  });

  testWidgets('wide (>= 900) renders the desktop shell with the sidebar', (
    tester,
  ) async {
    await tester.pumpWidget(_app(tester, const Size(1200, 900)));
    await tester.pump();

    expect(find.byType(MobiusShell), findsOneWidget);
    expect(find.byType(MobileShell), findsNothing);
    // No bottom NavigationBar on desktop.
    expect(find.byType(NavigationBar), findsNothing);
    // The MOBIUS wordmark top bar is a desktop-only affordance.
    expect(find.text('MOBIUS'), findsOneWidget);
  });
}
