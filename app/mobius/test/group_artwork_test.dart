import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/features/library/data/ffi_library_repository.dart';
import 'package:mobius/features/library/presentation/group_artwork.dart';

/// Only artwork lookups matter here; everything else is unreachable.
class _FakeRepository implements LibraryRepository {
  _FakeRepository(this.artworkByTrack);

  final Map<int, TrackArtwork?> artworkByTrack;
  final List<int> reads = [];

  @override
  TrackArtwork? getTrackArtwork(int trackId) {
    reads.add(trackId);
    return artworkByTrack[trackId];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TrackArtwork _art(int trackId) => TrackArtwork(
  trackId: trackId,
  mimeType: 'image/jpeg',
  data: Uint8List.fromList([1, 2, 3]),
);

void main() {
  test('picks the first track with non-empty artwork', () {
    final repo = _FakeRepository({
      1: null,
      2: TrackArtwork(trackId: 2, mimeType: 'image/jpeg', data: Uint8List(0)),
      3: _art(3),
      4: _art(4),
    });
    final source = GroupArtworkSource([1, 2, 3, 4]);

    expect(source.resolve(repo)?.trackId, 3);
    expect(repo.reads, [1, 2, 3]);
  });

  test('remembers the cover track instead of rescanning', () {
    final repo = _FakeRepository({1: null, 2: _art(2)});
    final source = GroupArtworkSource([1, 2]);

    source.resolve(repo);
    repo.reads.clear();
    expect(source.resolve(repo)?.trackId, 2);
    expect(repo.reads, [2]);
  });

  test('remembers that a group has no artwork', () {
    final repo = _FakeRepository({1: null, 2: null});
    final source = GroupArtworkSource([1, 2]);

    expect(source.resolve(repo), isNull);
    repo.reads.clear();
    expect(source.resolve(repo), isNull);
    expect(repo.reads, isEmpty);
  });

  test('a throwing lookup is treated as missing artwork', () {
    final repo = _ThrowingRepository();
    expect(GroupArtworkSource([1]).resolve(repo), isNull);
  });
}

class _ThrowingRepository implements LibraryRepository {
  @override
  TrackArtwork? getTrackArtwork(int trackId) => throw StateError('db closed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
