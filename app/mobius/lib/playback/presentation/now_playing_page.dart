import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ffi/offline_player.dart';
import '../../../core/keyboard/text_input_focus.dart';
import '../../../playback/audio_output_policy.dart';
import '../../../playback/player_controller.dart';
import '../../app/theme/colors.dart';
import '../../app/player_shell_state.dart' show kMobileBreakpoint;
import '../../features/library/data/ffi_library_repository.dart';
import '../../features/sound/presentation/sound_page.dart';
import '../playback_time_format.dart';
import '../../features/library/data/user_collections.dart';
import '../playback_poller.dart';
import '../lyrics/flac_lyrics_reader.dart';
import '../lyrics/lrc_parser.dart';
import '../lyrics/lyrics_view.dart';
import 'queue_panel.dart';
import 'shareable_music_card.dart';
import 'signal_path_view.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({
    super.key,
    required this.repository,
    required this.playerController,
    this.collections,
    this.initialOpenQueue = false,
    this.initialOpenLyrics = false,
    this.isFavorite = false,
    this.onToggleFavorite,
    this.onAddToPlaylist,
  });

  final FfiLibraryRepository repository;
  final PlayerController playerController;
  final UserCollections? collections;
  final bool initialOpenQueue;
  final bool initialOpenLyrics;

  /// Whether the current track is a favorite. The shell owns favorites, so it
  /// passes the value in (and the toggle below out). Null callback => the
  /// heart renders disabled (desktop, which has its own controls elsewhere).
  final bool isFavorite;
  final FutureOr<void> Function()? onToggleFavorite;

  /// Opens the shell's add-to-playlist flow for the current track. Null =>
  /// the mobile Playlist action is disabled.
  final VoidCallback? onAddToPlaylist;

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  static final Map<String, Color> _albumAccentColorCache = {};
  static final Map<int, Color> _accentColorCache = {};
  static final Map<String, ImageProvider> _albumArtworkProviderCache = {};
  static final Map<int, ImageProvider> _artworkProviderCache = {};
  static final Map<String, Uint8List> _albumArtworkBytesCache = {};
  static final Map<int, Uint8List> _artworkBytesCache = {};

  late final PlaybackPoller _poller = PlaybackPoller(
    onTick: _tick,
    isActive: () => _state == OfflinePlayerState.playing,
  );

  TrackMetadata? _track;
  ImageProvider? _artworkImage;
  Uint8List? _artworkBytes;
  Color? _extractedAccent;
  TrackTechnicalInfo? _technicalInfo;
  AudioOutputDecision? _audioOutputDecision;

  int _currentTrackId = 0;
  bool _isFavorite = false;

  // Position changes every poll tick; keep it out of
  // setState so only the seek bar and time label rebuild.
  final ValueNotifier<double> _positionNotifier = ValueNotifier<double>(0);
  double get _position => _positionNotifier.value;

  double _duration = 0;
  int _totalFrames = 0;

  OfflinePlayerState _state = OfflinePlayerState.idle;

  OfflinePlayerRepeatMode _repeatMode = OfflinePlayerRepeatMode.off;

  /// Latest resolved signal path for the inline strip. Kept in a notifier so
  /// the ~1 s refresh only rebuilds the strip, not the whole page. Null when
  /// nothing is loaded or the engine cannot report it (the engine side of the
  /// signal path is implemented in parallel and currently returns null — the
  /// strip handles that by rendering "Nothing playing").
  final ValueNotifier<SignalPath?> _signalPath = ValueNotifier<SignalPath?>(
    null,
  );

  /// Guards against overlapping async signal-path reads piling up.
  bool _signalPathInFlight = false;

  bool _isSeeking = false;

  bool _queueOpen = false;
  double _queueWidth = 340;

  static const double _minQueueWidth = 280;
  static const double _maxQueueWidth = 520;

  ParsedLyrics? _parsedLyrics;
  bool _showLyrics = false;
  int _lyricsTrackId = -1;

  void _toggleLyrics() {
    setState(() {
      _showLyrics = !_showLyrics;
    });
  }

  void _onSeekToLyric(Duration timestamp) {
    final seconds = timestamp.inMilliseconds / 1000.0;
    _onSeekEnd(seconds);
  }

  Future<void> _loadLyricsForTrack(int trackId) async {
    if (trackId <= 0) {
      if (mounted) setState(() => _parsedLyrics = null);
      return;
    }
    if (_lyricsTrackId == trackId && _parsedLyrics != null) return;
    _lyricsTrackId = trackId;

    final path = widget.playerController.currentTrackPath;
    if (path.isEmpty) {
      if (mounted) setState(() => _parsedLyrics = null);
      return;
    }

    try {
      final rawLyrics = await FlacLyricsReader.readLyrics(path);
      final parsed =
          rawLyrics != null ? ParsedLyrics.parse(rawLyrics) : null;
      if (mounted && _currentTrackId == trackId) {
        setState(() => _parsedLyrics = parsed);
      }
    } catch (_) {
      if (mounted && _currentTrackId == trackId) {
        setState(() => _parsedLyrics = null);
      }
    }
  }

  @override
  void initState() {
    super.initState();

    _isFavorite = widget.isFavorite;
    _syncPlayer();
    if (_currentTrackId > 0) {
      _loadFavoriteStatus(_currentTrackId);
      _loadLyricsForTrack(_currentTrackId);
    }

    widget.playerController.commands.addListener(_onPlayerCommand);
    widget.playerController.pendingTrackId.addListener(_onPendingTrack);
    _poller.start();

    _queueOpen = widget.initialOpenQueue;
    _showLyrics = widget.initialOpenLyrics;
    _refreshSignalPath();
  }

  @override
  void dispose() {
    widget.playerController.commands.removeListener(_onPlayerCommand);
    widget.playerController.pendingTrackId.removeListener(_onPendingTrack);
    _poller.stop();
    _positionNotifier.dispose();
    _signalPath.dispose();
    super.dispose();
  }

  /// Resolves the live signal path off the build path. Serialised through
  /// [_signalPathInFlight] so a slow read never stacks up behind the ~1 s
  /// poll cadence. Errors collapse to null (strip shows "Nothing playing").
  Future<void> _refreshSignalPath() async {
    if (_signalPathInFlight) return;
    _signalPathInFlight = true;
    try {
      final path = await widget.playerController.readSignalPath();
      if (mounted) _signalPath.value = path;
    } catch (_) {
      if (mounted) _signalPath.value = null;
    } finally {
      _signalPathInFlight = false;
    }
  }

  /// Paint the upcoming track before the native load blocks the UI thread.
  /// Technical info stays on the old track until the real sync, because it
  /// is only known once the new file is open.
  void _onPendingTrack() {
    final trackId = widget.playerController.pendingTrackId.value;
    if (!mounted || trackId == null || trackId == _currentTrackId) return;
    TrackMetadata? track;
    try {
      track = widget.repository.getTrackMetadata(trackId);
    } catch (_) {}
    _positionNotifier.value = 0;
    setState(() {
      _track = track;
      _loadArtworkForTrack(trackId, track: track);
    });
    _loadFavoriteStatus(trackId);
  }

  void _onPlayerCommand() {
    scheduleMicrotask(() {
      if (!mounted) return;
      _tick();
      _poller.wake();
    });
  }

  void _tick() {
    if (!mounted ||
        _isSeeking ||
        widget.playerController.pendingTrackId.value != null) {
      return;
    }

    _syncPlayer();
    _refreshSignalPath();
  }

  static String _resolveAlbumKey(TrackMetadata? metadata, int trackId) {
    if (metadata != null &&
        metadata.album.trim().isNotEmpty &&
        metadata.artist.trim().isNotEmpty) {
      return '${metadata.artist.trim().toLowerCase()} - ${metadata.album.trim().toLowerCase()}';
    }
    return 'track_$trackId';
  }

  void _loadArtworkForTrack(int trackId, {TrackMetadata? track}) {
    if (trackId <= 0) {
      _artworkImage = null;
      _artworkBytes = null;
      _extractedAccent = null;
      return;
    }

    TrackMetadata? metadata = track ?? _track;
    if (metadata == null || metadata.trackId != trackId) {
      try {
        metadata = widget.repository.getTrackMetadata(trackId);
      } catch (_) {
        metadata = null;
      }
    }

    final albumKey = _resolveAlbumKey(metadata, trackId);

    if (_albumAccentColorCache.containsKey(albumKey)) {
      _extractedAccent = _albumAccentColorCache[albumKey];
    } else if (_accentColorCache.containsKey(trackId)) {
      _extractedAccent = _accentColorCache[trackId];
    }

    if (_albumArtworkProviderCache.containsKey(albumKey)) {
      _artworkImage = _albumArtworkProviderCache[albumKey];
      _artworkBytes = _albumArtworkBytesCache[albumKey];
      if (!_albumAccentColorCache.containsKey(albumKey) &&
          !_accentColorCache.containsKey(trackId) &&
          _artworkBytes != null) {
        unawaited(_extractColorFromArtwork(trackId, albumKey, _artworkBytes));
      }
      return;
    }

    if (_artworkProviderCache.containsKey(trackId)) {
      _artworkImage = _artworkProviderCache[trackId];
      _artworkBytes = _artworkBytesCache[trackId];
      if (_artworkImage != null) {
        _albumArtworkProviderCache[albumKey] = _artworkImage!;
      }
      if (_artworkBytes != null) {
        _albumArtworkBytesCache[albumKey] = _artworkBytes!;
      }
      if (!_albumAccentColorCache.containsKey(albumKey) &&
          !_accentColorCache.containsKey(trackId) &&
          _artworkBytes != null) {
        unawaited(_extractColorFromArtwork(trackId, albumKey, _artworkBytes));
      }
      return;
    }

    try {
      final artwork = widget.repository.getTrackArtwork(trackId);

      if (artwork == null || artwork.data.isEmpty) {
        _artworkImage = null;
        _artworkBytes = null;
        _extractedAccent = null;
        return;
      }

      _artworkBytes = artwork.data;
      _artworkBytesCache[trackId] = artwork.data;
      _albumArtworkBytesCache[albumKey] = artwork.data;
      final provider = ResizeImage(
        MemoryImage(artwork.data),
        width: 960,
        height: 960,
      );
      _artworkImage = provider;
      _artworkProviderCache[trackId] = provider;
      _albumArtworkProviderCache[albumKey] = provider;

      if (!_albumAccentColorCache.containsKey(albumKey) &&
          !_accentColorCache.containsKey(trackId)) {
        unawaited(_extractColorFromArtwork(trackId, albumKey, artwork.data));
      }
    } catch (_) {
      _artworkImage = null;
      _artworkBytes = null;
      _extractedAccent = null;
    }
  }

  Future<void> _extractColorFromArtwork(
    int trackId,
    String albumKey,
    Uint8List? bytes,
  ) async {
    if (bytes == null || bytes.isEmpty) {
      if (mounted && _extractedAccent != null) {
        setState(() => _extractedAccent = null);
      }
      return;
    }
    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: MemoryImage(bytes),
        brightness: Brightness.dark,
      );
      _albumAccentColorCache[albumKey] = scheme.primary;
      _accentColorCache[trackId] = scheme.primary;
      if (mounted && _currentTrackId == trackId) {
        setState(() => _extractedAccent = scheme.primary);
      }
    } catch (_) {
      // Fallback cleanly
    }
  }

  Color _getTopGradientColor(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    final tunedHsl = hsl.withLightness(hsl.lightness.clamp(0.18, 0.32));
    return tunedHsl.toColor();
  }

  void _loadFavoriteStatus(int trackId) {
    if (trackId <= 0) {
      if (mounted) setState(() => _isFavorite = false);
      return;
    }
    widget.collections?.favorites().then((favs) {
      if (mounted && _currentTrackId == trackId) {
        setState(() => _isFavorite = favs.contains(trackId));
      }
    });
  }

  Future<void> _toggleFavorite() async {
    final trackId = _currentTrackId;
    if (trackId <= 0) return;

    setState(() {
      _isFavorite = !_isFavorite;
    });

    try {
      if (widget.onToggleFavorite != null) {
        await widget.onToggleFavorite!();
      } else if (widget.collections != null) {
        await widget.collections!.toggleFavorite(trackId);
      }
      if (widget.collections != null) {
        final favs = await widget.collections!.favorites();
        if (mounted && _currentTrackId == trackId) {
          setState(() => _isFavorite = favs.contains(trackId));
        }
      }
    } catch (_) {}
  }

  void _syncPlayer() {
    try {
      final currentTrackId = widget.playerController.currentTrackId;

      final position = widget.playerController.currentSeconds;

      final duration = widget.playerController.durationSeconds;

      final totalFrames = widget.playerController.totalFrames;

      final state = widget.playerController.state;

      final repeatMode = widget.playerController.repeatMode;

      TrackMetadata? track = _track;
      TrackTechnicalInfo? technicalInfo = _technicalInfo;
      AudioOutputDecision? audioOutputDecision = _audioOutputDecision;

      if (currentTrackId != _currentTrackId) {
        if (currentTrackId > 0) {
          try {
            track = widget.repository.getTrackMetadata(currentTrackId);
          } catch (_) {
            track = null;
          }

          try {
            technicalInfo = widget.playerController.technicalInfo;
          } catch (_) {
            technicalInfo = null;
          }

          try {
            audioOutputDecision = widget.playerController.audioOutputDecision;
          } catch (_) {
            audioOutputDecision = null;
          }
        } else {
          track = null;
          technicalInfo = null;
          audioOutputDecision = null;
        }

        _loadArtworkForTrack(currentTrackId, track: track);
        _loadFavoriteStatus(currentTrackId);
        _loadLyricsForTrack(currentTrackId);
      }

      if (!mounted) {
        return;
      }

      _positionNotifier.value = position;

      // Track metadata/technical info only change with the
      // track id, so the id check covers them.
      final discreteChanged =
          currentTrackId != _currentTrackId ||
          duration != _duration ||
          totalFrames != _totalFrames ||
          state != _state ||
          repeatMode != _repeatMode;

      if (!discreteChanged) {
        return;
      }

      setState(() {
        _currentTrackId = currentTrackId;
        _duration = duration;
        _totalFrames = totalFrames;
        _state = state;
        _repeatMode = repeatMode;
        _track = track;
        _technicalInfo = technicalInfo;
        _audioOutputDecision = audioOutputDecision;
      });
    } catch (_) {
      // Keep the current UI state if native state
      // temporarily cannot be read.
    }
  }

  void _togglePlayback() {
    try {
      if (_state == OfflinePlayerState.playing) {
        widget.playerController.pause();
      } else {
        widget.playerController.play();
      }

      _syncPlayer();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _previous() async {
    try {
      await widget.playerController.previous();
      if (mounted) _syncPlayer();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _next() async {
    try {
      await widget.playerController.next();
      if (mounted) _syncPlayer();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _cycleRepeatMode() {
    try {
      final nextMode = switch (_repeatMode) {
        OfflinePlayerRepeatMode.off => OfflinePlayerRepeatMode.track,
        OfflinePlayerRepeatMode.track => OfflinePlayerRepeatMode.queue,
        OfflinePlayerRepeatMode.queue => OfflinePlayerRepeatMode.off,
      };

      widget.playerController.setRepeatMode(nextMode);

      _syncPlayer();
    } catch (error) {
      _showError(error);
    }
  }

  void _toggleQueue() {
    setState(() {
      _queueOpen = !_queueOpen;
    });
  }

  void _resizeQueue(DragUpdateDetails details) {
    final nextWidth = (_queueWidth - details.delta.dx).clamp(
      _minQueueWidth,
      _maxQueueWidth,
    );

    if (nextWidth == _queueWidth) {
      return;
    }

    setState(() {
      _queueWidth = nextWidth;
    });
  }

  void _onSeekChanged(double value) {
    if (!_isSeeking) {
      setState(() {
        _isSeeking = true;
      });
    }

    _positionNotifier.value = value;
  }

  void _onSeekEnd(double value) {
    final duration = _duration;
    final totalFrames = _totalFrames;

    if (duration <= 0 || totalFrames <= 0) {
      setState(() {
        _isSeeking = false;
      });
      return;
    }

    if (value >= duration - 0.5) {
      setState(() {
        _isSeeking = false;
      });
      widget.playerController.next();
      return;
    }

    final ratio = (value / duration).clamp(0.0, 1.0);

    final maxSafeFrame = totalFrames > 22050 ? totalFrames - 22050 : totalFrames;
    final frame = (ratio * totalFrames).round().clamp(0, maxSafeFrame);

    try {
      widget.playerController.seekToFrame(frame);

      if (!mounted) {
        return;
      }

      _positionNotifier.value = value;

      setState(() {
        _isSeeking = false;
      });

      _syncPlayer();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSeeking = false;
      });

      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.toString())));
  }

  String _formatTime(double seconds) => formatPlaybackTime(seconds);

  String _formatSampleRate(int sampleRate) {
    return formatSampleRate(sampleRate);
  }

  String _formatChannels(int channels) {
    switch (channels) {
      case 1:
        return 'Mono';
      case 2:
        return 'Stereo';
      default:
        return '$channels ch';
    }
  }

  IconData _repeatIcon() {
    switch (_repeatMode) {
      case OfflinePlayerRepeatMode.off:
        return Icons.repeat;
      case OfflinePlayerRepeatMode.track:
        return Icons.repeat_one;
      case OfflinePlayerRepeatMode.queue:
        return Icons.repeat;
    }
  }

  String _repeatLabel() {
    switch (_repeatMode) {
      case OfflinePlayerRepeatMode.off:
        return 'Repeat off';
      case OfflinePlayerRepeatMode.track:
        return 'Repeat track';
      case OfflinePlayerRepeatMode.queue:
        return 'Repeat queue';
    }
  }

  KeyEventResult _handleKeyboardShortcut(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (isEditingText()) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final shift = keyboard.isShiftPressed;
    final key = event.logicalKey;
    if (!shift && key == LogicalKeyboardKey.space) {
      _togglePlayback();
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.arrowLeft) {
      _previous();
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.arrowRight) {
      _next();
      return KeyEventResult.handled;
    }
    if (!shift && key == LogicalKeyboardKey.arrowLeft) {
      _onSeekEnd(_enginePosition() - 5);
      return KeyEventResult.handled;
    }
    if (!shift && key == LogicalKeyboardKey.arrowRight) {
      _onSeekEnd(_enginePosition() + 5);
      return KeyEventResult.handled;
    }
    if (!shift && key == LogicalKeyboardKey.arrowUp) {
      _adjustVolume(0.05);
      return KeyEventResult.handled;
    }
    if (!shift && key == LogicalKeyboardKey.arrowDown) {
      _adjustVolume(-0.05);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Where audio really is -- not the seek bar's drag preview.
  double _enginePosition() {
    try {
      return widget.playerController.currentSeconds;
    } catch (_) {
      return _position;
    }
  }

  void _adjustVolume(double delta) {
    try {
      widget.playerController.setVolume(widget.playerController.volume + delta);
    } catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < kMobileBreakpoint;
    if (isMobile) {
      return _buildMobileScaffold(context);
    }
    return _buildDesktopScaffold(context);
  }

  Widget _buildDesktopScaffold(BuildContext context) {
    final track = _track;
    final technicalInfo = _technicalInfo;
    final audioOutputDecision = _audioOutputDecision;

    final maxValue = _duration > 0 ? _duration : 1.0;

    return Scaffold(
      backgroundColor: MobiusColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: MobiusColors.textOf(context),
        elevation: 0,
        title: const Text('Now Playing'),
        actions: [
          IconButton(
            tooltip: 'Share music card',
            icon: const Icon(Icons.share_rounded),
            onPressed: _openShareCard,
          ),
          IconButton(
            tooltip: _showLyrics ? 'Hide lyrics' : 'Lyrics',
            icon: Icon(
              _showLyrics ? Icons.lyrics_rounded : Icons.lyrics_outlined,
            ),
            color: _showLyrics
                ? MobiusColors.accentLightOf(context)
                : MobiusColors.textOf(context),
            onPressed: _toggleLyrics,
          ),
          IconButton(
            tooltip: _queueOpen ? 'Hide queue' : 'Show queue',
            onPressed: _toggleQueue,
            color: _queueOpen
                ? MobiusColors.accentLightOf(context)
                : MobiusColors.textOf(context),
            icon: const Icon(Icons.queue_music),
          ),
        ],
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: _handleKeyboardShortcut,
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (_showLyrics && constraints.maxWidth >= 780) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(36, 16, 36, 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 5,
                              child: SingleChildScrollView(
                                child: _buildDesktopPlayerControls(
                                  track: track,
                                  technicalInfo: technicalInfo,
                                  audioOutputDecision: audioOutputDecision,
                                  maxValue: maxValue,
                                  artworkSize: 260,
                                ),
                              ),
                            ),
                            const SizedBox(width: 36),
                            Expanded(
                              flex: 6,
                              child: Container(
                                height: constraints.maxHeight - 48,
                                decoration: BoxDecoration(
                                  color: MobiusColors.panelOf(context).withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: MobiusColors.borderOf(context).withValues(alpha: 0.3),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: LyricsView(
                                    lyrics: _parsedLyrics,
                                    positionNotifier: _positionNotifier,
                                    accentColor: _extractedAccent,
                                    onSeek: _onSeekToLyric,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 56,
                        ),
                        child: _buildDesktopPlayerControls(
                          track: track,
                          technicalInfo: technicalInfo,
                          audioOutputDecision: audioOutputDecision,
                          maxValue: maxValue,
                          artworkSize: 320,
                        ),
                      ),
                    );
                  },
                ),
              ),

              if (_queueOpen) ...[
                _QueueResizeHandle(onDragUpdate: _resizeQueue),

                SizedBox(
                  width: _queueWidth,
                  child: QueuePanel(
                    repository: widget.repository,
                    playerController: widget.playerController,
                    onTrackSelected: _syncPlayer,
                    onClose: _toggleQueue,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopPlayerControls({
    required TrackMetadata? track,
    required TrackTechnicalInfo? technicalInfo,
    required AudioOutputDecision? audioOutputDecision,
    required double maxValue,
    required double artworkSize,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Artwork(size: artworkSize, image: _artworkImage),
        SizedBox(height: artworkSize < 300 ? 20 : 32),
        Text(
          track?.title.isNotEmpty == true ? track!.title : 'Nothing playing',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: MobiusColors.textOf(context),
            fontSize: artworkSize < 300 ? 22 : 26,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          track?.artist.isNotEmpty == true ? track!.artist : 'Unknown artist',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: MobiusColors.textDimOf(context),
            fontSize: artworkSize < 300 ? 14 : 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          track?.album.isNotEmpty == true ? track!.album : 'Unknown album',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: MobiusColors.textDimOf(context),
            fontSize: artworkSize < 300 ? 13 : 14,
          ),
        ),
        const SizedBox(height: 14),
        if (technicalInfo != null)
          _TechnicalInfo(
            technicalInfo: technicalInfo,
            formatSampleRate: _formatSampleRate,
            formatChannels: _formatChannels,
          ),
        if (audioOutputDecision != null) ...[
          const SizedBox(height: 8),
          _AudioOutputInfo(decision: audioOutputDecision),
        ],
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ValueListenableBuilder<double>(
            valueListenable: _positionNotifier,
            builder: (context, position, _) => _SeekBar(
              value: position.clamp(0.0, maxValue),
              duration: _duration,
              enabled: _duration > 0 && _totalFrames > 0,
              onChanged: _onSeekChanged,
              onChangeEnd: _onSeekEnd,
              formatTime: _formatTime,
            ),
          ),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _positionNotifier,
                  builder: (context, position, _) => Text(
                    _formatTime(position),
                    style: TextStyle(
                      color: MobiusColors.textDimOf(context),
                      fontSize: 12,
                      fontFeatures: const [
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
                Text(
                  _formatTime(_duration),
                  style: TextStyle(
                    color: MobiusColors.textDimOf(context),
                    fontSize: 12,
                    fontFeatures: const [
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous',
              onPressed: widget.playerController.queueLength > 0 ? _previous : null,
              iconSize: 28,
              color: MobiusColors.textOf(context),
              icon: const Icon(Icons.skip_previous),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 60,
              height: 60,
              child: IconButton(
                tooltip: _state == OfflinePlayerState.playing ? 'Pause' : 'Play',
                onPressed: _togglePlayback,
                iconSize: 36,
                color: MobiusColors.onAccentOf(context),
                style: IconButton.styleFrom(
                  backgroundColor: MobiusColors.accentOf(context),
                ),
                icon: Icon(
                  _state == OfflinePlayerState.playing ? Icons.pause : Icons.play_arrow,
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              tooltip: 'Next',
              onPressed: widget.playerController.queueLength > 0 ? _next : null,
              iconSize: 28,
              color: MobiusColors.textOf(context),
              icon: const Icon(Icons.skip_next),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: _repeatLabel(),
              onPressed: _cycleRepeatMode,
              color: _repeatMode == OfflinePlayerRepeatMode.off
                  ? MobiusColors.textDimOf(context)
                  : MobiusColors.accentLightOf(context),
              icon: Icon(_repeatIcon()),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _toggleQueue,
              icon: const Icon(Icons.queue_music, size: 18),
              label: const Text('Queue'),
              style: OutlinedButton.styleFrom(
                foregroundColor: MobiusColors.textOf(context),
                side: BorderSide(
                  color: MobiusColors.borderOf(context),
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _toggleLyrics,
              icon: Icon(
                _showLyrics ? Icons.music_note_rounded : Icons.lyrics_rounded,
                size: 18,
              ),
              label: Text(_showLyrics ? 'Artwork' : 'Lyrics'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _showLyrics
                    ? (_extractedAccent ?? MobiusColors.accentLightOf(context))
                    : MobiusColors.textOf(context),
                side: BorderSide(
                  color: _showLyrics
                      ? (_extractedAccent ?? MobiusColors.accentLightOf(context))
                      : MobiusColors.borderOf(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          switch (_state) {
            OfflinePlayerState.playing => 'Playing',
            OfflinePlayerState.paused => 'Paused',
            OfflinePlayerState.loaded => 'Loaded',
            OfflinePlayerState.stopped => 'Stopped',
            OfflinePlayerState.idle => 'Idle',
          },
          style: TextStyle(
            color: MobiusColors.textDimOf(context),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // Mobile layout (Spotify-mobile style). Reuses the same state, poller,
  // seek logic and audio-output decision as the desktop layout.
  // -----------------------------------------------------------------------

  Widget _buildMobileScaffold(BuildContext context) {
    final track = _track;
    final maxValue = _duration > 0 ? _duration : 1.0;
    final hasQueue = widget.playerController.queueLength > 0;
    const defaultAccent = Color(0xFF181818);
    final topColor = _getTopGradientColor(_extractedAccent ?? defaultAccent);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: MobiusColors.textOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        // Android Back already pops this pushed route; the chevron is the
        // explicit affordance.
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          iconSize: 28,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Now Playing'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _showLyrics ? 'Show Artwork' : 'Show Lyrics',
            icon: Icon(
              _showLyrics ? Icons.music_note_rounded : Icons.lyrics_rounded,
            ),
            color: _showLyrics
                ? (_extractedAccent ?? MobiusColors.accentLightOf(context))
                : null,
            onPressed: _toggleLyrics,
          ),
          IconButton(
            tooltip: 'Share music card',
            icon: const Icon(Icons.share_rounded),
            onPressed: _openShareCard,
          ),
        ],
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.45, 1.0],
            colors: [
              topColor,
              Color.lerp(topColor, Colors.black, 0.60)!,
              const Color(0xFF000000),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _showLyrics
                      ? Padding(
                          key: const ValueKey('lyrics_screen'),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: LyricsView(
                            lyrics: _parsedLyrics,
                            positionNotifier: _positionNotifier,
                            accentColor: _extractedAccent,
                            onSeek: _onSeekToLyric,
                          ),
                        )
                      : Center(
                          key: const ValueKey('artwork_screen'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 8,
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final size = constraints.maxWidth <
                                        constraints.maxHeight
                                    ? constraints.maxWidth
                                    : constraints.maxHeight;
                                final clampedSize = size.clamp(0.0, 360.0);
                                return _Artwork(
                                  size: clampedSize,
                                  image: _artworkImage,
                                );
                              },
                            ),
                          ),
                        ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (_showLyrics && _artworkImage != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Image(
                                image: _artworkImage!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              NowPlayingMarqueeTitle(
                                key: ValueKey(track?.trackId ?? 0),
                                text: track?.title.isNotEmpty == true
                                    ? track!.title
                                    : 'Nothing playing',
                                style: TextStyle(
                                  color: MobiusColors.textOf(context),
                                  fontSize: _showLyrics ? 18 : 22,
                                  fontWeight: FontWeight.w700,
                                ),
                                isPlaying: _state == OfflinePlayerState.playing,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                track?.artist.isNotEmpty == true
                                    ? track!.artist
                                    : 'Unknown artist',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: MobiusColors.textDimOf(context),
                                  fontSize: _showLyrics ? 13 : 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          tooltip: _isFavorite
                              ? 'Remove from Favorites'
                              : 'Add to Favorites',
                          icon: Icon(
                            _isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                          ),
                          color: _isFavorite
                              ? MobiusColors.accentLightOf(context)
                              : MobiusColors.textDimOf(context),
                          onPressed: _toggleFavorite,
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    ValueListenableBuilder<SignalPath?>(
                      valueListenable: _signalPath,
                      builder: (context, path, _) => SignalPathStrip(
                        path: path,
                        onTap: () => _openSignalPathSheet(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    ValueListenableBuilder<double>(
                      valueListenable: _positionNotifier,
                      builder: (context, position, _) => _SeekBar(
                        value: position.clamp(0.0, maxValue),
                        duration: _duration,
                        enabled: _duration > 0 && _totalFrames > 0,
                        onChanged: _onSeekChanged,
                        onChangeEnd: _onSeekEnd,
                        formatTime: _formatTime,
                        glowThumb: true,
                      ),
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ValueListenableBuilder<double>(
                          valueListenable: _positionNotifier,
                          builder: (context, position, _) => Text(
                            _formatTime(position),
                            style: TextStyle(
                              color: MobiusColors.textDimOf(context),
                              fontSize: 12,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        Text(
                          _formatTime(_duration),
                          style: TextStyle(
                            color: MobiusColors.textDimOf(context),
                            fontSize: 12,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Control row: shuffle · previous · play/pause · next · loop.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        IconButton(
                          tooltip: 'Shuffle',
                          iconSize: 24,
                          color: MobiusColors.textDimOf(context),
                          icon: const Icon(Icons.shuffle_rounded),
                          onPressed: null,
                        ),
                        IconButton(
                          tooltip: 'Previous',
                          iconSize: 32,
                          color: hasQueue
                              ? MobiusColors.textOf(context)
                              : MobiusColors.textDimOf(context),
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: hasQueue ? _previous : null,
                        ),
                        SizedBox(
                          width: 66,
                          height: 66,
                          child: IconButton(
                            tooltip: _state == OfflinePlayerState.playing
                                ? 'Pause'
                                : 'Play',
                            iconSize: 38,
                            color: MobiusColors.onAccentOf(context),
                            style: IconButton.styleFrom(
                              backgroundColor: MobiusColors.accentOf(context),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                            icon: Icon(
                              _state == OfflinePlayerState.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            onPressed: _togglePlayback,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next',
                          iconSize: 32,
                          color: hasQueue
                              ? MobiusColors.textOf(context)
                              : MobiusColors.textDimOf(context),
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: hasQueue ? _next : null,
                        ),
                        IconButton(
                          tooltip: _repeatLabel(),
                          iconSize: 24,
                          color: _repeatMode == OfflinePlayerRepeatMode.off
                              ? MobiusColors.textDimOf(context)
                              : MobiusColors.accentLightOf(context),
                          icon: Icon(_repeatIcon()),
                          onPressed: _cycleRepeatMode,
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Bottom row: queue · lyrics · sound · playlist · share.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          tooltip: 'Queue',
                          iconSize: 20,
                          color: MobiusColors.textDimOf(context),
                          icon: const Icon(Icons.queue_music_rounded),
                          onPressed: _openQueueSheet,
                        ),
                        IconButton(
                          tooltip: _showLyrics ? 'Hide lyrics' : 'Lyrics',
                          iconSize: 20,
                          color: _showLyrics
                              ? (_extractedAccent ??
                                  MobiusColors.accentLightOf(context))
                              : MobiusColors.textDimOf(context),
                          icon: Icon(
                            _showLyrics
                                ? Icons.lyrics_rounded
                                : Icons.lyrics_outlined,
                          ),
                          onPressed: _toggleLyrics,
                        ),
                        IconButton(
                          tooltip: 'Sound',
                          iconSize: 20,
                          color: MobiusColors.textDimOf(context),
                          icon: const Icon(Icons.graphic_eq_rounded),
                          onPressed: _openSound,
                        ),
                        IconButton(
                          tooltip: 'Add to playlist',
                          iconSize: 20,
                          color: MobiusColors.textDimOf(context),
                          icon: const Icon(Icons.playlist_add_rounded),
                          onPressed: widget.onAddToPlaylist,
                        ),
                        IconButton(
                          tooltip: 'Share music card',
                          iconSize: 20,
                          color: MobiusColors.textDimOf(context),
                          icon: const Icon(Icons.share_rounded),
                          onPressed: _openShareCard,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openShareCard() async {
    final track = _track;
    if (track == null) return;

    SignalPath? path = _signalPath.value;
    try {
      path = await widget.playerController.readSignalPath();
      if (mounted) _signalPath.value = path;
    } catch (_) {}

    if (!mounted) return;
    await showShareableMusicCardModal(
      context: context,
      title: track.title,
      artist: track.artist,
      album: track.album,
      artworkBytes: _artworkBytes,
      signalPath: path,
    );
  }

  /// Opens the signal-path detail sheet with a FRESH read, so the sheet shows
  /// the state at tap time even between poll ticks.
  Future<void> _openSignalPathSheet() async {
    SignalPath? path = _signalPath.value;
    try {
      path = await widget.playerController.readSignalPath();
      if (mounted) _signalPath.value = path;
    } catch (_) {
      path = null;
    }
    if (!mounted) return;
    await showSignalPathSheet(context, path: path, controller: widget.playerController);
  }

  /// Pushes the Sound page (output / volume / equalizer) as its own route,
  /// matching how the mobile Settings page reaches it.
  void _openSound() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: MobiusColors.backgroundOf(context),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: MobiusColors.textOf(context),
            elevation: 0,
            title: const Text('Sound'),
          ),
          body: SafeArea(
            child: SoundPage(playerController: widget.playerController),
          ),
        ),
      ),
    );
  }

  /// Presents the same [QueuePanel] content as the desktop side panel, but as
  /// a draggable bottom sheet on mobile.
  Future<void> _openQueueSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MobiusColors.backgroundOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return QueuePanel(
              repository: widget.repository,
              playerController: widget.playerController,
              onTrackSelected: _syncPlayer,
              onClose: () => Navigator.of(sheetContext).maybePop(),
            );
          },
        );
      },
    );
  }
}


class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.value,
    required this.duration,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
    required this.formatTime,
    this.glowThumb = false,
  });

  final double value;
  final double duration;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final String Function(double) formatTime;

  /// Mobile: a thinner track with a white glowing thumb. Desktop leaves this
  /// false, keeping its existing accent thumb.
  final bool glowThumb;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _hoverValue;
  bool _dragging = false;

  @override
  void didUpdateWidget(covariant _SeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration || !widget.enabled) {
      _hoverValue = null;
      _dragging = false;
    }
  }

  double _valueFromPosition(double x, double width) {
    if (widget.duration <= 0 || width <= 0) {
      return 0;
    }

    final ratio = (x / width).clamp(0.0, 1.0);
    return ratio * widget.duration;
  }

  void _updateHover(PointerHoverEvent event, double width) {
    if (!widget.enabled || _dragging) {
      return;
    }

    setState(() {
      _hoverValue = _valueFromPosition(event.localPosition.dx, width);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final previewValue = _dragging ? widget.value : _hoverValue;

        final showPreview = widget.enabled && previewValue != null;

        final previewFraction = showPreview
            ? (previewValue / widget.duration).clamp(0.0, 1.0)
            : 0.0;

        const tooltipWidth = 68.0;
        final tooltipLeft = (previewFraction * width - tooltipWidth / 2).clamp(
          0.0,
          width - tooltipWidth,
        );

        return MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onHover: (event) => _updateHover(event, width),
          onExit: (_) {
            if (!_dragging && mounted) {
              setState(() {
                _hoverValue = null;
              });
            }
          },
          child: SizedBox(
            height: 54,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: widget.glowThumb ? 2.5 : 4,
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: widget.glowThumb ? 5 : 6,
                        elevation: 0,
                        pressedElevation: 0,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      activeTrackColor: MobiusColors.accentOf(context),
                      inactiveTrackColor: MobiusColors.borderOf(context),
                      thumbColor: widget.glowThumb
                          ? Colors.white
                          : MobiusColors.accentLightOf(context),
                      overlayColor: MobiusColors.accentOf(
                        context,
                      ).withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      min: 0,
                      max: widget.duration > 0 ? widget.duration : 1,
                      value: widget.value.clamp(
                        0.0,
                        widget.duration > 0 ? widget.duration : 1,
                      ),
                      onChangeStart: widget.enabled
                          ? (_) {
                              setState(() {
                                _dragging = true;
                                _hoverValue = widget.value;
                              });
                            }
                          : null,
                      onChanged: widget.enabled ? widget.onChanged : null,
                      onChangeEnd: widget.enabled
                          ? (value) {
                              widget.onChangeEnd(value);
                              if (mounted) {
                                setState(() {
                                  _dragging = false;
                                  _hoverValue = null;
                                });
                              }
                            }
                          : null,
                    ),
                  ),
                ),

                if (showPreview)
                  Positioned(
                    left: tooltipLeft,
                    bottom: 30,
                    child: IgnorePointer(
                      child: _SeekTooltip(
                        text: widget.formatTime(previewValue),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SeekTooltip extends StatelessWidget {
  const _SeekTooltip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scrim = MobiusColors.scrimOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 68,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scrim,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: MobiusColors.onScrimOf(context),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        CustomPaint(
          size: const Size(10, 6),
          painter: _SeekTooltipArrowPainter(color: scrim),
        ),
      ],
    );
  }
}

class _SeekTooltipArrowPainter extends CustomPainter {
  _SeekTooltipArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SeekTooltipArrowPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _TechnicalInfo extends StatelessWidget {
  const _TechnicalInfo({
    required this.technicalInfo,
    required this.formatSampleRate,
    required this.formatChannels,
  });

  final TrackTechnicalInfo technicalInfo;

  final String Function(int) formatSampleRate;
  final String Function(int) formatChannels;

  @override
  Widget build(BuildContext context) {
    // The sample rate lives on the SOURCE/OUTPUT line below, so this line
    // carries the file format instead of repeating it.
    final style = TextStyle(
      color: MobiusColors.textOf(context),
      fontSize: 13,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final parts = [
      if (technicalInfo.format.isNotEmpty) technicalInfo.format,
      '${technicalInfo.bitsPerSample}-bit',
      formatChannels(technicalInfo.channels),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '·',
                style: style.copyWith(color: MobiusColors.textDimOf(context)),
              ),
            ),
          Text(
            parts[i],
            style: i == 0 && technicalInfo.format.isNotEmpty
                ? style.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  )
                : style,
          ),
        ],
      ],
    );
  }
}

class _AudioOutputInfo extends StatelessWidget {
  const _AudioOutputInfo({required this.decision});

  final AudioOutputDecision decision;

  @override
  Widget build(BuildContext context) {
    final status = audioPlaybackStatusLabel(decision.status);

    final statusColor = decision.isNative
        ? MobiusColors.nativeOf(context)
        : MobiusColors.compatibleOf(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'SOURCE',
          style: TextStyle(
            color: MobiusColors.textDimOf(context),
            fontSize: 10,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          formatSampleRate(decision.sourceRate),
          style: TextStyle(
            color: MobiusColors.textOf(context),
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 20),
        Text(
          'OUTPUT',
          style: TextStyle(
            color: MobiusColors.textDimOf(context),
            fontSize: 10,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          formatSampleRate(decision.effectiveRate),
          style: TextStyle(
            color: MobiusColors.textOf(context),
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 10),
        _StatusBadge(
          label: status,
          color: statusColor,
          icon: decision.isNative
              ? Icons.verified_rounded
              : Icons.sync_alt_rounded,
        ),
      ],
    );
  }
}

/// Filled pill for the Native / Resampled verdict, so it reads at a glance
/// on both themes instead of as faint coloured text.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Output: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.size, required this.image});

  final double size;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: MobiusColors.panelOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MobiusColors.borderOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: image != null
          ? Image(
              image: image!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) {
                return Center(
                  child: Icon(
                    Icons.music_note,
                    size: 72,
                    color: MobiusColors.accentOf(context),
                  ),
                );
              },
            )
          : Center(
              child: Icon(
                Icons.music_note,
                size: 72,
                color: MobiusColors.accentOf(context),
              ),
            ),
    );
  }
}

class _QueueResizeHandle extends StatelessWidget {
  const _QueueResizeHandle({required this.onDragUpdate});

  final ValueChanged<DragUpdateDetails> onDragUpdate;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: onDragUpdate,
        child: SizedBox(
          width: 8,
          height: double.infinity,
          child: Center(
            child: Container(
              width: 1,
              height: double.infinity,
              color: MobiusColors.borderOf(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Running marquee text for Now Playing title on mobile.
///
/// If the text fits the container width, it renders static text.
/// If the text overflows, it smoothly scrolls horizontally with an initial
/// pause, soft right-edge fade mask, comfortable reading pace, and looping
/// pause, activating only while playback is active.
class NowPlayingMarqueeTitle extends StatefulWidget {
  const NowPlayingMarqueeTitle({
    super.key,
    required this.text,
    required this.style,
    required this.isPlaying,
  });

  final String text;
  final TextStyle style;
  final bool isPlaying;

  @override
  State<NowPlayingMarqueeTitle> createState() => _NowPlayingMarqueeTitleState();
}

class _NowPlayingMarqueeTitleState extends State<NowPlayingMarqueeTitle> {
  final ScrollController _controller = ScrollController();
  bool _isLooping = false;

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startLoop();
      });
    }
  }

  @override
  void didUpdateWidget(covariant NowPlayingMarqueeTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      if (_controller.hasClients) {
        _controller.jumpTo(0);
      }
      if (widget.isPlaying) {
        _startLoop();
      }
    } else if (!oldWidget.isPlaying && widget.isPlaying) {
      _startLoop();
    }
  }

  void _startLoop() {
    if (_isLooping) return;
    _isLooping = true;
    unawaited(_runAnimation());
  }

  Future<void> _runAnimation() async {
    // Initial pause so the user can comfortably read the beginning of the title
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    while (mounted && widget.isPlaying) {
      if (!_controller.hasClients) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final maxExtent = _controller.position.maxScrollExtent;
      if (maxExtent <= 0) break;

      // Comfortable reading speed: ~28 px/second
      final durationMs = (maxExtent / 28 * 1000).round().clamp(1500, 15000);
      await _controller.animateTo(
        maxExtent,
        duration: Duration(milliseconds: durationMs),
        curve: Curves.linear,
      );

      if (!mounted || !widget.isPlaying || !_controller.hasClients) break;

      // Pause at the end before returning
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      if (!mounted || !_controller.hasClients) break;

      _controller.jumpTo(0);
      await Future<void>.delayed(const Duration(milliseconds: 1400));
    }
    _isLooping = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();

        if (painter.width <= constraints.maxWidth) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        return ShaderMask(
          shaderCallback: (bounds) {
            return const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.90, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.only(right: 36),
              child: Text(
                widget.text,
                maxLines: 1,
                softWrap: false,
                style: widget.style,
              ),
            ),
          ),
        );
      },
    );
  }
}
