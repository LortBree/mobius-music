import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'android/android_audio_route.dart';
import 'android/android_folder_access.dart';
import 'android/android_platform_paths.dart';
import 'android/android_playback_activity.dart';
import 'macos/macos_audio_route.dart';
import 'macos/macos_folder_access.dart';
import 'macos/macos_platform_paths.dart';
import 'macos/macos_playback_activity.dart';
import 'shared/audio_route_service.dart';
import 'shared/folder_access_service.dart';
import 'shared/platform_paths_service.dart';
import 'shared/playback_activity_service.dart';

/// Central platform registry providing platform-specific service implementations
/// behind shared, platform-neutral interfaces.
class PlatformServices {
  PlatformServices._();

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  // --- Folder Access Service ---
  static FolderAccessService? _folderAccessOverride;

  @visibleForTesting
  static set folderAccessOverride(FolderAccessService? override) {
    _folderAccessOverride = override;
  }

  static FolderAccessService get folderAccess {
    if (_folderAccessOverride != null) return _folderAccessOverride!;
    if (isAndroid) {
      return const AndroidFolderAccessService();
    }
    return const MacOSFolderAccessService();
  }

  // --- Playback Activity Service ---
  static PlaybackActivityService? _playbackActivityOverride;

  @visibleForTesting
  static set playbackActivityOverride(PlaybackActivityService? override) {
    _playbackActivityOverride = override;
  }

  static PlaybackActivityService get playbackActivity {
    if (_playbackActivityOverride != null) return _playbackActivityOverride!;
    if (isAndroid) {
      return const AndroidPlaybackActivityService();
    }
    return const MacOSPlaybackActivityService();
  }

  // --- Audio Route Service ---
  static AudioRouteService? _audioRouteOverride;

  @visibleForTesting
  static set audioRouteOverride(AudioRouteService? override) {
    _audioRouteOverride = override;
  }

  static AudioRouteService get audioRoute {
    if (_audioRouteOverride != null) return _audioRouteOverride!;
    if (isAndroid) {
      return const AndroidAudioRouteService();
    }
    return const MacOSAudioRouteService();
  }

  // --- Platform Paths Service ---
  static PlatformPathsService? _pathsOverride;

  @visibleForTesting
  static set pathsOverride(PlatformPathsService? override) {
    _pathsOverride = override;
  }

  static PlatformPathsService get paths {
    if (_pathsOverride != null) return _pathsOverride!;
    if (isAndroid) {
      return const AndroidPlatformPathsService();
    }
    return const MacOSPlatformPathsService();
  }
}
