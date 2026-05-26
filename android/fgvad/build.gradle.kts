plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    `maven-publish`
}

android {
    namespace = "io.fengur.fgvad"
    compileSdk = 36

    defaultConfig {
        minSdk = 26

        ndk { abiFilters += "arm64-v8a" }

        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = "com.github.Fengur"
            artifactId = "fgvad"
            version = "0.2.0"

            afterEvaluate {
                from(components["release"])
            }

            pom {
                name.set("fgvad")
                description.set("智能 VAD 库 —— Rust 封装 ten-vad,带状态机和动态端点策略。")
                url.set("https://github.com/Fengur/fgvad")
                licenses {
                    license {
                        name.set("MIT")
                        url.set("https://opensource.org/licenses/MIT")
                    }
                }
                developers {
                    developer {
                        id.set("Fengur")
                        name.set("Fengur")
                    }
                }
                scm {
                    connection.set("scm:git:https://github.com/Fengur/fgvad.git")
                    developerConnection.set("scm:git:https://github.com/Fengur/fgvad.git")
                    url.set("https://github.com/Fengur/fgvad")
                }
            }
        }
    }
}
