import java.util.Properties

// Wear OS companion: a remote for the phone app (start/stop the night,
// snooze/stop the alarm, silent vibration wake-up, Snore Alert buzz).
// Same applicationId and signing as the phone app, which the Data Layer
// needs to pair the two. Build: ./gradlew :wear:assembleDebug
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Release signing from android/key.properties (gitignored), see signingConfigs below.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.example.sleep_tracker.wear"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.matchlab.lullwake"
        minSdk = 30
        targetSdk = 36
        // Play needs a version code of its own per bundle under one package:
        // the watch uses 1000 + the phone's (pubspec build number).
        versionCode = 1001
        versionName = "0.1.0"
    }

    // Release signing from android/key.properties (gitignored):
    //   storeFile=/path/to/upload-keystore.jks
    //   storePassword=...  keyAlias=upload  keyPassword=...
    // Without it, release builds fall back to the debug key (local testing only).
    signingConfigs {
        if (keyProps.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.wear.compose:compose-material:1.4.1")
    implementation("androidx.wear.compose:compose-foundation:1.4.1")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
}
