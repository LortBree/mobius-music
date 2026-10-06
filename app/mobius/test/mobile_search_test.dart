import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/features/library/data/ffi_library_repository.dart';
import 'package:mobius/features/library/data/user_collections.dart';
import 'package:mobius/features/library/presentation/search_page.dart';
import 'package:mobius/playback/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_offline_player.dart';

const _track = TrackMetadata(
  trackId: 11,
  title: 'Blue Monday',
  artist: 'New Order',
  album: 'Power, Corruption & Lies',
  albumArtist: 'New Order',
  composer: '',
  date: '',
  genre: '',
  trackNumber: 1,
  discNumber: 1,
  hasDiscNumber: false,
);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final player = FakeOfflinePlayer(track: _track);
  final repository = FfiLibraryRepository(player);
  final controller = PlayerController(player);
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: MobiusTheme.dark(),
      home: Scaffold(
        body: SearchPage(
          repository: repository,
          playerController: controller,
          collections: UserCollections(),
          onGoToArtist: (_) {},
          onGoToAlbum: (_) {},
          onLibraryChanged: () {},
        ),
      ),
    ),
  );
  await tester.pump(); // settle the async library load
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty query prompts the user to search', (tester) async {
    await _pump(tester);
    expect(find.text('Search your library'), findsOneWidget);
  });

  testWidgets('a matching query filters songs/artists/albums', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'order');
    await tester.pump();

    // Grouped result headers appear.
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);

    // The matching song title and artist are shown.
    expect(find.text('Blue Monday'), findsOneWidget);
    expect(find.text('New Order'), findsWidgets);
  });

  testWidgets('a non-matching query shows the empty state', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'zzzznope');
    await tester.pump();

    expect(find.textContaining('No results'), findsOneWidget);
    expect(find.text('Blue Monday'), findsNothing);
  });
}
