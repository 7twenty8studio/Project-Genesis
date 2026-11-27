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
