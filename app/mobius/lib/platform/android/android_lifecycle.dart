import 'dart:io';
import 'package:flutter/services.dart';

/// Android host lifecycle bridge (e.g. moving task to background without killing process).
class AndroidLifecycleBridge {
  const AndroidLifecycleBridge();

  static const MethodChannel _channel = MethodChannel('mobius/app_lifecycle');

  /// Puts the Android task into the background without destroying the activity
  /// or killing the audio engine / Flutter state.
  static Future<void> moveTaskToBack() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('moveTaskToBack');
      } catch (_) {}
    }
  }
}
