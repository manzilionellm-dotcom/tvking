package com.manzilionellm.tvking_device;

/** Classification de télémétrie pure : aucune marque d'app ni règle Cast.
 * Le même APK peut être installé sur une box, un téléphone ou une tablette.
 * Les signaux absents ne sont jamais transformés en preuve d'une box. */
public final class DeviceHardwareKind {
    private DeviceHardwareKind() {}

    public static String classify(
            boolean fireTv, boolean television, boolean leanback,
            boolean touchscreen, int smallestWidthDp, boolean otherFormFactor) {
        // Les déclarations TV restent prioritaires, même avec du tactile.
        if (fireTv) return "fire_tv";
        if (television || leanback) return "android_tv";
        // Montre, voiture et PC Android ne deviennent pas des téléphones.
        if (otherFormFactor || !touchscreen || smallestWidthDp <= 0) return "unknown";
        // Convention Android des ressources : 600 dp est le seuil tablette.
        // La configuration vient du contexte application, pas de la fenêtre
        // Flutter : ouvrir le clavier ne change donc pas le type envoyé.
        return smallestWidthDp >= 600 ? "android_tablet" : "android_phone";
    }
}
