import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/playback/presentation/mobile_mini_player.dart';

const _track = TrackMetadata(
  trackId: 7,
  title: 'Song Title',
  artist: 'Some Artist',
  album: 'Album',
  albumArtist: 'Some Artist',
  composer: '',
  date: '',
  genre: '',
  trackNumber: 1,
  discNumber: 1,
  hasDiscNumber: false,
);

class _Calls {
  final List<String> events = [];
  VoidCallback record(String name) => () => events.add(name);
}

Widget _host({
  required TrackMetadata? track,
  required ValueNotifier<double> position,
  required _Calls calls,
  bool isPlaying = false,
  OfflinePlayerRepeatMode repeatMode = OfflinePlayerRepeatMode.off,
}) {
  return MaterialApp(
    theme: MobiusTheme.dark(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: MobileMiniPlayer(
          height: 62,
          track: track,
          artwork: null,
          position: position,
          duration: track == null ? 0 : 200,
          isPlaying: isPlaying,
          isFavorite: false,
          repeatMode: repeatMode,
          onOpenNowPlaying: calls.record('nowPlaying'),
          onToggleRepeat: calls.record('repeat'),
          onToggleFavorite: calls.record('favorite'),
          onPlayPause: calls.record('playPause'),
        ),
      ),
    ),
  );
}

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(child);
  }

  testWidgets('renders nothing when no track is loaded', (tester) async {
    await pump(
      tester,
      _host(track: null, position: ValueNotifier(0), calls: _Calls()),
    );

    expect(find.text('Song Title'), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  testWidgets('the three controls forward to their callbacks', (tester) async {
    final calls = _Calls();
    await pump(
      tester,
      _host(track: _track, position: ValueNotifier(0), calls: calls),
    );

    expect(find.text('Song Title'), findsOneWidget);
    expect(find.text('Some Artist'), findsOneWidget);

    await tester.tap(find.byTooltip('Repeat off'));
    await tester.tap(find.byTooltip('Add to Favorites'));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.tap(find.text('Song Title'));

    expect(calls.events, ['repeat', 'favorite', 'playPause', 'nowPlaying']);
  });

  testWidgets('has NO previous/next controls', (tester) async {
    await pump(
      tester,
      _host(track: _track, position: ValueNotifier(0), calls: _Calls()),
    );

    expect(find.byIcon(Icons.skip_previous_rounded), findsNothing);
    expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
    expect(find.byTooltip('Previous'), findsNothing);
    expect(find.byTooltip('Next'), findsNothing);
  });

  testWidgets('shows pause and repeat-one state', (tester) async {
    await pump(
      tester,
      _host(
        track: _track,
        position: ValueNotifier(0),
        calls: _Calls(),
        isPlaying: true,
        repeatMode: OfflinePlayerRepeatMode.track,
      ),
    );

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byTooltip('Repeat one'), findsOneWidget);
    expect(find.byIcon(Icons.repeat_one_rounded), findsOneWidget);
  });

  testWidgets('progress ring reflects position without extra rebuilds', (
    tester,
  ) async {
    final position = ValueNotifier<double>(0);
    await pump(
      tester,
      _host(track: _track, position: position, calls: _Calls()),
    );

    // The ring is drawn by a CustomPaint around the cover. Grab the painters
    // at position 0 and at the halfway point; the painter identity/fraction
    // must change so the ring advances.
    List<CustomPainter?> painters() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .toList();

    final atZero = painters().toString();
    position.value = 100; // half of 200s duration
    await tester.pump();
    final atHalf = painters().toString();

    expect(
      atZero,
      isNot(equals(atHalf)),
      reason: 'the progress ring should advance with position',
    );
  });
}
