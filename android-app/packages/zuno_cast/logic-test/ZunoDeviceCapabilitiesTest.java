package com.sevenmotion.zuno_cast;

/** Contrat exhaustif des trois signaux, sans SDK Android ni dépendance de test. */
public final class ZunoDeviceCapabilitiesTest {
    private ZunoDeviceCapabilitiesTest() {}

    public static void main(String[] args) {
        // Colonnes : mode TV, Leanback, tactile, résultat attendu.
        // Une seule combinaison permet l'émission : un appareil tactile
        // qui n'est identifié ni comme TV ni comme appareil Leanback.
        boolean[][] cases = {
            {false, false, false, false}, // Box AOSP / projecteur sans tactile.
            {false, false, true, true},   // Téléphone ou tablette tactile.
            {false, true, false, false},  // Box Leanback.
            {false, true, true, false},   // Leanback reste prioritaire.
            {true, false, false, false},  // TV déclarée sans Leanback.
            {true, false, true, false},   // TV tactile : lecture locale.
            {true, true, false, false},   // Android TV classique.
            {true, true, true, false},    // Tous les signaux : TV prioritaire.
        };

        for (int index = 0; index < cases.length; index++) {
            boolean[] row = cases[index];
            boolean actual = ZunoDeviceCapabilities.isHandset(row[0], row[1], row[2]);
            if (actual != row[3]) {
                throw new AssertionError(
                        "Combinaison " + index + " : TV=" + row[0]
                                + ", Leanback=" + row[1] + ", tactile=" + row[2]
                                + ", attendu=" + row[3] + ", obtenu=" + actual);
            }
            for (String edition : new String[] {"tv", "mobile", "unknown"}) {
                boolean expected = "mobile".equals(edition) && row[3];
                boolean editionResult = ZunoDeviceCapabilities.isHandset(
                        edition, row[0], row[1], row[2]);
                if (editionResult != expected) {
                    throw new AssertionError("Édition " + edition + ", combinaison " + index);
                }
            }
        }

        System.out.println("ZunoDeviceCapabilities : 32 combinaisons matériel/édition validées");
    }
}
