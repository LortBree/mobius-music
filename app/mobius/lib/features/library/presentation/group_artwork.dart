import 'package:flutter/material.dart';

import '../../../core/ffi/offline_player.dart';
import '../data/ffi_library_repository.dart';

/// Remembers WHICH track of a group (album, artist) supplies its cover,
/// without holding the encoded image bytes.
///
/// The bytes are fetched on demand through the repository's bounded LRU, so
/// a grid of hundreds of albums keeps only integers alive instead of every
/// cover's full embedded image.
class GroupArtworkSource {
  GroupArtworkSource(this.trackIds);

  final List<int> trackIds;

  /// `null` = not resolved yet, `0` = no track in the group has artwork.
  int? _artworkTrackId;

  /// The cover for this group: the first track, in library order, that has
  /// non-empty artwork. The scan runs once; later calls read one track.
  TrackArtwork? resolve(LibraryRepository repository) {
    final known = _artworkTrackId;
    if (known == 0) return null;
    if (known != null) {
      final artwork = _read(repository, known);
      if (artwork != null) return artwork;
    }

    for (final trackId in trackIds) {
      final artwork = _read(repository, trackId);
      if (artwork != null) {
        _artworkTrackId = trackId;
        return artwork;
      }
    }
    _artworkTrackId = 0;
    return null;
  }

  static TrackArtwork? _read(LibraryRepository repository, int trackId) {
    try {
      final artwork = repository.getTrackArtwork(trackId);
      return artwork != null && artwork.data.isNotEmpty ? artwork : null;
    } catch (_) {
      return null;
    }
  }
}

/// Lazily loads and shows a [GroupArtworkSource] cover. Only cards that are
/// actually built (i.e. scrolled into view) touch the library.
class GroupArtwork extends StatefulWidget {
  const GroupArtwork({
    super.key,
    required this.repository,
    required this.source,
    required this.decodeSize,
    required this.filterQuality,
    required this.placeholder,
  });

  final LibraryRepository repository;
  final GroupArtworkSource source;

  /// Decoded pixel size (both axes). Match the displayed size in physical
  /// pixels; decoding larger only costs memory.
  final int decodeSize;
  final FilterQuality filterQuality;
  final Widget placeholder;

  @override
  State<GroupArtwork> createState() => _GroupArtworkState();
}

class _GroupArtworkState extends State<GroupArtwork> {
  TrackArtwork? _artwork;

  @override
  void initState() {
    super.initState();
    _artwork = widget.source.resolve(widget.repository);
  }

  @override
  void didUpdateWidget(covariant GroupArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source) ||
        !identical(oldWidget.repository, widget.repository)) {
      _artwork = widget.source.resolve(widget.repository);
    }
  }

  @override
  Widget build(BuildContext context) {
    final artwork = _artwork;
    if (artwork == null) return widget.placeholder;

    return Image.memory(
      artwork.data,
      cacheWidth: widget.decodeSize,
      cacheHeight: widget.decodeSize,
      fit: BoxFit.cover,
      filterQuality: widget.filterQuality,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => widget.placeholder,
    );
  }
}
