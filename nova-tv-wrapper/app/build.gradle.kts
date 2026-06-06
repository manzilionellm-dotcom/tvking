// =========================================================
//  app/build.gradle.kts — Config du module app (APK Android TV)
// =========================================================
//  Cible : SHIELD, Fire TV Stick 4K Max, Chromecast avec Google
//  TV, et toutes les Android TV recentes. minSdk 23 (Android 6,
//  fin 2015) couvre 99%+ des Android TV en circulation et permet
//  d'utiliser les API WebView modernes (MSE pour hls.js).
//
//  Note : on N'inclut PAS de Compose / RecyclerView / AndroidX
//  Leanback. Le wrapper est volontairement MINIMAL — toute l'UI
//  est dans la WebView (tv-web React). Le code Kotlin se limite
//  a creer l'Activity et a configurer la WebView.
// =========================================================

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.manzilionellm.tvkingtv"
    compileSdk = 34

    // CRITIQUE pour empaqueter Next.js : par defaut, aapt IGNORE tout
    // dossier commencant par « _ » (regle « <dir>_* » du pattern par
    // defaut). Or Next.js met TOUT son CSS/JS dans le dossier « _next ».
    // Sans cet override, « _next » n'est PAS inclus dans l'APK -> aucun
    // asset -> ecran fige (JS/Next ne demarre pas). On reprend le pattern
    // par defaut SANS le token « <dir>_* » pour conserver « _next ».
    androidResources {
        ignoreAssetsPattern =
            "!.svn:!.git:!.ds_store:!*.scc:.*:!CVS:!thumbs.db:!picasa.ini:!*~"
    }

    defaultConfig {
        // NOVA+ : applicationId DISTINCT pour cohabiter avec les autres
        // apps du projet sur le meme appareil. (Le namespace Kotlin reste
        // com.manzilionellm.tvkingtv — interne, sans impact.)
        applicationId = "com.nova.plus"
        // minSdk 21 = Android 5.0 (Lollipop, 2014) — c'est le PLANCHER des
        // AndroidX récents (appcompat/webkit) et ça couvre la quasi-totalité
        // des box/TV Android en circulation. Abaissé depuis 23 pour corriger
        // les « Application non installée » sur les box plus anciennes
        // (l'install échoue quand minSdk > version de la box).
        // NB : sur ces appareils, hls.js a besoin d'un System WebView à jour
        // (Chromium, mis à jour via le Play Store) — l'install passe, et la
        // lecture marche dès que le WebView est récent.
        minSdk = 21
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"

        // Filtres ABI : on garde TOUTES les ABI Android TV (armv7,
        // arm64, x86, x86_64) parce qu'on n'a aucune lib native a
        // packer (juste du Kotlin + WebView).
    }

    // Clé de signature STABLE (committée) pour le sideload via Downloader.
    // Sans clé fixe, chaque build CI utilise un debug.keystore régénéré -> la
    // signature change à chaque build -> Android refuse la MISE À JOUR par-dessus
    // ("Application non installée"). Avec cette clé constante, toutes les
    // versions s'installent les unes par-dessus les autres sans désinstaller.
    // (Clé debug-grade : OK pour un sideload ; un vrai keystore secret serait
    // requis pour une publication Play Store.)
    signingConfigs {
        getByName("debug") {
            storeFile = file("../nova-release.keystore")
            storePassword = "novapass"
            keyAlias = "nova"
            keyPassword = "novapass"
        }
    }

    buildTypes {
        getByName("debug") {
            // Signée avec la clé stable ci-dessus (signingConfigs.debug).
            isMinifyEnabled = false
            isDebuggable = true
        }
        getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false
            // Même clé stable que debug — sideload Downloader, pas de Play Store.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    // L'APK final embarque les assets de tv-web sous /assets/web/.
    // Le script CI copie tv-web/dist/* dedans avant le build.
    sourceSets {
        getByName("main") {
            assets.srcDir("src/main/assets")
        }
    }

    buildFeatures {
        // Pas de Compose, pas de DataBinding, pas de ViewBinding —
        // on n'a qu'une seule View XML-less.
        buildConfig = false
    }

    packaging {
        resources {
            excludes += listOf(
                "/META-INF/{AL2.0,LGPL2.1}",
            )
        }
    }
}

dependencies {
    // androidx.appcompat = AppCompatActivity + theme parent
    implementation("androidx.appcompat:appcompat:1.7.0")
    // androidx.webkit = WebViewAssetLoader (sert /assets/web/* en
    // https://appassets.androidplatform.net/ → permet a hls.js de
    // fonctionner avec same-origin policy stricte).
    implementation("androidx.webkit:webkit:1.11.0")
}
