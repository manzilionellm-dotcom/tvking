plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Une configuration incomplète arrête NOVATUBE. Aucun key.properties,
// aucune clé historique et aucun repli vers la signature debug ne sont lus.
fun novatubeSecret(name: String): String =
    System.getenv(name)?.takeIf { it.isNotBlank() }
        ?: throw GradleException("Configuration NOVATUBE manquante : $name")

val novatubeStore = file(novatubeSecret("NOVATUBE_KEYSTORE_PATH"))
require(novatubeStore.isFile) { "Keystore dédié NOVATUBE introuvable" }
val novatubeAlias = novatubeSecret("NOVATUBE_UPLOAD_KEY_ALIAS")
require(novatubeAlias == "novatube-upload") { "Alias de signature NOVATUBE inattendu" }
require(flutter.versionName == "0.1.5" && flutter.versionCode == 5) {
    "Cette branche prépare exclusivement NOVATUBE 0.1.5 (5)"
}

// Le mode Cast de test n'a aucune place dans un bundle Play de NOVATUBE.
val novatubeDefines = (project.findProperty("dart-defines") as? String)
    .orEmpty().split(',').filter { it.isNotBlank() }
    .map { String(java.util.Base64.getDecoder().decode(it), Charsets.UTF_8) }
require(novatubeDefines.none { it.startsWith("ZUNO_CAST_TEST=") }) {
    "Le drapeau ZUNO_CAST_TEST est interdit pour NOVATUBE"
}

android {
    namespace = "com.sevenmotion.novatube"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.sevenmotion.novatube"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("novatubeUpload") {
            storeFile = novatubeStore
            storeType = "JKS"
            storePassword = novatubeSecret("NOVATUBE_UPLOAD_STORE_PASSWORD")
            keyAlias = novatubeAlias
            keyPassword = novatubeSecret("NOVATUBE_UPLOAD_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("novatubeUpload")
        }
    }

    // Même pont Cast et même coexistence libc++ que la source mobile validée.
    packaging { jniLibs { pickFirsts.add("**/libc++_shared.so") } }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter { source = "../.." }

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.android.gms:play-services-cast-framework:21.5.0")
    implementation("androidx.mediarouter:mediarouter:1.6.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.fragment:fragment:1.6.2")
}
