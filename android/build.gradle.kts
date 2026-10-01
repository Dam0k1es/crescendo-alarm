allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Every project builds into the Flutter project's top-level build/ (:app into
// build/app/), where the flutter tool and CI look for the APK and the SBOM.
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// No compileSdk override for plugin subprojects any more: its only reason,
// `awesome_notifications_core`, left the build in docs/TODO.md T-97 (see
// CLAUDE.md). Should one ever be needed again, register its `afterEvaluate`
// before the `evaluationDependsOn(":app")` below - after it, Gradle throws
// "Cannot run Project.afterEvaluate(Action) when the project is already
// evaluated".

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
