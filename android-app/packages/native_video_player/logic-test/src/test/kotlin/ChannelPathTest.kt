package com.manzilionellm.native_video_player.logic

import kotlin.math.PI
import kotlin.math.sin
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Banc des canaux, sans Android et sans flux. Chaque cas est un PCM
 * fabriqué ici. On vérifie quel cas fait disparaître la voix dans la
 * somme gauche+droite, et que le chemin Zuno (identité) ne le crée pas
 * tout seul.
 */
class ChannelPathTest {

    private val rate = 48_000
    private val frames = 48_000

    @Test
    fun leCheminStereoDeZunoEstUneCopie() {
        val pcm = stereo { i ->
            val s = voix(i, 140.0)
            s to s
        }
        val out = ChannelPath.identite(pcm)
        assertEquals(pcm.size, out.size)
        for (i in pcm.indices) assertEquals(pcm[i], out[i])
        val m = ChannelPath.mesurer(out, 2, rate)
        println(m.ligne("identite en phase"))
        println("  " + m.raison)
        assertEquals(ChannelPath.Effet.PAS_UN_TROU, m.effet)
        assertTrue(m.correlation > 0.95, m.correlation.toString())
        assertTrue(m.niveau < 0.05, m.niveau.toString())
        assertTrue(m.creuxInter < 0.05, m.creuxInter.toString())
        assertTrue(m.gardeVoix > 0.8, m.gardeVoix.toString())
    }

    @Test
    fun voiesOpposeesFontUnTrouDansLaSomme() {
        val pcm = stereo { i ->
            val s = voix(i, 140.0)
            s to -s
        }
        // Zuno ne retourne pas la voie : l'identité laisse le trou en place.
        val out = ChannelPath.identite(pcm)
        val m = ChannelPath.mesurer(out, 2, rate)
        println(m.ligne("hors phase"))
        println("  " + m.raison)
        assertEquals(ChannelPath.Effet.TROU_PHASE, m.effet)
        assertTrue(m.correlation < -0.95, m.correlation.toString())
        assertTrue(m.gardeVoix < 0.05, m.gardeVoix.toString())
        assertTrue(m.creuxInter > 0.8, m.creuxInter.toString())
    }

    @Test
    fun unRetardEntreLesVoiesCreuseLaVoix() {
        val gauche = DoubleArray(frames) { voix(it, 180.0) }
        val droite = retarder(gauche, 96)
        val pcm = stereoDe(gauche, droite)
        val m = ChannelPath.mesurer(pcm, 2, rate)
        println(m.ligne("retard 2 ms"))
        println("  " + m.raison)
        assertEquals(ChannelPath.Effet.TROU_CREUX, m.effet)
        assertTrue(m.correlation > -0.5, m.correlation.toString())
        assertTrue(m.creuxInter >= ChannelPath.CREUX_PARTIEL, m.creuxInter.toString())
        assertTrue(m.gardeVoix < 0.85, m.gardeVoix.toString())
    }

    @Test
    fun unRetardDUneTrameAacEstUnPeigne() {
        val gauche = DoubleArray(frames) { voix(it, 180.0) }
        val droite = retarder(gauche, 1024)
        val m = ChannelPath.mesurer(stereoDe(gauche, droite), 2, rate)
        println(m.ligne("retard 1024 (21 ms)"))
        println("  " + m.raison)
        assertEquals(ChannelPath.Effet.TROU_CREUX, m.effet)
        assertTrue(m.gardeVoix < 0.5, m.gardeVoix.toString())
    }

    @Test
    fun unEchantillonDeDecalageNeFaitPasUnTrou() {
        val gauche = DoubleArray(frames) { voix(it, 140.0) }
        val m = ChannelPath.mesurer(stereoDe(gauche, retarder(gauche, 1)), 2, rate)
        println(m.ligne("retard 1 echantillon"))
        println("  " + m.raison)
        assertEquals(ChannelPath.Effet.PAS_UN_TROU, m.effet)
    }

    @Test
    fun monoCopieSurLesDeuxVoiesNestPasUnTrou() {
        val s = DoubleArray(frames) { voix(it, 140.0) }
        val m = ChannelPath.mesurer(stereoDe(s, s), 2, rate)
        println(m.ligne("mono duplique"))
        assertEquals(ChannelPath.Effet.PAS_UN_TROU, m.effet)
        assertTrue(m.correlation > 0.98)
    }

    @Test
    fun monoSurLaGaucheSeuleNestPasUnTrou() {
        val s = DoubleArray(frames) { voix(it, 140.0) }
        val m = ChannelPath.mesurer(stereoDe(s, DoubleArray(frames)), 2, rate)
        println(m.ligne("mono dans la gauche"))
        println("  garde-voix (attendu ~0,25) ${m.gardeVoix}")
        assertEquals(ChannelPath.Effet.PAS_UN_TROU, m.effet)
        assertTrue(m.correlation.isNaN() || m.creuxInter < ChannelPath.CREUX_PARTIEL)
    }

    @Test
    fun deuxProgrammesSeBattentSansAnnulerLaVoix() {
        val g = DoubleArray(frames) { voix(it, 140.0) }
        val d = DoubleArray(frames) { voix(it, 230.0, phase = 1.3) }
        val m = ChannelPath.mesurer(stereoDe(g, d), 2, rate)
        println(m.ligne("deux programmes"))
        println("  " + m.raison)
        assertEquals(ChannelPath.Effet.DEUX_PROGRAMMES, m.effet)
        assertTrue(m.gardeVoix > 0.4, m.gardeVoix.toString())
    }

    @Test
    fun milieuEtEcartJouesCommeGaucheDroite() {
        val a = DoubleArray(frames) { voix(it, 140.0) }
        val b = DoubleArray(frames) { voix(it, 230.0, phase = 0.7) }
        val mid = DoubleArray(frames) { (a[it] + b[it]) / 2.0 }
        val side = DoubleArray(frames) { (a[it] - b[it]) / 2.0 }
        val m = ChannelPath.mesurer(stereoDe(mid, side), 2, rate)
        println(m.ligne("M/S lu comme G/D"))
        println("  " + m.raison)
        // La somme (M+S)/2 ne garde qu'un des deux programmes : l'autre
        // est annulé. En stéréo, les deux voies ne racontent pas la même
        // chose. Le banc classe ça comme un creux, pas comme une simple
        // inversion.
        assertEquals(ChannelPath.Effet.TROU_CREUX, m.effet)
        assertTrue(m.creuxInter >= ChannelPath.CREUX_PARTIEL, m.creuxInter.toString())
    }

    @Test
    fun lePeigneDejaDansLesDeuxVoiesEstInvisibleALaCorrelation() {
        val s = DoubleArray(frames) { voix(it, 180.0) }
        val creux = DoubleArray(frames)
        val retard = retarder(s, 96)
        for (i in creux.indices) creux[i] = (s[i] + retard[i]) / 2.0
        val m = ChannelPath.mesurer(stereoDe(creux, creux), 2, rate)
        val voixOrigine = ChannelPath.energieVoix(s, rate)
        val voixCreuse = ChannelPath.energieVoix(creux, rate)
        println(m.ligne("peigne deja identique G=D"))
        println("  voix restante par rapport a l'original : ${voixCreuse / voixOrigine}")
        // Les deux voies sont d'accord : la sonde G/D dit « pas un trou ».
        // Pourtant la voix a déjà été creusée avant la stéréo.
        assertEquals(ChannelPath.Effet.PAS_UN_TROU, m.effet)
        assertTrue(m.correlation > 0.95, m.correlation.toString())
        assertTrue(voixCreuse / voixOrigine < 0.85, (voixCreuse / voixOrigine).toString())
    }

    @Test
    fun garderLesDeuxPremieresVoiesJetteLeCentre() {
        val mix = cinqUn(voixAuCentre = true)
        val jete = ChannelPath.garderPremieres(mix, 6, 2)
        val itu = ChannelPath.ituStereo(mix, 6)
        val voixJete = ChannelPath.energieVoixCanal(jete, 2, 0, rate) +
            ChannelPath.energieVoixCanal(jete, 2, 1, rate)
        val voixItu = ChannelPath.energieVoixCanal(itu, 2, 0, rate) +
            ChannelPath.energieVoixCanal(itu, 2, 1, rate)
        val m = ChannelPath.mesurer(jete, 2, rate)
        println(m.ligne("5.1 garde L/R seulement"))
        println("  voix L+R jetees=$voixJete  voix ITU=$voixItu")
        assertTrue(ChannelPath.centrePerdu(voixJete, voixItu), "jete=$voixJete itu=$voixItu")
        assertFalse(ChannelPath.centrePerdu(voixItu, voixItu))
        // L et R sont le même aigu : la corrélation dit « d'accord ».
        // Elle ne voit pas que la voix, elle, était au centre.
        assertEquals(ChannelPath.Effet.PAS_UN_TROU, m.effet)
        assertTrue(m.correlation > 0.95, m.correlation.toString())
    }

    @Test
    fun echangerCentreEtCaissonPuisItuPerdLaVoix() {
        val mix = cinqUn(voixAuCentre = true)
        val swap = ChannelPath.echangerCentreEtCaisson(mix, 6)
        val ituJuste = ChannelPath.ituStereo(mix, 6)
        val ituFaux = ChannelPath.ituStereo(swap, 6)
        val voixJuste = ChannelPath.energieVoixCanal(ituJuste, 2, 0, rate)
        val voixFaux = ChannelPath.energieVoixCanal(ituFaux, 2, 0, rate)
        println("centre/caisson echanges puis ITU : voix gauche juste=$voixJuste faux=$voixFaux")
        assertTrue(ChannelPath.centrePerdu(voixFaux, voixJuste), "faux=$voixFaux juste=$voixJuste")
    }

    @Test
    fun ordreDesElementsAacMetLaVoixAGauche() {
        val mix = cinqUn(voixAuCentre = true)
        val faux = ChannelPath.ordreElementsAac(mix)
        // Interprété comme L,R,C,... la première voie est en fait le centre.
        val voixPremiere = ChannelPath.energieVoixCanal(faux, 6, 0, rate)
        val voixCentreAttendu = ChannelPath.energieVoixCanal(mix, 6, 2, rate)
        val voixDeuxieme = ChannelPath.energieVoixCanal(faux, 6, 1, rate)
        println("ordre elements : voix voie0=$voixPremiere (doit coller au centre $voixCentreAttendu) voie1=$voixDeuxieme")
        assertTrue(voixPremiere > voixCentreAttendu * 0.5)
        // La deuxième voie du faux ordre est l'ancienne gauche : des aigus, pas la voix.
        assertTrue(voixDeuxieme < voixPremiere * 0.25, voixDeuxieme.toString())
    }

    @Test
    fun planaireLuCommeEntrelaceNeRestePasEnPhase() {
        val g = DoubleArray(frames) { voix(it, 140.0) }
        val pcm = ChannelPath.planaireLuCommeEntrelace(
            g.map { it.toInt().toShort() }.toShortArray(),
            g.map { it.toInt().toShort() }.toShortArray(),
        )
        val m = ChannelPath.mesurer(pcm, 2, rate)
        println(m.ligne("planaire lu entrelace"))
        println("  " + m.raison)
        // Deux échantillons voisins d'une voix grave se ressemblent :
        // les lire comme gauche/droite ne fabrique PAS une opposition.
        // Le son est faux (le temps est replié), mais ce n'est pas le trou.
        assertEquals(ChannelPath.Effet.PAS_UN_TROU, m.effet)
        assertTrue(m.correlation > 0.95, m.correlation.toString())
        assertEquals(g[1].toInt().toShort(), pcm[1])
    }

    private fun voix(i: Int, f0: Double, phase: Double = 0.0): Double {
        val env = 0.65 + 0.35 * sin(2.0 * PI * 3.0 * i / rate)
        var s = 0.0
        var h = 1
        var f = f0
        while (f < 3_600.0 && h <= 24) {
            val formant = when {
                f in 500.0..900.0 -> 2.2
                f in 1_000.0..1_600.0 -> 1.6
                else -> 1.0
            }
            s += (formant / h) * sin(2.0 * PI * f * i / rate + phase * h)
            h++
            f = f0 * h
        }
        return s * env * 1_800.0
    }

    /** 5.1 : aigus à gauche et à droite, voix seulement au centre, grave au caisson. */
    private fun cinqUn(voixAuCentre: Boolean): ShortArray {
        val out = ShortArray(frames * 6)
        for (i in 0 until frames) {
            val b = i * 6
            val aigu = (sin(2.0 * PI * 6_000.0 * i / rate) * 4_000.0).toInt().toShort()
            out[b] = aigu
            out[b + 1] = aigu
            out[b + 2] = if (voixAuCentre) voix(i, 140.0).toInt().toShort() else 0
            out[b + 3] = (sin(2.0 * PI * 80.0 * i / rate) * 8_000.0).toInt().toShort()
            // Surrounds hors de la bande de voix : ils ne doivent pas
            // servir de fausse « voix restante » après un mauvais downmix.
            out[b + 4] = (sin(2.0 * PI * 8_000.0 * i / rate) * 800.0).toInt().toShort()
            out[b + 5] = (sin(2.0 * PI * 9_000.0 * i / rate) * 800.0).toInt().toShort()
        }
        return out
    }

    private fun retarder(x: DoubleArray, delai: Int): DoubleArray {
        val y = DoubleArray(x.size)
        for (i in x.indices) {
            val j = i - delai
            y[i] = if (j >= 0) x[j] else 0.0
        }
        return y
    }

    private fun stereo(sample: (Int) -> Pair<Double, Double>): ShortArray {
        val pcm = ShortArray(frames * 2)
        for (i in 0 until frames) {
            val (l, r) = sample(i)
            pcm[i * 2] = l.toInt().toShort()
            pcm[i * 2 + 1] = r.toInt().toShort()
        }
        return pcm
    }

    private fun stereoDe(g: DoubleArray, d: DoubleArray): ShortArray {
        val n = minOf(g.size, d.size)
        val pcm = ShortArray(n * 2)
        for (i in 0 until n) {
            pcm[i * 2] = g[i].toInt().toShort()
            pcm[i * 2 + 1] = d[i].toInt().toShort()
        }
        return pcm
    }
}
