package com.manzilionellm.native_video_player.logic

/**
 * Plafond EN OCTETS du tampon réseau (Media3 `DefaultLoadControl`) sur les
 * box à faible mémoire.
 *
 * Pourquoi : le lecteur charge jusqu'à 45 s d'avance et donne la priorité au
 * TEMPS (`setPrioritizeTimeOverSizeThresholds(true)`). Sans plafond en
 * octets, la limite effective est celle de Media3 (~131 Mo vidéo + ~13 Mo
 * audio). Sur une Fire TV Stick à 899 Mo (journal du 03/11/2026 : processus
 * à 318 Mo, 297 Mo libres pendant un import), 45 s d'un flux à 15 Mbit/s
 * occupent à elles seules ~84 Mo.
 *
 * Ce qui NE change PAS (règle « on ne touche pas à ces chiffres ») :
 * démarrage 5 s, reprise après coupure, zapping, 45 s max en temps. La
 * priorité au temps garantit que les 5 premières secondes sont TOUJOURS
 * chargées, même si le plafond est atteint avant. Au-delà, le chargement
 * s'arrête au premier des deux : 45 s OU [TIGHT_TARGET_BYTES].
 *
 * Box > 1 Go : `null` → défaut Media3 inchangé, comportement d'avant.
 */
object LowRamBuffer {
    /** 32 Mio ≈ 32 s de HD à 8 Mbit/s, ≈ 10 s d'un flux à 25 Mbit/s. */
    const val TIGHT_TARGET_BYTES: Int = 32 * 1024 * 1024

    private const val ONE_GIB: Long = 1024L * 1024L * 1024L

    /**
     * Même seuil que `BoxMemoryBudget` côté Dart : ≤ 1 Go, ou le drapeau
     * Android « low RAM ». Une mémoire lue à 0 (inconnue) n'est PAS serrée,
     * comme côté Dart.
     */
    fun isTight(totalMemBytes: Long, isLowRamDevice: Boolean): Boolean =
        isLowRamDevice || totalMemBytes in 1..ONE_GIB

    /** Octets cibles à imposer, ou null = défaut Media3 (box plus grosses). */
    fun targetBytes(totalMemBytes: Long, isLowRamDevice: Boolean): Int? =
        if (isTight(totalMemBytes, isLowRamDevice)) TIGHT_TARGET_BYTES else null
}
