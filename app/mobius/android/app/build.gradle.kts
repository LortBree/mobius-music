plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Repo root: app/mobius/android -> app/mobius -> app -> <repo>
val mobiusRepoRoot: File = rootProject.projectDir.parentFile.parentFile.parentFile
val rustJniLibs: File = file("src/main/jniLibs")

android {
    namespace = "com.mobius.mobius"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.mobius.mobius"
        // 26 = AAudio floor; the target device runs Android 13 (API 33).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The Rust core is only built for arm64 (Galaxy Note20 5G).
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir(rustJniLibs)
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Cross-compiles the Rust FFI crate to liboffline_player_ffi.so before every
// Android build, so the APK always carries a .so matching the current Rust
// sources. Release profile in both debug and release APKs (debug Rust audio is
// too slow to decode in real time).
val buildRustAndroid by tasks.registering(Exec::class) {
    group = "build"
    description = "Build liboffline_player_ffi.so for arm64-v8a via cargo-ndk"
    workingDir = mobiusRepoRoot
    val home = System.getProperty("user.home")
    val sdkDir = android.sdkDirectory
    environment("ANDROID_NDK_HOME", "${sdkDir}/ndk/27.0.12077973")
    environment("PATH", "$home/.cargo/bin:" + System.getenv("PATH"))
    commandLine(
        "$home/.cargo/bin/cargo", "ndk",
        "-t", "arm64-v8a",
        // Platform level = minSdk; libaaudio is only in the API 26+ sysroots.
        "--platform", "26",
        "-o", rustJniLibs.absolutePath,
        "build", "-p", "offline-player-ffi", "--release",
    )
}

tasks.named("preBuild") {
    dependsOn(buildRustAndroid)
}

dependencies {
    // MediaSession + media notification + foreground playback service.
    implementation("androidx.media3:media3-session:1.11.1")
}

flutter {
    source = "../.."
}
