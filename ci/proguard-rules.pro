# =========================================================
#  proguard-rules.pro — Règles R8/ProGuard (durcissement prod 7 MOTION)
# =========================================================
#  But : activer le rétrécissement de code ET de ressources SANS casser
#  les plugins natifs qui utilisent la réflexion ou JNI. R8 est le
#  shrinker/optimiseur par défaut d'Android ; ces règles disent quoi NE
#  PAS renommer/supprimer. On reste volontairement CONSERVATEUR (variante
#  proguard-android.txt, pas -optimize) pour minimiser tout risque de
#  casse runtime sur une box bas de gamme.
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

# ----- Bruit fréquent (classes optionnelles absentes du classpath) -----
-dontwarn javax.annotation.**
-dontwarn javax.naming.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-dontwarn kotlin.**
-dontnote
