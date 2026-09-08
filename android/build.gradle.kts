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

// Some plugin AARs (e.g. awesome_notifications_core) still declare an old
// compileSdkVersion and haven't been updated to satisfy the compileSdk >= 34
// requirement of their own newer AndroidX transitive dependencies. Force every
// Android library subproject to compile against the same SDK level as the app
// module so the AAR metadata check passes. Must be registered before
// evaluationDependsOn(":app") below forces early evaluation of subprojects.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let { android ->
            android.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
