package com.manzilionellm.native_video_player.logic

import java.io.File
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * PHASE ET VOIES. Signaux fabriqués ici, aucun flux, aucun secret.
 * La corrélation et (G−D)/(G+D) doivent voir une opposition, y compris
 * silence et saturation. Le mélange mono (G+D)/2 doit effacer la voix
 * opposée et garder la voix dupliquée.
 */
class AudioChannelsTest {

    @Test
    fun voixSynthDupliqueeResteEnsembleEtLeMonoLaGarde() {
        val pcm = AudioChannels.duplicatedMono(48_000)
        val reading = measure(pcm, 2)
        println(line("voix G=D", reading, pcm))
        assertTrue(reading.correlation > 0.95, reading.correlation.toString())
        assertTrue(reading.level() < 0.05, reading.level().toString())
        assertFalse(reading.opposed)
        assertFalse(reading.cancelled)
        assertEquals(1.0, reading.monoKept, 1e-9)
        assertEquals(1.0, AudioChannels.monoKept(pcm), 1e-9)
        val folded = AudioChannels.fold(pcm)
        val voiceEnergy = energyOf(pcm, channel = 0)
        assertTrue(AudioChannels.energy(folded) > voiceEnergy * 0.98)
    }

    @Test
    fun voixOpposeeEstAnnuleeParLeMelangeMono() {
        val pcm = AudioChannels.opposed(48_000)
        val reading = measure(pcm, 2)
        println(line("voix G=−D", reading, pcm))
        assertTrue(reading.correlation < -0.95, reading.correlation.toString())
        assertTrue(reading.level().isInfinite(), reading.levelText())
        assertTrue(reading.sideToMid.isInfinite() || reading.sideToMid >= AudioPhase.SIDE_MIN)
        assertTrue(reading.opposed)
        assertTrue(reading.cancelled)
        assertEquals(0.0, reading.monoKept, 1e-12)
        assertEquals(0.0, AudioChannels.monoKept(pcm), 1e-12)
        val folded = AudioChannels.fold(pcm)
        assertEquals(0.0, AudioChannels.energy(folded), 0.0)
        // Casque : on ne mélange pas. Chaque oreille garde la voix.
        assertTrue(energyOf(pcm, 0) > 0.0)
        assertEquals(energyOf(pcm, 0), energyOf(pcm, 1), 0.0)
    }

    @Test
    fun droiteFaibleInverseeNeffacePasLaVoix() {
        // D = −0,25 G. Corrélation −1, mais (G+D)/2 garde 37,5 % de G.
        val pcm = AudioChannels.stereo(48_000, gain = 0.55, left = AudioChannels::voice, right = { -0.25 * AudioChannels.voice(it) })
        val reading = measure(pcm, 2)
        println(line("D=−0,25 G", reading, pcm))
        assertTrue(reading.correlation < -0.95, reading.correlation.toString())
        assertTrue(reading.opposed)
        assertFalse(reading.cancelled, "une voie inverse mais faible ne doit pas être dite annulée")
        assertTrue(reading.monoKept > 0.10, reading.monoKept.toString())
        assertTrue(abs(reading.level() - (1.25 / 0.75)) < 0.05, reading.level().toString())
        val kept = AudioChannels.monoKept(pcm)
        assertEquals(kept, reading.monoKept, 1e-6)
    }

    @Test
    fun correlationMoyenneNestPasUneOpposition() {
        val rate = 48_000
        val pcm = AudioChannels.stereo(rate, gain = 0.5, left = { sine(it, 440.0) }, right = { i ->
            val s1 = sine(i, 440.0)
            val s2 = sine(i, 880.0)
            -0.50 * s1 + sqrt(0.75) * s2
        })
        val reading = measure(pcm, 2)
        println(line("corr ~ −0,5", reading, pcm))
        assertTrue(reading.correlation < -0.40, reading.correlation.toString())
        assertTrue(reading.correlation > AudioPhase.INVERT_MAX, reading.correlation.toString())
        assertFalse(reading.opposed)
        assertFalse(reading.cancelled)
        assertTrue(reading.monoKept > AudioPhase.CANCEL_MAX)
    }

    @Test
    fun silenceNeDitPasDopposition() {
        val pcm = AudioChannels.silence(48_000)
        val reading = measure(pcm, 2)
        println(line("silence", reading, pcm))
        assertTrue(reading.correlation.isNaN())
        assertTrue(reading.monoKept.isNaN())
        assertTrue(reading.level().isNaN())
        assertFalse(reading.opposed)
        assertFalse(reading.cancelled)
        assertTrue(AudioChannels.monoKept(pcm).isNaN())
        assertEquals(0.0, AudioChannels.energy(AudioChannels.fold(pcm)), 0.0)
    }

    @Test
    fun continuOpposeNestPasUneVoix() {
        // G = 8000, D = −8000, sans variation. Pearson est indéfini.
        // Le mélange vaut 0, mais ce n'est pas une voix : un haut-parleur
        // ne joue pas un continu. On ne dit pas « annulée ».
        val pcm = ShortArray(48_000 * 2) { i -> if (i % 2 == 0) 8_000 else -8_000 }
        val reading = measure(pcm, 2)
        println(line("continu opposé", reading, pcm))
        assertTrue(reading.correlation.isNaN(), reading.correlation.toString())
        assertEquals(0.0, reading.monoKept, 1e-12)
        assertFalse(reading.opposed)
        assertFalse(reading.cancelled)
    }

    @Test
    fun uneSeuleVoieActiveNestPasUneAnnulation() {
        val pcm = AudioChannels.stereo(48_000, gain = 0.55, left = AudioChannels::voice, right = { 0.0 })
        val reading = measure(pcm, 2)
        println(line("D muette", reading, pcm))
        assertTrue(reading.correlation.isNaN())
        assertFalse(reading.opposed)
        assertFalse(reading.cancelled)
        // (G+0)/2 garde le quart de l'énergie de G : la voix est plus
        // faible, elle n'a pas disparu.
        assertEquals(0.25, reading.monoKept, 0.02)
    }

    @Test
    fun saturationOpposeeResteAnnulee() {
        val pcm = AudioChannels.opposed(48_000, gain = 8.0)
        val reading = measure(pcm, 2)
        val clip = AudioChannels.clippedFraction(pcm)
        println(line("voix saturée G=−D", reading, pcm) + " clip=$clip")
        assertTrue(clip >= AudioSpectrum.CLIP_SURE, clip.toString())
        assertTrue(reading.correlation < -0.95, reading.correlation.toString())
        assertTrue(reading.level().isInfinite() || reading.level() > 20.0, reading.levelText())
        assertTrue(reading.opposed)
        assertTrue(reading.cancelled)
        assertTrue(reading.monoKept <= AudioPhase.CANCEL_MAX, reading.monoKept.toString())
        assertEquals(0.0, AudioChannels.energy(AudioChannels.fold(pcm)), 0.0)
    }

    @Test
    fun saturationEnsembleNestPasOpposee() {
        val pcm = AudioChannels.duplicatedMono(48_000, gain = 8.0)
        val reading = measure(pcm, 2)
        println(line("voix saturée G=D", reading, pcm))
        assertTrue(AudioChannels.clippedFraction(pcm) >= AudioSpectrum.CLIP_SURE)
        assertTrue(reading.correlation > 0.95, reading.correlation.toString())
        assertFalse(reading.opposed)
        assertFalse(reading.cancelled)
        assertTrue(reading.monoKept > 0.95, reading.monoKept.toString())
    }

    @Test
    fun gainIdentiqueSurLesDeuxVoiesNeCreePasDopposition() {
        val together = AudioChannels.applyGain(AudioChannels.duplicatedMono(48_000), 0.45)
        val flipped = AudioChannels.applyGain(AudioChannels.opposed(48_000), 0.45)
        val a = measure(together, 2)
        val b = measure(flipped, 2)
        println(line("gain 0,45 G=D", a, together))
        println(line("gain 0,45 G=−D", b, flipped))
        assertFalse(a.opposed)
        assertTrue(a.monoKept > 0.95)
        assertTrue(b.cancelled)
        assertTrue(b.monoKept <= AudioPhase.CANCEL_MAX)
    }

    @Test
    fun inverserUneVoieALaMainCreeLannulationQueLeMappingNeFaitPas() {
        val dup = AudioChannels.duplicatedMono(48_000)
        val swapped = AudioChannels.remap(dup, 2, intArrayOf(1, 0))
        val inverted = AudioChannels.invertChannel(dup, 2, index = 1)
        val swapReading = measure(swapped, 2)
        val invReading = measure(inverted, 2)
        println(line("carte 1,0 (échange)", swapReading, swapped))
        println(line("inversion manuelle de D", invReading, inverted))
        assertTrue(swapReading.correlation > 0.95)
        assertFalse(swapReading.cancelled)
        assertTrue(invReading.cancelled)
        assertEquals(0.0, invReading.monoKept, 1e-9)
        val opp = AudioChannels.opposed(48_000)
        val swappedOpp = AudioChannels.remap(opp, 2, intArrayOf(1, 0))
        assertTrue(measure(swappedOpp, 2).cancelled, "échanger G et −G les laisse opposées")
    }

    @Test
    fun lireDuPlanaireCommeDeLentrelaceCacheLopposition() {
        val n = 48_000
        val g = ShortArray(n)
        val d = ShortArray(n)
        val interleaved = AudioChannels.opposed(n)
        for (i in 0 until n) {
            g[i] = interleaved[i * 2]
            d[i] = interleaved[i * 2 + 1]
        }
        val wrong = AudioChannels.misreadPlanar(g, d)
        val bad = measure(wrong, 2)
        val good = measure(interleaved, 2)
        println(line("planaire lu comme entrelacé", bad, wrong))
        println(line("même voix, entrelacé vrai", good, interleaved))
        assertTrue(bad.correlation > 0.90, bad.correlation.toString())
        assertFalse(bad.opposed, "le planaire mal lu ne doit pas être dit opposé")
        assertFalse(bad.cancelled)
        assertTrue(good.cancelled)
    }

    @Test
    fun cinqUnVoixAuCentreNaPasEtreDiteAnnulee() {
        // G = voix, D = −voix, centre = voix. La sonde ne regarde que
        // les deux premières voies : elles s'opposent. Le dialogue, lui,
        // est au centre et survit à un repli qui l'ajoute.
        val frames = 48_000
        val ch = 6
        val pcm = ShortArray(frames * ch)
        for (i in 0 until frames) {
            val v = (AudioChannels.voice(i) * 0.55 * 32_767.0).toInt().coerceIn(-32767, 32767).toShort()
            val base = i * ch
            pcm[base] = v
            pcm[base + 1] = (-v.toInt()).toShort()
            pcm[base + 2] = v
        }
        val reading = measure(pcm, ch)
        println(line("5.1 G=−D et centre", reading, pcm))
        assertTrue(reading.opposed, "G et D s'opposent vraiment")
        assertFalse(reading.cancelled, "on ne dit pas la voix annulée : elle est au centre")
        val kept = AudioChannels.monoKeptWithCenter(pcm, ch)
        assertTrue(kept > 0.4, kept.toString())
    }

    @Test
    fun hautParleurGaucheSeulNeAnnulePas() {
        // Certains replis « jettent » la droite au lieu d'additionner.
        // L'opposition n'efface alors pas la voix.
        val pcm = AudioChannels.opposed(48_000)
        val kept = AudioChannels.monoKept(pcm, leftCoef = 1.0, rightCoef = 0.0)
        println("repli gauche seule, énergie gardée=$kept")
        assertEquals(1.0, kept, 1e-9)
        val call = AudioChannels.monoKept(pcm, leftCoef = AudioChannels.FOLD_LEFT, rightCoef = AudioChannels.FOLD_RIGHT)
        assertEquals(0.0, call, 1e-12)
    }

    @Test
    fun deuxMorceauxValsentLeMemeChiffre() {
        val pcm = AudioChannels.opposed(48_000)
        val cut = pcm.size / 2
        val one = AudioPhase.push(AudioPhase.start(), pcm, 2)
        val two = AudioPhase.push(
            AudioPhase.push(AudioPhase.start(), pcm.copyOfRange(0, cut), 2),
            pcm.copyOfRange(cut, pcm.size),
            2,
        )
        assertEquals(one, two)
        assertTrue(AudioPhase.judge(two, 2).cancelled)
    }

    @Test
    fun laChaineDeLAppNeMelangePasEtNinversePas() {
        val chain = source("ZunoAudioChain.kt")
        val array = chain.substringAfter("arrayOf<AudioProcessor>(").substringBefore(")")
        val order = listOf(
            "probeDecoder", "clearVoice", "probeVoice", "silence",
            "probeSilence", "sonic", "probeSink",
        )
        var at = -1
        for (name in order) {
            val i = array.indexOf(name)
            assertTrue(i > at, "$name devrait suivre dans $array")
            at = i
        }
        assertFalse(chain.contains("ChannelMixing"))
        val probe = source("AudioProbeProcessor.kt")
        assertTrue(probe.contains("output.put(inputBuffer)"))
        assertTrue(probe.contains("Le tampon d'entrée repart inchangé"))
        assertFalse(probe.contains("invert"))
        val view = source("NativeVideoView.kt")
        assertTrue(view.contains("setEnableFloatOutput(false)"))
        assertFalse(view.contains("ChannelMixingAudioProcessor"))
        val clear = source("ClearVoiceProcessor.kt")
        assertTrue(clear.contains("sample * applied"))
        assertTrue(clear.contains("if (!enabled) return AudioProcessor.AudioFormat.NOT_SET"))
    }

    private fun measure(pcm: ShortArray, channels: Int): AudioPhase.Reading {
        val acc = AudioPhase.push(AudioPhase.start(), pcm, channels)
        assertTrue(AudioPhase.ready(acc, 48_000), "frames=${acc.frames}")
        return AudioPhase.judge(acc, channels)
    }

    private fun energyOf(pcm: ShortArray, channel: Int, channels: Int = 2): Double {
        var e = 0.0
        var i = channel
        while (i < pcm.size) {
            val v = pcm[i].toDouble()
            e += v * v
            i += channels
        }
        return e
    }

    private fun sine(i: Int, hz: Double): Double = sin(2.0 * PI * hz * i / 48_000.0)

    private fun line(name: String, r: AudioPhase.Reading, pcm: ShortArray): String =
        "$name corr=${r.correlationText()} (G-D)/(G+D)=${r.levelText()} " +
            "energie=${r.sideText()} mono=${r.monoKeptText()} " +
            "oppose=${r.opposed} annule=${r.cancelled} " +
            "energieMix=${AudioChannels.energy(AudioChannels.fold(pcm, r.channels.coerceAtLeast(2)))}"

    private fun source(name: String): String {
        val rel = "com/manzilionellm/native_video_player/$name"
        val candidates = listOf(
            File("../android/src/main/kotlin/$rel"),
            File("android-app/packages/native_video_player/android/src/main/kotlin/$rel"),
            File("packages/native_video_player/android/src/main/kotlin/$rel"),
        )
        val file = candidates.firstOrNull { it.isFile }
            ?: error("introuvable $name dans ${File(".").absolutePath}")
        return file.readText()
    }
}
