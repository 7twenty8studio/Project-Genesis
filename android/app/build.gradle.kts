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
        // Crash reports go to the same Sentry project as the iPhone app's (none without a DSN).
        buildConfigField("String", "SENTRY_DSN", "\"${cloudSetting("SENTRY_DSN", "versely.sentryDsn")}\"")
        // Push (Firebase Cloud Messaging): off until the Firebase project exists (android/PLAY_SETUP.md).
        buildConfigField("String", "FIREBASE_APP_ID", "\"${cloudSetting("FIREBASE_APP_ID", "versely.firebaseAppId")}\"")
        buildConfigField("String", "FIREBASE_API_KEY", "\"${cloudSetting("FIREBASE_API_KEY", "versely.firebaseApiKey")}\"")
        buildConfigField("String", "FIREBASE_PROJECT_ID", "\"${cloudSetting("FIREBASE_PROJECT_ID", "versely.firebaseProjectId")}\"")
        buildConfigField("String", "FIREBASE_SENDER_ID", "\"${cloudSetting("FIREBASE_SENDER_ID", "versely.firebaseSenderId")}\"")
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
    sourceSets {
        // Ambient sounds: the same loops as iOS (Genesis/Resources/Ambient), never copied.
        getByName("main").assets.directories.add("../../Genesis/Resources/Ambient")
        // The page-turn sound's five levels (page-turn-1…5.caf), shared with iOS.
        getByName("main").assets.directories.add("../../Genesis/Resources/Sounds")
    }
    androidResources {
        // Screens in English, Spanish and Brazilian Portuguese, as on iOS.
        localeFilters += listOf("en", "es", "pt-rBR")
        // Android's default list, then the study databases whose features haven't
        // arrived yet (shared with iOS in Genesis/Resources/Study): not in the APK.
        ignoreAssetsPattern = "!.svn:!.git:!.ds_store:!*.scc:.*:<dir>_*:!CVS:!thumbs.db:!picasa.ini:!*~:!Topics.sqlite"
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
    implementation(libs.media3.session)
    implementation(libs.media3.exoplayer)
    implementation(libs.sentry.android)
    implementation(libs.play.services.auth)
    implementation(libs.firebase.messaging)
    implementation(libs.play.billing)
    implementation(libs.kotlinx.coroutines.play.services)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.junit)
}
