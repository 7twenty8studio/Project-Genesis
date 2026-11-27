// Read access to the bundled Bible databases: the same SQLite files the
// iOS app ships (Genesis/Resources/Bibles), opened read-only with the
// bundled SQLite driver (FTS5 included on every phone).
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.genesis.core.bible"
    compileSdk = libs.versions.compileSdk.get().toInt()
    compileSdkMinor = libs.versions.compileSdkMinor.get().toInt()
    defaultConfig { minSdk = libs.versions.minSdk.get().toInt() }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    sourceSets {
        // One copy of each Bible in the repository, shared with iOS. The
        // cross references ride along for phase 2.
        getByName("main").assets.directories.add("../../../Genesis/Resources/Bibles")
        // Explore's people, places and events (Study.sqlite and its LICENSE.txt);
        // the app leaves out the folder's other databases until their features arrive.
        getByName("main").assets.directories.add("../../../Genesis/Resources/Study")
    }
}

dependencies {
    api(project(":core:domain"))
    implementation(libs.androidx.sqlite.bundled)
    implementation(libs.kotlinx.coroutines.android)
}
