import com.manzilionellm.native_video_player.logic.AudioDiagnosis
import com.manzilionellm.native_video_player.logic.AudioQuality
import com.manzilionellm.native_video_player.logic.AudioSnapshot
import com.manzilionellm.native_video_player.logic.AudioSpectrum
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Les seuils viennent du banc Python (trous mesurés), pas d'un réglage
 * à la main. Ici on refait les mêmes familles de signaux : harmoniques
 * en 1/k, puis un filtre écrit dans CE fichier (le détecteur, lui,
 * ne filtre pas : il mesure un spectre).
 */
class AudioQualityTest {

    @Test
    fun laFftColleANumpyEtLaFenetreDeHannAussi() {
        assertEquals(0.0, AudioQuality.hann(0, 8), 1e-9)
        assertEquals(0.1882550991, AudioQuality.hann(1, 8), 1e-8)
        assertEquals(0.6112604670, AudioQuality.hann(2, 8), 1e-8)
        assertEquals(0.9504844340, AudioQuality.hann(3, 8), 1e-8)
        val re = doubleArrayOf(0.5, -0.25, 0.125, -0.0625, 0.0, 0.3, -0.3, 0.1)
        val im = DoubleArray(8)
        AudioQuality.Fft.transform(re, im, inverse = false)
        // numpy.fft.fft du même vecteur, 03/10/2026.
        val attenduRe = doubleArrayOf(
            0.4125000000, 0.2259961223, 0.6750000000, 0.7740038777,
            0.2375000000, 0.7740038777, 0.6750000000, 0.2259961223,
        )
        val attenduIm = doubleArrayOf(
            0.0, 0.0788135816, -0.0125000000, 0.9288135816,
            0.0, -0.9288135816, 0.0125000000, -0.0788135816,
        )
        for (i in re.indices) {
            assertEquals(attenduRe[i], re[i], 1e-8, "re[$i]")
            assertEquals(attenduIm[i], im[i], 1e-8, "im[$i]")
        }
    }

    @Test
    fun lePourcentageAuDessusDe4kHzNeSeparePasLeTelephoneDeLaParole() {
        val sr = 48_000
        val propre = harmoniques(sr, sr, 120.0, 7600.0)
        val tel = telephone(propre, sr)
        val bas = lowpassTwice(propre, sr, 3400.0)
        val haut = highpassTwice(propre, sr, 300.0)
        val qPropre = AudioQuality.measure(toShort(propre), sr, 1)
        val qTel = AudioQuality.measure(toShort(tel), sr, 1)
        val qBas = AudioQuality.measure(toShort(bas), sr, 1)
        val qHaut = AudioQuality.measure(toShort(haut), sr, 1)
        val sPropre = AudioSpectrum.measure(toShort(propre), sr, 1)
        val sTel = AudioSpectrum.measure(toShort(tel), sr, 1)
        println("FORME propre grave=${qPropre.graveRatio} aigu=${qPropre.aiguRatio} ${qPropre.profil} >4k=${sPropre.highRatio}")
        println("FORME tel    grave=${qTel.graveRatio} aigu=${qTel.aiguRatio} ${qTel.profil} >4k=${sTel.highRatio}")
        println("FORME bas    grave=${qBas.graveRatio} aigu=${qBas.aiguRatio} ${qBas.profil}")
        println("FORME haut   grave=${qHaut.graveRatio} aigu=${qHaut.aiguRatio} ${qHaut.profil}")
        // L'ancien mètre met les deux dans la même case.
        assertEquals(AudioSpectrum.Band.LOW, sPropre.band, ">4k propre ${sPropre.highRatio}")
        assertEquals(AudioSpectrum.Band.LOW, sTel.band, ">4k tel ${sTel.highRatio}")
        // Le téléphone n'a pas « enlevé les aigus » au sens de ce mètre :
        // le rapport reste du même ordre (pas 10 fois plus petit).
        assertTrue(sTel.highRatio > sPropre.highRatio * 0.4, "tel ${sTel.highRatio} propre ${sPropre.highRatio}")
        assertEquals(AudioQuality.Profil.LARGE, qPropre.profil)
        assertTrue(qPropre.graveRatio > AudioQuality.GRAVE_BAS, "grave propre ${qPropre.graveRatio}")
        assertTrue(qPropre.aiguRatio > AudioQuality.AIGU_BAS, "aigu propre ${qPropre.aiguRatio}")
        assertEquals(AudioQuality.Profil.TELEPHONE, qTel.profil)
        assertTrue(qTel.graveRatio < AudioQuality.GRAVE_BAS, "grave tel ${qTel.graveRatio}")
        assertTrue(qTel.aiguRatio < AudioQuality.AIGU_BAS, "aigu tel ${qTel.aiguRatio}")
        // Passe-bas seul : le grave reste. > 4 kHz aurait confondu avec le téléphone.
        assertEquals(AudioQuality.Profil.SOURD, qBas.profil)
        assertTrue(qBas.graveRatio > AudioQuality.GRAVE_BAS, "grave bas ${qBas.graveRatio}")
        // Passe-haut seul : l'aigu reste. Le grave seul ne dit pas « téléphone ».
        assertEquals(AudioQuality.Profil.MAIGRE, qHaut.profil)
        assertTrue(qHaut.aiguRatio > AudioQuality.AIGU_BAS, "aigu haut ${qHaut.aiguRatio}")
        assertTrue(qPropre.echo < AudioQuality.ECHO_MIN, "écho parole ${qPropre.echo}")
    }

    @Test
    fun uneCopieDecaleeDe30msDepasseLeSeuilEtDeuxImpulsionsAussi() {
        val sr = 48_000
        val propre = harmoniques(sr, sr, 120.0, 7600.0)
        val decale = DoubleArray(propre.size)
        val d = (0.030 * sr).toInt()
        for (i in propre.indices) {
            decale[i] = propre[i]
            if (i >= d) decale[i] += 0.8 * propre[i - d]
        }
        norm(decale, 0.45)
        val qPropre = AudioQuality.measure(toShort(propre), sr, 1)
        val qEcho = AudioQuality.measure(toShort(decale), sr, 1)
        println("ECHO propre=${qPropre.echo} copie=${qEcho.echo} à ${qEcho.echoMs} ms")
        assertTrue(qPropre.echo < AudioQuality.ECHO_MIN, "propre ${qPropre.echo}")
        assertTrue(qEcho.echo >= AudioQuality.ECHO_MIN, "copie ${qEcho.echo}")
        assertTrue(qEcho.echoNet)
        assertFalse(qPropre.echoNet)
        // Deux impulsions à 30 ms : le score part très haut (médiane
        // presque nulle). Une seule impulsion ne doit pas s'allumer.
        val n = 32_768
        val une = DoubleArray(n)
        une[1000] = 0.8
        val deux = une.copyOf()
        deux[1000 + d] = 0.6
        val qUne = AudioQuality.measure(toShort(une), sr, 1)
        val qDeux = AudioQuality.measure(toShort(deux), sr, 1)
        println("ECHO impulsion=${qUne.echo} deux=${qDeux.echo} ms=${qDeux.echoMs}")
        assertFalse(qUne.echoNet)
        assertTrue(qDeux.echo >= AudioQuality.ECHO_MIN, "deux ${qDeux.echo}")
        assertTrue(abs(qDeux.echoMs - 30.0) < 1.5, "retard ${qDeux.echoMs}")
    }

    @Test
    fun laBaisseTenueDepasse8dBEtUnePauseNon() {
        val sr = 48_000
        val plein = niveaux(tonConstant(sr, 0.40), sr)
        val duck = niveaux(gainParSecondes(sr, 0.40, mapOf(3 to 0.2, 4 to 0.2, 5 to 0.2)), sr)
        val pause = niveaux(gainParSecondes(sr, 0.40, mapOf(3 to 0.0, 4 to 0.0)), sr)
        val cPlein = AudioQuality.chuteDb(plein)
        val cDuck = AudioQuality.chuteDb(duck)
        val cPause = AudioQuality.chuteDb(pause)
        println("CHUTE plein=$cPlein duck=$cDuck pause=$cPause")
        println("NIVEAUX duck=$duck")
        assertTrue(cPlein < AudioQuality.CHUTE_DB, "plein $cPlein")
        assertTrue(cDuck >= AudioQuality.CHUTE_DB, "duck $cDuck")
        assertTrue(cDuck > 12.0, "un gain × 0,2 fait environ 14 dB, mesuré $cDuck")
        assertTrue(cPause < AudioQuality.CHUTE_DB, "pause $cPause")
    }

    @Test
    fun desVoiesOpposeesNeDonnentPasUnSilenceAuSpectre() {
        val sr = 48_000
        val mono = toShort(harmoniques(sr, sr, 120.0, 7600.0))
        val stereo = ShortArray(mono.size * 2)
        for (i in mono.indices) {
            stereo[i * 2] = mono[i]
            val inv = -mono[i].toInt()
            stereo[i * 2 + 1] = inv.coerceIn(-32768, 32767).toShort()
        }
        val q = AudioQuality.measure(stereo, sr, 2)
        println("OPPOSE profil=${q.profil} grave=${q.graveRatio}")
        assertEquals(AudioQuality.Profil.LARGE, q.profil)
        assertFalse(q.graveRatio.isNaN())
    }

    @Test
    fun uneFenetreCourteNeConclutPas() {
        val q = AudioQuality.measure(ShortArray(1000) { 1000 }, 48_000, 1)
        assertEquals(AudioQuality.Profil.COURT, q.profil)
        assertFalse(q.echoNet)
    }

    @Test
    fun laFicheDitLaFormeSansEnFaireUneCauseSure() {
        val tel = qualite(
            AudioQuality.Profil.TELEPHONE,
            grave = 0.07,
            aigu = 0.004,
            echo = 6.0,
            chute = 0.6,
        )
        val s = base(tel)
        val report = AudioDiagnosis.report(s)
        println(report)
        assertTrue(report.contains("téléphone"), report)
        assertTrue(report.contains("grave/milieu"), report)
        assertTrue(AudioDiagnosis.findings(s).any { it.id == "profil_telephone" })
        assertTrue(AudioDiagnosis.sureCauses(s).none { it.id == "profil_telephone" })
        assertFalse(report.contains("http"))
        val large = base(qualite(AudioQuality.Profil.LARGE, 3.4, 0.05, 7.0, 0.6))
        assertFalse(AudioDiagnosis.report(large).contains("profil_telephone"))
        assertTrue(AudioDiagnosis.findings(large).none { it.id == "profil_telephone" })
        val echo = base(qualite(AudioQuality.Profil.LARGE, 3.4, 0.05, echo = 170.0, chute = 1.0, echoMs = 30.0))
        assertTrue(AudioDiagnosis.findings(echo).any { it.id == "echo_double" })
        assertTrue(AudioDiagnosis.sureCauses(echo).none { it.id == "echo_double" })
        val chute = base(qualite(AudioQuality.Profil.LARGE, 3.4, 0.05, echo = 6.0, chute = 14.0))
        assertTrue(AudioDiagnosis.findings(chute).any { it.id == "chute_niveau" })
        assertTrue(AudioDiagnosis.sureCauses(chute).none { it.id == "chute_niveau" })
        // Sonde coupée : pas de ligne « Forme », le texte d'avant reste.
        val sans = AudioDiagnosis.report(
            AudioSnapshot(
                mime = "audio/mp4a-latm", codecs = "mp4a.40.2",
                decoder = "ffmpeg6.0-aac", outSampleRate = 48_000, outChannels = 2,
                outEncoding = "PCM 16 bits",
            ),
        )
        assertFalse(sans.contains("grave/milieu"), sans)
    }

    private fun qualite(
        profil: AudioQuality.Profil,
        grave: Double,
        aigu: Double,
        echo: Double,
        chute: Double,
        echoMs: Double = Double.NaN,
    ) = AudioQuality.Reading(
        profil = profil,
        graveRatio = grave,
        aiguRatio = aigu,
        echo = echo,
        echoMs = echoMs,
        fortDb = -20.0,
        chuteDb = chute,
        sampleRate = 48_000,
        frames = 32_768,
    )

    private fun base(q: AudioQuality.Reading) = AudioSnapshot(
        mime = "audio/mp4a-latm",
        codecs = "mp4a.40.2",
        inSampleRate = 48_000,
        inChannels = 2,
        decoder = "ffmpeg6.0-aac",
        outSampleRate = 48_000,
        outChannels = 2,
        outEncoding = "PCM 16 bits",
        spectrum = AudioSpectrum.Judgement(
            band = AudioSpectrum.Band.LOW,
            highRatio = 0.012,
            clippedFraction = 0.0,
            peak = 8000,
            frames = 48_000,
            sampleRate = 48_000,
            quality = q,
        ),
    )

    /** Harmoniques en 1/k, syllabes. Pic à 0,45. */
    private fun harmoniques(n: Int, sr: Int, f0: Double, fMax: Double): DoubleArray {
        val y = DoubleArray(n)
        val on = (0.12 * sr).toInt().coerceAtLeast(8)
        val periode = (0.20 * sr).toInt()
        for (i in 0 until n) {
            val pos = i % periode
            val env = if (pos >= on) 0.0 else 0.5 - 0.5 * cos(2.0 * PI * pos / (on - 1))
            var s = 0.0
            var k = 1
            while (f0 * k < fMax && k <= 64) {
                s += (1.0 / k) * sin(2.0 * PI * f0 * k * i / sr)
                k++
            }
            y[i] = s * env
        }
        norm(y, 0.45)
        return y
    }

    private fun tonConstant(sr: Int, amp: Double): DoubleArray {
        val n = sr * 8
        val y = DoubleArray(n)
        for (i in 0 until n) y[i] = amp * sin(2.0 * PI * 440.0 * i / sr)
        return y
    }

    /** [gains] : numéro de seconde → facteur. Les autres secondes restent à [amp]. */
    private fun gainParSecondes(sr: Int, amp: Double, gains: Map<Int, Double>): DoubleArray {
        val y = tonConstant(sr, amp)
        for ((sec, g) in gains) {
            val a = sec * sr
            val b = minOf(y.size, (sec + 1) * sr)
            for (i in a until b) y[i] *= g
        }
        return y
    }

    private fun niveaux(y: DoubleArray, sr: Int): List<Double> {
        val out = ArrayList<Double>(8)
        var s = 0
        while (s + sr <= y.size) {
            out.add(AudioQuality.niveauFortDb(y.copyOfRange(s, s + sr), sr))
            s += sr
        }
        return out
    }

    /** Passe-bande 300–3400 Hz, chaque coupure appliquée deux fois. */
    private fun telephone(src: DoubleArray, sr: Int): DoubleArray {
        val haut = highpassTwice(src, sr, 300.0)
        return lowpassTwice(haut, sr, 3400.0)
    }

    private fun highpassTwice(src: DoubleArray, sr: Int, fc: Double): DoubleArray =
        biquad(biquad(src, sr, fc, high = true), sr, fc, high = true)

    private fun lowpassTwice(src: DoubleArray, sr: Int, fc: Double): DoubleArray =
        biquad(biquad(src, sr, fc, high = false), sr, fc, high = false)

    /** Butterworth ordre 2. Copie locale : le détecteur n'utilise pas ce filtre. */
    private fun biquad(src: DoubleArray, sr: Int, fc: Double, high: Boolean): DoubleArray {
        val q = sqrt(0.5)
        val w0 = 2.0 * PI * fc / sr
        val c = cos(w0)
        val alpha = sin(w0) / (2.0 * q)
        val a0 = 1.0 + alpha
        val b0: Double
        val b1: Double
        val b2: Double
        if (high) {
            b0 = ((1.0 + c) / 2.0) / a0
            b1 = (-(1.0 + c)) / a0
            b2 = ((1.0 + c) / 2.0) / a0
        } else {
            b0 = ((1.0 - c) / 2.0) / a0
            b1 = (1.0 - c) / a0
            b2 = ((1.0 - c) / 2.0) / a0
        }
        val a1 = (-2.0 * c) / a0
        val a2 = (1.0 - alpha) / a0
        var x1 = 0.0
        var x2 = 0.0
        var y1 = 0.0
        var y2 = 0.0
        val out = DoubleArray(src.size)
        for (i in src.indices) {
            val x = src[i]
            val y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            out[i] = y
        }
        return out
    }

    private fun norm(y: DoubleArray, picCible: Double) {
        var pic = 0.0
        for (v in y) {
            val a = abs(v)
            if (a > pic) pic = a
        }
        if (pic < 1e-12) return
        val g = picCible / pic
        for (i in y.indices) y[i] *= g
    }

    private fun toShort(x: DoubleArray): ShortArray = ShortArray(x.size) { i ->
        (x[i] * 32767.0).toInt().coerceIn(-32768, 32767).toShort()
    }
}
