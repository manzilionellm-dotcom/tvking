package com.manzilionellm.tvking_device;

/** Tests de vrais cas ambigus : le produit ZUNO/Cast n'est jamais une entrée. */
public final class DeviceHardwareKindTest {
    private static int assertions;
    private DeviceHardwareKindTest() {}

    private static void expect(String name, String wanted, boolean fireTv,
            boolean television, boolean leanback, boolean touch, int width, boolean other) {
        String actual = DeviceHardwareKind.classify(fireTv, television, leanback, touch, width, other);
        if (!wanted.equals(actual)) {
            throw new AssertionError(name + ": attendu " + wanted + ", obtenu " + actual);
        }
        assertions++;
    }

    public static void main(String[] args) {
        expect("SHIELD / box Leanback", "android_tv", false, false, true, false, 960, false);
        expect("TV tactile", "android_tv", false, true, false, true, 400, false);
        expect("TV avec largeur absente", "android_tv", false, true, false, false, 0, false);
        expect("Fire TV partenaire", "fire_tv", true, true, true, false, 960, false);
        expect("Fire TV sans Leanback", "fire_tv", true, false, false, false, 0, false);
        expect("Téléphone avec édition ZUNO TV", "android_phone", false, false, false, true, 411, false);
        expect("Téléphone limite 599dp", "android_phone", false, false, false, true, 599, false);
        expect("Tablette limite 600dp", "android_tablet", false, false, false, true, 600, false);
        expect("Tablette Fire sans feature Fire TV", "android_tablet", false, false, false, true, 800, false);
        expect("Box AOSP non identifiable", "unknown", false, false, false, false, 960, false);
        expect("Tactile largeur absente", "unknown", false, false, false, true, 0, false);
        expect("Largeur invalide", "unknown", false, false, false, true, -1, false);
        expect("Aucune information", "unknown", false, false, false, false, 0, false);
        expect("Montre / voiture", "unknown", false, false, false, true, 400, true);
        expect("PC Android tactile", "unknown", false, false, false, true, 1000, true);
        // Le clavier, l'orientation et le Cast ne font pas partie du contrat :
        // même plus petite largeur de configuration = même catégorie.
        expect("Téléphone rotation", "android_phone", false, false, false, true, 411, false);
        System.out.println("DeviceHardwareKind : " + assertions + " cas matériels validés");
    }
}
