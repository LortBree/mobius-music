import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/playback/presentation/mini_player.dart';
import 'package:mobius/playback/presentation/mini_seek_bar.dart';

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
  VoidCallback record(String name) =>
      () => events.add(name);
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
        child: MiniPlayer(
          height: 112,
          track: track,
          artwork: null,
          position: position,
          duration: track == null ? 0 : 200,
          isPlaying: isPlaying,
          isFavorite: false,
          repeatMode: repeatMode,
          onOpenNowPlaying: calls.record('nowPlaying'),
          onPrevious: calls.record('previous'),
          onPlayPause: calls.record('playPause'),
          onNext: calls.record('next'),
          onSeekPreview: (v) => calls.events.add('preview'),
          onSeek: (v) => calls.events.add('seek'),
          onToggleFavorite: calls.record('favorite'),
          onAddToPlaylist: calls.record('playlist'),
          onToggleRepeat: calls.record('repeat'),
          onOpenQueue: calls.record('queue'),
        ),
      ),
    ),
  );
}

void main() {
  // Wide enough that the three flex columns lay out without overflow.
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(child);
  }

  testWidgets('empty state disables every control', (tester) async {
    final calls = _Calls();
    await pump(
      tester,
      _host(track: null, position: ValueNotifier(0), calls: calls),
    );

    expect(find.text('Nothing playing'), findsOneWidget);
    await tester.tap(find.byTooltip('Next'));
    await tester.tap(find.byTooltip('Queue'));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    expect(calls.events, isEmpty);
  });

  testWidgets('controls forward to their callbacks', (tester) async {
    final calls = _Calls();
    await pump(
      tester,
      _host(track: _track, position: ValueNotifier(0), calls: calls),
    );

    expect(find.text('Song Title'), findsOneWidget);
    expect(find.text('Some Artist'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous'));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.tap(find.byTooltip('Next'));
    await tester.tap(find.byTooltip('Add to Favorites'));
    await tester.tap(find.byTooltip('Add to playlist'));
    await tester.tap(find.byTooltip('Repeat off'));
    await tester.tap(find.byTooltip('Queue'));
    await tester.tap(find.text('Song Title'));

    expect(calls.events, [
      'previous',
      'playPause',
      'next',
      'favorite',
      'playlist',
      'repeat',
      'queue',
      'nowPlaying',
    ]);
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

  testWidgets('position ticks update the elapsed time label', (tester) async {
    final position = ValueNotifier<double>(0);
    await pump(
      tester,
      _host(track: _track, position: position, calls: _Calls()),
    );

    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('3:20'), findsOneWidget);

    position.value = 65;
    await tester.pump();

    expect(find.text('1:05'), findsOneWidget);
  });

  testWidgets('tapping the seek track previews then commits', (tester) async {
    final calls = _Calls();
    await pump(
      tester,
      _host(track: _track, position: ValueNotifier(0), calls: calls),
    );

    final track = find.descendant(
      of: find.byType(MiniSeekBar),
      matching: find.byType(CustomPaint),
    );
    await tester.tap(track.first);
    expect(calls.events, ['preview', 'seek']);
  });
}
