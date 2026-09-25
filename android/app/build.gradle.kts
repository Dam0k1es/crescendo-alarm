import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // docs/TODO.md T-148: see settings.gradle.kts's comment on the plugin
    // version - `:app:cyclonedxBom` (invoked from CI) writes
    // build/reports/bom.json for osv-scanner.
    id("org.cyclonedx.bom")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.crescendoalarm.crescendoalarm"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // docs/TODO.md T-90: `java.time.*` only exists on Android from API 26
        // onward, but this project promises minSdk 24. Confirmed in the built
        // release dex: `strings classes.dex | grep '^Ljava/time/'` finds
        // `Ljava/time/Duration;`, and there are NO `Lj$/` replacement classes -
        // so the call went into the APK un-desugared. The source is the
        // `alarm` plugin (AlarmSettings.kt:138, `Duration.ofMillis`), which
        // doesn't enable its own desugaring and itself declares minSdk 19.
        //
        // On closer reading, the call sits on a backward-compatibility path
        // for old v4 alarm JSON that the current app version normally never
        // enters - so it's a LATENT API-26 mine under a minSdk-24 contract,
        // not a confirmed crash. Desugaring defuses it regardless and only
        // costs build time; that's considerably cheaper than leaving the
        // question open, since this project has no evidence whatsoever that
        // the app runs on API 24 (the E2E emulator has so far only run
        // API 34).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.crescendoalarm.crescendoalarm"
        // Was intended to stay below the Flutter default (21) for older-device
        // compatibility, but several plugins (image_picker_android,
        // shared_preferences_android, flutter_plugin_android_lifecycle in their
        // currently-resolved versions) declare minSdk=24 in their own Gradle
        // modules; Android's manifest merger always takes the highest minSdk
        // across the app and all dependencies, so 24 is the real enforced floor
        // regardless of what's set here. Set explicitly to 24 to match reality
        // (found via MobSF static analysis flagging a mismatch) rather than
        // leave a value that looks lower than what actually gets enforced.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

// docs/TODO.md T-148: scoped to exactly what ships in a release APK. Left
// unscoped, the SBOM (and therefore osv-scanner) also picked up
// `androidTestImplementation`/instrumentation-test infrastructure (found via
// this project's own integration_test/androidTest setup) - `netty`,
// pulled in transitively by `com.google.testing.platform:core` and
// `com.android.tools.emulator:proto`, is real test-runner tooling that never
// reaches a shipped build, and osv-scanner flagged a long list of real CVEs
// against it. Scoping here, not by hand-listing every such CVE as an
// exception, keeps the gate meaningful as those dependencies' versions
// change.
tasks.named<org.cyclonedx.gradle.CyclonedxDirectTask>("cyclonedxDirectBom") {
    includeConfigs.set(listOf("releaseRuntimeClasspath"))
}

// docs/TODO.md T-148: the one real finding the scoped SBOM above turned up -
// `device_calendar` transitively pulls `gson:2.8.8`, which carries
// GHSA-4jrv-ppp4-jm57/CVE-2022-25647 (a deserialization type-confusion
// issue, CVSS 7.7). Forced to the fixed 2.8.9 rather than accepted as an
// exception: a same-minor-series patch release is exceedingly unlikely to
// break anything `device_calendar` does with it, and there is no reason to
// carry a fixable HIGH when the fix is a one-line version bump.
configurations.all {
    resolutionStrategy {
        force("com.google.code.gson:gson:2.14.0")
    }
}

dependencies {
    // Belongs to isCoreLibraryDesugaringEnabled above (docs/TODO.md T-90):
    // supplies the `java.time` replacement classes (`Lj$/...`) for API < 26.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
