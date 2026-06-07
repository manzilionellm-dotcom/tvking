// =========================================================
//  settings.gradle.kts — Definit le projet Gradle racine
// =========================================================
//  Sous-projets : `:app` (l'APK wrapper Android TV).
//
//  Repositories : Google + Maven Central — AGP est sur Google,
//  Kotlin + AndroidX sont sur Maven Central. Pas de JitPack ici,
//  on n'a aucune dep tierce.
// =========================================================

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "tv-king-tv-wrapper"
include(":app")
