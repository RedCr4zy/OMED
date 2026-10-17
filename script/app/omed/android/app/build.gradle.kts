plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseStoreFile = providers.gradleProperty("OMED_RELEASE_STORE_FILE").orNull
val releaseStorePassword = providers.gradleProperty("OMED_RELEASE_STORE_PASSWORD").orNull
val releaseKeyAlias = providers.gradleProperty("OMED_RELEASE_KEY_ALIAS").orNull
val releaseKeyPassword = providers.gradleProperty("OMED_RELEASE_KEY_PASSWORD").orNull
val releaseSigningValues = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
)
val hasReleaseSigning = releaseSigningValues.all { !it.isNullOrBlank() }
val validateOmedReleaseSigning = tasks.register("validateOmedReleaseSigning") {
    doLast {
        if (!hasReleaseSigning) {
            throw GradleException(
                "Release signing is not configured. Provide OMED_RELEASE_STORE_FILE, " +
                    "OMED_RELEASE_STORE_PASSWORD, OMED_RELEASE_KEY_ALIAS, and " +
                    "OMED_RELEASE_KEY_PASSWORD through private Gradle properties."
            )
        }
        if (!rootProject.file(releaseStoreFile!!).isFile) {
            throw GradleException(
                "The release keystore configured by OMED_RELEASE_STORE_FILE does not exist."
            )
        }
    }
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
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.create("omedRelease").apply {
                    storeFile = rootProject.file(releaseStoreFile!!)
                    storePassword = releaseStorePassword
                    keyAlias = releaseKeyAlias
                    keyPassword = releaseKeyPassword
                }
            } else {
                null
            }
            ndk {
                abiFilters.clear()
                abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
            }
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

tasks.configureEach {
    if ((name.startsWith("package") || name.startsWith("bundle")) &&
        name.endsWith("Release")
    ) {
        dependsOn(validateOmedReleaseSigning)
    }
}
