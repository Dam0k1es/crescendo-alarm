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
        // docs/TODO.md T-90 / T-220: no core-library desugaring. It was enabled
        // only because the `alarm` plugin calls `java.time.Duration` on a
        // backward-compatibility path while the app promised minSdk 24
        // (`java.time` exists from API 26), and it shipped
        // `desugar_jdk_libs` - GPL-2.0 with the Classpath Exception, with no
        // matching source tag or sources jar to point at. The maintainer
        // raised minSdk to 26 instead (2026-10-23): both the latent bug and the
        // GPL component are gone.
    }

    defaultConfig {
        applicationId = "com.crescendoalarm.crescendoalarm"
        // Pinned, not `flutter.minSdkVersion`: Flutter's own default is lower
        // (24) and may move with an SDK upgrade, while this app needs API 26 -
        // `java.time` without desugaring (see compileOptions above). The
        // plugins' own floors (several declare 24) sit below it, so 26 is the
        // enforced minimum. Raised from 24 on 2026-10-23 (docs/TODO.md T-220):
        // Android 7.0 and 7.1 are no longer supported.
        minSdk = 26
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
            // docs/TODO.md (F-Droid readiness): without key.properties the
            // release config has no keystore and `validateSigningRelease` fails
            // ("Keystore file not set for signing config release"). F-Droid's
            // builder has no key - it builds and re-signs with its own - so the
            // F-Droid recipe sets CRESCENDO_ALLOW_DEBUG_SIGNED_RELEASE=1 to let
            // the build fall back to the debug key. Never the default: a CI
            // release build that lost its key must stay red, not publish a
            // debug-signed APK (test/build_pins_test.dart; no workflow sets it).
            signingConfig =
                if (keystoreProperties["storeFile"] == null &&
                    System.getenv("CRESCENDO_ALLOW_DEBUG_SIGNED_RELEASE") == "1") {
                    signingConfigs.getByName("debug")
                } else {
                    signingConfigs.getByName("release")
                }
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
// scripts/gen_android_library_notices.py turns this SBOM into the in-app
// list of Android libraries (assets/text/licences/AndroidLibraries.txt).
tasks.named<org.cyclonedx.gradle.CyclonedxDirectTask>("cyclonedxDirectBom") {
    includeConfigs.set(listOf("releaseRuntimeClasspath"))
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
    // docs/TODO.md T-198: JVM unit tests for SleepTimeDndPolicy
    // (src/test/kotlin), run by ci.yml's build-dev-apk job. Test classpath
    // only - never part of releaseRuntimeClasspath, the SBOM, or the APK.
    testImplementation("junit:junit:4.13.2")
}
