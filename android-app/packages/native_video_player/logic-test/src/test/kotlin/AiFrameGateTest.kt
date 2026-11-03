import com.manzilionellm.native_video_player.logic.AiBenchmarkReport
import com.manzilionellm.native_video_player.logic.AiBypassReason
import com.manzilionellm.native_video_player.logic.AiFrameGate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AiFrameGateTest {
    private val model = "244df05bf44edfef802db7195ef9f072384b8ee35afadb9a7ed22c4a311edc44"
    private val driver = "pilote-de-test"

    private fun report(ns: Long = 5_000_000L) = AiBenchmarkReport(
        model, driver, 640, 360, 4, 5, List(20) { ns },
        completionSynchronized = true, numericalCheckPassed = true,
    )

    private fun gate(fps: Double = 60.0, gpu: Boolean = true, hdr: Boolean = false,
                     memory: Long? = 1_000_000_000L, maxTexture: Int = 8192): AiFrameGate {
        val result = AiFrameGate(model, driver)
        result.configure(640, 360, 4, maxTexture, 100_000_000L, memory, gpu, hdr, fps)
        return result
    }

    @Test
    fun toutesLesPreuvesValidesActiventReellementLeTraitementSansAutreFlag() {
        val gate = gate()
        gate.loadBenchmark(report())
        assertTrue(gate.shouldProcess(), "Régression : une box éligible ne doit pas perdre l'IA sans raison.")
        assertNull(gate.decision.reason)
        assertEquals(333, gate.decision.score)
        assertEquals(5.0, gate.decision.p95Ms)
    }

    @Test
    fun avantLaMesureLeRenduNatifResteChoisiPuisLaPreuveAutoriseLia() {
        val gate = gate()
        assertFalse(gate.shouldProcess())
        assertEquals(AiBypassReason.BENCHMARK_MISSING, gate.decision.reason)
        gate.loadBenchmark(report())
        assertTrue(gate.shouldProcess())
    }

    @Test
    fun uneMesurePour30ImagesSecondeNeSuffitPasPour60() {
        val thirty = gate(fps = 30.0)
        val sixty = gate(fps = 60.0)
        thirty.loadBenchmark(report(10_000_000L))
        sixty.loadBenchmark(report(10_000_000L))
        assertTrue(thirty.shouldProcess())
        assertFalse(sixty.shouldProcess())
        assertEquals(AiBypassReason.TOO_SLOW, sixty.decision.reason)
        assertEquals(166, sixty.decision.score)
    }

    @Test
    fun unSeulPicHorsBudgetRefuseUnBenchmarkDontLeP95EstBon() {
        val gate = gate()
        gate.loadBenchmark(report().copy(completedFrameNs = List(19) { 5_000_000L } + 20_000_000L))
        assertEquals(AiBypassReason.TOO_SLOW, gate.decision.reason)
    }

    @Test
    fun aucuneExtrapolationDuneTuileOuDunAutreModeleOuPilote() {
        val cases = listOf(
            report().copy(width = 128, height = 128) to AiBypassReason.BENCHMARK_OTHER_SIZE,
            report().copy(scale = 2) to AiBypassReason.BENCHMARK_OTHER_SIZE,
            report().copy(modelSha256 = "autres-poids") to AiBypassReason.BENCHMARK_OTHER_MODEL,
            report().copy(driverId = "autre-pilote") to AiBypassReason.BENCHMARK_OTHER_DRIVER,
        )
        for ((report, reason) in cases) {
            val gate = gate()
            gate.loadBenchmark(report)
            assertFalse(gate.shouldProcess())
            assertEquals(reason, gate.decision.reason)
        }
    }

    @Test
    fun niTempsDeSoumissionNiMesureIncompleteNiPixelsInvalidesNeSuffisent() {
        val cases = listOf(
            report().copy(completionSynchronized = false) to AiBypassReason.BENCHMARK_INCOMPLETE,
            report().copy(warmupFrames = 4) to AiBypassReason.BENCHMARK_INCOMPLETE,
            report().copy(completedFrameNs = List(19) { 1L }) to AiBypassReason.BENCHMARK_INCOMPLETE,
            report().copy(completedFrameNs = List(20) { 0L }) to AiBypassReason.BENCHMARK_INCOMPLETE,
            report().copy(numericalCheckPassed = false) to AiBypassReason.NUMERICAL_CHECK_FAILED,
        )
        for ((report, reason) in cases) {
            val gate = gate()
            gate.loadBenchmark(report)
            assertEquals(reason, gate.decision.reason)
        }
    }

    @Test
    fun hdrDrmGpuMemoireEtTailleRestentDesRefusReelsMemeAvecUnBonScore() {
        val cases = listOf(
            gate(hdr = true) to AiBypassReason.HDR_OR_DRM,
            gate(gpu = false) to AiBypassReason.GPU_UNSUPPORTED,
            gate(memory = null) to AiBypassReason.MEMORY_UNKNOWN,
            gate(memory = 200_000_000L) to AiBypassReason.MEMORY_LOW,
            gate(maxTexture = 2048) to AiBypassReason.OUTPUT_TOO_LARGE,
        )
        for ((gate, reason) in cases) {
            gate.loadBenchmark(report())
            assertFalse(gate.shouldProcess())
            assertEquals(reason, gate.decision.reason)
        }
    }

    @Test
    fun uneCadenceInconnueGardeLeBudgetPrudentDe60ImagesSeconde() {
        for (fps in listOf(0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            val gate = gate(fps)
            gate.loadBenchmark(report(10_000_000L))
            assertFalse(gate.shouldProcess())
        }
    }

    @Test
    fun erreurOuDepassementEnLectureCoupeLiaEtUnRapportTardifNeLaRallumePas() {
        for ((elapsed, success, reason) in listOf(
            Triple(1L, false, AiBypassReason.INFERENCE_FAILED),
            Triple(20_000_000L, true, AiBypassReason.FRAME_DEADLINE),
        )) {
            val gate = gate()
            gate.loadBenchmark(report())
            gate.record(elapsed, success)
            assertFalse(gate.shouldProcess())
            assertEquals(reason, gate.decision.reason)
            gate.loadBenchmark(report())
            assertFalse(gate.shouldProcess())
            assertEquals(reason, gate.decision.reason)
        }
    }

    @Test
    fun perteDeMargeDurableCoupeMaisTempsNormauxNeDesactiventPasSansRaison() {
        val healthy = gate()
        healthy.loadBenchmark(report())
        repeat(100) { healthy.record(5_000_000L, true) }
        assertTrue(healthy.shouldProcess())
        assertNull(healthy.decision.reason)
        repeat(20) { healthy.record(10_000_000L, true) }
        assertFalse(healthy.shouldProcess())
        assertEquals(AiBypassReason.MARGIN_LOST, healthy.decision.reason)
    }
}
