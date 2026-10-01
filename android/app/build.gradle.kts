import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // docs/TODO.md T-148: see settings.gradle.kts's comment on the plugin
    // version - `:app:cyclonedxBom` (invoked from CI) writes
    // build/app/reports/cyclonedx/bom.json (from the repository root) for
    // osv-scanner and scripts/check_proprietary_native_deps.py.
    id("org.cyclonedx.bom")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// docs/TODO.md T-187 (maintainer request): a fixed, shared debug keystore so
// every dev build - CI's own "Build Android (development)" job and any local
// `flutter build apk --debug` - carries the SAME signature. Without this,
// each machine (a fresh CI runner every run included) silently generates its
// own random debug key the first time one is needed, so no two dev builds
// from different machines/runs can ever update each other in place -
// Android refuses the install with INSTALL_FAILED_UPDATE_INCOMPATIBLE. Not a
// secret in the meaningful sense (its only job is internal consistency, not
// proving identity), but still gitignored like every other keystore here
// (`**/*.jks`) and absent on a fresh clone by design: falls back to AGP's
// own ordinary per-machine debug signing when the file isn't present, so
// this is additive, never a hard requirement to build at all.
val devKeystoreFile = rootProject.file("app/keystore/crescendo-alarm-dev.jks")

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
        // the app runs on API 24 (the E2E emulator runs API 36, and ran
        // API 34 before that).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.crescendoalarm.crescendoalarm"
        // Pinned, not `flutter.minSdkVersion` (24 as well on the current
        // Flutter, but free to move with an SDK upgrade): several plugins
        // (image_picker_android, shared_preferences_android,
        // flutter_plugin_android_lifecycle in their currently-resolved
        // versions) declare minSdk=24 in their own Gradle modules, and
        // Android's manifest merger always takes the highest minSdk across
        // the app and all dependencies, so 24 is the real enforced floor
        // regardless of what's set here (found via MobSF static analysis
        // flagging a mismatch). Going lower needs those plugins downgraded
        // first, not just this line changed.
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
        if (devKeystoreFile.exists()) {
            // Conventional Android debug alias/passwords (matching AGP's own
            // default debug signing config) - not sensitive on their own,
            // since the key material in the file itself is what actually
            // needs to be identical across machines/runs, not the password.
            create("dev") {
                storeFile = devKeystoreFile
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
    }

    // docs/TODO.md T-213 (F-1): without this, AGP writes the resolved
    // dependency list into the APK Signing Block (ID 0x504b4453), encrypted
    // with a key only Google holds. F-Droid rejects that block - nobody else
    // can read or verify it. scripts/check_apk_dependency_block.py checks
    // every APK CI builds, so a DSL change that silently re-enables it fails.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        debug {
            if (devKeystoreFile.exists()) {
                signingConfig = signingConfigs.getByName("dev")
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
//
// docs/TODO.md T-213: `coreLibraryDesugaring` too, because desugar_jdk_libs
// ships (as the APK's classes2.dex, GPL-2.0 with the Classpath Exception)
// but lives in its own configuration, outside releaseRuntimeClasspath.
// scripts/gen_android_library_notices.py turns this SBOM into the in-app
// list of Android libraries (assets/text/licences/AndroidLibraries.txt).
tasks.named<org.cyclonedx.gradle.CyclonedxDirectTask>("cyclonedxDirectBom") {
    includeConfigs.set(listOf("releaseRuntimeClasspath", "coreLibraryDesugaring"))
}

// docs/TODO.md T-148: the one real finding the scoped SBOM above turned up -
// `device_calendar` transitively pulls `gson:2.8.8`, which carries
// GHSA-4jrv-ppp4-jm57/CVE-2022-25647 (a deserialization type-confusion
// issue, CVSS 7.7). Forced to a fixed release (2.8.9 or later) rather than
// accepted as an exception: there is no reason to carry a fixable HIGH when
// the fix is a one-line version bump. Dependabot keeps bumping this pin
// (2.8.9 -> 2.14.0 on 2026-09-25), so it is no longer the same-minor patch
// release T-148 chose: every bump has to keep `device_calendar` working,
// which serializes calendars and events to Dart with Gson.
configurations.all {
    resolutionStrategy {
        force("com.google.code.gson:gson:2.14.0")
    }
}

dependencies {
    // Belongs to isCoreLibraryDesugaringEnabled above (docs/TODO.md T-90):
    // supplies the `java.time` replacement classes (`Lj$/...`) for API < 26.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // docs/TODO.md T-198: JVM unit tests for SleepTimeDndPolicy
    // (src/test/kotlin), run by ci.yml's build-dev-apk job. Test classpath
    // only - never part of releaseRuntimeClasspath, the SBOM, or the APK.
    testImplementation("junit:junit:4.13.2")
}
