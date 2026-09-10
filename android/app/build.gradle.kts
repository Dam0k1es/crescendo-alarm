import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.wakeywakey.wakeywakey"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // docs/TODO.md T-90: `java.time.*` gibt es auf Android erst ab API 26,
        // dieses Projekt verspricht aber minSdk 24. Nachgewiesen im gebauten
        // Release-Dex: `strings classes.dex | grep '^Ljava/time/'` findet
        // `Ljava/time/Duration;`, und es gibt KEINE `Lj$/`-Ersatzklassen -
        // der Aufruf ging also un-desugart ins APK. Quelle ist das
        // `alarm`-Plugin (AlarmSettings.kt:138, `Duration.ofMillis`), das kein
        // eigenes Desugaring aktiviert und selbst minSdk 19 deklariert.
        //
        // Nach genauerem Lesen sitzt der Aufruf auf einem
        // Rueckwaertskompatibilitaets-Pfad fuer altes v4-Alarm-JSON, den die
        // aktuelle App-Version normalerweise nicht betritt - es ist also eine
        // LATENTE API-26-Mine unter einem minSdk-24-Vertrag, kein bestaetigter
        // Absturz. Desugaring entschaerft sie unabhaengig davon und kostet nur
        // Bauzeit; das ist deutlich billiger als die Frage offen zu lassen,
        // denn es gibt in diesem Projekt keinen einzigen Beweis, dass die App
        // auf API 24 laeuft (der E2E-Emulator fuhr bisher nur API 34).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.wakeywakey.wakeywakey"
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

dependencies {
    // Gehoert zu isCoreLibraryDesugaringEnabled oben (docs/TODO.md T-90):
    // liefert die `java.time`-Ersatzklassen (`Lj$/...`) fuer API < 26.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
