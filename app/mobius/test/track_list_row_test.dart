import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/theme/colors.dart';
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/features/library/presentation/track_list_row.dart';

/// Mirrors how the detail pages wire a row: `onPlay: () => play(index)`. The
/// list records the index the row played, standing in for the controller's
/// `setQueue` + `selectAndPlay(index)` pair.
Widget _host({
  required List<Widget> rows,
}) {
  return MaterialApp(
    theme: MobiusTheme.dark(),
    home: Scaffold(
      body: ListView(children: rows),
    ),
  );
}

void main() {
  testWidgets('the playing row is highlighted with an accent eq glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        rows: [
          TrackListRow(
            trackNumber: 1,
            title: 'First',
            isCurrent: false,
            onPlay: () {},
          ),
          TrackListRow(
            trackNumber: 2,
            title: 'Playing Now',
            isCurrent: true,
            onPlay: () {},
          ),
        ],
      ),
    );

    // The current row shows the equalizer glyph instead of a number.
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);

    // Its title is painted in the accent colour.
    final context = tester.element(find.text('Playing Now'));
    final accent = MobiusColors.accentOf(context);
    final playingTitle = tester.widget<Text>(find.text('Playing Now'));
    expect(playingTitle.style?.color, accent);

    // A non-playing row keeps the ordinary text colour.
    final otherTitle = tester.widget<Text>(find.text('First'));
    expect(otherTitle.style?.color, isNot(accent));
  });

  testWidgets('double-tap plays this row (with its bound index)', (
    tester,
  ) async {
    final played = <int>[];
    // Bind indices the way the pages do: onPlay: () => play(index).
    void play(int index) => played.add(index);

    await tester.pumpWidget(
      _host(
        rows: [
          for (var i = 0; i < 3; i++)
            TrackListRow(
              key: ValueKey(i),
              trackNumber: i + 1,
              title: 'Track ${i + 1}',
              isCurrent: false,
              onPlay: () => play(i),
            ),
        ],
      ),
    );

    final center = tester.getCenter(find.text('Track 2'));
    // Two quick down/up pairs on the same spot = a double-tap.
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    // The double-tap on the second row should play index 1.
    expect(played, [1]);
  });

  testWidgets('hovering a row turns the number into a play button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        rows: [
          TrackListRow(
            trackNumber: 5,
            title: 'Hover Me',
            isCurrent: false,
            onPlay: () {},
          ),
        ],
      ),
    );

    // No play affordance until hovered: the number is shown.
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    expect(find.text('5'), findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('Hover Me')));
    await tester.pump();

    // Hovering swaps the number for a play button.
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('5'), findsNothing);
  });

  testWidgets('duration renders in m:ss, or -- when unknown', (tester) async {
    await tester.pumpWidget(
      _host(
        rows: [
          TrackListRow(
            trackNumber: 1,
            title: 'Timed',
            isCurrent: false,
            duration: 125,
            onPlay: () {},
          ),
          TrackListRow(
            trackNumber: 2,
            title: 'Untimed',
            isCurrent: false,
            onPlay: () {},
          ),
        ],
      ),
    );

    expect(find.text('2:05'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
  });
}
