// Wear OS companion: a remote for the phone app (start/stop the night,
// snooze/stop the alarm, silent vibration wake-up, Snore Alert buzz).
// Same applicationId and signing as the phone app, which the Data Layer
// needs to pair the two. Build: ./gradlew :wear:assembleDebug
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.example.sleep_tracker.wear"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.matchlab.lullwake"
        minSdk = 30
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
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
