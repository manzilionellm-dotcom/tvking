import com.manzilionellm.native_video_player.logic.AacSource
import com.manzilionellm.native_video_player.logic.AudioDiagnosis
import com.manzilionellm.native_video_player.logic.AudioSnapshot
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Octets réels, relevés sur des fichiers de test (pas des flux du client) :
 *   • ASC de 2 octets, LC 22,05 kHz mono — forme du HE-AAC implicite ;
 *   • le même, plus l'extension 0x2b7 qui écrit le SBR ;
 *   • la même extension avec le bit SBR à 0 ;
 *   • ASC qui commence par le type 29 (HE-AAC v2 explicite) ;
 *   • ASC LC 48 kHz stéréo (ce que la fiche terrain annonce) ;
 *   • en-tête ADTS d'un HE-AAC v2 implicite (profil LC, 22,05 kHz, mono) ;
 *   • sync LOAS 56 E0.
 */
class AacSourceTest {

    @Test
    fun ascCourtEstUnLcMono22kHzDoncSbrImplicitePossible() {
        val r = AacSource.read(hex("1388"))
        assertEquals(2, r.audioObjectType)
        assertEquals("AAC-LC", r.profile)
        assertEquals(22_050, r.headerHz)
        assertEquals(1, r.channels)
        assertTrue(r.implicitCandidate)
        assertFalse(r.explicitSbr)
        assertEquals("ASC", r.container)
        val line = AacSource.describe(r)
        assertTrue(line.contains("SBR implicite à chercher"), line)
        assertTrue(line.contains("Débit annoncé : inconnu"), line)
        assertTrue(line.contains("Deux octets"), line)
        assertFalse(line.contains("http"), line)
    }

    @Test
    fun extensionEcritLeSbrMemeSiLePremierTypeEstLc() {
        val r = AacSource.read(hex("138856e5a0"))
        assertEquals(2, r.audioObjectType)
        assertTrue(r.explicitSbr, r.toString())
        assertEquals(22_050, r.headerHz)
        assertEquals(44_100, r.extensionHz)
        assertEquals(1, r.channels)
        assertFalse(r.implicitCandidate)
        assertTrue(AacSource.describe(r).contains("mp4a.40.2"), AacSource.describe(r))
        assertTrue(AacSource.describe(r).contains("SBR explicite : oui"), AacSource.describe(r))
    }

    @Test
    fun extensionPeutInterdireLeSbr() {
        val r = AacSource.read(hex("138856e500"))
        assertTrue(r.sbrForbidden, r.toString())
        assertFalse(r.explicitSbr)
        assertFalse(r.implicitCandidate)
        assertTrue(AacSource.describe(r).contains("déclare absent"), AacSource.describe(r))
    }

    @Test
    fun type29EstHeAacV2Explicite() {
        val r = AacSource.read(hex("eb8a0800"))
        assertEquals(29, r.audioObjectType)
        assertEquals("HE-AAC v2", r.profile)
        assertTrue(r.explicitPs)
        assertTrue(r.explicitSbr)
        assertEquals(22_050, r.headerHz)
        assertEquals(44_100, r.extensionHz)
        assertEquals(1, r.channels)
        assertFalse(r.implicitCandidate)
    }

    @Test
    fun lc48kHzStereoNeDemandePasDeChercherLeSbr() {
        val r = AacSource.read(hex("1190"), announcedBps = 0, formatHz = 48_000, formatChannels = 2)
        assertEquals(2, r.audioObjectType)
        assertEquals(48_000, r.headerHz)
        assertEquals(2, r.channels)
        assertFalse(r.implicitCandidate)
        assertFalse(r.explicitSbr)
        assertFalse(r.note.contains("ne dit pas la même chose"), r.note)
        val line = AacSource.describe(r)
        assertTrue(line.contains("au-dessus de 24 kHz"), line)
    }

    @Test
    fun frequenceDuFormatDifferenteDesOctetsEstDite() {
        val r = AacSource.read(hex("1190"), formatHz = 44_100, formatChannels = 2)
        assertTrue(r.note.contains("44,10 kHz") || r.note.contains("44.10"), r.note)
        assertTrue(r.note.contains("ne dit pas la même chose"), r.note)
    }

    @Test
    fun adtsDitLcMaisNePeutPasEcrireLeHeAacEtDonneLeDebit() {
        // En-tête réel : profil LC, 22 050 Hz, mono, trame de 138 octets.
        val r = AacSource.read(hex("fff95c4011420c"))
        assertEquals("ADTS", r.container)
        assertEquals(2, r.audioObjectType)
        assertEquals(22_050, r.headerHz)
        assertEquals(1, r.channels)
        assertTrue(r.implicitCandidate)
        assertEquals(138, r.frameBytes)
        assertEquals(AacSource.bitrateOfFrame(138, 22_050), r.measuredBps)
        assertTrue(r.measuredBps in 20_000..30_000, r.measuredBps.toString())
        val line = AacSource.describe(r)
        assertTrue(line.contains("2 bits de profil"), line)
        assertTrue(line.contains("Débit mesuré :"), line)
        assertFalse(line.contains("http"), line)
    }

    @Test
    fun loasNestPasUnAsc() {
        val r = AacSource.read(hex("56e0a720001190"))
        assertEquals("LOAS/LATM", r.container)
        assertFalse(r.explicitSbr)
        assertTrue(AacSource.describe(r).contains("56 E0") || AacSource.describe(r).contains("LOAS"), AacSource.describe(r))
    }

    @Test
    fun sansOctetsLeMimeNeTranchePasEntreAdtsEtLatm() {
        val r = AacSource.read(null, mime = "audio/mp4a-latm")
        assertEquals(0, r.bytes)
        val line = AacSource.describe(r)
        assertTrue(line.contains("audio/mp4a-latm"), line)
        assertTrue(line.contains("ne dit pas"), line)
    }

    @Test
    fun laFicheDitLaSignalisationSansChangerLaConclusionParDefaut() {
        val source = AacSource.read(hex("1190"), formatHz = 48_000, formatChannels = 2)
        val s = AudioSnapshot(
            mime = "audio/mp4a-latm",
            codecs = "mp4a.40.2",
            inSampleRate = 48_000,
            inChannels = 2,
            decoder = "ffmpeg6.0-aac",
            outSampleRate = 48_000,
            outChannels = 2,
            outEncoding = "PCM 16 bits",
            source = source,
        )
        val report = AudioDiagnosis.report(s)
        assertTrue(report.contains("Signalisation :"), report)
        assertTrue(report.contains("au-dessus de 24 kHz"), report)
        assertTrue(AudioDiagnosis.findings(s).any { it.id == "sbr_non_demande" })
        assertTrue(AudioDiagnosis.sureCauses(s).none { it.id == "sbr_non_demande" })
        assertFalse(report.contains("http"), report)
    }

    @Test
    fun enTeteMonoEtSortieStereoNestPasUnMonoDOrigine() {
        val source = AacSource.read(hex("1388"))
        val s = AudioSnapshot(
            mime = "audio/mp4a-latm",
            codecs = "mp4a.40.2",
            inSampleRate = 22_050,
            inChannels = 1,
            decoder = "ffmpeg6.0-aac",
            outSampleRate = 44_100,
            outChannels = 2,
            outEncoding = "PCM 16 bits",
            source = source,
        )
        val ids = AudioDiagnosis.findings(s).map { it.id }
        assertTrue("sbr_implicite" in ids, ids.toString())
        assertTrue("stereo_parametrique" in ids, ids.toString())
        assertFalse("source_mono" in ids, ids.toString())
        val arrows = AudioDiagnosis.verdicts(s).joinToString("\n")
        assertTrue(arrows.contains("stéréo paramétrique"), arrows)
        assertFalse(arrows.contains("MONO à l'origine"), arrows)
    }

    @Test
    fun debitMesureBasEstDitQuandRienNestAnnonce() {
        val source = AacSource.read(hex("fff95c4011420c"))
        val s = AudioSnapshot(
            mime = "audio/mp4a-latm",
            codecs = "mp4a.40.2",
            inSampleRate = 22_050,
            inChannels = 1,
            decoder = "ffmpeg6.0-aac",
            outSampleRate = 22_050,
            outChannels = 1,
            source = source,
        )
        assertTrue(AudioDiagnosis.findings(s).any { it.id == "debit_mesure_bas" })
        assertTrue(AudioDiagnosis.sureCauses(s).any { it.id == "debit_mesure_bas" })
        val report = AudioDiagnosis.report(s)
        assertTrue(report.contains("Débit mesuré : 23 kb/s"), report)
        assertNullSetting(s)
    }

    @Test
    fun sautDHorlogeEtPlusieursPistesSontEcrits() {
        val s = AudioSnapshot(
            mime = "audio/mp4a-latm",
            codecs = "mp4a.40.2",
            inSampleRate = 48_000,
            inChannels = 2,
            decoder = "ffmpeg6.0-aac",
            outSampleRate = 48_000,
            outChannels = 2,
            audioTrackCount = 2,
            ptsJumps = 3,
            ptsMaxAbsMs = 5_973,
        )
        val report = AudioDiagnosis.report(s)
        assertTrue(report.contains("Pistes audio annoncées : 2"), report)
        assertTrue(report.contains("5973"), report)
        assertTrue(AudioDiagnosis.findings(s).any { it.id == "plusieurs_pistes" })
        val jump = AudioDiagnosis.findings(s).first { it.id == "sauts_horloge" }
        assertEquals(AudioDiagnosis.Confidence.INCERTAINE, jump.confidence)
        assertEquals(null, jump.fix.settingKey)
    }

    private fun assertNullSetting(s: AudioSnapshot) {
        val f = AudioDiagnosis.findings(s).first { it.id == "debit_mesure_bas" }
        assertEquals(null, f.fix.settingKey)
    }

    private fun hex(s: String): ByteArray {
        val out = ByteArray(s.length / 2)
        var i = 0
        while (i < out.size) {
            out[i] = s.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            i++
        }
        return out
    }
}
