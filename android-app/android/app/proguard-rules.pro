# Pont appelé par l'APK d'instrumentation contre le véritable APK release.
# Conserver uniquement ses deux entrées publiques utilisées par le test ;
# le pipeline privé de conversion et les autres classes restent optimisables.
# Flutter ajoute déjà ce fichier à la configuration R8 lorsqu'il existe.
-keep class com.sevenmotion.novatube.GalleryExporter {
    public <init>(io.flutter.plugin.common.BinaryMessenger, android.content.Context, android.app.Activity);
    public void onMethodCall(io.flutter.plugin.common.MethodCall, io.flutter.plugin.common.MethodChannel$Result);
}

# Flutter et AndroidJUnitRunner partagent cette petite API. Le test n'en
# embarque donc pas une seconde copie. Garder son nom et ses méthodes évite
# que R8 les supprime/renomme dans le vrai APK release testé. Ses helpers
# internes et le reste de l'application conservent leurs optimisations.
-keep class androidx.tracing.Trace { *; }
