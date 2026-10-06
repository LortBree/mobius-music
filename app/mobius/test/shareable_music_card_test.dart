import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/playback/presentation/shareable_music_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ShareableMusicCard renders title, artist, clean resolution, and Mobius Music branding in minimal mode', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShareableMusicCard(
            title: 'Stairway to Heaven',
            artist: 'Led Zeppelin',
            album: 'Led Zeppelin IV',
            formatLabel: 'FLAC 24-bit · 96.0 kHz',
            isBitPerfect: true,
          ),
        ),
      ),
    );

    // Track metadata
    expect(find.text('Stairway to Heaven'), findsOneWidget);
    expect(find.text('Led Zeppelin'), findsOneWidget);

    // Audio specs normalized to clean "24-bit / 96.0 kHz"
    expect(find.text('24-bit / 96.0 kHz'), findsOneWidget);

    // Verify NO bit-perfect badge in minimal mode as explicitly requested
    expect(find.text('Bit-Perfect UAC2'), findsNothing);
    expect(find.text('BIT-PERFECT'), findsNothing);

    // Bottom left Mobius Music branding
    expect(find.text('Mobius Music'), findsOneWidget);

    // Verify NO mini scrubber is rendered (as explicitly requested by user)
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('ShareableMusicCard renders Archival Vinyl layout with specs rail and bit-perfect badge', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShareableMusicCard(
            title: 'Stairway to Heaven',
            artist: 'Led Zeppelin',
            album: 'Led Zeppelin IV',
            formatLabel: 'FLAC 24-bit · 96.0 kHz',
            isBitPerfect: true,
            layout: ShareCardLayout.archivalVinyl,
          ),
        ),
      ),
    );

    expect(find.text('CAT. MBS-0909 // ARCHIVAL'), findsOneWidget);
    expect(find.text('Stairway to Heaven'), findsOneWidget);
    expect(find.text('Led Zeppelin  ·  Led Zeppelin IV'), findsOneWidget);
    expect(find.text('FLAC 24-bit · 96.0 kHz'), findsOneWidget);
    expect(find.text('Bit-Perfect UAC2'), findsOneWidget);
    expect(find.text('BIT-PERFECT'), findsOneWidget);
    expect(find.text('Mobius Music'), findsOneWidget);
  });

  testWidgets('ShareableMusicCard renders fallback art and standard badges when bit-perfect is false', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShareableMusicCard(
            title: 'Bohemian Rhapsody',
            artist: 'Queen',
            album: 'A Night at the Opera',
            formatLabel: 'MP3 16-bit · 44.1 kHz',
            isBitPerfect: false,
          ),
        ),
      ),
    );

    expect(find.text('Bohemian Rhapsody'), findsOneWidget);
    expect(find.text('Queen'), findsOneWidget);
    expect(find.text('16-bit / 44.1 kHz'), findsOneWidget);
    expect(find.text('Bit-Perfect UAC2'), findsNothing);
    expect(find.text('BIT-PERFECT'), findsNothing);
    expect(find.text('Mobius Music'), findsOneWidget);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
  });

  testWidgets('ShareableMusicCard adapts height to title length', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ShareableMusicCard(
              title: 'Short',
              artist: 'Artist',
              album: 'Album',
            ),
          ),
        ),
      ),
    );

    final shortFinder = find.byType(ShareableMusicCard);
    expect(shortFinder, findsOneWidget);
    final shortSize = tester.getSize(shortFinder);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ShareableMusicCard(
              title: 'A Very Long Multi-Line Song Title That Wraps Smoothly Across Multiple Lines Without Getting Cut Off',
              artist: 'Artist',
              album: 'Album',
            ),
          ),
        ),
      ),
    );

    final longFinder = find.byType(ShareableMusicCard);
    final longSize = tester.getSize(longFinder);
    expect(longSize.height, greaterThan(shortSize.height));
  });

  testWidgets('ShareableMusicCard renders Swiss Modular Grid 1:1 layout', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShareableMusicCard(
            title: 'Blue in Green',
            artist: 'Miles Davis',
            album: 'Kind of Blue',
            formatLabel: 'DSD 1-bit · 2822.4 kHz',
            isBitPerfect: true,
            layout: ShareCardLayout.swissModular,
          ),
        ),
      ),
    );

    expect(find.text('+ SWISS MODULAR // SPEC 01'), findsOneWidget);
    expect(find.text('AUDIO SOURCE FILE'), findsOneWidget);
    expect(find.text('TRACK TITLE'), findsOneWidget);
    expect(find.text('Blue in Green'), findsOneWidget);
    expect(find.text('Miles Davis  ·  Kind of Blue'), findsOneWidget);
    expect(find.text('DSD 1-bit · 2822.4 kHz'), findsOneWidget);
    expect(find.text('Bit-Perfect UAC2'), findsOneWidget);
    expect(find.text('BIT-PERFECT'), findsOneWidget);
    expect(find.text('Mobius Music'), findsOneWidget);
    expect(find.text('MODULAR LAB'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('ShareableMusicCard renders Precision Audio Lab 1:1 layout', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShareableMusicCard(
            title: 'Time',
            artist: 'Pink Floyd',
            album: 'The Dark Side of the Moon',
            formatLabel: 'FLAC 24-bit · 192.0 kHz',
            isBitPerfect: true,
            layout: ShareCardLayout.audioLab,
          ),
        ),
      ),
    );

    expect(find.text('LAB-SPEC // MASTER VERIFIED'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('Pink Floyd  ·  The Dark Side of the Moon'), findsOneWidget);
    expect(find.text('FLAC 24-bit · 192.0 kHz'), findsOneWidget);
    expect(find.text('Bit-Perfect UAC2'), findsOneWidget);
    expect(find.text('BIT-PERFECT'), findsOneWidget);
    expect(find.text('Mobius Music'), findsOneWidget);
    expect(find.text('UAC2 LAB'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('Modal opens with Minimal card and action buttons', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showShareableCardModal(
                context: context,
                title: 'So What',
                artist: 'Miles Davis',
                album: 'Kind of Blue',
              ),
              child: const Text('Open Modal'),
            ),
          ),
        ),
      ),
    );

    // Open the modal
    await tester.tap(find.text('Open Modal'));
    await tester.pumpAndSettle();

    // Verify modal header and minimal card contents
    expect(find.text('Share Music Card'), findsOneWidget);
    expect(find.text('So What'), findsOneWidget);
    expect(find.text('Miles Davis'), findsOneWidget);

    // Verify Save Image and Share action buttons exist
    expect(find.text('Save Image'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('Precision Audio Lab displays CALIBRATED badge when not bit-perfect', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShareableMusicCard(
            title: 'Roundabout',
            artist: 'Yes',
            album: 'Fragile',
            isBitPerfect: false,
            layout: ShareCardLayout.audioLab,
          ),
        ),
      ),
    );

    expect(find.text('LAB-SPEC // MASTER VERIFIED'), findsOneWidget);
    expect(find.text('CALIBRATED'), findsOneWidget);
    expect(find.text('DIRECT PCM'), findsOneWidget);
    expect(find.text('SYSTEM DAC'), findsOneWidget);
  });

  testWidgets('Swiss Modular displays SYSTEM MIXER route when not bit-perfect', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShareableMusicCard(
            title: 'Roundabout',
            artist: 'Yes',
            album: 'Fragile',
            isBitPerfect: false,
            layout: ShareCardLayout.swissModular,
          ),
        ),
      ),
    );

    expect(find.text('+ SWISS MODULAR // SPEC 01'), findsOneWidget);
    expect(find.text('SYSTEM MIXER'), findsOneWidget);
  });
}
