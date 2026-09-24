import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ffi/offline_player.dart';
import '../../../playback/audio_output_policy.dart';
import '../../../playback/player_controller.dart';
import '../../features/library/data/ffi_library_repository.dart';
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
  State<NowPlayingPage> createState() =>
      _NowPlayingPageState();
}

class _NowPlayingPageState
    extends State<NowPlayingPage> {
  Timer? _timer;

  TrackMetadata? _track;
  ImageProvider? _artworkImage;
  TrackTechnicalInfo? _technicalInfo;
  AudioOutputDecision? _audioOutputDecision;

  int _currentTrackId = 0;
  double _position = 0;
  double _duration = 0;
  int _totalFrames = 0;

  OfflinePlayerState _state =
      OfflinePlayerState.idle;

  OfflinePlayerRepeatMode _repeatMode =
      OfflinePlayerRepeatMode.off;

  bool _isSeeking = false;

  bool _queueOpen = false;
  double _queueWidth = 340;

  static const double _minQueueWidth = 280;
  static const double _maxQueueWidth = 520;

  @override
  void initState() {
    super.initState();

    _syncPlayer();

    _timer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _tick(),
    );

    _queueOpen = widget.initialOpenQueue;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted || _isSeeking) {
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
      final currentTrackId =
          widget.playerController.currentTrackId;

      final position =
          widget.playerController.currentSeconds;

      final duration =
          widget.playerController.durationSeconds;

      final totalFrames =
          widget.playerController.totalFrames;

      final state =
          widget.playerController.state;

      final repeatMode =
          widget.playerController.repeatMode;

      TrackMetadata? track = _track;
      TrackTechnicalInfo? technicalInfo =
          _technicalInfo;
      AudioOutputDecision? audioOutputDecision =
          _audioOutputDecision;

      if (currentTrackId != _currentTrackId) {
        _loadArtworkForTrack(currentTrackId);

        if (currentTrackId > 0) {
          try {
            track = widget.repository
                .getTrackMetadata(currentTrackId);
          } catch (_) {
            track = null;
          }

          try {
            technicalInfo =
                widget.playerController.technicalInfo;
          } catch (_) {
            technicalInfo = null;
          }

          try {
            audioOutputDecision =
                widget.playerController
                    .audioOutputDecision;
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

      setState(() {
        _currentTrackId = currentTrackId;
        _position = position;
        _duration = duration;
        _totalFrames = totalFrames;
        _state = state;
        _repeatMode = repeatMode;
        _track = track;
        _technicalInfo = technicalInfo;
        _audioOutputDecision =
            audioOutputDecision;
      });
    } catch (_) {
      // Keep the current UI state if native state
      // temporarily cannot be read.
    }
  }

  void _togglePlayback() {
    try {
      if (_state ==
          OfflinePlayerState.playing) {
        widget.playerController.pause();
      } else {
        widget.playerController.play();
      }

      _syncPlayer();
    } catch (error) {
      _showError(error);
    }
  }

  void _previous() {
    try {
      widget.playerController.previous();
      _syncPlayer();
    } catch (error) {
      _showError(error);
    }
  }

  void _next() {
    try {
      widget.playerController.next();
      _syncPlayer();
    } catch (error) {
      _showError(error);
    }
  }

  void _cycleRepeatMode() {
    try {
      final nextMode =
          switch (_repeatMode) {
        OfflinePlayerRepeatMode.off =>
          OfflinePlayerRepeatMode.track,
        OfflinePlayerRepeatMode.track =>
          OfflinePlayerRepeatMode.queue,
        OfflinePlayerRepeatMode.queue =>
          OfflinePlayerRepeatMode.off,
      };

      widget.playerController
          .setRepeatMode(nextMode);

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

    setState(() {
      _position = value;
    });
  }

  void _onSeekEnd(double value) {
    final duration = _duration;
    final totalFrames = _totalFrames;

    if (duration <= 0 ||
        totalFrames <= 0) {
      setState(() {
        _isSeeking = false;
      });
      return;
    }

    final ratio =
        (value / duration).clamp(0.0, 1.0);

    final frame =
        (ratio * totalFrames).round().clamp(
              0,
              totalFrames,
            );

    try {
      widget.playerController
          .seekToFrame(frame);

      if (!mounted) {
        return;
      }

      setState(() {
        _position = value;
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
      ..showSnackBar(
        SnackBar(
          content: Text(
            error.toString(),
          ),
        ),
      );
  }

  String _formatTime(double seconds) {
    if (!seconds.isFinite ||
        seconds < 0) {
      return '00:00';
    }

    final totalSeconds =
        seconds.floor();

    final minutes =
        totalSeconds ~/ 60;

    final remainingSeconds =
        totalSeconds % 60;

    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

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
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed || keyboard.isAltPressed) {
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
      _onSeekEnd(_position - 5);
      return KeyEventResult.handled;
    }
    if (!shift && key == LogicalKeyboardKey.arrowRight) {
      _onSeekEnd(_position + 5);
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

  void _adjustVolume(double delta) {
    try {
      widget.playerController.setVolume(
        widget.playerController.volume + delta,
      );
    } catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    final technicalInfo = _technicalInfo;
    final audioOutputDecision =
        _audioOutputDecision;

    final maxValue =
        _duration > 0 ? _duration : 1.0;

    final sliderValue =
        _position.clamp(
          0.0,
          maxValue,
        );

    return Scaffold(
      backgroundColor:
          const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor:
            const Color(0xFFFAFAFA),
        elevation: 0,
        title: const Text(
          'Now Playing',
        ),
        actions: [
          IconButton(
            tooltip:
                _queueOpen ? 'Hide queue' : 'Show queue',
            onPressed: _toggleQueue,
            color: _queueOpen
                ? const Color(0xFFC4A8F0)
                : const Color(0xFFEDEDED),
            icon: const Icon(
              Icons.queue_music,
            ),
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
          builder: (
            context,
            constraints,
          ) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                32,
                24,
                32,
                32,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      constraints.maxHeight -
                          56,
                ),
                child: Column(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    _Artwork(
                      size: 320,
                      image: _artworkImage,
                    ),

                    const SizedBox(
                      height: 32,
                    ),

                    Text(
                      track?.title.isNotEmpty ==
                              true
                          ? track!.title
                          : 'Nothing playing',
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                      textAlign:
                          TextAlign.center,
                      style: const TextStyle(
                        color:
                            Color(0xFFFAFAFA),
                        fontSize: 26,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    Text(
                      track?.artist.isNotEmpty ==
                              true
                          ? track!.artist
                          : 'Unknown artist',
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      textAlign:
                          TextAlign.center,
                      style: const TextStyle(
                        color:
                            Color(0xFF9A9A9A),
                        fontSize: 16,
                      ),
                    ),

                    const SizedBox(
                      height: 4,
                    ),

                    Text(
                      track?.album.isNotEmpty ==
                              true
                          ? track!.album
                          : 'Unknown album',
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      textAlign:
                          TextAlign.center,
                      style: const TextStyle(
                        color:
                            Color(0xFF9A9A9A),
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    if (technicalInfo != null)
                      _TechnicalInfo(
                        technicalInfo:
                            technicalInfo,
                        formatSampleRate:
                            _formatSampleRate,
                        formatChannels:
                            _formatChannels,
                      ),

                    if (audioOutputDecision !=
                        null) ...[
                      const SizedBox(
                        height: 8,
                      ),
                      _AudioOutputInfo(
                        decision:
                            audioOutputDecision,
                      ),
                    ],

                    const SizedBox(
                      height: 24,
                    ),

                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 760,
                      ),
                      child: _SeekBar(
                        value: sliderValue,
                        duration: _duration,
                        enabled: _duration > 0 &&
                            _totalFrames > 0,
                        onChanged: _onSeekChanged,
                        onChangeEnd: _onSeekEnd,
                        formatTime: _formatTime,
                      ),
                    ),

                    const SizedBox(height: 4),

                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 760,
                      ),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatTime(_position),
                              style: const TextStyle(
                                color: Color(0xFF9A9A9A),
                                fontSize: 12,
                                fontFeatures: [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            Text(
                              _formatTime(_duration),
                              style: const TextStyle(
                                color: Color(0xFF9A9A9A),
                                fontSize: 12,
                                fontFeatures: [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 20,
                    ),

                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Previous',
                          onPressed:
                              widget.playerController
                                          .queueLength >
                                      0
                                  ? _previous
                                  : null,
                          iconSize: 28,
                          color:
                              const Color(
                            0xFFEDEDED,
                          ),
                          icon: const Icon(
                            Icons.skip_previous,
                          ),
                        ),

                        const SizedBox(
                          width: 16,
                        ),

                        SizedBox(
                          width: 64,
                          height: 64,
                          child: IconButton(
                            tooltip:
                                _state ==
                                        OfflinePlayerState
                                            .playing
                                    ? 'Pause'
                                    : 'Play',
                            onPressed:
                                _togglePlayback,
                            iconSize: 38,
                            color:
                                const Color(
                              0xFFFAFAFA,
                            ),
                            style:
                                IconButton.styleFrom(
                              backgroundColor:
                                  const Color(
                                0xFF8A63D2,
                              ),
                            ),
                            icon: Icon(
                              _state ==
                                      OfflinePlayerState
                                          .playing
                                  ? Icons.pause
                                  : Icons.play_arrow,
                            ),
                          ),
                        ),

                        const SizedBox(
                          width: 16,
                        ),

                        IconButton(
                          tooltip: 'Next',
                          onPressed:
                              widget.playerController
                                          .queueLength >
                                      0
                                  ? _next
                                  : null,
                          iconSize: 28,
                          color:
                              const Color(
                            0xFFEDEDED,
                          ),
                          icon: const Icon(
                            Icons.skip_next,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 20,
                    ),

                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip:
                              _repeatLabel(),
                          onPressed:
                              _cycleRepeatMode,
                          color:
                              _repeatMode ==
                                      OfflinePlayerRepeatMode
                                          .off
                                  ? const Color(
                                      0xFF9A9A9A,
                                    )
                                  : const Color(
                                      0xFFC4A8F0,
                                    ),
                          icon: Icon(
                            _repeatIcon(),
                          ),
                        ),

                        const SizedBox(
                          width: 12,
                        ),

                        OutlinedButton.icon(
                          onPressed:
                              _toggleQueue,
                          icon: const Icon(
                            Icons.queue_music,
                            size: 18,
                          ),
                          label: const Text(
                            'Queue',
                          ),
                          style:
                              OutlinedButton.styleFrom(
                            foregroundColor:
                                const Color(
                              0xFFEDEDED,
                            ),
                            side:
                                const BorderSide(
                              color: Color(
                                0xFF2A2A2A,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    Text(
                      switch (_state) {
                        OfflinePlayerState.playing =>
                          'Playing',
                        OfflinePlayerState.paused =>
                          'Paused',
                        OfflinePlayerState.loaded =>
                          'Loaded',
                        OfflinePlayerState.stopped =>
                          'Stopped',
                        OfflinePlayerState.idle =>
                          'Idle',
                      },
                      style: const TextStyle(
                        color:
                            Color(0xFF9A9A9A),
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
              _QueueResizeHandle(
                onDragUpdate: _resizeQueue,
              ),

              SizedBox(
                width: _queueWidth,
                child: QueuePanel(
                  repository: widget.repository,
                  playerController:
                      widget.playerController,
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
      _hoverValue = _valueFromPosition(
        event.localPosition.dx,
        width,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final previewValue =
            _dragging ? widget.value : _hoverValue;

        final showPreview =
            widget.enabled && previewValue != null;

        final previewFraction = showPreview
            ? (previewValue / widget.duration)
                .clamp(0.0, 1.0)
            : 0.0;

        const tooltipWidth = 68.0;
        final tooltipLeft =
            (previewFraction * width - tooltipWidth / 2)
                .clamp(0.0, width - tooltipWidth);

        return MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onHover: (event) =>
              _updateHover(event, width),
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
                      thumbShape:
                          const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape:
                          const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      activeTrackColor:
                          const Color(0xFF8A63D2),
                      inactiveTrackColor:
                          const Color(0xFF2A2A2A),
                      thumbColor:
                          const Color(0xFFC4A8F0),
                      overlayColor:
                          const Color(0x338A63D2),
                    ),
                    child: Slider(
                      min: 0,
                      max: widget.duration > 0
                          ? widget.duration
                          : 1,
                      value: widget.value.clamp(
                        0.0,
                        widget.duration > 0
                            ? widget.duration
                            : 1,
                      ),
                      onChangeStart: widget.enabled
                          ? (_) {
                              setState(() {
                                _dragging = true;
                                _hoverValue =
                                    widget.value;
                              });
                            }
                          : null,
                      onChanged: widget.enabled
                          ? widget.onChanged
                          : null,
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
                        text: widget.formatTime(
                          previewValue,
                        ),
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
  const _SeekTooltip({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 68,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFFFAFAFA),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFeatures: [
                FontFeature.tabularFigures(),
              ],
            ),
          ),
        ),
        CustomPaint(
          size: const Size(10, 6),
          painter: _SeekTooltipArrowPainter(),
        ),
      ],
    );
  }
}

class _SeekTooltipArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFF2A2A2A),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
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
    return Row(
      mainAxisAlignment:
          MainAxisAlignment.center,
      children: [
        Text(
          formatSampleRate(
            technicalInfo.sampleRate,
          ),
          style: const TextStyle(
            color: Color(0xFFEDEDED),
            fontSize: 13,
            fontFeatures: [
              FontFeature.tabularFigures(),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Text(
          '${technicalInfo.bitsPerSample}-bit',
          style: const TextStyle(
            color: Color(0xFFEDEDED),
            fontSize: 13,
            fontFeatures: [
              FontFeature.tabularFigures(),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Text(
          formatChannels(
            technicalInfo.channels,
          ),
          style: const TextStyle(
            color: Color(0xFFEDEDED),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _AudioOutputInfo extends StatelessWidget {
  const _AudioOutputInfo({
    required this.decision,
  });

  final AudioOutputDecision decision;

  @override
  Widget build(BuildContext context) {
    final status =
        audioPlaybackStatusLabel(
      decision.status,
    );

    final statusColor =
        decision.isNative
            ? const Color(0xFF7FD99A)
            : const Color(0xFFE8B74A);

    return Row(
      mainAxisAlignment:
          MainAxisAlignment.center,
      children: [
        const Text(
          'SOURCE',
          style: TextStyle(
            color: Color(0xFF9A9A9A),
            fontSize: 10,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          formatSampleRate(
            decision.sourceRate,
          ),
          style: const TextStyle(
            color: Color(0xFFEDEDED),
            fontSize: 12,
            fontFeatures: [
              FontFeature.tabularFigures(),
            ],
          ),
        ),
        const SizedBox(width: 20),
        const Text(
          'OUTPUT',
          style: TextStyle(
            color: Color(0xFF9A9A9A),
            fontSize: 10,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          formatSampleRate(
            decision.effectiveRate,
          ),
          style: const TextStyle(
            color: Color(0xFFEDEDED),
            fontSize: 12,
            fontFeatures: [
              FontFeature.tabularFigures(),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          status,
          style: TextStyle(
            color: statusColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.size,
    required this.image,
  });

  final double size;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF2A2A2A),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: image != null
          ? Image(
              image: image!,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) {
                return const Center(
                  child: Icon(
                    Icons.music_note,
                    size: 72,
                    color: Color(0xFF6A3FC0),
                  ),
                );
              },
            )
          : const Center(
              child: Icon(
                Icons.music_note,
                size: 72,
                color: Color(0xFF6A3FC0),
              ),
            ),
    );
  }
}


class _QueueResizeHandle extends StatelessWidget {
  const _QueueResizeHandle({
    required this.onDragUpdate,
  });

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
              color: const Color(0xFF2A2A2A),
            ),
          ),
        ),
      ),
    );
  }
}
