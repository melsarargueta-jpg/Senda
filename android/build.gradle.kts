allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// Forzar compileSdk = 34 a nivel de cada subproyecto (librerías externas)
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library")) {
            configure<com.android.build.api.dsl.LibraryExtension> {
                compileSdk = 34
            }
        }
    }
}

// Opción de respaldo: Desactivar la validación estricta de AAR metadata en los subproyectos
subprojects {
    tasks.withType<com.android.build.gradle.tasks.CheckAarMetadata> {
        enabled = false
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}