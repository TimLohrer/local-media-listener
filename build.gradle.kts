plugins {
    `maven-publish`
    id("com.gradleup.shadow") version "9.3.1"
    kotlin("jvm") version "2.0.21"
    kotlin("plugin.serialization") version embeddedKotlinVersion
}

group = "dev.timlohrer"
version = "1.0.8-SNAPSHOT"

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("org.endlesssource.mediainterface:all:0.1.2")
    implementation("org.slf4j:slf4j-api:2.0.16")
    runtimeOnly("org.slf4j:slf4j-simple:2.0.16")
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
    duplicatesStrategy = DuplicatesStrategy.INCLUDE // include all service files
    mergeServiceFiles { // always merge service files
        include("META-INF/services/org.endlesssource.mediainterface.spi.PlatformMediaProvider")
    }
}

tasks.build {
    dependsOn(tasks.shadowJar)
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
        maven {
            name = "timlohrer-snapshots"
            url = uri("https://reposilite.timlohrer.dev/snapshots")
            credentials {
                username = System.getenv("REPOSILITE_USERNAME")
                password = System.getenv("REPOSILITE_PASSWORD")
            }
        }
    }
}
