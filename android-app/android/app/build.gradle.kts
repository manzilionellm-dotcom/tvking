import com.android.build.api.dsl.ApplicationExtension
import java.util.Base64

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
// Le mode Cast de test n'a aucune place dans un bundle Play de NOVATUBE.
val novatubeDefines = (project.findProperty("dart-defines") as? String)
    .orEmpty().split(',').filter { it.isNotBlank() }
    .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
require(novatubeDefines.none { it.startsWith("ZUNO_CAST_TEST=") }) {
    "Le drapeau ZUNO_CAST_TEST est interdit pour NOVATUBE"
}
val novatubePrivateApk = novatubeDefines.contains("NOVATUBE_PRIVATE_APK=true")
val novatubeExpectedName = if (novatubePrivateApk) "0.1.5" else "0.1.6"
val novatubeExpectedCode = if (novatubePrivateApk) 5 else 6
require(flutter.versionName == novatubeExpectedName && flutter.versionCode == novatubeExpectedCode) {
    "Version NOVATUBE inattendue pour cette distribution"
}

extensions.configure<ApplicationExtension> {
    namespace = "com.sevenmotion.novatube"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    buildFeatures { buildConfig = true }

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
        // Constante native fermée à la compilation : les adaptations FGS
        // de Google Play ne modifient jamais le comportement de l'APK privé.
        buildConfigField("boolean", "NOVATUBE_PLAY", "false")
        // Les tests d'export tournent contre le véritable APK release signé.
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    testBuildType = "release"

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
        getByName("release") {
            signingConfig = signingConfigs.getByName("novatubeUpload")
            buildConfigField("boolean", "NOVATUBE_PLAY", (!novatubePrivateApk).toString())
        }
    }

    // Surcouche réservée au bundle Play NOVATUBE : le manifeste principal
    // et les modèles ZUNO/TV restent inchangés. L'APK privé conserve aussi
    // son manifeste actuel ; sa commande transmet explicitement ce define.
    if (!novatubePrivateApk) {
        sourceSets.getByName("release").manifest.srcFile(
            "src/novatubePlay/AndroidManifest.xml"
        )
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
    // Même extracteur TS/HEVC que le lecteur existant, sans nouveau codec natif.
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    // Banc Android isolé : vrais codecs/MediaStore, absent de l'APK livré.
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}
