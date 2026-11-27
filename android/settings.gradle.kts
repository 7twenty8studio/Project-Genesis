// Versely for Android (code name Genesis). Native Kotlin + Jetpack Compose,
// sharing the Supabase backend, the bundled Bible databases and the data
// tools with the iOS app. Plan: docs/ANDROID_PLAN.md.
pluginManagement {
    // The plugin portal first: Maven Central rate-limits shared build
    // machines (HTTP 429), and the portal serves the Kotlin plugins too.
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
    }
}

plugins {
    // Downloads Java 21 for the build when the machine doesn't have it
    // (a Mac with only Android Studio's own Java, for example).
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "Versely"

include(":app")
include(":core:domain")
include(":core:bible")
include(":core:design")
include(":core:data")
