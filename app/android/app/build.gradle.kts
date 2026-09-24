import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Der Schlüssel, mit dem Release-APKs signiert werden. Android nimmt ein
// Update nur an, wenn es mit demselben Schlüssel signiert ist wie die
// installierte Version – ein wechselnder Schlüssel hieße: deinstallieren und
// dabei die lokalen Zettel verlieren.
//
// Lokal steht er in android/key.properties (nicht im Repository), in der
// Release-Pipeline kommt er über Umgebungsvariablen aus den Secrets.
// Fehlt beides, bleibt es beim Debug-Schlüssel, damit
// `flutter run --release` ohne Einrichtung funktioniert.
val keyProperties =
    Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }

fun signingValue(property: String, environment: String): String? =
    keyProperties.getProperty(property) ?: System.getenv(environment)

android {
    namespace = "dev.fusen.fusen"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.fusen.fusen"
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

    signingConfigs {
        val storePath = signingValue("storeFile", "FUSEN_KEYSTORE")
        if (storePath != null) {
            create("release") {
                storeFile = file(storePath)
                storePassword = signingValue("storePassword", "FUSEN_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "FUSEN_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "FUSEN_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
