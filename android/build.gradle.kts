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

// Configuración directa de compileSdk y desactivación del check de AAR metadata
subprojects {
    plugins.withId("com.android.library") {
        configure<com.android.build.api.dsl.LibraryExtension> {
            compileSdk = 34
        }
    }
    
    tasks.matching { it.name.contains("CheckAarMetadata") }.configureEach {
        enabled = false
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}