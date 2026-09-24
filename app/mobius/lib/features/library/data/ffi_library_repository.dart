import 'dart:collection';

import '../../../core/ffi/offline_player.dart';

abstract interface class LibraryRepository {
  ScanResult scan(String path);

  int getTrackCount();

  int getTrackIdAt(int index);

  TrackMetadata getTrackMetadata(int trackId);

  TrackArtwork? getTrackArtwork(int trackId);
}

class FfiLibraryRepository implements LibraryRepository {
  FfiLibraryRepository(this._player);

  final OfflinePlayer _player;
  List<int>? _trackIds;
  final Map<int, TrackMetadata> _metadataByTrackId = {};
  final LinkedHashMap<int, TrackArtwork?> _artworkByTrackId =
      LinkedHashMap<int, TrackArtwork?>();
  static const int _maxCachedArtworkEntries = 64;
  static const int _maxCachedArtworkBytes = 32 * 1024 * 1024;
  int _cachedArtworkBytes = 0;

  @override
  ScanResult scan(String path) {
    final result = _player.scanDirectory(path);
    _trackIds = null;
    _metadataByTrackId.clear();
    _artworkByTrackId.clear();
    _cachedArtworkBytes = 0;
    return result;
  }

  @override
  int getTrackCount() {
    return _loadTrackIds().length;
  }

  @override
  int getTrackIdAt(int index) {
    return _loadTrackIds()[index];
  }

  @override
  TrackMetadata getTrackMetadata(int trackId) {
    return _metadataByTrackId.putIfAbsent(
      trackId,
      () => _player.getTrackMetadata(trackId),
    );
  }

  @override
  TrackArtwork? getTrackArtwork(int trackId) {
    if (_artworkByTrackId.containsKey(trackId)) {
      final artwork = _artworkByTrackId.remove(trackId);
      _artworkByTrackId[trackId] = artwork;
      return artwork;
    }

    final artwork = _player.getTrackArtwork(trackId);
    _artworkByTrackId[trackId] = artwork;
    _cachedArtworkBytes += artwork?.data.length ?? 0;
    while (_artworkByTrackId.length > _maxCachedArtworkEntries ||
        _cachedArtworkBytes > _maxCachedArtworkBytes) {
      final oldestId = _artworkByTrackId.keys.first;
      final oldestArtwork = _artworkByTrackId.remove(oldestId);
      _cachedArtworkBytes -= oldestArtwork?.data.length ?? 0;
    }
    return artwork;
  }

  List<int> _loadTrackIds() {
    final cached = _trackIds;
    if (cached != null) return cached;

    final count = _player.getTrackCount();
    final ids = List<int>.generate(
      count,
      _player.getTrackIdAt,
      growable: false,
    );
    _trackIds = ids;
    return ids;
  }
}
