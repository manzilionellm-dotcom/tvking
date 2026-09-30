import com.manzilionellm.native_video_player.logic.AudioDiagnosis
import com.manzilionellm.native_video_player.logic.AudioSnapshot
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class AudioDiagnosisTest {
    private val heAacBox = AudioSnapshot(
        mime = "audio/mp4a-latm", codecs = "mp4a.40.5", inSampleRate = 24_000, inChannels = 2,
        decoder = "OMX.amlogic.aac.decoder", outSampleRate = 24_000, outChannels = 1,
        outEncoding = "PCM 16 bits",
    )

    @Test
    fun vieilleRadioProuveeQuandLaBoxSortA24kHz() {
        val v = AudioDiagnosis.verdicts(heAacBox)
        assertTrue(v[0].startsWith("BOX : son sorti à 24 kHz"), v.toString())
        assertTrue(v.any { it.contains("MONO → stéréo perdue") }, v.toString())
    }

    @Test
    fun ffmpegQuiReconstruitLes48kHzNestPasAccuse() {
        val ok = heAacBox.copy(decoder = "ffmpeg6.0-aac", outSampleRate = 48_000, outChannels = 2)
        val v = AudioDiagnosis.verdicts(ok)
        assertTrue(v.none { it.startsWith("BOX") }, v.toString())
        assertTrue(v.last().startsWith("Rien d'anormal côté app"), v.toString())
    }

    @Test
    fun defautsDeLaSource() {
        val src = AudioSnapshot(
            mime = "audio/mpeg-L2", inSampleRate = 22_050, inChannels = 1, bitrate = 64_000,
            decoder = "ffmpeg6.0-mp2", outSampleRate = 22_050, outChannels = 1, outEncoding = "PCM 16 bits",
        )
        val v = AudioDiagnosis.verdicts(src)
        assertTrue(v.any { it.startsWith("SOURCE : le flux est MONO") }, v.toString())
        assertTrue(v.any { it.startsWith("SOURCE : débit audio faible (64 kb/s)") }, v.toString())
        assertTrue(v.any { it.startsWith("SOURCE : son échantillonné à 22,1 kHz") }, v.toString())
    }

    @Test
    fun coupuresEtPassthrough() {
        val v = AudioDiagnosis.verdicts(
            AudioSnapshot(mime = "audio/ac3", passthrough = true, outEncoding = "AC-3", underruns = 3),
        )
        assertTrue(v.any { it.startsWith("SORTIE : 3 coupure(s)") }, v.toString())
        assertTrue(v.any { it.startsWith("Info : son Dolby/DTS") }, v.toString())
    }

    @Test
    fun ligneFactuelle() {
        assertEquals(
            "reçu : HE-AAC 24 kHz 2 voies · décodé par : box (OMX.amlogic.aac.decoder) · sortie : PCM 16 bits 24 kHz mono",
            AudioDiagnosis.describe(heAacBox),
        )
        assertEquals("HE-AAC v2", AudioDiagnosis.aacProfile("mp4a.40.29"))
        assertEquals("AAC-LC", AudioDiagnosis.aacProfile("mp4a.40.2"))
    }
}
