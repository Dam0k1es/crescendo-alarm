pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.4.1" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    // docs/TODO.md T-148: generates a CycloneDX SBOM of the FULLY RESOLVED
    // native Android dependency tree (AndroidX, media3, the camera plugin's
    // own transitive deps, ...) for osv-scanner to check - which
    // `--lockfile=pubspec.lock` alone never covered, since that only sees
    // the Dart side. Purely a reporting step (`:app:cyclonedxBom`, applied
    // in app/build.gradle.kts): it does not lock or pin anything, so it
    // carries none of Gradle dependency locking's maintenance burden.
    id("org.cyclonedx.bom") version "3.4.1" apply false
}

include(":app")
