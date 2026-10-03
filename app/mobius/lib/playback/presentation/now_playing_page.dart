import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ffi/offline_player.dart';
import '../../../core/keyboard/text_input_focus.dart';
import '../../../playback/audio_output_policy.dart';
import '../../../playback/player_controller.dart';
import '../../app/theme/colors.dart';
import '../../features/library/data/ffi_library_repository.dart';
import '../playback_time_format.dart';
import '../playback_poller.dart';
import 'queue_panel.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({
    super.key,
    required this.repository,
    required this.playerController,
    this.initialOpenQueue = false,
  });

  final FfiLibraryRepository repository;
  final PlayerController playerController;
  final bool initialOpenQueue;

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  late final PlaybackPoller _poller = PlaybackPoller(
    onTick: _tick,
    isActive: () => _state == OfflinePlayerState.playing,
  );

  TrackMetadata? _track;
  ImageProvider? _artworkImage;
  TrackTechnicalInfo? _technicalInfo;
  AudioOutputDecision? _audioOutputDecision;

  int _currentTrackId = 0;

  // Position changes every poll tick; keep it out of
  // setState so only the seek bar and time label rebuild.
  final ValueNotifier<double> _positionNotifier = ValueNotifier<double>(0);
  double get _position => _positionNotifier.value;

  double _duration = 0;
  int _totalFrames = 0;

  OfflinePlayerState _state = OfflinePlayerState.idle;

  OfflinePlayerRepeatMode _repeatMode = OfflinePlayerRepeatMode.off;

  bool _isSeeking = false;

  bool _queueOpen = false;
  double _queueWidth = 340;

  static const double _minQueueWidth = 280;
  static const double _maxQueueWidth = 520;

  @override
  void initState() {
    super.initState();

    _syncPlayer();

    widget.playerController.commands.addListener(_onPlayerCommand);
    widget.playerController.pendingTrackId.addListener(_onPendingTrack);
    _poller.start();

    _queueOpen = widget.initialOpenQueue;
  }

  @override
  void dispose() {
    widget.playerController.commands.removeListener(_onPlayerCommand);
    widget.playerController.pendingTrackId.removeListener(_onPendingTrack);
    _poller.stop();
    _positionNotifier.dispose();
    super.dispose();
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
      _loadArtworkForTrack(trackId);
    });
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
  }

  void _loadArtworkForTrack(int trackId) {
    if (trackId <= 0) {
      _artworkImage = null;
      return;
    }

    try {
      final artwork = widget.repository.getTrackArtwork(trackId);

      if (artwork == null || artwork.data.isEmpty) {
        _artworkImage = null;
        return;
      }

      _artworkImage = ResizeImage(
        MemoryImage(artwork.data),
        width: 960,
        height: 960,
      );
    } catch (_) {
      _artworkImage = null;
    }
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
        _loadArtworkForTrack(currentTrackId);

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

    final ratio = (value / duration).clamp(0.0, 1.0);

    final frame = (ratio * totalFrames).round().clamp(0, totalFrames);

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
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 56,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _Artwork(size: 320, image: _artworkImage),

                            const SizedBox(height: 32),

                            Text(
                              track?.title.isNotEmpty == true
                                  ? track!.title
                                  : 'Nothing playing',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: MobiusColors.textOf(context),
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            const SizedBox(height: 8),

                            Text(
                              track?.artist.isNotEmpty == true
                                  ? track!.artist
                                  : 'Unknown artist',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: MobiusColors.textDimOf(context),
                                fontSize: 16,
                              ),
                            ),

                            const SizedBox(height: 4),

                            Text(
                              track?.album.isNotEmpty == true
                                  ? track!.album
                                  : 'Unknown album',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: MobiusColors.textDimOf(context),
                                fontSize: 14,
                              ),
                            ),

                            const SizedBox(height: 16),

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

                            const SizedBox(height: 24),

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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    ValueListenableBuilder<double>(
                                      valueListenable: _positionNotifier,
                                      builder: (context, position, _) => Text(
                                        _formatTime(position),
                                        style: TextStyle(
                                          color: MobiusColors.textDimOf(
                                            context,
                                          ),
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

                            const SizedBox(height: 20),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: 'Previous',
                                  onPressed:
                                      widget.playerController.queueLength > 0
                                      ? _previous
                                      : null,
                                  iconSize: 28,
                                  color: MobiusColors.textOf(context),
                                  icon: const Icon(Icons.skip_previous),
                                ),

                                const SizedBox(width: 16),

                                SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: IconButton(
                                    tooltip:
                                        _state == OfflinePlayerState.playing
                                        ? 'Pause'
                                        : 'Play',
                                    onPressed: _togglePlayback,
                                    iconSize: 38,
                                    color: MobiusColors.onAccentOf(context),
                                    style: IconButton.styleFrom(
                                      backgroundColor: MobiusColors.accentOf(
                                        context,
                                      ),
                                    ),
                                    icon: Icon(
                                      _state == OfflinePlayerState.playing
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 16),

                                IconButton(
                                  tooltip: 'Next',
                                  onPressed:
                                      widget.playerController.queueLength > 0
                                      ? _next
                                      : null,
                                  iconSize: 28,
                                  color: MobiusColors.textOf(context),
                                  icon: const Icon(Icons.skip_next),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: _repeatLabel(),
                                  onPressed: _cycleRepeatMode,
                                  color:
                                      _repeatMode == OfflinePlayerRepeatMode.off
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
                                    foregroundColor: MobiusColors.textOf(
                                      context,
                                    ),
                                    side: BorderSide(
                                      color: MobiusColors.borderOf(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

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
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.value,
    required this.duration,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
    required this.formatTime,
  });

  final double value;
  final double duration;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final String Function(double) formatTime;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _hoverValue;
  bool _dragging = false;

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
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      activeTrackColor: MobiusColors.accentOf(context),
                      inactiveTrackColor: MobiusColors.borderOf(context),
                      thumbColor: MobiusColors.accentLightOf(context),
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
                                  _hoverValue = value;
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
              filterQuality: FilterQuality.high,
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
