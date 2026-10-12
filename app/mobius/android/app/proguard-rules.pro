# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep native FFI entry points and JNI registrations
-keepclasseswithmembernames class * {
    native <methods>;
}

# AndroidX Media3 Session & Player
-keep class androidx.media3.session.** { *; }
-keep class androidx.media3.common.** { *; }
-keep class com.mobius.mobius.** { *; }

# Suppress warnings for optional Play Store deferred components in Flutter engine
-dontwarn com.google.android.play.core.**
-dontwarn androidx.media3.**
-dontwarn com.google.common.**
