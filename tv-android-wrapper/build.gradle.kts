// =========================================================
//  build.gradle.kts (racine) — Plugins declares "apply false"
// =========================================================
//  Le pattern recommande Gradle 8+ : on declare les versions des
//  plugins au niveau racine et on les applique dans les modules
//  enfants. Permet de pin Kotlin / AGP a un endroit unique.
// =========================================================

plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
