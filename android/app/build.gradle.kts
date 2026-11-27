import java.util.Properties

/**
 * Supabase's address and public (anon) key: the same git-ignored
 * Config/Secrets.xcconfig the iPhone app reads, or versely.supabaseUrl /
 * versely.supabaseAnonKey in android/local.properties. Without them the build
 * still runs, and the Account screen says sync isn't set up.
 */
fun cloudSetting(xcconfigKey: String, propertyKey: String): String {
    val local = Properties().apply {
        rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
    }
    local.getProperty(propertyKey)?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
    val secrets = rootProject.file("../Config/Secrets.xcconfig").takeIf { it.exists() } ?: return ""
    val line = secrets.readLines().map { it.trim() }.firstOrNull { it.startsWith("$xcconfigKey ") || it.startsWith("$xcconfigKey=") }
        ?: return ""
    val value = line.substringAfter('=').trim().replace("\$(SLASH)", "/")
    return if (value.startsWith("YOUR-") || value.contains("YOUR-PROJECT")) "" else value
}

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.genesis.app"
    compileSdk = libs.versions.compileSdk.get().toInt()
    compileSdkMinor = libs.versions.compileSdkMinor.get().toInt()

    defaultConfig {
        // Proposed in the plan, waiting for the owner's yes: Android ids
        // can't start a part with a digit, so the iOS id can't be reused.
        // It can never change after the first Play upload.
        applicationId = "com.seventwenty8studio.versely"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 1
        versionName = "0.1.0"
        buildConfigField("String", "SUPABASE_URL", "\"${cloudSetting("SUPABASE_URL", "versely.supabaseUrl")}\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"${cloudSetting("SUPABASE_ANON_KEY", "versely.supabaseAnonKey")}\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    androidResources {
        // Screens in English, Spanish and Brazilian Portuguese, as on iOS.
        localeFilters += listOf("en", "es", "pt-rBR")
        // Android's default list, then the study databases whose features haven't
        // arrived yet (shared with iOS in Genesis/Resources/Study): not in the APK.
        ignoreAssetsPattern = "!.svn:!.git:!.ds_store:!*.scc:.*:<dir>_*:!CVS:!thumbs.db:!picasa.ini:!*~:!WordStudy.sqlite:!Glosses.sqlite:!Topics.sqlite"
    }
}

dependencies {
    implementation(project(":core:domain"))
    implementation(project(":core:bible"))
    implementation(project(":core:design"))
    implementation(project(":core:data"))
    implementation(project(":core:cloud"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.glance.appwidget)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.junit)
}
