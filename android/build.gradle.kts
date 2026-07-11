allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// flutter_thermal_printer (and some other plugins) pin compileSdk 33, but
// their AndroidX deps require compiling against 34+. Force every Android
// plugin module to compile against SDK 36. Reflection keeps this working
// across AGP versions without importing AGP DSL types.
subprojects {
    afterEvaluate {
        val android = project.extensions.findByName("android") ?: return@afterEvaluate
        runCatching {
            android.javaClass.methods
                .firstOrNull { it.name == "setCompileSdk" && it.parameterTypes.size == 1 }
                ?.invoke(android, 36)
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
