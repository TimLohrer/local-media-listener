plugins {
    `maven-publish`
    id("com.github.johnrengelman.shadow") version "8.1.1"
    kotlin("jvm") version "2.0.21"
    kotlin("plugin.serialization") version embeddedKotlinVersion
}

group = "dev.timlohrer"
version = "1.0.0"

repositories {
    mavenLocal()
    mavenCentral()
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
}

tasks.test {
    useJUnitPlatform()
}
kotlin {
    jvmToolchain(21)
}

val cleanNativeLibs = tasks.register("cleanNativeLibs") {
    description = "Clean up native libraries from resources/lib"
    group = "native"
    
    doLast {
        val libDir = file("src/main/resources/lib")
        if (libDir.exists()) {
            libDir.listFiles()?.forEach { file ->
                if (file.isFile && (file.extension == "so" || file.extension == "dylib")) {
                    println("Deleting: ${file.name}")
                    file.delete()
                }
            }
        }
    }
}

val buildNativeLibs = tasks.register<Exec>("buildNativeLibs") {
    description = "Build native libraries for all platforms"
    group = "native"
    
    dependsOn(cleanNativeLibs)
    
    workingDir = file("native-hooks")
    commandLine = listOf("./build_all.sh")
    
    // Ensure the script is executable
    doFirst {
        val buildScript = file("native-hooks/build_all.sh")
        if (!buildScript.canExecute()) {
            buildScript.setExecutable(true)
        }
    }
}

tasks.jar {
//    dependsOn(buildNativeLibs)
    manifest {
        attributes["Main-Class"] = "dev.timlohrer.lml.LocalMediaListener"
    }
}

//tasks.shadowJar {
//    dependsOn(buildNativeLibs)
//    archiveClassifier.set("")
//    mergeServiceFiles()
//}

publishing {
    publications {
        create<MavenPublication>("maven") {
            groupId = project.group.toString()
            artifactId = "local_media_listener"
            version = project.version.toString()

            from(components["java"])
        }
    }
    repositories {
        mavenLocal()
    }
}