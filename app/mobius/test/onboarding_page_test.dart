import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/features/library/data/ffi_library_repository.dart';
import 'package:mobius/features/onboarding/presentation/onboarding_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_offline_player.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders mobile onboarding with Connect to Computer and Use Local Storage options', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final player = FakeOfflinePlayer();
    final repository = FfiLibraryRepository(player);
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: MobiusTheme.dark(),
        home: OnboardingPage(
          repository: repository,
          onComplete: () => completed = true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Welcome to Mobius'), findsOneWidget);
    expect(find.text('Connect to Computer'), findsOneWidget);
    expect(find.text('Use Local Storage'), findsOneWidget);
    // Tapping skip completes onboarding
    final skipFinder = find.text('Skip for now (configure in Settings)');
    await tester.ensureVisible(skipFinder);
    await tester.tap(skipFinder);
    await tester.pumpAndSettle();

    expect(completed, isTrue);
  });

  testWidgets('renders desktop onboarding layout on wide screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final player = FakeOfflinePlayer();
    final repository = FfiLibraryRepository(player);
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: MobiusTheme.dark(),
        home: OnboardingPage(
          repository: repository,
          onComplete: () => completed = true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('MOBIUS MUSIC'), findsOneWidget);
    expect(find.text('Step 1: Choose Master Music Folder'), findsOneWidget);
    expect(find.text('Step 2: Listen on Your Phone'), findsOneWidget);
    expect(find.text('Enter Mobius'), findsOneWidget);

    await tester.tap(find.text('Enter Mobius'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
  });
}
