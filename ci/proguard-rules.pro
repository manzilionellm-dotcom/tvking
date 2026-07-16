# =========================================================
#  proguard-rules.pro — Règles R8/ProGuard (durcissement prod 7 MOTION)
# =========================================================
#  But : activer le rétrécissement de code ET de ressources SANS casser
#  les plugins natifs qui utilisent la réflexion ou JNI. R8 est le
#  shrinker/optimiseur par défaut d'Android ; ces règles disent quoi NE
#  PAS renommer/supprimer. NOTE (vérité 2026-07-16) : les workflows
#  build-android/tv/prive passent en réalité proguard-android-OPTIMIZE
#  .txt — ce fichier doit donc rester assez conservateur pour survivre
#  aux optimisations agressives (d'où les keep larges ci-dessous).
# =========================================================

# ----- Flutter (moteur + embedding + plugins générés) -----
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# ----- Google Play Core (composants différés Flutter) -----
# L'embedding Flutter RÉFÉRENCE com.google.android.play.core.* (SplitCompat,
# deferred components) MAIS la lib n'est pas embarquée → R8 échoue sur
# « Missing class » si on ne l'ignore pas. C'est LA cassure R8 #1 des apps
# Flutter. On n'utilise pas les composants différés → on ignore sans risque.
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.**
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }

# ----- Méthodes natives (JNI) : ne JAMAIS renommer -----
-keepclasseswithmembernames class * { native <methods>; }

# ----- Plugins natifs MAISON (native_video_player, tvking_device…) -----
-keep class com.manzilionellm.** { *; }
-dontwarn com.manzilionellm.**

# ----- media_kit / libmpv (lecteur principal) -----
-keep class com.alexmercerind.** { *; }
-dontwarn com.alexmercerind.**

# ----- ExoPlayer / AndroidX Media3 (lecteur natif TV) -----
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# ----- libVLC (flutter_vlc_player — repli lecteur sur certaines box TV) -----
# Le moteur libVLC est instancié et appelé par RÉFLEXION + JNI (org.videolan.*).
# Sans keep, R8 peut supprimer des classes utilisées au runtime → crash au
# démarrage de la lecture sur la build TV (qui embarque ce repli). Additif,
# aucun risque (on empêche seulement le stripping).
-keep class org.videolan.** { *; }
-dontwarn org.videolan.**

# ----- @Keep (androidx) : respecter l'intention explicite des libs tierces -----
# Toute classe/membre annoté @androidx.annotation.Keep DOIT survivre à R8
# (sinon ClassNotFound/NoSuchMethod au runtime). On ne s'appuyait avant que sur
# le wildcard de package des plugins maison → on couvre désormais aussi les deps.
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# ----- Firebase / Crashlytics (actif seulement si configuré) -----
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Stacktraces LISIBLES dans Crashlytics (sinon lignes obfusquées illisibles).
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*
-keepattributes Signature,Exceptions,InnerClasses,EnclosingMethod

# ----- Enums (valueOf/values appelés par réflexion) -----
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ----- Modèles potentiellement (dé)sérialisés -----
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ----- flutter_local_notifications (rappels d'émission) -----
# BOÎTE NOIRE (terrain 2026-07-16) : crash « Missing type parameter »
# rattrapé par le filet global, à chaque appel de cancel() →
# loadScheduledNotifications au démarrage. CAUSE : le plugin sérialise ses
# notifications planifiées via Gson avec un TypeToken GÉNÉRIQUE
# (ArrayList<...>). Sous R8, faute de règle keep sur ses modèles, le type
# générique du TypeToken est effacé → Gson ne sait plus reconstruire la
# liste → RuntimeException. On garde les classes du plugin ET les TypeToken
# Gson (avec leur signature, déjà préservée plus haut) pour rétablir l'info
# de type. Additif, aucun risque : on empêche seulement un stripping.
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# ----- Bruit fréquent (classes optionnelles absentes du classpath) -----
-dontwarn javax.annotation.**
-dontwarn javax.naming.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-dontwarn kotlin.**
-dontnote
