import '../../platform/android/android_lifecycle.dart';

/// Bridges platform-specific app lifecycle actions (e.g. Android moveTaskToBack).
class AppLifecycleBridge {
  static Future<void> moveTaskToBack() {
    return AndroidLifecycleBridge.moveTaskToBack();
  }
}
