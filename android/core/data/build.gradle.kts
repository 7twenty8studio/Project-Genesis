// The person's own data on the device: highlights now, then notes,
// bookmarks, prayers and the rest, with the fields sync needs (updated_at,
// deleted_at) from the start, as the Supabase tables have them.
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.genesis.core.data"
    compileSdk = libs.versions.compileSdk.get().toInt()
    compileSdkMinor = libs.versions.compileSdkMinor.get().toInt()
    defaultConfig { minSdk = libs.versions.minSdk.get().toInt() }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    api(project(":core:domain"))
    implementation(libs.androidx.sqlite.bundled)
    implementation(libs.kotlinx.coroutines.android)
}
