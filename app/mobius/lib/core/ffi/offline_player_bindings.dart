import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import '../../platform/platform_services.dart';

final class OfflinePlayerHandle extends ffi.Opaque {}

final class OfflinePlayerTrackMetadata extends ffi.Struct {
  @ffi.Int64()
  external int trackId;

  external ffi.Pointer<Utf8> title;

  @ffi.Uint64()
  external int titleCapacity;

  external ffi.Pointer<Utf8> artist;

  @ffi.Uint64()
  external int artistCapacity;

  external ffi.Pointer<Utf8> album;

  @ffi.Uint64()
  external int albumCapacity;

  external ffi.Pointer<Utf8> albumArtist;

  @ffi.Uint64()
  external int albumArtistCapacity;

  external ffi.Pointer<Utf8> composer;

  @ffi.Uint64()
  external int composerCapacity;

  external ffi.Pointer<Utf8> date;

  @ffi.Uint64()
  external int dateCapacity;

  external ffi.Pointer<Utf8> genre;

  @ffi.Uint64()
  external int genreCapacity;

  @ffi.Uint32()
  external int trackNumber;

  @ffi.Uint32()
  external int discNumber;

  @ffi.Uint8()
  external int hasDiscNumber;
}

final class OfflinePlayerTrackArtwork extends ffi.Struct {
  @ffi.Int64()
  external int trackId;

  external ffi.Pointer<Utf8> mimeType;

  @ffi.Uint64()
  external int mimeTypeCapacity;

  @ffi.Uint64()
  external int mimeTypeSize;

  external ffi.Pointer<ffi.Uint8> data;

  @ffi.Uint64()
  external int dataCapacity;

  @ffi.Uint64()
  external int dataSize;
}

/// Mirrors the C `OfflinePlayerSignalPath` struct (offline_player.h). Field
/// order and sizes MUST match the header; the two inline char arrays are
/// fixed-capacity, NUL-terminated UTF-8 the native side fills.
final class OfflinePlayerSignalPath extends ffi.Struct {
  @ffi.Uint32()
  external int outputSampleRate;

  @ffi.Uint32()
  external int outputChannels;

  @ffi.Uint32()
  external int outputBitsPerSample;

  @ffi.Uint8()
  external int outputIsFloat;

  @ffi.Uint8()
  external int resampling;

  @ffi.Uint8()
  external int equalizerActive;

  @ffi.Uint8()
  external int bitPerfect;

  @ffi.Uint32()
  external int equalizerBands;

  @ffi.Float()
  external double volume;

  @ffi.Uint32()
  external int bufferMs;

  @ffi.Uint64()
  external int underrunSamples;

  @ffi.Uint64()
  external int callbackCount;

  @ffi.Int32()
  external int route;

  @ffi.Array<ffi.Char>(16)
  external ffi.Array<ffi.Char> outputApi;

  @ffi.Array<ffi.Char>(96)
  external ffi.Array<ffi.Char> deviceName;
}

final class OfflinePlayerUsbSpikeResult extends ffi.Struct {
  @ffi.Uint8()
  external int success;

  @ffi.Uint8()
  external int wrapOk;

  @ffi.Uint8()
  external int claimOk;

  @ffi.Uint8()
  external int altsettingOk;

  @ffi.Uint8()
  external int outEndpoint;

  @ffi.Uint8()
  external int feedbackEndpoint;

  @ffi.Int32()
  external int altSetting;

  @ffi.Uint64()
  external int packetsSubmitted;

  @ffi.Uint64()
  external int packetsCompleted;

  @ffi.Uint64()
  external int packetsError;

  @ffi.Uint64()
  external int feedbackPacketsRead;

  @ffi.Uint32()
  external int lastFeedbackRaw;

  @ffi.Double()
  external double feedbackFreqKhz;

  @ffi.Double()
  external double durationSecs;

  @ffi.Array<ffi.Char>(256)
  external ffi.Array<ffi.Char> errorMsg;

  @ffi.Array<ffi.Char>(2048)
  external ffi.Array<ffi.Char> descriptorSummary;
}

/*
 * Version
 */

typedef VersionNative = ffi.Pointer<Utf8> Function();
typedef VersionDart = ffi.Pointer<Utf8> Function();

/*
 * Lifecycle
 */

typedef CreateNative =
    ffi.Int32 Function(
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Pointer<OfflinePlayerHandle>>,
    );

typedef CreateDart =
    int Function(
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Pointer<OfflinePlayerHandle>>,
    );

typedef DestroyNative = ffi.Void Function(ffi.Pointer<OfflinePlayerHandle>);

typedef DestroyDart = void Function(ffi.Pointer<OfflinePlayerHandle>);

/*
 * Error
 */

typedef LastErrorNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<Utf8>,
      ffi.Uint64,
    );

typedef LastErrorDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<Utf8>, int);

/*
 * Library
 */

typedef ScanDirectoryNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Int64>,
      ffi.Pointer<ffi.Int64>,
      ffi.Pointer<ffi.Int64>,
      ffi.Pointer<ffi.Int64>,
    );

typedef ScanDirectoryDart =
    int Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Int64>,
      ffi.Pointer<ffi.Int64>,
      ffi.Pointer<ffi.Int64>,
      ffi.Pointer<ffi.Int64>,
    );

typedef TrackCountNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Int64>,
    );

typedef TrackCountDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Int64>);

typedef TrackIdAtNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Int64,
      ffi.Pointer<ffi.Int64>,
    );

typedef TrackIdAtDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, int, ffi.Pointer<ffi.Int64>);

typedef TrackIdsNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Int64>,
      ffi.Size,
      ffi.Pointer<ffi.Size>,
    );

typedef TrackIdsDart =
    int Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Int64>,
      int,
      ffi.Pointer<ffi.Size>,
    );

typedef LibraryTrackMetadataNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Int64,
      ffi.Pointer<OfflinePlayerTrackMetadata>,
    );

typedef LibraryTrackMetadataDart =
    int Function(
      ffi.Pointer<OfflinePlayerHandle>,
      int,
      ffi.Pointer<OfflinePlayerTrackMetadata>,
    );

/*
 * Current track technical information
 */

typedef TrackSampleRateNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Uint32>,
    );

typedef TrackSampleRateDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Uint32>);

typedef TrackChannelsNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Uint16>,
    );

typedef TrackChannelsDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Uint16>);

typedef TrackBitsPerSampleNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Uint16>,
    );

typedef TrackBitsPerSampleDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Uint16>);

/*
 * Cover Art
 */

typedef LibraryTrackArtworkNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Int64,
      ffi.Pointer<OfflinePlayerTrackArtwork>,
    );

typedef LibraryTrackArtworkDart =
    int Function(
      ffi.Pointer<OfflinePlayerHandle>,
      int,
      ffi.Pointer<OfflinePlayerTrackArtwork>,
    );

/*
 * Playback
 */

typedef LoadTrackNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Int64);

typedef LoadTrackDart = int Function(ffi.Pointer<OfflinePlayerHandle>, int);

typedef PlayNative = ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>);

typedef PlayDart = int Function(ffi.Pointer<OfflinePlayerHandle>);

typedef PauseNative = ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>);

typedef PauseDart = int Function(ffi.Pointer<OfflinePlayerHandle>);

typedef StopNative = ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>);

typedef StopDart = int Function(ffi.Pointer<OfflinePlayerHandle>);

typedef SeekToFrameNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Uint64);

typedef SeekToFrameDart = int Function(ffi.Pointer<OfflinePlayerHandle>, int);

/*
 * Playback state / position
 */

typedef StateNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Int32>,
    );

typedef StateDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Int32>);

typedef CurrentFrameNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Uint64>,
    );

typedef CurrentFrameDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Uint64>);

typedef CurrentSecondsNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Double>,
    );

typedef CurrentSecondsDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Double>);

typedef DurationSecondsNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Double>,
    );

typedef DurationSecondsDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Double>);

typedef TotalFramesNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Uint64>,
    );

typedef TotalFramesDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Uint64>);

/*
 * Queue
 */

typedef QueueSetNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Int64>,
      ffi.Uint64,
    );

typedef SetVolumeNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Float);

typedef SetVolumeDart = int Function(ffi.Pointer<OfflinePlayerHandle>, double);

typedef SetHardwareVolumeNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Float);

typedef SetHardwareVolumeDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, double);

typedef GetHardwareVolumeNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Float>);

typedef GetHardwareVolumeDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Float>);

typedef SetBitPerfectModeNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Uint8);

typedef SetBitPerfectModeDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, int);

typedef GetBitPerfectModeNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Uint8>);

typedef GetBitPerfectModeDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Uint8>);


typedef SetVolumeNormalizationNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Uint8);

typedef SetVolumeNormalizationDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, int);

typedef GetVolumeNormalizationNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Uint8>);

typedef GetVolumeNormalizationDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Uint8>);

typedef TrackGainDbNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Float>);

typedef TrackGainDbDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Float>);
typedef SwitchOutputRouteNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>);

typedef SwitchOutputRouteDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>);

typedef SetEqualizerGainsNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Float>,
      ffi.Uint64,
    );

typedef SetEqualizerGainsDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Float>, int);

typedef QueueSetDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Int64>, int);

typedef QueueAddNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Int64);

typedef QueueAddDart = int Function(ffi.Pointer<OfflinePlayerHandle>, int);

typedef QueueClearNative = ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueueClearDart = int Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueueLengthNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Uint64>,
    );

typedef QueueLengthDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Uint64>);

typedef QueueTrackIdAtNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Uint64,
      ffi.Pointer<ffi.Int64>,
    );

typedef QueueTrackIdAtDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, int, ffi.Pointer<ffi.Int64>);

typedef QueueUpNextCountNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Uint64>,
    );

typedef QueueUpNextCountDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Uint64>);

typedef QueueReorderSegmentNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Uint64,
      ffi.Pointer<ffi.Int64>,
      ffi.Uint64,
    );

typedef QueueReorderSegmentDart =
    int Function(
      ffi.Pointer<OfflinePlayerHandle>,
      int,
      ffi.Pointer<ffi.Int64>,
      int,
    );

typedef QueueCurrentIndexNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Uint64>,
    );

typedef QueueCurrentIndexDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Uint64>);

typedef QueueCurrentTrackIdNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Int64>,
    );

typedef QueueCurrentTrackIdDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Int64>);

typedef QueueSetRepeatModeNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Int32);

typedef QueueSetRepeatModeDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, int);

typedef QueueRepeatModeNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Int32>,
    );

typedef QueueRepeatModeDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Int32>);

typedef QueueSelectNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Uint64);

typedef QueueSelectDart = int Function(ffi.Pointer<OfflinePlayerHandle>, int);

typedef QueuePlayCurrentNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueuePlayCurrentDart = int Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueueSelectAndLoadNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Uint64);

typedef QueueSelectAndLoadDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, int);

typedef QueueSelectAndPlayNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Uint64);

typedef QueueSelectAndPlayDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, int);

typedef QueueNextNative = ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueueNextDart = int Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueueNextAndPlayNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueueNextAndPlayDart = int Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueuePreviousNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueuePreviousDart = int Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueuePreviousAndPlayNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueuePreviousAndPlayDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueueRepeatCurrentAndPlayNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueueRepeatCurrentAndPlayDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueueAdvanceAndPlayNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueueAdvanceAndPlayDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueueAdvanceIfAtEndNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>);

typedef QueueAdvanceIfAtEndDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>);

/*
 * Output mode
 */

typedef SetOutputModeNative =
    ffi.Int32 Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Int32);

typedef SetOutputModeDart = int Function(ffi.Pointer<OfflinePlayerHandle>, int);

typedef OutputModeNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Int32>,
    );

typedef OutputModeDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Int32>);

typedef EffectiveOutputRateNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<ffi.Uint32>,
    );

typedef EffectiveOutputRateDart =
    int Function(ffi.Pointer<OfflinePlayerHandle>, ffi.Pointer<ffi.Uint32>);

/*
 * Signal path
 */

typedef SignalPathNative =
    ffi.Int32 Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<OfflinePlayerSignalPath>,
    );

typedef SignalPathDart =
    int Function(
      ffi.Pointer<OfflinePlayerHandle>,
      ffi.Pointer<OfflinePlayerSignalPath>,
    );

/*
 * USB Spike (Android UAC2 bit-perfect gate)
 */

typedef RunUsbSpikeNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Uint16,
      ffi.Uint16,
      ffi.Int32,
      ffi.Uint32,
      ffi.Pointer<OfflinePlayerUsbSpikeResult>,
    );

typedef RunUsbSpikeDart =
    int Function(
      int,
      int,
      int,
      int,
      int,
      ffi.Pointer<OfflinePlayerUsbSpikeResult>,
    );

typedef SetUsbDacNative = ffi.Int32 Function(ffi.Int32, ffi.Uint16, ffi.Uint16);
typedef SetUsbDacDart = int Function(int, int, int);

/*
 * Bindings
 */

class OfflinePlayerBindings {
  OfflinePlayerBindings(this.library) {
    version = library.lookupFunction<VersionNative, VersionDart>(
      'offline_player_version',
    );

    create = library.lookupFunction<CreateNative, CreateDart>(
      'offline_player_create',
    );

    destroy = library.lookupFunction<DestroyNative, DestroyDart>(
      'offline_player_destroy',
    );

    lastError = library.lookupFunction<LastErrorNative, LastErrorDart>(
      'offline_player_last_error',
    );

    scanDirectory = library
        .lookupFunction<ScanDirectoryNative, ScanDirectoryDart>(
          'offline_player_scan_directory',
        );

    trackCount = library.lookupFunction<TrackCountNative, TrackCountDart>(
      'offline_player_library_track_count',
    );

    trackIdAt = library.lookupFunction<TrackIdAtNative, TrackIdAtDart>(
      'offline_player_library_track_id_at',
    );

    trackIds = library.lookupFunction<TrackIdsNative, TrackIdsDart>(
      'offline_player_library_track_ids',
    );

    libraryTrackMetadata = library
        .lookupFunction<LibraryTrackMetadataNative, LibraryTrackMetadataDart>(
          'offline_player_library_track_metadata',
        );

    libraryTrackArtwork = library
        .lookupFunction<LibraryTrackArtworkNative, LibraryTrackArtworkDart>(
          'offline_player_library_track_artwork',
        );

    trackSampleRate = library
        .lookupFunction<TrackSampleRateNative, TrackSampleRateDart>(
          'offline_player_track_sample_rate',
        );

    trackChannels = library
        .lookupFunction<TrackChannelsNative, TrackChannelsDart>(
          'offline_player_track_channels',
        );

    trackBitsPerSample = library
        .lookupFunction<TrackBitsPerSampleNative, TrackBitsPerSampleDart>(
          'offline_player_track_bits_per_sample',
        );

    // Same (handle, buffer, capacity) string-out shape as last_error.
    trackPath = library.lookupFunction<LastErrorNative, LastErrorDart>(
      'offline_player_track_path',
    );

    loadTrack = library.lookupFunction<LoadTrackNative, LoadTrackDart>(
      'offline_player_load_track',
    );

    play = library.lookupFunction<PlayNative, PlayDart>('offline_player_play');

    pause = library.lookupFunction<PauseNative, PauseDart>(
      'offline_player_pause',
    );

    stop = library.lookupFunction<StopNative, StopDart>('offline_player_stop');

    seekToFrame = library.lookupFunction<SeekToFrameNative, SeekToFrameDart>(
      'offline_player_seek_to_frame',
    );

    state = library.lookupFunction<StateNative, StateDart>(
      'offline_player_state',
    );

    currentFrame = library.lookupFunction<CurrentFrameNative, CurrentFrameDart>(
      'offline_player_current_frame',
    );

    currentSeconds = library
        .lookupFunction<CurrentSecondsNative, CurrentSecondsDart>(
          'offline_player_current_seconds',
        );

    durationSeconds = library
        .lookupFunction<DurationSecondsNative, DurationSecondsDart>(
          'offline_player_duration_seconds',
        );

    totalFrames = library.lookupFunction<TotalFramesNative, TotalFramesDart>(
      'offline_player_total_frames',
    );

    queueSet = library.lookupFunction<QueueSetNative, QueueSetDart>(
      'offline_player_queue_set',
    );

    setVolume = library.lookupFunction<SetVolumeNative, SetVolumeDart>(
      'offline_player_set_volume',
    );

    setSoftwareVolume = library.lookupFunction<SetVolumeNative, SetVolumeDart>(
      'offline_player_set_software_volume',
    );

    setHardwareVolume = library.lookupFunction<
      SetHardwareVolumeNative,
      SetHardwareVolumeDart
    >('offline_player_set_hardware_volume');

    getHardwareVolume = library.lookupFunction<
      GetHardwareVolumeNative,
      GetHardwareVolumeDart
    >('offline_player_get_hardware_volume');

    setBitPerfectMode = library.lookupFunction<
      SetBitPerfectModeNative,
      SetBitPerfectModeDart
    >('offline_player_set_bit_perfect_mode');

    getBitPerfectMode = library.lookupFunction<
      GetBitPerfectModeNative,
      GetBitPerfectModeDart
    >('offline_player_get_bit_perfect_mode');


    try {
      setVolumeNormalization = library.lookupFunction<
        SetVolumeNormalizationNative,
        SetVolumeNormalizationDart
      >('offline_player_set_volume_normalization');
    } catch (_) {
      setVolumeNormalization = null;
    }

    try {
      getVolumeNormalization = library.lookupFunction<
        GetVolumeNormalizationNative,
        GetVolumeNormalizationDart
      >('offline_player_get_volume_normalization');
    } catch (_) {
      getVolumeNormalization = null;
    }

    try {
      trackGainDb = library.lookupFunction<
        TrackGainDbNative,
        TrackGainDbDart
      >('offline_player_track_gain_db');
    } catch (_) {
      trackGainDb = null;
    }
    switchOutputRoute = library.lookupFunction<
      SwitchOutputRouteNative,
      SwitchOutputRouteDart
    >('offline_player_switch_output_route');

    setEqualizerGains = library
        .lookupFunction<SetEqualizerGainsNative, SetEqualizerGainsDart>(
          'offline_player_set_equalizer_gains',
        );

    queueAdd = library.lookupFunction<QueueAddNative, QueueAddDart>(
      'offline_player_queue_add',
    );

    queueClear = library.lookupFunction<QueueClearNative, QueueClearDart>(
      'offline_player_queue_clear',
    );

    queueLength = library.lookupFunction<QueueLengthNative, QueueLengthDart>(
      'offline_player_queue_length',
    );

    queueTrackIdAt = library
        .lookupFunction<QueueTrackIdAtNative, QueueTrackIdAtDart>(
          'offline_player_queue_track_id_at',
        );

    queueUpNextCount = library
        .lookupFunction<QueueUpNextCountNative, QueueUpNextCountDart>(
          'offline_player_queue_up_next_count',
        );

    queueReorderSegment = library
        .lookupFunction<QueueReorderSegmentNative, QueueReorderSegmentDart>(
          'offline_player_queue_reorder_segment',
        );

    queueCurrentIndex = library
        .lookupFunction<QueueCurrentIndexNative, QueueCurrentIndexDart>(
          'offline_player_queue_current_index',
        );

    queueCurrentTrackId = library
        .lookupFunction<QueueCurrentTrackIdNative, QueueCurrentTrackIdDart>(
          'offline_player_queue_current_track_id',
        );

    queueSetRepeatMode = library
        .lookupFunction<QueueSetRepeatModeNative, QueueSetRepeatModeDart>(
          'offline_player_queue_set_repeat_mode',
        );

    queueRepeatMode = library
        .lookupFunction<QueueRepeatModeNative, QueueRepeatModeDart>(
          'offline_player_queue_repeat_mode',
        );

    queueSelect = library.lookupFunction<QueueSelectNative, QueueSelectDart>(
      'offline_player_queue_select',
    );

    queueSelectAndLoad = library
        .lookupFunction<QueueSelectAndLoadNative, QueueSelectAndLoadDart>(
          'offline_player_queue_select_and_load',
        );

    queuePlayCurrent = library
        .lookupFunction<QueuePlayCurrentNative, QueuePlayCurrentDart>(
          'offline_player_queue_play_current',
        );

    queueSelectAndPlay = library
        .lookupFunction<QueueSelectAndPlayNative, QueueSelectAndPlayDart>(
          'offline_player_queue_select_and_play',
        );

    queueNext = library.lookupFunction<QueueNextNative, QueueNextDart>(
      'offline_player_queue_next',
    );

    queueNextAndPlay = library
        .lookupFunction<QueueNextAndPlayNative, QueueNextAndPlayDart>(
          'offline_player_queue_next_and_play',
        );

    queuePrevious = library
        .lookupFunction<QueuePreviousNative, QueuePreviousDart>(
          'offline_player_queue_previous',
        );

    queuePreviousAndPlay = library
        .lookupFunction<QueuePreviousAndPlayNative, QueuePreviousAndPlayDart>(
          'offline_player_queue_previous_and_play',
        );

    queueRepeatCurrentAndPlay = library
        .lookupFunction<
          QueueRepeatCurrentAndPlayNative,
          QueueRepeatCurrentAndPlayDart
        >('offline_player_queue_repeat_current_and_play');

    queueAdvanceAndPlay = library
        .lookupFunction<QueueAdvanceAndPlayNative, QueueAdvanceAndPlayDart>(
          'offline_player_queue_advance_and_play',
        );

    queueAdvanceIfAtEnd = library
        .lookupFunction<QueueAdvanceIfAtEndNative, QueueAdvanceIfAtEndDart>(
          'offline_player_queue_advance_if_at_end',
        );

    setOutputMode = library
        .lookupFunction<SetOutputModeNative, SetOutputModeDart>(
          'offline_player_set_output_mode',
        );

    outputMode = library.lookupFunction<OutputModeNative, OutputModeDart>(
      'offline_player_output_mode',
    );

    effectiveOutputRate = library
        .lookupFunction<EffectiveOutputRateNative, EffectiveOutputRateDart>(
          'offline_player_effective_output_rate',
        );

    signalPath = library.lookupFunction<SignalPathNative, SignalPathDart>(
      'offline_player_signal_path',
    );

    try {
      runUsbSpike = library
          .lookupFunction<RunUsbSpikeNative, RunUsbSpikeDart>(
            'offline_player_run_usb_spike',
          );
    } catch (_) {
      runUsbSpike = null;
    }

    try {
      setUsbDac = library
          .lookupFunction<SetUsbDacNative, SetUsbDacDart>(
            'offline_player_set_usb_dac',
          );
    } catch (_) {
      setUsbDac = null;
    }
  }

  final ffi.DynamicLibrary library;

  late final VersionDart version;

  late final CreateDart create;
  late final DestroyDart destroy;
  late final LastErrorDart lastError;

  late final ScanDirectoryDart scanDirectory;
  late final TrackCountDart trackCount;
  late final TrackIdAtDart trackIdAt;
  late final TrackIdsDart trackIds;
  late final LibraryTrackMetadataDart libraryTrackMetadata;
  late final LibraryTrackArtworkDart libraryTrackArtwork;
  late final TrackSampleRateDart trackSampleRate;
  late final TrackChannelsDart trackChannels;
  late final TrackBitsPerSampleDart trackBitsPerSample;
  late final LastErrorDart trackPath;

  late final LoadTrackDart loadTrack;
  late final PlayDart play;
  late final PauseDart pause;
  late final StopDart stop;
  late final SeekToFrameDart seekToFrame;

  late final StateDart state;
  late final CurrentFrameDart currentFrame;
  late final CurrentSecondsDart currentSeconds;
  late final DurationSecondsDart durationSeconds;
  late final TotalFramesDart totalFrames;

  late final QueueSetDart queueSet;

  late final SetVolumeDart setVolume;
  late final SetVolumeDart setSoftwareVolume;
  late final SetHardwareVolumeDart setHardwareVolume;
  late final GetHardwareVolumeDart getHardwareVolume;
  late final SetBitPerfectModeDart setBitPerfectMode;
  late final GetBitPerfectModeDart getBitPerfectMode;
  late final SetVolumeNormalizationDart? setVolumeNormalization;
  late final GetVolumeNormalizationDart? getVolumeNormalization;
  late final TrackGainDbDart? trackGainDb;
  late final SwitchOutputRouteDart switchOutputRoute;
  late final SetEqualizerGainsDart setEqualizerGains;
  late final QueueAddDart queueAdd;
  late final QueueClearDart queueClear;
  late final QueueLengthDart queueLength;

  late final QueueTrackIdAtDart queueTrackIdAt;

  late final QueueUpNextCountDart queueUpNextCount;

  late final QueueReorderSegmentDart queueReorderSegment;
  late final QueueCurrentIndexDart queueCurrentIndex;
  late final QueueCurrentTrackIdDart queueCurrentTrackId;
  late final QueueSetRepeatModeDart queueSetRepeatMode;
  late final QueueRepeatModeDart queueRepeatMode;

  late final QueueSelectDart queueSelect;
  late final QueueSelectAndLoadDart queueSelectAndLoad;
  late final QueuePlayCurrentDart queuePlayCurrent;
  late final QueueSelectAndPlayDart queueSelectAndPlay;
  late final QueueNextDart queueNext;
  late final QueueNextAndPlayDart queueNextAndPlay;
  late final QueuePreviousDart queuePrevious;
  late final QueuePreviousAndPlayDart queuePreviousAndPlay;
  late final QueueRepeatCurrentAndPlayDart queueRepeatCurrentAndPlay;
  late final QueueAdvanceAndPlayDart queueAdvanceAndPlay;
  late final QueueAdvanceIfAtEndDart queueAdvanceIfAtEnd;

  late final SetOutputModeDart setOutputMode;
  late final OutputModeDart outputMode;
  late final EffectiveOutputRateDart effectiveOutputRate;
  late final SignalPathDart signalPath;
  late final RunUsbSpikeDart? runUsbSpike;
  late final SetUsbDacDart? setUsbDac;

  static ffi.DynamicLibrary openLibrary(String path) {
    return PlatformServices.paths.openLibrary(path);
  }
}
