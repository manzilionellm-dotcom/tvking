# Pont appelé par l'APK d'instrumentation contre le véritable APK release.
# Conserver uniquement ses deux entrées publiques utilisées par le test ;
# le pipeline privé de conversion et les autres classes restent optimisables.
# Flutter ajoute déjà ce fichier à la configuration R8 lorsqu'il existe.
-keep class com.sevenmotion.novatube.GalleryExporter {
    public <init>(io.flutter.plugin.common.BinaryMessenger, android.content.Context, android.app.Activity);
    public void onMethodCall(io.flutter.plugin.common.MethodCall, io.flutter.plugin.common.MethodChannel$Result);
}
