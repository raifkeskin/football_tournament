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
// Eski eklentiler düşük compileSdk ile geliyor; güncel androidx ve
// permission_handler en az 37 ister. (evaluationDependsOn'dan önce olmalı.)
subprojects {
    afterEvaluate {
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.let {
            val current = it.compileSdkVersion?.substringAfter("android-")?.toIntOrNull() ?: 0
            if (current < 37) it.compileSdkVersion(37)
        }
    }
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
                else ->
                    org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
            },
        )
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
