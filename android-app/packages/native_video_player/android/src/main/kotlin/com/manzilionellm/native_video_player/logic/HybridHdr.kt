package com.manzilionellm.native_video_player.logic

import java.nio.ByteBuffer

/**
 * FILM 4K « DOLBY VISION + HDR10+ » (14/11/2026) — l'image devient d'une
 * seule couleur (noire, bleue, magenta…) et le son continue.
 *
 * CE QUI SE PASSE. Beaucoup de films 4K récents sont « hybrides » : le même
 * flux HEVC porte DEUX jeux de réglages d'image qui changent à chaque plan :
 *
 *  - Dolby Vision : une petite unité à la fin de chaque image
 *    (unité NAL de type 62, plus le type 63 pour la seconde couche) ;
 *  - HDR10+ : un message placé avant l'image (message SEI de type 4,
 *    « ITU-T T.35 », signé B5 00 3C 00 01 04).
 *
 * Une box saine en choisit un et ignore l'autre. Les clés Amazon à puce
 * MediaTek MT8696 (Fire TV Stick 4K Max, Fire TV Stick 4K 2e génération)
 * et le Google TV Streamer ne savent pas choisir : la sortie HDMI reçoit
 * les deux, l'écran reste noir ou d'une seule couleur, le son continue.
 * Défaut connu du constructeur (androidx/media, ticket 1895) : il n'est
 * pas dans notre code, mais c'est notre lecteur qui lui donne le flux.
 *
 * LE CORRECTIF. On ne donne JAMAIS les deux au décodeur de ces appareils :
 *
 *  - décodeur Dolby Vision choisi → on retire HDR10+, Dolby Vision reste ;
 *  - décodeur HEVC ordinaire et flux hybride → on retire les deux : le
 *    film passe en HDR10 simple, que tous les téléviseurs HDR savent lire.
 *
 * APRÈS UN SAUT. Chez le client qui a signalé le défaut, le film démarre
 * bien et l'écran se vide juste après une avance. Au démarrage le décodeur
 * est NEUF ; après un saut Media3 le VIDE et le réutilise. Sur ces mêmes
 * appareils, pour un film 4K, on recrée donc le décodeur après un saut :
 * la lecture repart exactement comme elle démarre (voir
 * [HybridHdr.freshDecoderAfterSeek]). C'est une précaution fondée sur ce
 * constat, pas un défaut documenté par le constructeur.
 *
 * Rien d'autre n'est touché : ni l'image elle-même (les unités « VCL »
 * ne sont jamais modifiées), ni un flux qui ne porte qu'un seul des deux
 * jeux, ni les autres appareils. Trois niveaux, décidés par [HybridHdr] :
 *
 *  - [HybridHdrMode.AUTO]   : appareil connu pour ce défaut. Agit seul.
 *  - [HybridHdrMode.STRICT] : réglage « Compatibilité HDR » allumé par la
 *    personne, sur n'importe quelle box. Retire toujours les deux jeux.
 *  - [HybridHdrMode.WATCH]  : autres appareils Amazon. Ne change RIEN,
 *    écrit seulement ce que le flux contient dans la boîte noire.
 *
 * Tout est en règles pures (aucune classe Android) : testé sans box dans
 * `logic-test`. Le branchement sur le lecteur est dans `NativeVideoView`.
 */
enum class HybridHdrScope {
    /** Appareil sans défaut connu : aucune lecture du flux. */
    NONE,

    /** Même famille que les appareils en défaut : on observe, sans modifier. */
    WATCH,

    /** Appareil connu pour le défaut : correctif automatique. */
    FIX,
}

enum class HybridHdrMode { WATCH, AUTO, STRICT }

/** Quel décodeur reçoit le flux : c'est lui qui décide de ce qu'on retire. */
enum class HybridHdrPath { HEVC_DECODER, DOLBY_DECODER }

object HybridHdr {
    const val MIME_HEVC: String = "video/hevc"
    const val MIME_DOLBY_VISION: String = "video/dolby-vision"

    /**
     * Interrupteur de REPLI (clé `zuno.player.hybrid_hdr_off`) : vrai =
     * ancien comportement, le correctif automatique ne fait plus rien.
     * Le réglage manuel, lui, reste un choix de la personne.
     */
    @Volatile
    var autoOff: Boolean = false

    /** Réglage « Compatibilité HDR » (Réglages → Plus). Faux par défaut. */
    @Volatile
    var manual: Boolean = false

    /** Tests instrumentés seulement : l'émulateur n'est pas une clé Amazon. */
    @Volatile
    var forcedScope: HybridHdrScope? = null

    /** Modèles Amazon (`Build.MODEL`) où le défaut est constaté. */
    private val defectiveFireModels: Set<String> = setOf(
        "AFTKA", // Fire TV Stick 4K Max (1re génération)
        "AFTKM", // Fire TV Stick 4K (2e génération)
        "AFTKRT", // Fire TV Stick 4K Max (2e génération)
    )

    /** Puce en cause, quelle que soit la marque (Google TV Streamer…). */
    private const val DEFECTIVE_CHIP: String = "mt8696"

    /**
     * Que faire sur CET appareil. Les cinq textes viennent de
     * `android.os.Build` ; un texte absent ne compte pas.
     */
    fun scope(
        manufacturer: String?,
        model: String?,
        hardware: String?,
        board: String?,
        socModel: String?,
    ): HybridHdrScope {
        forcedScope?.let { return it }
        val chip = listOf(hardware, board, socModel).any {
            it != null && it.lowercase().contains(DEFECTIVE_CHIP)
        }
        if (chip) return HybridHdrScope.FIX
        if (!manufacturer.equals("Amazon", ignoreCase = true)) return HybridHdrScope.NONE
        val name = model?.trim()?.uppercase().orEmpty()
        return if (name in defectiveFireModels) HybridHdrScope.FIX else HybridHdrScope.WATCH
    }

    /** Niveau pour une ouverture de décodeur. `null` = on ne lit pas le flux. */
    fun mode(
        scope: HybridHdrScope,
        manual: Boolean = this.manual,
        autoOff: Boolean = this.autoOff,
    ): HybridHdrMode? {
        if (manual) return HybridHdrMode.STRICT
        if (autoOff) return null
        return when (scope) {
            HybridHdrScope.FIX -> HybridHdrMode.AUTO
            HybridHdrScope.WATCH -> HybridHdrMode.WATCH
            HybridHdrScope.NONE -> null
        }
    }

    /**
     * Après un saut dans le film : recréer le décodeur au lieu de le vider ?
     * [mode] est le niveau du décodeur en cours (`null` = filtre absent),
     * [ultraHd] vrai pour une source 4K.
     *
     *  - automatique (appareil en défaut) : seulement en 4K, là où le
     *    défaut a été vu. Les chaînes et films HD gardent le saut rapide ;
     *  - réglage « Compatibilité HDR » : toujours, la personne l'a demandé ;
     *  - observation ou filtre absent : jamais, rien ne change.
     *
     * Ne concerne que les sauts demandés (avance, retour, reprise) : quand
     * Media3 vide le décodeur pour rattraper un retard, il reste vidé.
     */
    fun freshDecoderAfterSeek(mode: HybridHdrMode?, ultraHd: Boolean): Boolean = when (mode) {
        HybridHdrMode.STRICT -> true
        HybridHdrMode.AUTO -> ultraHd
        HybridHdrMode.WATCH, null -> false
    }

    /**
     * Le flux est-il du HEVC que ce filtre sait lire, et par quel décodeur
     * passe-t-il ? [codecMime] est le type DEMANDÉ au décodeur choisi
     * (`MediaCodecInfo.mimeType`) : « video/dolby-vision » = décodeur Dolby,
     * « video/hevc » = décodeur ordinaire (y compris quand Media3 le prend
     * en remplacement parce que le téléviseur n'a pas Dolby Vision).
     * `null` = autre codec (H.264, AV1…) : on n'y touche pas.
     */
    fun path(sampleMime: String?, codecs: String?, codecMime: String?): HybridHdrPath? {
        val source = sampleMime?.lowercase()
        val codec = codecMime?.lowercase()
        if (codec == MIME_HEVC) {
            return if (source == MIME_HEVC || source == MIME_DOLBY_VISION) {
                HybridHdrPath.HEVC_DECODER
            } else {
                null
            }
        }
        if (codec == MIME_DOLBY_VISION && source == MIME_DOLBY_VISION) {
            // Dolby Vision existe aussi sur H.264 (dvav) et AV1 (dav1) :
            // leurs unités ne sont pas du HEVC, ce filtre ne les lit pas.
            val base = codecs?.trim()?.lowercase().orEmpty()
            if (base.startsWith("dvhe") || base.startsWith("dvh1")) {
                return HybridHdrPath.DOLBY_DECODER
            }
        }
        return null
    }
}

/**
 * Filtre d'UNE ouverture de décodeur. Reçoit chaque image compressée
 * (« unité d'accès », format Annex B : `00 00 01` devant chaque unité NAL)
 * juste avant qu'elle parte au décodeur, et la réécrit sur place.
 *
 * COÛT. Un flux sans Dolby Vision ni HDR10+ (la quasi-totalité des chaînes)
 * n'est lu que sur ses [PROBE_UNITS] premières images puis sur les images
 * clés. Un flux à corriger est lu en entier, une comparaison sur trois
 * octets ; la copie qui referme le trou passe par un tableau tampon (deux
 * `memcpy`), jamais octet par octet.
 *
 * Pas sûr pour plusieurs fils : Media3 appelle toujours depuis le fil de
 * lecture.
 */
class HybridHdrFilter(
    val mode: HybridHdrMode,
    val path: HybridHdrPath,
) {
    /** Une unité Dolby Vision (62 ou 63) a été vue dans ce flux. */
    var sawDolbyVision: Boolean = false
        private set

    /** Un message HDR10+ a été vu dans ce flux. */
    var sawHdr10Plus: Boolean = false
        private set

    /** Unités Dolby Vision retirées depuis l'ouverture. */
    var removedDolbyVision: Long = 0
        private set

    /** Messages HDR10+ retirés (ou masqués) depuis l'ouverture. */
    var removedHdr10Plus: Long = 0
        private set

    private var probesLeft: Int = PROBE_UNITS

    // Index de l'unité d'accès en cours. Réutilisés d'une image à l'autre :
    // aucune allocation pendant la lecture.
    private var rangeBegin = IntArray(64)
    private var payloadStart = IntArray(64)
    private var payloadEnd = IntArray(64)
    private var drop = BooleanArray(64)
    private var count = 0

    private val maskAt = IntArray(MAX_MASKS)
    private var maskCount = 0
    private val scratch = ByteArray(SCRATCH_BYTES)

    // Lecteur d'un message SEI, octets « anti-émulation » (00 00 03) sautés.
    private var seiPos = 0
    private var seiEnd = 0
    private var seiZeros = 0
    private var seiLast = -1

    /** Les deux jeux sont dans le flux : c'est le cas du défaut. */
    val hybrid: Boolean
        get() = sawDolbyVision && sawHdr10Plus

    /** La fenêtre d'observation du début est finie. */
    val settled: Boolean
        get() = probesLeft <= 0

    /**
     * Lit [data] de sa position à sa limite et retire ce que le niveau
     * demande. La position est rendue telle quelle ; la limite recule si
     * des octets ont été retirés.
     *
     * @return vrai si le contenu a changé.
     */
    fun process(data: ByteBuffer, keyFrame: Boolean): Boolean {
        if (!keyFrame && probesLeft <= 0 && !mustReadEveryUnit()) return false
        if (probesLeft > 0) probesLeft--
        val start = data.position()
        val end = data.limit()
        if (end - start < MIN_UNIT_BYTES) return false
        if (!index(data, start, end)) return false

        // 1) Ce que cette image contient.
        var dolbyHere = false
        var hdrHere = false
        maskCount = 0
        for (i in 0 until count) {
            drop[i] = false
            val type = nalType(data, i)
            if (type == NAL_DOLBY_RPU || type == NAL_DOLBY_LAYER) {
                dolbyHere = true
            } else if (type == NAL_PREFIX_SEI || type == NAL_SUFFIX_SEI) {
                when (readSei(data, payloadStart[i] + NAL_HEADER_BYTES, payloadEnd[i])) {
                    SEI_ONLY_HDR10_PLUS -> {
                        hdrHere = true
                        drop[i] = true // provisoire : confirmé plus bas
                    }
                    SEI_MIXED -> hdrHere = true
                    else -> Unit
                }
            }
        }
        if (dolbyHere) sawDolbyVision = true
        if (hdrHere) sawHdr10Plus = true

        // 2) Ce qu'on retire, selon le niveau et le décodeur.
        val stripHdr: Boolean
        val stripDolby: Boolean
        when (mode) {
            HybridHdrMode.WATCH -> {
                stripHdr = false
                stripDolby = false
            }
            HybridHdrMode.AUTO -> {
                stripHdr = path == HybridHdrPath.DOLBY_DECODER || hybrid
                stripDolby = path == HybridHdrPath.HEVC_DECODER && hybrid
            }
            HybridHdrMode.STRICT -> {
                stripHdr = true
                stripDolby = path == HybridHdrPath.HEVC_DECODER
            }
        }
        var changed = false
        var removals = false
        for (i in 0 until count) {
            val type = nalType(data, i)
            if (type == NAL_DOLBY_RPU || type == NAL_DOLBY_LAYER) {
                drop[i] = stripDolby
                if (stripDolby) {
                    removedDolbyVision++
                    removals = true
                }
            } else if (drop[i]) {
                // Unité SEI qui ne contient QUE du HDR10+.
                drop[i] = stripHdr
                if (stripHdr) {
                    removedHdr10Plus++
                    removals = true
                }
            }
        }
        // Message HDR10+ rangé avec d'autres messages dans la même unité :
        // on ne jette pas les autres. On change son numéro de type (4 → 254,
        // un numéro que la norme demande d'ignorer). Un seul octet écrit.
        if (stripHdr && maskCount > 0) {
            for (m in 0 until maskCount) data.put(maskAt[m], SEI_TYPE_IGNORED.toByte())
            removedHdr10Plus += maskCount
            changed = true
        }
        if (!removals) return changed

        // 3) Refermer les trous, dans l'ordre, sans jamais toucher une
        //    unité gardée.
        var write = start
        try {
            for (i in 0 until count) {
                if (drop[i]) continue
                val from = rangeBegin[i]
                val length = rangeEndOf(i, end) - from
                if (from != write) move(data, from, write, length)
                write += length
            }
        } catch (error: RuntimeException) {
            // La copie déplace la position : on la rend avant de signaler.
            data.position(start)
            throw error
        }
        data.limit(write)
        data.position(start)
        return true
    }

    private fun mustReadEveryUnit(): Boolean = when (mode) {
        HybridHdrMode.WATCH -> false
        HybridHdrMode.AUTO ->
            if (path == HybridHdrPath.DOLBY_DECODER) sawHdr10Plus else hybrid
        HybridHdrMode.STRICT ->
            if (path == HybridHdrPath.DOLBY_DECODER) sawHdr10Plus else sawHdr10Plus || sawDolbyVision
    }

    private fun rangeEndOf(i: Int, end: Int): Int = if (i + 1 < count) rangeBegin[i + 1] else end

    /** Type de l'unité [i], ou -1 si son en-tête est absent ou invalide. */
    private fun nalType(data: ByteBuffer, i: Int): Int {
        val at = payloadStart[i]
        if (payloadEnd[i] - at < NAL_HEADER_BYTES) return -1
        val first = data.get(at).toInt() and 0xFF
        if (first and 0x80 != 0) return -1 // forbidden_zero_bit
        return (first shr 1) and 0x3F
    }

    /**
     * Range les unités NAL de [start] à [end]. Faux si le tampon ne
     * commence pas par un code de départ : ce n'est pas de l'Annex B,
     * on ne devine pas, on ne touche à rien.
     */
    private fun index(data: ByteBuffer, start: Int, end: Int): Boolean {
        count = 0
        var code = findStartCode(data, start, end)
        if (code < 0) return false
        for (k in start until code) {
            if (data.get(k) != ZERO) return false
        }
        var begin = start
        while (code >= 0) {
            val payload = code + START_CODE_BYTES
            val next = findStartCode(data, payload, end)
            var stop = if (next < 0) end else next
            // Les zéros collés devant un code de départ lui appartiennent
            // (code sur quatre octets, ou bourrage) : une unité NAL ne finit
            // jamais par un zéro.
            while (stop > payload && data.get(stop - 1) == ZERO) stop--
            if (count == rangeBegin.size) grow()
            rangeBegin[count] = begin
            payloadStart[count] = payload
            payloadEnd[count] = stop
            count++
            begin = stop
            code = next
        }
        return count > 0
    }

    private fun grow() {
        val size = rangeBegin.size * 2
        rangeBegin = rangeBegin.copyOf(size)
        payloadStart = payloadStart.copyOf(size)
        payloadEnd = payloadEnd.copyOf(size)
        drop = drop.copyOf(size)
    }

    /**
     * Lit tous les messages d'une unité SEI. Les positions des messages
     * HDR10+ sont notées dans [maskAt] seulement si l'unité contient aussi
     * autre chose (cas [SEI_MIXED]).
     */
    private fun readSei(data: ByteBuffer, from: Int, to: Int): Int {
        seiPos = from
        seiEnd = to
        seiZeros = 0
        seiLast = -1
        var hdr = 0
        var other = 0
        val firstMask = maskCount
        while (true) {
            var value = nextSeiByte(data)
            if (value < 0) break
            // Dernier octet seul = bits de fin (1000 0000), pas un message.
            if (value == 0x80 && seiPos >= seiEnd) break
            var type = 0
            while (value == 0xFF) {
                type += 255
                value = nextSeiByte(data)
            }
            if (value < 0) return unreadable(firstMask)
            type += value
            val typeAt = seiLast
            value = nextSeiByte(data)
            var size = 0
            while (value == 0xFF) {
                size += 255
                value = nextSeiByte(data)
            }
            if (value < 0) return unreadable(firstMask)
            size += value
            var read = 0
            var isHdr = type == SEI_TYPE_T35 && size >= HDR10_PLUS_SIGNATURE.size
            if (isHdr) {
                for (expected in HDR10_PLUS_SIGNATURE) {
                    value = nextSeiByte(data)
                    if (value < 0) return unreadable(firstMask)
                    read++
                    if (value != expected) {
                        isHdr = false
                        break
                    }
                }
            }
            while (read < size) {
                if (nextSeiByte(data) < 0) return unreadable(firstMask)
                read++
            }
            if (isHdr) {
                hdr++
                if (maskCount < MAX_MASKS) maskAt[maskCount++] = typeAt
            } else {
                other++
            }
        }
        if (hdr == 0) {
            maskCount = firstMask
            return SEI_OTHER
        }
        if (other == 0) {
            // Toute l'unité part : rien à masquer dedans.
            maskCount = firstMask
            return SEI_ONLY_HDR10_PLUS
        }
        return SEI_MIXED
    }

    /** Message coupé ou incohérent : on ne conclut rien, l'unité reste. */
    private fun unreadable(firstMask: Int): Int {
        maskCount = firstMask
        return SEI_OTHER
    }

    private fun nextSeiByte(data: ByteBuffer): Int {
        while (seiPos < seiEnd) {
            val value = data.get(seiPos).toInt() and 0xFF
            if (seiZeros >= 2 && value == 0x03) {
                // Octet anti-émulation : pas une donnée du message.
                seiZeros = 0
                seiPos++
                continue
            }
            seiZeros = if (value == 0) seiZeros + 1 else 0
            seiLast = seiPos
            seiPos++
            return value
        }
        return -1
    }

    /**
     * Déplace [length] octets vers la gauche. Chaque paquet est d'abord
     * copié dans [scratch] : le résultat ne dépend pas de la façon dont la
     * box copie deux zones qui se chevauchent.
     */
    private fun move(data: ByteBuffer, from: Int, to: Int, length: Int) {
        var done = 0
        while (done < length) {
            val size = minOf(scratch.size, length - done)
            data.position(from + done)
            data.get(scratch, 0, size)
            data.position(to + done)
            data.put(scratch, 0, size)
            done += size
        }
    }

    companion object {
        /** Images lues à chaque ouverture avant de conclure « flux ordinaire ». */
        const val PROBE_UNITS: Int = 12

        /** Dernier type d'unité qui porte de l'image (« VCL »). */
        const val MAX_PICTURE_TYPE: Int = 31

        const val NAL_PREFIX_SEI: Int = 39
        const val NAL_SUFFIX_SEI: Int = 40
        const val NAL_DOLBY_RPU: Int = 62
        const val NAL_DOLBY_LAYER: Int = 63

        /** user_data_registered_itu_t_t35 */
        const val SEI_TYPE_T35: Int = 4

        /** Numéro de type non attribué : un décodeur doit ignorer le message. */
        const val SEI_TYPE_IGNORED: Int = 254

        /**
         * Signature HDR10+ au début du message T.35 : pays B5 (États-Unis),
         * fournisseur 00 3C, code 00 01, application 4. La version qui suit
         * n'est pas regardée (0 et 1 existent).
         */
        val HDR10_PLUS_SIGNATURE: IntArray = intArrayOf(0xB5, 0x00, 0x3C, 0x00, 0x01, 0x04)

        private const val SEI_OTHER = 0
        private const val SEI_ONLY_HDR10_PLUS = 1
        private const val SEI_MIXED = 2

        private const val NAL_HEADER_BYTES = 2
        private const val START_CODE_BYTES = 3
        private const val MIN_UNIT_BYTES = START_CODE_BYTES + NAL_HEADER_BYTES
        private const val MAX_MASKS = 16
        private const val SCRATCH_BYTES = 64 * 1024
        private const val ZERO: Byte = 0

        /**
         * Type (0 à 31) de la première unité d'IMAGE de [data], ou -1 si le
         * tampon n'en montre pas. Lecture seule, et rapide : on s'arrête à
         * l'en-tête de l'image, sans lire son contenu. Sert à écrire dans la
         * boîte noire sur quelle image le décodeur repart après un saut.
         */
        fun firstPictureType(data: ByteBuffer): Int {
            val end = data.limit()
            var code = findStartCode(data, data.position(), end)
            while (code >= 0) {
                val at = code + START_CODE_BYTES
                if (at >= end) return -1
                val first = data.get(at).toInt() and 0xFF
                if (first and 0x80 != 0) return -1
                val type = (first shr 1) and 0x3F
                if (type <= MAX_PICTURE_TYPE) return type
                code = findStartCode(data, at, end)
            }
            return -1
        }

        /**
         * Position du prochain `00 00 01` à partir de [from], ou -1.
         * On regarde le TROISIÈME octet : s'il ne vaut ni 0 ni 1, aucun
         * code de départ ne peut commencer sur ces trois positions.
         */
        fun findStartCode(data: ByteBuffer, from: Int, end: Int): Int {
            var i = from
            val last = end - START_CODE_BYTES
            while (i <= last) {
                val third = data.get(i + 2).toInt()
                if (third == 1) {
                    if (data.get(i) == ZERO && data.get(i + 1) == ZERO) return i
                    i += 3
                } else if (third == 0) {
                    i += 1
                } else {
                    i += 3
                }
            }
            return -1
        }
    }
}

/**
 * Lignes écrites dans la boîte noire (étiquette « IMAGE »). Du texte pur :
 * la prochaine fois qu'un client envoie son journal, on y lit ce que le
 * film contenait, quel décodeur l'a reçu et ce qui a été retiré.
 */
object HybridHdrReport {
    /** Ce que le flux contient, pour ce décodeur et cet appareil. */
    fun content(filter: HybridHdrFilter, decoder: String, device: String): String {
        val what = when {
            filter.hybrid -> "Dolby Vision oui, HDR10+ oui (film hybride)"
            filter.sawDolbyVision -> "Dolby Vision oui, HDR10+ non"
            filter.sawHdr10Plus -> "Dolby Vision non, HDR10+ oui"
            else -> "ni Dolby Vision ni HDR10+"
        }
        val line = "HDR du flux : $what. Décodeur $decoder. Appareil $device."
        // Observation seule : dire pourquoi rien n'est retiré, et quoi essayer.
        return if (filter.mode == HybridHdrMode.WATCH && filter.hybrid) {
            "$line Rien n'est retiré sur cet appareil ; si l'image disparaît, " +
                "allumer « Compatibilité HDR » (Réglages → Plus)."
        } else {
            line
        }
    }

    /**
     * Sur quelle image le décodeur repart après un saut dans le film.
     * [pictureType] vient de [HybridHdrFilter.firstPictureType]. `null` =
     * rien à signaler : image clé fermée (types 19 et 20), le cas sans
     * histoire, ou type illisible.
     */
    fun afterSeek(pictureType: Int): String? = when (pictureType) {
        19, 20 -> null
        in 16..18, 21 ->
            "Après un saut : reprise sur une image clé ouverte (type $pictureType)."
        in 0..15 ->
            "Après un saut : la première image donnée au décodeur n'est pas une image clé " +
                "(type $pictureType). L'image peut rester abîmée jusqu'à la prochaine image clé."
        else -> null
    }

    /** Le décodeur a été recréé pour ce saut au lieu d'être vidé. */
    const val FRESH_DECODER: String =
        "Après un saut : décodeur recréé au lieu d'être vidé, la lecture repart comme au démarrage."

    /** Ce que le correctif a retiré depuis l'ouverture, ou `null` : rien. */
    fun action(filter: HybridHdrFilter): String? {
        val dolby = filter.removedDolbyVision > 0
        val hdr = filter.removedHdr10Plus > 0
        if (!dolby && !hdr) return null
        val origin = if (filter.mode == HybridHdrMode.STRICT) "réglage" else "automatique"
        val what = when {
            dolby && hdr -> "Dolby Vision et HDR10+ retirés"
            hdr -> "HDR10+ retiré"
            else -> "Dolby Vision retiré"
        }
        val where = if (filter.path == HybridHdrPath.DOLBY_DECODER) {
            "avant le décodeur Dolby Vision, Dolby Vision gardé"
        } else {
            "avant le décodeur HEVC, le film passe en HDR10"
        }
        return "Correctif HDR ($origin) : $what $where."
    }
}
