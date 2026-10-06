import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/features/library/data/ffi_library_repository.dart';
import 'package:mobius/features/library/data/user_collections.dart';
import 'package:mobius/features/library/presentation/library_page.dart';
import 'package:mobius/playback/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_offline_player.dart';

const _track = TrackMetadata(
  trackId: 3,
  title: 'Ceremony',
  artist: 'New Order',
  album: 'Movement',
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
        body: LibraryPage(
          repository: repository,
          playerController: controller,
          onOpenNowPlaying: () {},
          onLibraryChanged: () {},
          onGoToArtist: (_) {},
          onGoToAlbum: (_) {},
          collections: UserCollections(),
          currentTrackId: 0,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('mobile Library shows the One UI title and text tabs', (
    tester,
  ) async {
    await _pump(tester);

    // Large title with the One UI size (34).
    final title = tester.widget<Text>(find.text('Library').first);
    expect(title.style?.fontSize, 34);

    // The four text tabs are present.
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);

    // The song from the library renders inside the grouped Songs surface.
    expect(find.text('Ceremony'), findsOneWidget);
    expect(find.text('New Order · Movement'), findsOneWidget);
  });

  testWidgets('switching to the Albums tab swaps content', (tester) async {
    await _pump(tester);

    expect(find.text('Ceremony'), findsOneWidget);

    await tester.tap(find.text('Albums'));
    await tester.pump();
    await tester.pump();

    // Albums tab renders the embedded AlbumsPage (the album title appears,
    // the song row no longer does).
    expect(find.text('Movement'), findsWidgets);
  });

  testWidgets('sliding a song row to the right in the Songs tab adds it to queue', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Ceremony'), findsOneWidget);

    // Slide track row to the right past threshold
    await tester.drag(find.text('Ceremony'), const Offset(200, 0));
    await tester.pumpAndSettle();

    expect(find.text('Added to queue: Ceremony'), findsOneWidget);
    expect(find.text('Ceremony'), findsOneWidget);
  });
}
