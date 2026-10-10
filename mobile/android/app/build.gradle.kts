import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties (git-ignored), e.g.
//   storeFile=C:/keys/upload-keystore.jks
//   storePassword=...
//   keyAlias=upload
//   keyPassword=...
// Release builds fail without it rather than shipping debug-signed.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.thyantra.billing"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent Play Store identity: never change after the first upload.
        applicationId = "com.thyantra.billing"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

// Checked only when a release task actually runs, so debug builds work
// without a keystore.
gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { it.project == project && it.name.contains("Release") }
    if (buildingRelease && android.signingConfigs.findByName("release") == null) {
        throw GradleException(
            "Release signing is not configured: create android/key.properties " +
                "(see https://docs.flutter.dev/deployment/android#sign-the-app).",
        )
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
