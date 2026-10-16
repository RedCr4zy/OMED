plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.chaquo.python")
}

android {
    namespace = "com.example.omed"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.omed"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Restriction explicite globale
        ndk {
            abiFilters.clear()
            abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
        }
    }

    buildTypes {
        getByName("debug") {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
            }
        }
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
            ndk {
                abiFilters.clear()
                abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
            }
        }
    }
}

val pythonPath = if (System.getProperty("os.name").lowercase().contains("windows")) {
    "C:/Program Files/Python313/python.exe"
} else {
    "/usr/bin/python3.13"
}

chaquopy {
    defaultConfig {
        version = "3.13"
        buildPython(pythonPath)
        pip {
            install("websockets")
            install("numpy")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
