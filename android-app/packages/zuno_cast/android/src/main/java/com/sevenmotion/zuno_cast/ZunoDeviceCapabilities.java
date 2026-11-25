package com.sevenmotion.zuno_cast;

/**
 * Décision matérielle pure, partagée avec le plugin et testable sans Android.
 *
 * <p>Le téléphone et la tablette tactiles peuvent envoyer une vidéo à une TV.
 * Une TV, une box Leanback ou une box AOSP sans écran tactile restent des
 * lecteurs locaux : elles ne doivent pas initialiser le moteur Cast émetteur.
 */
public final class ZunoDeviceCapabilities {
    private ZunoDeviceCapabilities() {}

    /** TV et Leanback interdisent toujours l'émission, même avec du tactile. */
    public static boolean isHandset(
            boolean televisionMode, boolean leanback, boolean touchscreen) {
        return isHandset("auto", televisionMode, leanback, touchscreen);
    }

    /** L'édition TV ne devient jamais un émetteur, même installée sur téléphone. */
    public static boolean isHandset(
            String edition, boolean televisionMode, boolean leanback, boolean touchscreen) {
        // Une valeur inconnue échoue fermée. L'absence de métadonnée conserve
        // uniquement le comportement des anciens paquets adaptatifs.
        boolean senderEdition = "auto".equals(edition) || "mobile".equals(edition);
        return senderEdition && !televisionMode && !leanback && touchscreen;
    }
}
