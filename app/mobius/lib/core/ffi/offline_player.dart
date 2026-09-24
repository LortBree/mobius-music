import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'offline_player_bindings.dart';

class ScanResult {
  const ScanResult({
    required this.added,
    required this.updated,
    required this.removed,
    required this.total,
  });

  final int added;
  final int updated;
  final int removed;
  final int total;
}

class TrackMetadata {
  const TrackMetadata({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.composer,
    required this.date,
    required this.genre,
    required this.trackNumber,
    required this.discNumber,
    required this.hasDiscNumber,
  });

  final int trackId;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String composer;
  final String date;
  final String genre;
  final int trackNumber;
  final int discNumber;
  final bool hasDiscNumber;
}

class TrackArtwork {
  const TrackArtwork({
    required this.trackId,
    required this.mimeType,
    required this.data,
  });

  final int trackId;
  final String mimeType;
  final Uint8List data;

  bool get isEmpty => data.isEmpty;
}

class OfflinePlayerException implements Exception {
  const OfflinePlayerException(
    this.code,
    this.message,
  );

  final int code;
  final String message;

  @override
  String toString() {
    return 'OfflinePlayerException($code): $message';
  }
}

enum OfflinePlayerState {
  idle,
  loaded,
  playing,
  paused,
  stopped,
}

enum OfflinePlayerRepeatMode {
  off,
  track,
  queue,
}

enum OfflinePlayerOutputMode {
  auto,
  khz44_1,
  khz48,
  khz96,
}

OfflinePlayerState _stateFromRaw(int value) {
  switch (value) {
    case 0:
      return OfflinePlayerState.idle;
    case 1:
      return OfflinePlayerState.loaded;
    case 2:
      return OfflinePlayerState.playing;
    case 3:
      return OfflinePlayerState.paused;
    case 4:
      return OfflinePlayerState.stopped;
    default:
      throw StateError(
        'Unknown OfflinePlayerState value: $value',
      );
  }
}

OfflinePlayerRepeatMode _repeatModeFromRaw(int value) {
  switch (value) {
    case 0:
      return OfflinePlayerRepeatMode.off;
    case 1:
      return OfflinePlayerRepeatMode.track;
    case 2:
      return OfflinePlayerRepeatMode.queue;
    default:
      throw StateError(
        'Unknown OfflinePlayerRepeatMode value: $value',
      );
  }
}

OfflinePlayerOutputMode _outputModeFromRaw(int value) {
  switch (value) {
    case 0:
      return OfflinePlayerOutputMode.auto;
    case 1:
      return OfflinePlayerOutputMode.khz44_1;
    case 2:
      return OfflinePlayerOutputMode.khz48;
    case 3:
      return OfflinePlayerOutputMode.khz96;
    default:
      throw StateError('Unknown OfflinePlayerOutputMode value: $value');
  }
}

class TrackTechnicalInfo {
  const TrackTechnicalInfo({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
}

class OfflinePlayer {
  OfflinePlayer._({
    required OfflinePlayerBindings bindings,
    required ffi.Pointer<OfflinePlayerHandle> handle,
  })  : _bindings = bindings,
        _handle = handle;

  final OfflinePlayerBindings _bindings;
  ffi.Pointer<OfflinePlayerHandle> _handle;

  bool _disposed = false;

  static OfflinePlayer open({
    required String libraryPath,
    required String dbPath,
  }) {
    final library = OfflinePlayerBindings.openLibrary(
      libraryPath,
    );

    final bindings = OfflinePlayerBindings(library);

    final dbPathPointer = dbPath.toNativeUtf8();
    final handleOut =
        calloc<ffi.Pointer<OfflinePlayerHandle>>();

    try {
      final result = bindings.create(
        dbPathPointer,
        handleOut,
      );

      if (result != 0) {
        throw OfflinePlayerException(
          result,
          'Failed to create OfflinePlayer.',
        );
      }

      final handle = handleOut.value;

      if (handle == ffi.nullptr) {
        throw const OfflinePlayerException(
          8,
          'Rust returned a null OfflinePlayer handle.',
        );
      }

      return OfflinePlayer._(
        bindings: bindings,
        handle: handle,
      );
    } finally {
      calloc.free(dbPathPointer);
      calloc.free(handleOut);
    }
  }

  String get version {
    _ensureNotDisposed();

    final pointer = _bindings.version();

    if (pointer == ffi.nullptr) {
      return '';
    }

    return pointer.toDartString();
  }

  String lastError() {
    _ensureNotDisposed();

    const capacity = 4096;

    final buffer = calloc<ffi.Uint8>(capacity);

    try {
      final result = _bindings.lastError(
        _handle,
        buffer.cast<Utf8>(),
        capacity,
      );

      if (result != 0 && result != 7) {
        return 'Unknown native error ($result).';
      }

      return buffer.cast<Utf8>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  ScanResult scanDirectory(String path) {
    _ensureNotDisposed();

    final pathPointer = path.toNativeUtf8();

    final added = calloc<ffi.Int64>();
    final updated = calloc<ffi.Int64>();
    final removed = calloc<ffi.Int64>();
    final total = calloc<ffi.Int64>();

    try {
      _check(
        _bindings.scanDirectory(
          _handle,
          pathPointer,
          added,
          updated,
          removed,
          total,
        ),
      );

      return ScanResult(
        added: added.value,
        updated: updated.value,
        removed: removed.value,
        total: total.value,
      );
    } finally {
      calloc.free(pathPointer);
      calloc.free(added);
      calloc.free(updated);
      calloc.free(removed);
      calloc.free(total);
    }
  }

  int getTrackCount() {
    _ensureNotDisposed();

    final out = calloc<ffi.Int64>();

    try {
      _check(
        _bindings.trackCount(
          _handle,
          out,
        ),
      );

      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  int getTrackIdAt(int index) {
    _ensureNotDisposed();

    final out = calloc<ffi.Int64>();

    try {
      _check(
        _bindings.trackIdAt(
          _handle,
          index,
          out,
        ),
      );

      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  TrackMetadata getTrackMetadata(int trackId) {
    _ensureNotDisposed();

    const titleCapacity = 1024;
    const artistCapacity = 1024;
    const albumCapacity = 1024;
    const albumArtistCapacity = 1024;
    const composerCapacity = 1024;
    const dateCapacity = 256;
    const genreCapacity = 256;

    final metadata =
        calloc<OfflinePlayerTrackMetadata>();

    final title = calloc<ffi.Uint8>(titleCapacity);
    final artist = calloc<ffi.Uint8>(artistCapacity);
    final album = calloc<ffi.Uint8>(albumCapacity);
    final albumArtist =
        calloc<ffi.Uint8>(albumArtistCapacity);
    final composer = calloc<ffi.Uint8>(composerCapacity);
    final date = calloc<ffi.Uint8>(dateCapacity);
    final genre = calloc<ffi.Uint8>(genreCapacity);

    try {
      metadata.ref.trackId = trackId;

      metadata.ref.title =
          title.cast<Utf8>();
      metadata.ref.titleCapacity =
          titleCapacity;

      metadata.ref.artist =
          artist.cast<Utf8>();
      metadata.ref.artistCapacity =
          artistCapacity;

      metadata.ref.album =
          album.cast<Utf8>();
      metadata.ref.albumCapacity =
          albumCapacity;

      metadata.ref.albumArtist =
          albumArtist.cast<Utf8>();
      metadata.ref.albumArtistCapacity =
          albumArtistCapacity;

      metadata.ref.composer =
          composer.cast<Utf8>();
      metadata.ref.composerCapacity =
          composerCapacity;

      metadata.ref.date =
          date.cast<Utf8>();
      metadata.ref.dateCapacity =
          dateCapacity;

      metadata.ref.genre =
          genre.cast<Utf8>();
      metadata.ref.genreCapacity =
          genreCapacity;

      _check(
        _bindings.libraryTrackMetadata(
          _handle,
          trackId,
          metadata,
        ),
      );

      return TrackMetadata(
        trackId: metadata.ref.trackId,
        title: metadata.ref.title.toDartString(),
        artist: metadata.ref.artist.toDartString(),
        album: metadata.ref.album.toDartString(),
        albumArtist:
            metadata.ref.albumArtist.toDartString(),
        composer:
            metadata.ref.composer.toDartString(),
        date: metadata.ref.date.toDartString(),
        genre: metadata.ref.genre.toDartString(),
        trackNumber:
            metadata.ref.trackNumber,
        discNumber:
            metadata.ref.discNumber,
        hasDiscNumber:
            metadata.ref.hasDiscNumber != 0,
      );
    } finally {
      calloc.free(metadata);

      calloc.free(title);
      calloc.free(artist);
      calloc.free(album);
      calloc.free(albumArtist);
      calloc.free(composer);
      calloc.free(date);
      calloc.free(genre);
    }
  }

TrackArtwork? getTrackArtwork(int trackId) {
  _ensureNotDisposed();

  final artwork = calloc<OfflinePlayerTrackArtwork>();

  try {
    artwork.ref.trackId = trackId;
    artwork.ref.mimeType = ffi.nullptr.cast<Utf8>();
    artwork.ref.mimeTypeCapacity = 0;
    artwork.ref.mimeTypeSize = 0;
    artwork.ref.data = ffi.nullptr;
    artwork.ref.dataCapacity = 0;
    artwork.ref.dataSize = 0;

    /*
     * First pass:
     * Ask Rust for the required buffer sizes.
     */
    final firstResult =
        _bindings.libraryTrackArtwork(
      _handle,
      trackId,
      artwork,
    );

    // Rust returns NOT_FOUND when the track has no artwork.
    if (firstResult == 4) {
      return null;
    }

    // BUFFER_TOO_SMALL is expected during the sizing pass.
    if (firstResult != 7) {
      _check(firstResult);
    }

    final mimeTypeSize = artwork.ref.mimeTypeSize;
    final dataSize = artwork.ref.dataSize;

    final mimeTypeBuffer = calloc<ffi.Uint8>(
      mimeTypeSize == 0 ? 1 : mimeTypeSize,
    );

    final dataBuffer = calloc<ffi.Uint8>(
      dataSize == 0 ? 1 : dataSize,
    );

    try {
      /*
       * Second pass:
       * Provide buffers and ask Rust to copy the artwork.
       */
      artwork.ref.mimeType =
          mimeTypeBuffer.cast<Utf8>();
      artwork.ref.mimeTypeCapacity =
          mimeTypeSize;

      artwork.ref.data = dataBuffer;
      artwork.ref.dataCapacity =
          dataSize;

      artwork.ref.mimeTypeSize = 0;
      artwork.ref.dataSize = 0;

      _check(
        _bindings.libraryTrackArtwork(
          _handle,
          trackId,
          artwork,
        ),
      );

      final mimeType =
          artwork.ref.mimeType.toDartString();

      final data = Uint8List.fromList(dataBuffer.asTypedList(dataSize));

      return TrackArtwork(
        trackId: artwork.ref.trackId,
        mimeType: mimeType,
        data: data,
      );
    } finally {
      calloc.free(mimeTypeBuffer);
      calloc.free(dataBuffer);
    }
  } finally {
    calloc.free(artwork);
  }
}

  int get sampleRate {
    _ensureNotDisposed();
    final out = calloc<ffi.Uint32>();
    try {
      _check(_bindings.trackSampleRate(_handle, out));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  int get channels {
    _ensureNotDisposed();
    final out = calloc<ffi.Uint16>();
    try {
      _check(_bindings.trackChannels(_handle, out));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  int get bitsPerSample {
    _ensureNotDisposed();
    final out = calloc<ffi.Uint16>();
    try {
      _check(_bindings.trackBitsPerSample(_handle, out));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  TrackTechnicalInfo get technicalInfo {
    return TrackTechnicalInfo(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
    );
  }

  OfflinePlayerOutputMode get outputMode {
    _ensureNotDisposed();
    final out = calloc<ffi.Int32>();
    try {
      _check(_bindings.outputMode(_handle, out));
      return _outputModeFromRaw(out.value);
    } finally {
      calloc.free(out);
    }
  }

  void setOutputMode(OfflinePlayerOutputMode mode) {
    _ensureNotDisposed();
    _check(_bindings.setOutputMode(_handle, mode.index));
  }

  void setVolume(double volume) {
    _ensureNotDisposed();
    _check(_bindings.setVolume(_handle, volume.clamp(0.0, 1.0)));
  }

  void setEqualizerGains(List<double> gainsDb) {
    _ensureNotDisposed();
    if (gainsDb.length != 10) {
      throw ArgumentError.value(gainsDb.length, 'gainsDb.length', 'Must be 10');
    }
    final gains = calloc<ffi.Float>(gainsDb.length);
    try {
      for (var index = 0; index < gainsDb.length; index++) {
        gains[index] = gainsDb[index];
      }
      _check(_bindings.setEqualizerGains(_handle, gains, gainsDb.length));
    } finally {
      calloc.free(gains);
    }
  }

  void loadTrack(int trackId) {
    _ensureNotDisposed();

    _check(
      _bindings.loadTrack(
        _handle,
        trackId,
      ),
    );
  }

  void play() {
    _ensureNotDisposed();

    _check(
      _bindings.play(_handle),
    );
  }

  void pause() {
    _ensureNotDisposed();

    _check(
      _bindings.pause(_handle),
    );
  }

  void stop() {
    _ensureNotDisposed();

    final result = _bindings.stop(_handle);

    _check(result);
  }

  void seekToFrame(int frame) {
    _ensureNotDisposed();

    if (frame < 0) {
      throw ArgumentError.value(
        frame,
        'frame',
        'Frame cannot be negative.',
      );
    }

    _check(
      _bindings.seekToFrame(
        _handle,
        frame,
      ),
    );
  }

  OfflinePlayerState get state {
    _ensureNotDisposed();

    final out = calloc<ffi.Int32>();

    try {
      _check(
        _bindings.state(
          _handle,
          out,
        ),
      );

      return _stateFromRaw(out.value);
    } finally {
      calloc.free(out);
    }
  }

  int get currentFrame {
    _ensureNotDisposed();

    final out = calloc<ffi.Uint64>();

    try {
      _check(
        _bindings.currentFrame(
          _handle,
          out,
        ),
      );

      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  double get currentSeconds {
    _ensureNotDisposed();

    final out = calloc<ffi.Double>();

    try {
      _check(
        _bindings.currentSeconds(
          _handle,
          out,
        ),
      );

      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  double get durationSeconds {
    _ensureNotDisposed();

    final out = calloc<ffi.Double>();

    try {
      _check(
        _bindings.durationSeconds(
          _handle,
          out,
        ),
      );

      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  int get totalFrames {
    _ensureNotDisposed();

    final out = calloc<ffi.Uint64>();

    try {
      _check(
        _bindings.totalFrames(
          _handle,
          out,
        ),
      );

      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /*
   * Queue
   */

  void setQueue(List<int> trackIds) {
    _ensureNotDisposed();

    if (trackIds.isEmpty) {
      _check(
        _bindings.queueSet(
          _handle,
          ffi.nullptr.cast<ffi.Int64>(),
          0,
        ),
      );

      return;
    }

    final ids =
        calloc<ffi.Int64>(trackIds.length);

    try {
      for (var i = 0; i < trackIds.length; i++) {
        ids[i] = trackIds[i];
      }

      _check(
        _bindings.queueSet(
          _handle,
          ids,
          trackIds.length,
        ),
      );
    } finally {
      calloc.free(ids);
    }
  }

  void clearQueue() {
    _ensureNotDisposed();

    _check(
      _bindings.queueClear(_handle),
    );
  }

  void addToQueue(int trackId) {
    _ensureNotDisposed();
    _check(_bindings.queueAdd(_handle, trackId));
  }

  int get queueLength {
    _ensureNotDisposed();

    final out = calloc<ffi.Uint64>();

    try {
      _check(
        _bindings.queueLength(
          _handle,
          out,
        ),
      );

      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  List<int> get queueTrackIds {
    _ensureNotDisposed();
    final count = queueLength;
    final ids = <int>[];
    final out = calloc<ffi.Int64>();
    try {
      for (var index = 0; index < count; index++) {
        _check(_bindings.queueTrackIdAt(_handle, index, out));
        ids.add(out.value);
      }
    } finally {
      calloc.free(out);
    }
    return ids;
  }

  int get queueUpNextCount {
    _ensureNotDisposed();
    final out = calloc<ffi.Uint64>();
    try {
      _check(_bindings.queueUpNextCount(_handle, out));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  void reorderQueueSegment(int start, List<int> trackIds) {
    _ensureNotDisposed();
    final ffi.Pointer<ffi.Int64> ids = trackIds.isEmpty
        ? ffi.nullptr.cast<ffi.Int64>()
        : calloc<ffi.Int64>(trackIds.length);
    try {
      for (var i = 0; i < trackIds.length; i++) {
        ids[i] = trackIds[i];
      }
      _check(
        _bindings.queueReorderSegment(_handle, start, ids, trackIds.length),
      );
    } finally {
      if (trackIds.isNotEmpty) calloc.free(ids);
    }
  }

  int get queueCurrentIndex {
    _ensureNotDisposed();

    final out = calloc<ffi.Uint64>();

    try {
      _check(
        _bindings.queueCurrentIndex(
          _handle,
          out,
        ),
      );

      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  int get queueCurrentTrackId {
    _ensureNotDisposed();

    final out = calloc<ffi.Int64>();

    try {
      _check(
        _bindings.queueCurrentTrackId(
          _handle,
          out,
        ),
      );

      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  OfflinePlayerRepeatMode get repeatMode {
    _ensureNotDisposed();

    final out = calloc<ffi.Int32>();

    try {
      _check(
        _bindings.queueRepeatMode(
          _handle,
          out,
        ),
      );

      return _repeatModeFromRaw(
        out.value,
      );
    } finally {
      calloc.free(out);
    }
  }

  void setRepeatMode(
    OfflinePlayerRepeatMode mode,
  ) {
    _ensureNotDisposed();

    _check(
      _bindings.queueSetRepeatMode(
        _handle,
        mode.index,
      ),
    );
  }

  void selectQueueIndex(int index) {
    _ensureNotDisposed();

    if (index < 0) {
      throw ArgumentError.value(
        index,
        'index',
        'Queue index cannot be negative.',
      );
    }

    _check(
      _bindings.queueSelect(
        _handle,
        index,
      ),
    );
  }

  void selectAndLoadQueueIndex(int index) {
    _ensureNotDisposed();

    if (index < 0) {
      throw ArgumentError.value(
        index,
        'index',
        'Queue index cannot be negative.',
      );
    }

    _check(
      _bindings.queueSelectAndLoad(
        _handle,
        index,
      ),
    );
  }

  void playCurrentQueueTrack() {
    _ensureNotDisposed();

    _check(
      _bindings.queuePlayCurrent(_handle),
    );
  }

  void selectAndPlayQueueIndex(int index) {
    _ensureNotDisposed();

    if (index < 0) {
      throw ArgumentError.value(
        index,
        'index',
        'Queue index cannot be negative.',
      );
    }

    _check(
      _bindings.queueSelectAndPlay(
        _handle,
        index,
      ),
    );
  }

  void nextQueue() {
    _ensureNotDisposed();

    _check(
      _bindings.queueNext(_handle),
    );
  }

  void nextQueueAndPlay() {
    _ensureNotDisposed();

    _check(
      _bindings.queueNextAndPlay(_handle),
    );
  }

  void previousQueue() {
    _ensureNotDisposed();

    _check(
      _bindings.queuePrevious(_handle),
    );
  }

  void previousQueueAndPlay() {
    _ensureNotDisposed();

    _check(
      _bindings.queuePreviousAndPlay(
        _handle,
      ),
    );
  }

  void repeatCurrentQueueTrackAndPlay() {
    _ensureNotDisposed();

    _check(
      _bindings.queueRepeatCurrentAndPlay(
        _handle,
      ),
    );
  }

  void advanceQueueAndPlay() {
    _ensureNotDisposed();

    _check(
      _bindings.queueAdvanceAndPlay(
        _handle,
      ),
    );
  }

  bool advanceQueueIfAtEnd() {
    _ensureNotDisposed();

    final result =
        _bindings.queueAdvanceIfAtEnd(
      _handle,
    );

    if (result == 0) {
      return true;
    }

    if (result == 4) {
      return false;
    }

    _check(result);

    return false;
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _bindings.destroy(_handle);

    _handle = ffi.nullptr;

    _disposed = true;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        'OfflinePlayer has already been disposed.',
      );
    }
  }

  void _check(int result) {
    if (result == 0) {
      return;
    }

    final message = _readLastError();

    throw OfflinePlayerException(
      result,
      message.isEmpty
          ? 'OfflinePlayer operation failed.'
          : message,
    );
  }

  String _readLastError() {
    const capacity = 4096;

    final buffer = calloc<ffi.Uint8>(capacity);

    try {
      final result = _bindings.lastError(
        _handle,
        buffer.cast<Utf8>(),
        capacity,
      );

      if (result != 0 && result != 7) {
        return '';
      }

      return buffer
          .cast<Utf8>()
          .toDartString();
    } finally {
      calloc.free(buffer);
    }
  }
}
