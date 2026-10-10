plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.findit.findit"
    // 37 required by permission_handler_android (was flutter.compileSdkVersion=36)
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.findit.findit"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
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

    packaging {
        resources {
            // annotation and annotation-jvm both ship this LICENSE
            excludes += "META-INF/androidx/annotation/annotation/LICENSE.txt"
            // Kotlin multiplatform metadata is duplicated across common/jvm
            // artifacts; the content is identical, so pick the first.
            pickFirsts += "commonMain/default/manifest"
            pickFirsts += "commonMain/default/linkdata/module"
            pickFirsts += "META-INF/kotlin-project-structure-metadata.json"
        }
    }
}

// tracing-ktx is superseded by tracing-android; drop the old artifact to
// avoid duplicate androidx.tracing.TraceKt classes.
configurations.all {
    exclude(group = "androidx.tracing", module = "tracing-ktx")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
