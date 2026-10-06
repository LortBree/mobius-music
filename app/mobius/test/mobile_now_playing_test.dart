import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/features/library/data/ffi_library_repository.dart';
import 'package:mobius/playback/player_controller.dart';
import 'package:mobius/playback/presentation/now_playing_page.dart';
import 'package:mobius/playback/presentation/queue_panel.dart';

import 'support/fake_offline_player.dart';

const _track = TrackMetadata(
  trackId: 7,
  title: 'Mobile Song',
  artist: 'Mobile Artist',
  album: 'Mobile Album',
  albumArtist: 'Mobile Artist',
  composer: '',
  date: '',
  genre: '',
  trackNumber: 1,
  discNumber: 1,
  hasDiscNumber: false,
);

Future<void> _pumpMobile(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final player = FakeOfflinePlayer(track: _track, playing: true);
  final repository = FfiLibraryRepository(player);
  final controller = PlayerController(player);
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: MobiusTheme.dark(),
      home: NowPlayingPage(
        repository: repository,
        playerController: controller,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'mobile branch renders artwork, title, heart, scrubber, controls',
    (tester) async {
      await _pumpMobile(tester);

      expect(find.text('Mobile Song'), findsOneWidget);
      expect(find.text('Mobile Artist'), findsOneWidget);

      // Heart (favorite) on the title row.
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

      // Scrubber present.
      expect(find.byType(Slider), findsOneWidget);

      // Control row: shuffle · prev · play/pause · next · loop.
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      // The loop control uses the page's shared repeat-icon helper (Icons.repeat
      // for the "off" state).
      expect(find.byIcon(Icons.repeat), findsOneWidget);

      // The down-chevron dismiss affordance.
      expect(find.byTooltip('Close'), findsOneWidget);
    },
  );

  testWidgets('the signal-path strip renders and opens the sheet (STANDARD)', (
    tester,
  ) async {
    await _pumpMobile(tester);
    // Let the async readSignalPath() resolve into the strip.
    await tester.pump();
    await tester.pump();

    // The strip shows the source → … → device summary built from the path.
    // The fake's default path is a resampled FLAC => amber (non-bit-perfect).
    expect(find.textContaining('→'), findsOneWidget);

    // Tapping the strip opens the Signal path sheet.
    await tester.tap(find.textContaining('→'));
    await tester.pumpAndSettle();

    expect(find.text('Signal path'), findsOneWidget);
    // Non-bit-perfect => STANDARD status label.
    expect(find.text('STANDARD'), findsOneWidget);
    expect(find.text('BIT-PERFECT'), findsNothing);
    // Timeline stage titles are present.
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Decoder'), findsOneWidget);
    expect(find.text('Output'), findsOneWidget);
    expect(find.text('Device'), findsOneWidget);
    // The default path is not resampling-free: Resampler reads "Converting
    // rate"; DSP is bypassed (no EQ, full volume) so it reads "Passthrough".
    expect(find.text('Passthrough'), findsOneWidget);
  });

  testWidgets('the queue opens as a bottom sheet', (tester) async {
    await _pumpMobile(tester);

    // No queue side-panel on mobile until the queue button is tapped.
    expect(find.byType(QueuePanel), findsNothing);

    await tester.tap(find.byTooltip('Queue'));
    await tester.pumpAndSettle();

    // The queue is presented in a modal bottom sheet.
    expect(find.byType(QueuePanel), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });
}
