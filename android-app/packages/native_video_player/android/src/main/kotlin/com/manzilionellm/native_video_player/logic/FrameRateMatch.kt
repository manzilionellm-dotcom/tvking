package com.manzilionellm.native_video_player.logic

/**
 * Choisit un mode d'écran pour la cadence du flux.
 *
 * Coupé par défaut : sur les box visées, changer le mode HDMI a déjà
 * fait un écran noir de plusieurs secondes (v104 le laisse donc
 * désactivé). Ici on calcule seulement LE mode, et l'appelant ne
 * l'applique que si l'option est allumée.
 *
 * Correspondances voulues (film / télé) :
 *   ~24 image/s → 24 Hz (pas 60 : le télécinéma 3:2 saccade) ;
 *   ~25        → 50 Hz, sinon 25 Hz ;
 *   ~30        → 60 Hz, sinon 30 Hz ;
 *   ~50        → 50 Hz ;
 *   ~60        → 60 Hz.
 * 23,976 compte comme 24, 29,97 comme 30, 59,94 comme 60.
 *
 * Si aucun mode de la TV n'est à moins de 1 Hz de la cible, on ne
 * change rien. Si le mode actuel est déjà le bon, on ne change rien
 * non plus (un second appel ne doit pas refaire clignoter l'écran).
 *
 * La cadence du flux est reconnue à 0,5 Hz près : 23,976 compte
 * comme 24, mais 25 ne doit pas être pris pour 24 (écart d'1 Hz).
 */
data class DisplayModeOption(val id: Int, val refreshHz: Float)

object FrameRateMatch {
    fun pick(
        enabled: Boolean,
        contentFps: Float,
        modes: List<DisplayModeOption>,
        currentModeId: Int,
    ): DisplayModeOption? {
        if (!enabled || modes.isEmpty()) return null
        val wanted = preferredHz(contentFps)
        if (wanted.isEmpty()) return null
        for (hz in wanted) {
            val found = modes.firstOrNull { kotlin.math.abs(it.refreshHz - hz) <= 1f }
            if (found != null) {
                if (found.id == currentModeId) return null
                return found
            }
        }
        return null
    }

    /**
     * Liste ordonnée : la première cadence qu'un mode réel peut fournir
     * gagne. Vide = cadence inconnue, on ne touche pas à l'écran.
     */
    fun preferredHz(contentFps: Float): List<Float> {
        if (contentFps < 10f || contentFps > 120f) return emptyList()
        return when {
            near(contentFps, 23.976f) || near(contentFps, 24f) -> listOf(24f, 23.976f)
            near(contentFps, 25f) -> listOf(50f, 25f)
            near(contentFps, 29.97f) || near(contentFps, 30f) -> listOf(59.94f, 60f, 29.97f, 30f)
            near(contentFps, 50f) -> listOf(50f, 25f)
            near(contentFps, 59.94f) || near(contentFps, 60f) -> listOf(59.94f, 60f)
            else -> emptyList()
        }
    }

    /** 0,5 Hz : les fractions NTSC passent, 24 et 25 restent distincts. */
    private fun near(value: Float, target: Float): Boolean =
        kotlin.math.abs(value - target) <= 0.5f
}
