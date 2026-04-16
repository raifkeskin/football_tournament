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

subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions.jvmTarget.set(
            when (project.name) {
                "image_gallery_saver2", "image_gallery_saver2_fixed" ->
                    org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
                "flutter_image_compress_common" ->
                    org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
                else ->
                    org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
            },
        )
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
