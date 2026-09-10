allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Hier stand ein Override, der jedes Android-Library-Subprojekt auf
// compileSdk 36 zwang. Grund war `awesome_notifications_core`, das
// compileSdkVersion 33 hartkodiert hatte und damit die AAR-Metadatenpruefung
// gegen seine eigenen neueren AndroidX-Abhaengigkeiten reissen liess.
//
// Entfallen im Hygiene-Durchgang 2026-09-10 (docs/TODO.md T-97):
// `awesome_notifications` 0.12.1 fordert `awesome_notifications_core`
// ueberhaupt nicht - der Eintrag in pubspec.yaml war Altlast aus der
// 0.9.x/0.10.x-Zeit, als das Hauptpaket ihn noch brauchte. Ohne die
// Abhaengigkeit ist die stoerende AAR aus dem Build, und der Behelf hat seinen
// Grund verloren. Verifiziert mit einem `flutter clean`-Release-Build, nicht
// nur inkrementell.

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
