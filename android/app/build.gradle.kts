plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.motionix.motionix"
    compileSdk = flutter.compileSdkVersion
    // Pinned to the NDK revision already installed in the build sandbox
    // (auto-downloaded by AGP for the smoke build). Do not bump blindly:
    // each revision is ~2.2 GB.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.motionix.motionix"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Phase 1 targets the founder's arm64 device (and all modern phones).
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        externalNativeBuild {
            cmake {
                // Hard-pin the ABI so direct gradlew runs never try to
                // configure ABIs whose sysroot was trimmed from the NDK.
                abiFilters += listOf("arm64-v8a")
            }
        }
    }

    // The Motionix C++ core (rational time, proxy planner, project model),
    // loaded from Dart via dart:ffi as libmotionix_core.so.
    externalNativeBuild {
        cmake {
            path = file("../../core/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // CI test signing: a throwaway key delivered as a GitHub Actions secret,
    // so consecutive CI builds upgrade-install over each other instead of
    // requiring an uninstall. Without the key (local `flutter run --release`)
    // we fall back to debug signing. The real release key arrives in Phase 9.
    val ciKeystore = file("keys/ci-test-signing.jks")
    if (ciKeystore.exists()) {
        signingConfigs {
            create("ci") {
                storeFile = ciKeystore
                storePassword = System.getenv("MOTIONIX_STORE_PASSWORD") ?: "motionix-ci-test"
                keyAlias = System.getenv("MOTIONIX_KEY_ALIAS") ?: "motionix"
                keyPassword = System.getenv("MOTIONIX_KEY_PASSWORD") ?: "motionix-ci-test"
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (ciKeystore.exists()) signingConfigs.getByName("ci")
                else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Media3 Transformer: hardware-accelerated transcode for proxies & export.
    implementation("androidx.media3:media3-transformer:1.8.0")
    implementation("androidx.media3:media3-effect:1.8.0")
    implementation("androidx.media3:media3-common:1.8.0")
}

flutter {
    source = "../.."
}
