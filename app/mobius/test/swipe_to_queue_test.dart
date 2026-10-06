import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/features/library/data/user_collections.dart';
import 'package:mobius/features/library/presentation/track_context_menu.dart';
import 'package:mobius/playback/player_controller.dart';

import 'support/fake_offline_player.dart';

const _testTrack = TrackMetadata(
  trackId: 42,
  title: 'Paranoid Android',
  artist: 'Radiohead',
  album: 'OK Computer',
  albumArtist: 'Radiohead',
  composer: '',
  date: '1997',
  genre: 'Alternative',
  trackNumber: 2,
  discNumber: 1,
  hasDiscNumber: false,
);

void main() {
  testWidgets('sliding track row to the right adds track to queue (Spotify style)', (tester) async {
    final fakePlayer = FakeOfflinePlayer(track: _testTrack);
    final controller = PlayerController(fakePlayer);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: MobiusTheme.dark(),
        home: Scaffold(
          body: TrackContextMenu(
            track: _testTrack,
            collections: UserCollections(),
            playerController: controller,
            child: const SizedBox(
              height: 60,
              width: double.infinity,
              child: Text('Paranoid Android'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Paranoid Android'), findsOneWidget);
    expect(fakePlayer.queuedTrackIds, isEmpty);

    // Drag row horizontally from left to right (past 28% threshold)
    await tester.drag(find.text('Paranoid Android'), const Offset(200, 0));
    await tester.pumpAndSettle();

    // Verify track is queued
    expect(fakePlayer.queuedTrackIds, contains(42));

    // Verify confirmation SnackBar is shown
    expect(find.text('Added to queue: Paranoid Android'), findsOneWidget);

    // Verify track is NOT removed from list (springs back into place)
    expect(find.text('Paranoid Android'), findsOneWidget);
  });

  testWidgets('short slide below threshold does not add track to queue', (tester) async {
    final fakePlayer = FakeOfflinePlayer(track: _testTrack);
    final controller = PlayerController(fakePlayer);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: MobiusTheme.dark(),
        home: Scaffold(
          body: TrackContextMenu(
            track: _testTrack,
            collections: UserCollections(),
            playerController: controller,
            child: const SizedBox(
              height: 60,
              width: double.infinity,
              child: Text('Paranoid Android'),
            ),
          ),
        ),
      ),
    );

    // Drag slightly (e.g. 20 pixels, well below threshold)
    await tester.drag(find.text('Paranoid Android'), const Offset(20, 0));
    await tester.pumpAndSettle();

    // Verify track was NOT queued
    expect(fakePlayer.queuedTrackIds, isEmpty);
    expect(find.text('Added to queue: Paranoid Android'), findsNothing);
  });
}
