plugins {
    `maven-publish`
    id("com.github.johnrengelman.shadow") version "8.1.1"
    kotlin("jvm") version "2.1.21"
    kotlin("plugin.serialization") version "1.9.23"
}

group = "dev.timlohrer"
version = "1.0.0"

repositories {
    mavenCentral()
    mavenLocal()
}

dependencies {
    testImplementation(kotlin("test"))
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
}

tasks.test {
    useJUnitPlatform()
}
kotlin {
    jvmToolchain(21)
}

tasks.jar {
    manifest {
        attributes["Main-Class"] = "dev.timlohrer.lml.LocalMediaListener"
    }
}

tasks.shadowJar {
    archiveClassifier.set("")
    mergeServiceFiles()
}

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