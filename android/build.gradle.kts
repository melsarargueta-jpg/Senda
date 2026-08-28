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

// Forzar compileSdk a 34 en todos los submódulos para satisfacer los metadatos de AndroidX
subprojects {
    afterEvaluate {
        val extension = extensions.findByName("android")
        if (extension != null) {
            try {
                val method = extension.javaClass.getMethod("compileSdk", Int::class.java)
                method.invoke(extension, 34)
            } catch (e: Exception) {
                // Ignorar si el submódulo no usa la extensión de Android
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}