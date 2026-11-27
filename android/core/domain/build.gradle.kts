// Pure rules, no Android code: Bible books and references, verse ids,
// themes. Tested on the JVM against the fixtures the iOS app and the web
// already share, so all three clients give the same answers.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvmToolchain(21)
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

val shared = rootProject.layout.projectDirectory.dir("../supabase/functions/_shared")

sourceSets {
    // bibleBooks.json is generated from BibleBook.swift and the KJV by
    // Tools/BibleData/export_reference_books.py: one source for every client.
    main { resources.srcDir(layout.buildDirectory.dir("generated/bibleBooks")) }
    test { resources.srcDir(shared.dir("fixtures")) }
}

val copyBibleBooks = tasks.register<Copy>("copyBibleBooks") {
    from(shared.file("bibleBooks.json"))
    into(layout.buildDirectory.dir("generated/bibleBooks/com/genesis/core/domain/bible"))
}
tasks.named("processResources") { dependsOn(copyBibleBooks) }

dependencies {
    implementation(libs.kotlinx.serialization.json)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.junit)
}
