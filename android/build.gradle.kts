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
subprojects {
    project.evaluationDependsOn(":app")
}

// Plugins that don't set compileOptions get Java 1.8 by default, but with
// JDK 21 installed Kotlin defaults to jvmTarget=21 — causing a mismatch.
// Fix: raise Java to 21 for library subprojects that have no explicit setting.
// plugins.withId fires at plugin-application time so the callback runs before
// the subproject's own build.gradle, meaning plugins that explicitly set their
// own compileOptions (e.g. activity_recognition_flutter with Java 11) will
// override this and remain self-consistent. Don't touch Kotlin — let each
// plugin's own kotlinOptions stand to avoid creating new mismatches.
subprojects {
    plugins.withId("com.android.library") {
        configure<com.android.build.gradle.LibraryExtension> {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_21
                targetCompatibility = JavaVersion.VERSION_21
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
