package com.manzilionellm.native_video_player.logic

/**
 * Règles de reconnexion, SANS lecteur et SANS réseau.
 *
 * Le vrai ExoPlayer ([com.manzilionellm.native_video_player.NativeVideoView])
 * exécute. Ici on décide seulement :
 *  - combien de temps attendre avant de ré-ouvrir (1 s, 2 s, 4 s, puis 8 s) ;
 *  - quand abandonner ;
 *  - quand un second essai ferait deux lectures en même temps ;
 *  - quand le panneau opaque cacherait une image encore bonne ;
 *  - quand le volume a le droit de revenir (pas avant la nouvelle session).
 *
 * Mêmes chiffres que `lib/features/player/domain/reconnect_plan.dart`.
 * Si l'un change, l'autre doit changer : les deux tests le verrouillent.
 *
 * Le tampon de démarrage (1 s) n'est PAS allongé. En v99–v101, le passer
 * à 5 s a laissé des chaînes sur le logo. Le budget « sous 2 s » côté
 * application, c'est ce 1 s + le groupement des touches de zap (180 ms).
 * Le réseau et le décodeur, eux, ne se mesurent que sur une box.
 */
object ReconnectPlan {
    /** Essais silencieux avant de prévenir l'écran (filet ultime). */
    const val MAX_SILENT: Int = 8

    const val BASE_MS: Long = 1_000L
    const val CAP_MS: Long = 8_000L

    /**
     * Données minimum avant de lancer la lecture.
     * Recopié dans le LoadControl : ne pas le monter.
     */
    const val BUFFER_FOR_PLAYBACK_MS: Int = 1_000

    /** On attend la fin des appuis Haut/Bas avant d'ouvrir UN flux. */
    const val ZAP_SETTLE_MS: Int = 180

    /** Objectif d'ouverture / de zap, côté application (hors réseau). */
    const val STARTUP_TARGET_MS: Int = 2_000

    /**
     * Ce que l'application ajoute AVANT que le serveur réponde :
     * groupement du zap + tampon de démarrage. Doit rester sous
     * [STARTUP_TARGET_MS]. Le temps réseau n'est pas dedans.
     */
    fun appSideBudgetMs(): Int = ZAP_SETTLE_MS + BUFFER_FOR_PLAYBACK_MS

    /**
     * Attente avant l'essai [attempt] (1 = le premier).
     * 1 s, 2 s, 4 s, puis plafond 8 s. Un essai invalide donne 0 :
     * on n'invente pas un délai négatif.
     */
    fun delayMs(attempt: Int): Long {
        if (attempt <= 0) return 0L
        val shift = (attempt - 1).coerceAtMost(3)
        return (BASE_MS shl shift).coerceAtMost(CAP_MS)
    }

    /**
     * Panneau plein écran (fond sombre) par-dessus la vidéo ?
     *
     *  - Jamais eu d'image : oui, sinon on montrerait du noir.
     *  - Même adresse, image déjà vue : non. On garde la dernière
     *    image (copie native) le temps de revenir. Un panneau ici
     *    ferait un écran noir / un logo à chaque hoquet réseau.
     *  - Autre adresse (zap, ou secours) : oui. L'ancienne image
     *    serait la mauvaise chaîne.
     */
    fun coverWithLoader(hadFrame: Boolean, sameUrl: Boolean): Boolean {
        if (!hadFrame) return true
        if (sameUrl) return false
        return true
    }
}

/**
 * Compteur d'essais + verrou « un seul ré-ouverture à la fois ».
 *
 * [onFailure] pendant qu'une attente est déjà posée renvoie null :
 * on ne prépare pas un second flux par-dessus le premier (deux sons).
 * Le volume reste baissé ([holdMute]) jusqu'à ce que la NOUVELLE
 * session joue vraiment.
 */
class ReconnectGate {
    var attempt: Int = 0
        private set

    /** Un délai est en cours : pas de second prepare. */
    var retryPending: Boolean = false
        private set

    /** true : le volume doit rester à 0. */
    var holdMute: Boolean = false
        private set

    /** Volume à 0 jusqu'à la nouvelle image ou le nouveau son. */
    fun armMute() {
        holdMute = true
    }

    /** Zap : autre adresse. Le budget repart de zéro. */
    fun onDifferentUrl() {
        attempt = 0
        retryPending = false
        holdMute = true
    }

    /**
     * L'écran ré-ouvre lui-même la MÊME adresse (chien de garde).
     * On annule l'attente native pour ne pas préparer deux fois,
     * sans remettre le budget à zéro : sinon 8 essais silencieux
     * recommenceraient sans fin.
     */
    fun onExternalReopen() {
        retryPending = false
        holdMute = true
    }

    /**
     * Panne du flux en cours.
     *
     * @return le délai en ms, ou null si on abandonne ou si un essai
     *         est déjà programmé.
     */
    fun onFailure(): Long? {
        if (retryPending) return null
        val next = attempt + 1
        if (next > ReconnectPlan.MAX_SILENT) return null
        attempt = next
        retryPending = true
        holdMute = true
        return ReconnectPlan.delayMs(next)
    }

    /**
     * Le délai est écoulé. true une seule fois : un callback en double
     * ne relance pas le son.
     */
    fun onRetryFired(): Boolean {
        if (!retryPending) return false
        retryPending = false
        return true
    }

    /**
     * L'attente ne doit plus partir (silence, zap, flux redevenu prêt).
     * On ne remet PAS le compteur à zéro : seul un vrai son ou une
     * vraie image le fait ([onRecovered]).
     */
    fun cancelWait() {
        retryPending = false
    }

    /** La lecture est vraiment revenue. On oublie les pannes. */
    fun onRecovered() {
        attempt = 0
        retryPending = false
    }

    /**
     * La nouvelle session produit du son ou une image.
     * @return true seulement la première fois : c'est le moment
     *         de remettre le volume, pas avant.
     */
    fun onNewSoundAllowed(): Boolean {
        if (!holdMute) return false
        holdMute = false
        return true
    }
}
