plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    // com.google.gms.google-services is applied just below this block, so a
    // local emulator build can leave the production config out.
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Production Firebase configuration (google-services.json). Applied to every
// build EXCEPT a local emulator build made with HT_EMULATOR=true in the build
// environment: that build has no production config compiled in, so the app
// can only start against the local demo emulator project
// (lib/core/firebase/emulator_config.dart; RumptyCloud staging media tests).
if (System.getenv("HT_EMULATOR") != "true") {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.example.handy_trust"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.handy_trust"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}
