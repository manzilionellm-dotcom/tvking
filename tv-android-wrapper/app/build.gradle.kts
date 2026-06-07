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

    defaultConfig {
        applicationId = "com.manzilionellm.tvkingtv"
        // minSdk 23 = Android 6.0 (Marshmallow, oct 2015) — MSE WebView
        // disponible, hls.js fonctionne. Fire TV Stick 1st gen (API 22)
        // EST EXCLU sciemment — son WebView est trop ancien pour MSE.
        minSdk = 23
        targetSdk = 34
        versionCode = 1
        versionName = "0.2.0"

        // Filtres ABI : on garde TOUTES les ABI Android TV (armv7,
        // arm64, x86, x86_64) parce qu'on n'a aucune lib native a
        // packer (juste du Kotlin + WebView).
    }

    buildTypes {
        getByName("debug") {
            // Signature debug auto par Gradle.
            isMinifyEnabled = false
            isDebuggable = true
        }
        getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false
            // On signe en debug.keystore aussi pour la release dans cette
            // premiere version — pas de Play Store immediatement, c'est
            // un sideload via Downloader. Si on publie un jour au store
            // il faudra un vrai keystore.
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
