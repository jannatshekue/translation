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

// Some plugins (e.g. tflite_flutter) don't pin their own JVM target and end
// up inheriting whatever JDK runs Gradle, which can drift from the app's
// Java 17 compileOptions and fail with "Inconsistent JVM Target
// Compatibility Between Java and Kotlin Tasks". Force every subproject's
// Kotlin compile tasks to match.
subprojects {
    fun alignJvmTarget() {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
    }
    // Must run after the plugin's own build.gradle (which may set Java 11
    // itself) so our override isn't clobbered — but afterEvaluate throws if
    // the project has already finished evaluating, which happens for some
    // subprojects depending on evaluation order, so guard for both cases.
    if (state.executed) alignJvmTarget() else afterEvaluate { alignJvmTarget() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
