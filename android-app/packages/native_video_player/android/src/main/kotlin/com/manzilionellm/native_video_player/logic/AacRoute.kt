package com.manzilionellm.native_video_player.logic

/**
 * REPLI AAC PAR CHAÎNE (01/10/2026) — « le son devient vieille radio
 * après beaucoup de zapping, sur des chaînes déjà vues ».
 *
 * CE QUI SE PASSAIT (v103 → v106) : le drapeau « l'AAC passe par le
 * décodeur de la box » était UN SEUL booléen pour tout le processus
 * (`companion object`). Un seul événement le mettait à vrai pour toujours :
 *   • le filet des 8 s (FFmpeg actif et lecteur pas « prêt » à la 8e
 *     seconde, donc aussi un simple re-tamponnage réseau à cet instant) ;
 *   • une erreur du rendu FFmpeg (paquet TS abîmé, fréquent après une
 *     reconnexion) ;
 *   • une erreur de sortie son ou de décodeur pendant que FFmpeg décode.
 * Ensuite, TOUTES les chaînes AAC repassaient par le décodeur de la box,
 * c'est-à-dire le chemin de la v98, celui qui faisait le son « vieille
 * radio ». Les chaînes entendues bonnes au début (FFmpeg) devenaient
 * mauvaises au retour (box). Seul « FFmpeg : réessayer » le défaisait.
 *
 * MAINTENANT : la mémoire de repli est PAR CHAÎNE, dans cet objet pur.
 * Une chaîne où FFmpeg a vraiment échoué reste sur la box (pas de 8 s
 * d'attente à chaque retour). Les autres gardent FFmpeg. On ne garde que
 * `url.hashCode()` : aucune adresse ni mot de passe en mémoire.
 *
 * INTERRUPTEUR DE REPLI : [sessionWide] = vrai rétablit exactement l'ancien
 * comportement (une panne → la box pour tout le monde). Faux par défaut.
 *
 * Pur Kotlin (pas d'Android) → testé dans logic-test/ (50 zaps simulés).
 */
object AacRoute {

    /** Chaînes mémorisées au plus. Au-delà, la plus ancienne est oubliée. */
    const val MAX_REMEMBERED: Int = 32

    enum class Reason(val label: String) {
        /** Filet des 8 s : FFmpeg n'a jamais rendu la chaîne prête. */
        TIMEOUT("délai de 8 s"),

        /** Erreur du rendu FFmpeg (ExoPlaybackException TYPE_RENDERER). */
        RENDERER_ERROR("erreur du moteur FFmpeg"),

        /** La sortie son a refusé le PCM pendant que FFmpeg décodait. */
        SINK_ERROR("erreur de la sortie son"),

        /** Le décodeur FFmpeg a jeté une exception. */
        CODEC_ERROR("erreur du décodeur"),
    }

    /** Une chaîne passée à la box : pourquoi, et au zap numéro combien. */
    data class Failure(val key: Int, val reason: Reason, val zap: Int)

    /**
     * Ancien comportement (v103–v106) : une seule panne envoie TOUTES les
     * chaînes AAC vers la box. Faux par défaut. @Volatile : écrit par le
     * réglage, lu par le sélecteur de décodeurs (autre fil).
     */
    @Volatile
    var sessionWide: Boolean = false

    private val failed = LinkedHashMap<Int, Failure>()
    private var lastFailure: Failure? = null

    /** Clé d'une chaîne. Le hachage ne permet pas de retrouver l'adresse. */
    fun key(url: String): Int = url.hashCode()

    /**
     * La chaîne [url] doit-elle passer par le décodeur de la box ?
     * null = non, FFmpeg comme d'habitude.
     */
    @Synchronized
    fun boxFor(url: String): Failure? {
        if (sessionWide) return lastFailure
        return failed[key(url)]
    }

    /** FFmpeg a échoué sur [url] : on s'en souvient pour CETTE chaîne. */
    @Synchronized
    fun markFailed(url: String, reason: Reason, zap: Int): Failure {
        val k = key(url)
        val f = Failure(k, reason, zap)
        failed.remove(k)
        failed[k] = f
        while (failed.size > MAX_REMEMBERED) {
            val oldest = failed.keys.first()
            failed.remove(oldest)
        }
        lastFailure = f
        return f
    }

    /** « FFmpeg : réessayer » sur cette chaîne : on oublie son repli. */
    @Synchronized
    fun forget(url: String) {
        val k = key(url)
        failed.remove(k)
        if (lastFailure?.key == k) lastFailure = failed.values.lastOrNull()
    }

    /** Tout oublier (« FFmpeg : réessayer » en mode session entière, tests). */
    @Synchronized
    fun forgetAll() {
        failed.clear()
        lastFailure = null
    }

    /** Nombre de chaînes actuellement envoyées vers la box. */
    @Synchronized
    fun count(): Int = if (sessionWide && lastFailure != null) Int.MAX_VALUE else failed.size

    /**
     * Décision pour l'ouverture de [url] : ce qu'il faut mettre dans le
     * drapeau du lecteur. [keepFfmpeg] vrai (réglage « réessayer ») efface
     * d'abord la mémoire de cette chaîne (ou de toutes en mode session).
     */
    @Synchronized
    fun decideForOpen(url: String, keepFfmpeg: Boolean): Failure? {
        if (keepFfmpeg) {
            if (sessionWide) forgetAll() else forget(url)
            return null
        }
        return boxFor(url)
    }
}
