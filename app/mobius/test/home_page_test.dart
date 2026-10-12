import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/features/home/presentation/home_page.dart';
import 'package:mobius/features/library/data/ffi_library_repository.dart';
import 'package:mobius/playback/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_offline_player.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders HomePage with empty state when 0 tracks', (
    tester,
  ) async {
    final player = FakeOfflinePlayer();
    final repository = FfiLibraryRepository(player);
    final controller = PlayerController(player);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: MobiusTheme.dark(),
        home: HomePage(
          repository: repository,
          playerController: controller,
          onOpenNowPlaying: () {},
          onLibraryChanged: () {},
          onGoToLibrary: () {},
          onGoToAlbum: (_) {},
          onGoToArtist: (_) {},
          libraryVersion: 0,
          favoritesVersion: 0,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Your Library is Empty'), findsOneWidget);
    expect(find.text('Add Music Folder'), findsOneWidget);
  });

  testWidgets('renders HomePage with Jump Back In and Smart Mixes when tracks exist', (
    tester,
  ) async {
    const fakeTrack = TrackMetadata(
      trackId: 42,
      title: 'In Rainbows',
      artist: 'Radiohead',
      album: 'In Rainbows',
      albumArtist: 'Radiohead',
      composer: '',
      date: '2007',
      genre: 'Alternative',
      trackNumber: 1,
      discNumber: 1,
      hasDiscNumber: false,
    );

    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final player = FakeOfflinePlayer(track: fakeTrack, playing: true);
    final repository = FfiLibraryRepository(player);
    final controller = PlayerController(player);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: MobiusTheme.dark(),
        home: HomePage(
          repository: repository,
          playerController: controller,
          onOpenNowPlaying: () {},
          onLibraryChanged: () {},
          onGoToLibrary: () {},
          onGoToAlbum: (_) {},
          onGoToArtist: (_) {},
          libraryVersion: 1,
          favoritesVersion: 0,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('MOBIUS'), findsOneWidget);
    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('In Rainbows'), findsWidgets);
    expect(find.text('SMART MIXES'), findsOneWidget);
    expect(find.text('Shuffle All'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
  });
}
