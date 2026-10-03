package com.manzilionellm.native_video_player.logic

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Mise en forme de la fiche « effets système ».
 * Aucun Android : on vérifie les phrases, pas le son.
 */
class AudioSystemEffectsTest {

    private val dolby = AudioSystemEffects.Engine(
        name = "Dolby Audio Processing",
        implementor = "Dolby Laboratories",
        typeUuid = "11111111-2222-3333-4444-555555555555",
        connectMode = AudioSystemEffects.CONNECT_POST,
    )
    private val eq = AudioSystemEffects.Engine(
        name = "Equalizer",
        implementor = "The Android Open Source Project",
        typeUuid = AudioSystemEffects.TYPE_EQUALIZER,
        connectMode = AudioSystemEffects.CONNECT_INSERT,
    )
    private val ns = AudioSystemEffects.Engine(
        name = "Noise Suppression",
        implementor = "AOSP",
        typeUuid = AudioSystemEffects.TYPE_NS,
        connectMode = AudioSystemEffects.CONNECT_PRE,
    )
    private val virt = AudioSystemEffects.Engine(
        name = "Virtualizer",
        implementor = "AOSP",
        typeUuid = AudioSystemEffects.TYPE_VIRTUALIZER,
        connectMode = AudioSystemEffects.CONNECT_INSERT,
    )

    private fun quietSheet() = AudioSystemEffects.Sheet(
        sessionId = 42,
        engines = listOf(eq, virt),
        catalogRead = true,
        outputSampleRate = 48_000,
        framesPerBuffer = 960,
        micMuted = true,
        spatial = AudioSystemEffects.Spatial(
            level = AudioSystemEffects.SPATIALIZER_NONE,
            available = false,
            enabled = false,
            headTracker = false,
            stereoMovie = false,
            fiveOneMovie = false,
        ),
        plays = listOf(ourMovie()),
        mode = AudioRouteState.MODE_NORMAL,
    )

    private fun ourMovie(flags: Int = 0, complete: Boolean = true) = AudioSystemEffects.Play(
        usage = AudioRouteState.USAGE_MEDIA,
        contentType = AudioRouteState.CONTENT_MOVIE,
        flags = flags,
        flagsComplete = complete,
        deviceType = AudioRouteState.TYPE_HDMI,
        deviceName = "TV",
        ours = true,
    )

    @Test
    fun unEgaliseurPresentNestPasUnEffetAllume() {
        val block = AudioSystemEffects.block(quietSheet())
        assertTrue(block.contains("Égaliseur « Equalizer » (dans la piste"), block)
        assertTrue(block.contains("Présent ne veut pas dire allumé"), block)
        assertTrue(block.contains("Session de Zuno n°42"), block)
        assertTrue(block.contains("On n'en crée pas"), block)
        assertTrue(block.contains("48000 Hz"), block)
        assertTrue(block.contains("960 trames"), block)
        assertTrue(block.contains("Micro : muet"), block)
        assertTrue(block.contains("Spatialiseur : niveau aucun, activé non"), block)
        assertTrue(block.contains("cette app, musique (contenu film)"), block)
        assertTrue(block.contains("sortie HDMI « TV »"), block)
        assertNull(AudioSystemEffects.suspect(quietSheet()))
    }

    @Test
    fun unDolbyDansLeCatalogueNeDeclenchePasLeSuspect() {
        val sheet = quietSheet().copy(engines = listOf(dolby, eq))
        val block = AudioSystemEffects.block(sheet)
        assertTrue(block.contains("Effet fabricant « Dolby Audio Processing »"), block)
        assertTrue(block.contains("après le mixage"), block)
        assertEquals("Effet fabricant", AudioSystemEffects.family(dolby))
        assertNull(AudioSystemEffects.suspect(sheet))
    }

    @Test
    fun leSpatialiseurAllumeSurUnFilmStereoEstUnIndice() {
        val sheet = quietSheet().copy(
            spatial = AudioSystemEffects.Spatial(
                level = AudioSystemEffects.SPATIALIZER_OTHER,
                available = true,
                enabled = true,
                headTracker = false,
                stereoMovie = true,
                fiveOneMovie = false,
            ),
        )
        val suspect = AudioSystemEffects.suspect(sheet)
        assertTrue(suspect != null)
        assertTrue(suspect!!.symptom.contains("spatialiseur activé"), suspect.symptom)
        assertTrue(suspect.cause.contains("après l'AudioTrack"), suspect.cause)
        val block = AudioSystemEffects.block(sheet)
        assertTrue(block.contains("niveau autre, activé oui"), block)
        assertTrue(block.contains("film stéréo spatialisable oui"), block)
    }

    @Test
    fun unSpatialiseurAllumeQuiRefuseLeStereoNeSuffitPas() {
        val sheet = quietSheet().copy(
            spatial = AudioSystemEffects.Spatial(
                level = AudioSystemEffects.SPATIALIZER_MULTICHANNEL,
                available = true,
                enabled = true,
                headTracker = null,
                stereoMovie = false,
                fiveOneMovie = true,
            ),
        )
        assertNull(AudioSystemEffects.suspect(sheet))
        assertTrue(
            AudioSystemEffects.block(sheet).contains("film stéréo spatialisable non"),
        )
        assertTrue(AudioSystemEffects.block(sheet).contains("film 5.1 spatialisable oui"))
    }

    @Test
    fun leModeAppelEtLeMicroOuvertSontDits() {
        val sheet = quietSheet().copy(
            mode = AudioRouteState.MODE_IN_COMMUNICATION,
            micMuted = false,
            engines = listOf(ns, eq),
        )
        val block = AudioSystemEffects.block(sheet)
        assertTrue(block.contains("Réduction de bruit « Noise Suppression » (avant le micro"), block)
        assertTrue(block.contains("Micro : ouvert"), block)
        val suspect = AudioSystemEffects.suspect(sheet)
        assertTrue(suspect != null)
        assertTrue(suspect!!.symptom.contains("mode communication"), suspect.symptom)
        assertTrue(suspect.symptom.contains("micro ouvert"), suspect.symptom)
    }

    @Test
    fun seizeKiloHertzEstUneFrequenceDeTelephonie() {
        val sheet = quietSheet().copy(outputSampleRate = 16_000, framesPerBuffer = 256)
        val block = AudioSystemEffects.block(sheet)
        assertTrue(block.contains("16000 Hz ⚠ fréquence de téléphonie"), block)
        assertTrue(block.contains("256 trames"), block)
        assertTrue(AudioSystemEffects.suspect(sheet)!!.symptom.contains("16000 Hz"))
    }

    @Test
    fun leDrapeauScoEstUnCheminDappel() {
        val sheet = quietSheet().copy(
            plays = listOf(ourMovie(flags = AudioSystemEffects.FLAG_SCO, complete = true)),
        )
        val block = AudioSystemEffects.block(sheet)
        assertTrue(block.contains("drapeaux SCO appel"), block)
        assertTrue(AudioSystemEffects.suspect(sheet)!!.symptom.contains("SCO"))
    }

    @Test
    fun lesDrapeauxPublicsSeulsSontNommes() {
        val label = AudioSystemEffects.flagsLabel(
            AudioSystemEffects.FLAG_LOW_LATENCY or AudioSystemEffects.FLAG_HW_AV_SYNC,
            complete = false,
        )
        assertEquals("synchro image, faible latence (publics seulement)", label)
        assertEquals("aucun (publics seulement)", AudioSystemEffects.flagsLabel(0, complete = false))
        assertEquals("aucun", AudioSystemEffects.flagsLabel(0, complete = true))
    }

    @Test
    fun uneAutreApplicationEstComptee() {
        val other = ourMovie().copy(
            ours = false,
            usage = AudioRouteState.USAGE_VOICE_COMMUNICATION,
            contentType = AudioRouteState.CONTENT_SPEECH,
            deviceType = AudioRouteState.TYPE_BUILTIN_EARPIECE,
            deviceName = "",
        )
        val sheet = quietSheet().copy(plays = listOf(ourMovie(), other))
        val block = AudioSystemEffects.block(sheet)
        assertTrue(block.contains("Lectures annoncées : 2."), block)
        assertTrue(block.contains("une autre application, appel (contenu parole)"), block)
        assertTrue(block.contains("écouteur d'appel"), block)
        assertTrue(AudioSystemEffects.suspect(sheet)!!.symptom.contains("1 autre"))
    }

    @Test
    fun leCatalogueVideEtLaLectureRateeNeDisentPasLaMemeChose() {
        val unread = AudioSystemEffects.block(AudioSystemEffects.Sheet())
        assertTrue(unread.contains("Catalogue queryEffects : pas lu."))
        assertTrue(unread.contains("Session de Zuno : pas encore connue."))
        assertTrue(unread.contains("Micro : état non lu."))
        assertTrue(unread.contains("Spatialiseur : pas lu"))
        assertTrue(unread.contains("Lectures annoncées : aucune"))
        val failed = AudioSystemEffects.block(
            AudioSystemEffects.Sheet(catalogFailed = true, catalogRead = false),
        )
        assertTrue(failed.contains("Catalogue queryEffects : lecture ratée."))
        val empty = AudioSystemEffects.block(
            AudioSystemEffects.Sheet(catalogRead = true, engines = emptyList()),
        )
        assertTrue(empty.contains("aucun moteur déclaré"))
    }

    @Test
    fun huitMoteursPuisLeCompteDesAutres() {
        val many = (1..10).map { i ->
            eq.copy(name = "Effet $i", typeUuid = "pas-un-type-connu")
        }
        val block = AudioSystemEffects.block(
            quietSheet().copy(engines = many, catalogRead = true),
        )
        assertTrue(block.contains("10 moteur(s)"), block)
        assertTrue(block.contains("… et 2 autre(s)"), block)
        assertFalse(block.contains("Effet 10"))
    }

    @Test
    fun aucuneLigneNeCommenceCommeUnJournal() {
        val block = AudioSystemEffects.block(
            quietSheet().copy(
                engines = listOf(dolby, ns, virt, eq),
                mode = AudioRouteState.MODE_IN_CALL,
            ),
        )
        val forbidden = listOf(
            "Seconde ",
            "Zap :",
            "Focus audio",
            "Repli :",
            "AudioTrack ",
            "Session audio",
            "Annonces :",
            "Sonde :",
            "Arrière-plan",
            "Retour :",
            "Libération",
            "Décodeur audio :",
            "Erreur ",
        )
        for (line in block.lines()) {
            for (start in forbidden) {
                assertFalse(line.startsWith(start), line)
            }
        }
        assertFalse(block.contains("http"))
        assertFalse(block.contains("password"))
    }

    @Test
    fun laFichePorteLeBlocEtLeSuspectSansReglage() {
        val sheet = quietSheet().copy(
            mode = AudioRouteState.MODE_IN_CALL,
            outputSampleRate = 8_000,
        )
        val report = AudioDiagnosis.report(
            AudioSnapshot(
                mime = "audio/mp4a-latm",
                codecs = "mp4a.40.2",
                inSampleRate = 48_000,
                inChannels = 2,
                decoder = "ffmpeg6.0-aac",
                outSampleRate = 48_000,
                outChannels = 2,
                outEncoding = "PCM 16 bits",
                effects = sheet,
            ),
        )
        assertTrue(report.contains("Effets système (lecture seule"), report)
        assertTrue(report.contains("[INCERTAINE · INFO] effet_systeme"), report)
        assertTrue(report.contains("8000 Hz"), report)
        assertFalse(report.contains("Réglage :"), report)
        assertTrue(AudioDiagnosis.sureCauses(AudioSnapshot(effects = sheet)).isEmpty())
        val redacted = AudioDiagnosis.redact(
            AudioSystemEffects.block(
                quietSheet().copy(
                    engines = listOf(eq.copy(name = "http://secret.example/eq password=abc")),
                ),
            ),
        )
        assertFalse(redacted.contains("http://"))
        assertFalse(redacted.contains("password=abc"))
    }
}
