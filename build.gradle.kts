plugins {
    `maven-publish`
    id("com.gradleup.shadow") version "9.3.1"
    kotlin("jvm") version "2.0.21"
    kotlin("plugin.serialization") version embeddedKotlinVersion
}

group = "dev.timlohrer"
version = "1.0.3-SNAPSHOT"

repositories {
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

tasks.jar {
    manifest {
        attributes["Main-Class"] = "dev.timlohrer.lml.LocalMediaListener"
    }
}

//tasks.shadowJar {
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