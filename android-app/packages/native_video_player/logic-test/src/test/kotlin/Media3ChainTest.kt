import com.manzilionellm.native_video_player.logic.AudioDiagnosis
import com.manzilionellm.native_video_player.logic.AudioFixes
import com.manzilionellm.native_video_player.logic.AudioSnapshot
import com.manzilionellm.native_video_player.logic.Media3Chain
import com.manzilionellm.native_video_player.logic.ProbeAttach
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * La chaîne par défaut ne change pas. L'essai « Media3 nu » retire
 * les étages Zuno. On ne prétend pas avoir entendu le résultat.
 */
class Media3ChainTest {
    @Test
    fun leDefautNestPasLaFabriqueNue() {
        assertFalse(Media3Chain.useStockFactory(pure = false))
        assertFalse(AudioFixes.pureMedia3Chain)
        assertEquals("zuno.audio.chain.stock", Media3Chain.KEY)
    }

    @Test
    fun zunoAuReposEtMedia3AuReposEcriventLePcmTelQuel() {
        val zuno = Media3Chain.activeZunoStages(
            pure = false,
            probe = false,
            clearVoice = false,
            skipSilence = false,
            speed = 1f,
            pitch = 1f,
        )
        val stock = Media3Chain.activeStockUserStages(
            skipSilence = false,
            speed = 1f,
            pitch = 1f,
        )
        assertTrue(zuno.isEmpty(), zuno.toString())
        assertTrue(stock.isEmpty(), stock.toString())
        assertTrue(Media3Chain.straightToAudioTrack(zuno))
        assertTrue(Media3Chain.straightToAudioTrack(stock))
    }

    @Test
    fun lessaiIgnoreLesEtagesMemeSiOnLesAllume() {
        val actifs = Media3Chain.activeZunoStages(
            pure = true,
            probe = true,
            clearVoice = true,
            skipSilence = true,
            speed = 1.03f,
            pitch = 1.02f,
            sampleRateChanged = true,
        )
        assertTrue(actifs.isEmpty(), actifs.toString())
        assertTrue(Media3Chain.useStockFactory(pure = true))
    }

    @Test
    fun lesSondesEtLaVoixClaireNentrentQueSiOnLesAllume() {
        val sondes = Media3Chain.activeZunoStages(
            pure = false,
            probe = true,
            clearVoice = false,
            skipSilence = false,
            speed = 1f,
            pitch = 1f,
        )
        assertEquals(
            listOf(
                Media3Chain.STAGE_PROBE_DECODER,
                Media3Chain.STAGE_PROBE_VOICE,
                Media3Chain.STAGE_PROBE_SILENCE,
                Media3Chain.STAGE_PROBE_SINK,
            ),
            sondes,
        )
        val voix = Media3Chain.activeZunoStages(
            pure = false,
            probe = false,
            clearVoice = true,
            skipSilence = false,
            speed = 1f,
            pitch = 1f,
        )
        assertEquals(listOf(Media3Chain.STAGE_CLEAR), voix)
    }

    @Test
    fun sonicResteInactifAUnEtSallumeDesQueLaVitesseBouge() {
        assertFalse(Media3Chain.sonicActive(1f, 1f, sampleRateChanged = false))
        // Sous le seuil Media3 (0,0001) : toujours inactif.
        assertFalse(Media3Chain.sonicActive(1f + 0.00005f, 1f, sampleRateChanged = false))
        assertTrue(Media3Chain.sonicActive(0.97f, 1f, sampleRateChanged = false))
        assertTrue(Media3Chain.sonicActive(1.03f, 1f, sampleRateChanged = false))
        assertTrue(Media3Chain.sonicActive(1f, 1.01f, sampleRateChanged = false))
        val bougé = Media3Chain.activeZunoStages(
            pure = false,
            probe = false,
            clearVoice = false,
            skipSilence = false,
            speed = 0.97f,
            pitch = 1f,
        )
        assertEquals(listOf(Media3Chain.STAGE_SONIC), bougé)
        val stock = Media3Chain.activeStockUserStages(
            skipSilence = false,
            speed = 0.97f,
            pitch = 1f,
        )
        assertEquals(listOf(Media3Chain.STAGE_SONIC), stock)
    }

    @Test
    fun leSautDeSilenceEntreSeulementSiOnLeDemande() {
        val zuno = Media3Chain.activeZunoStages(
            pure = false,
            probe = false,
            clearVoice = false,
            skipSilence = true,
            speed = 1f,
            pitch = 1f,
        )
        assertEquals(listOf(Media3Chain.STAGE_SILENCE), zuno)
        val stock = Media3Chain.activeStockUserStages(
            skipSilence = true,
            speed = 1f,
            pitch = 1f,
        )
        assertEquals(listOf(Media3Chain.STAGE_SILENCE), stock)
    }

    @Test
    fun laFicheDitQuelleChaineTourne() {
        val habituel = AudioDiagnosis.report(AudioSnapshot(stockChain = false))
        assertTrue(habituel.contains("Chaîne : Zuno (défaut)"), habituel)
        assertFalse(habituel.contains("http"))
        val essai = AudioDiagnosis.report(AudioSnapshot(stockChain = true))
        assertTrue(essai.contains("Chaîne : essai Media3 par défaut"), essai)
        assertTrue(essai.contains("aucun étage Zuno") || essai.contains("sans étage Zuno"), essai)
        val absence = ProbeAttach.absence(
            requested = true,
            inChain = false,
            frames = 0,
            reject = ProbeAttach.REJECT_STOCK,
        )
        assertTrue(absence.symptom.contains("chaîne Media3 par défaut"), absence.symptom)
        assertTrue(AudioDiagnosis.report(
            AudioSnapshot(probeRequested = true, probeReject = ProbeAttach.REJECT_STOCK, stockChain = true),
        ).contains("retire les sondes"))
    }
}
