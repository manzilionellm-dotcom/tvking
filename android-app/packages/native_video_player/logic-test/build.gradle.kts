plugins {
    kotlin("jvm") version "2.0.21"
}

repositories {
    mavenCentral()
}

dependencies {
    testImplementation(kotlin("test"))
}

kotlin {
    jvmToolchain(21)
}

sourceSets {
    named("main") {
        // Racine = le dossier kotlin du plugin, pour respecter les packages.
        // On ne compile PAS les fichiers Android (ExoPlayer, Flutter) : ils
        // ne servent pas à ces tests, et ils exigent le SDK Android.
        kotlin.setSrcDirs(listOf("../android/src/main/kotlin"))
        kotlin.exclude("**/NativeVideoView.kt")
        kotlin.exclude("**/NativeVideoViewFactory.kt")
        kotlin.exclude("**/NativeVideoPlayerPlugin.kt")
        // Parle à AudioManager : le test n'a pas le SDK Android.
        // La décision (écrire ou pas) est dans AudioModeGuard.kt.
        kotlin.exclude("**/AudioModeApplier.kt")
        kotlin.exclude("**/ClearVoiceProcessor.kt")
        kotlin.exclude("**/AudioProbeProcessor.kt")
        kotlin.exclude("**/ZunoAudioChain.kt")
        kotlin.exclude("**/SystemEffectsRead.kt")
        kotlin.exclude("**/RememberingAudioTrackProvider.kt")
    }
}

tasks.test {
    testLogging {
        events("passed", "failed", "standardOut")
        showStandardStreams = true
    }
}
