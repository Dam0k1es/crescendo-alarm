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

// An override used to sit here that forced every Android library subproject
// to compileSdk 36. The reason was `awesome_notifications_core`, which
// hardcoded compileSdkVersion 33 and thereby made the AAR metadata check fail
// against its own newer AndroidX dependencies.
//
// Removed in the 2026-09-10 hygiene pass (docs/TODO.md T-97):
// `awesome_notifications` 0.12.1 does not require `awesome_notifications_core`
// at all - the entry in pubspec.yaml was leftover cruft from the
// 0.9.x/0.10.x era, when the main package still needed it. Without that
// dependency the offending AAR is out of the build, and the workaround lost
// its reason to exist. Verified with a `flutter clean` release build, not
// just an incremental one.

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
