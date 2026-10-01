package com.manzilionellm.native_video_player.logic

/**
 * Ordre des décodeurs MediaCodec pour UNE piste vidéo.
 *
 * La liste que donne Android met en général le matériel en premier.
 * On la garde telle quelle, sauf si la personne (ou le repli) demande
 * le logiciel : alors `OMX.google.*` et `c2.android.*` passent devant.
 *
 * On ne retire JAMAIS un décodeur. Une liste vide en entrée reste vide
 * (la box n'a rien). Une liste sans logiciel reste dans l'ordre d'origine :
 * mieux vaut l'image de la box qu'une chaîne sans décodeur.
 */
data class NamedCodec(val name: String)

object CodecOrder {
    /** Vrai pour le décodeur logiciel fourni par Android, pas par le fabricant. */
    fun isSoftware(name: String): Boolean {
        val n = name.lowercase()
        return n.startsWith("omx.google.") || n.startsWith("c2.android.")
    }

    fun order(codecs: List<NamedCodec>, preferSoftware: Boolean): List<NamedCodec> {
        if (codecs.isEmpty() || !preferSoftware) return codecs
        val soft = codecs.filter { isSoftware(it.name) }
        if (soft.isEmpty()) return codecs
        val hard = codecs.filter { !isSoftware(it.name) }
        return soft + hard
    }
}
