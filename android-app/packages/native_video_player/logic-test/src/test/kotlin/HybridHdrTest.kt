import com.manzilionellm.native_video_player.logic.HybridHdr
import com.manzilionellm.native_video_player.logic.HybridHdrFilter
import com.manzilionellm.native_video_player.logic.HybridHdrMode
import com.manzilionellm.native_video_player.logic.HybridHdrPath
import com.manzilionellm.native_video_player.logic.HybridHdrReport
import com.manzilionellm.native_video_player.logic.HybridHdrScope
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import kotlin.random.Random
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Film « Dolby Vision + HDR10+ » sur les clés Amazon MT8696 : écran d'une
 * seule couleur, le son continue. Ces tests fabriquent de vraies unités
 * d'accès HEVC (Annex B) à la main : aucun film, aucun flux fournisseur.
 */
class HybridHdrTest {
    @AfterTest
    fun defauts() {
        HybridHdr.autoOff = false
        HybridHdr.manual = false
        HybridHdr.forcedScope = null
    }

    // ---- Quel appareil -----------------------------------------------------

    @Test
    fun lesTroisClesAmazonEnDefautRecoiventLeCorrectif() {
        for (model in listOf("AFTKA", "AFTKM", "AFTKRT", "aftka", " AFTKRT ")) {
            assertEquals(
                HybridHdrScope.FIX,
                HybridHdr.scope("Amazon", model, "mt8696", "kara", null),
                model,
            )
            // Le modèle suffit : certaines versions ne donnent pas la puce.
            assertEquals(HybridHdrScope.FIX, HybridHdr.scope("Amazon", model, "qcom", null, null), model)
        }
    }

    @Test
    fun autreAppareilAmazon_onObserveSansModifier() {
        assertEquals(HybridHdrScope.WATCH, HybridHdr.scope("Amazon", "AFTMM", "mt8695", "mantis", null))
        assertEquals(HybridHdrScope.WATCH, HybridHdr.scope("amazon", "AFTSSS", null, null, null))
    }

    @Test
    fun laPuceMt8696SuffitQuelleQueSoitLaMarque() {
        assertEquals(
            HybridHdrScope.FIX,
            HybridHdr.scope("Google", "Google TV Streamer", "kirkwood", "kirkwood", "MT8696"),
        )
        assertEquals(HybridHdrScope.FIX, HybridHdr.scope("Onn", "box", "mt8696", null, null))
        assertEquals(HybridHdrScope.FIX, HybridHdr.scope(null, null, null, "MT8696B", null))
    }

    @Test
    fun boxOrdinaire_rienNEstLu() {
        assertEquals(HybridHdrScope.NONE, HybridHdr.scope("Xiaomi", "MIBOX4", "amlogic", "once", null))
        assertEquals(HybridHdrScope.NONE, HybridHdr.scope(null, null, null, null, null))
        // Un modèle de la liste chez une autre marque n'est pas une clé Amazon.
        assertEquals(HybridHdrScope.NONE, HybridHdr.scope("Acme", "AFTKA", null, null, null))
    }

    @Test
    fun leTestInstrumentePeutForcerLAppareil() {
        HybridHdr.forcedScope = HybridHdrScope.FIX
        assertEquals(HybridHdrScope.FIX, HybridHdr.scope("Google", "sdk_gphone64_x86_64", "ranchu", null, null))
    }

    // ---- Quel niveau -------------------------------------------------------

    @Test
    fun niveauSelonAppareilReglageEtRepli() {
        assertEquals(HybridHdrMode.AUTO, HybridHdr.mode(HybridHdrScope.FIX, manual = false, autoOff = false))
        assertEquals(HybridHdrMode.WATCH, HybridHdr.mode(HybridHdrScope.WATCH, manual = false, autoOff = false))
        assertNull(HybridHdr.mode(HybridHdrScope.NONE, manual = false, autoOff = false))
        // Repli : l'automatique redevient l'ancien comportement.
        assertNull(HybridHdr.mode(HybridHdrScope.FIX, manual = false, autoOff = true))
        assertNull(HybridHdr.mode(HybridHdrScope.WATCH, manual = false, autoOff = true))
        // Le réglage de la personne passe avant tout, sur n'importe quelle box.
        for (scope in HybridHdrScope.values()) {
            assertEquals(HybridHdrMode.STRICT, HybridHdr.mode(scope, manual = true, autoOff = false))
            assertEquals(HybridHdrMode.STRICT, HybridHdr.mode(scope, manual = true, autoOff = true))
        }
    }

    @Test
    fun niveauLitLesReglagesCourantsParDefaut() {
        assertEquals(HybridHdrMode.AUTO, HybridHdr.mode(HybridHdrScope.FIX))
        HybridHdr.autoOff = true
        assertNull(HybridHdr.mode(HybridHdrScope.FIX))
        HybridHdr.manual = true
        assertEquals(HybridHdrMode.STRICT, HybridHdr.mode(HybridHdrScope.NONE))
    }

    // ---- Quel décodeur -----------------------------------------------------

    @Test
    fun cheminSelonLeDecodeurChoisi() {
        assertEquals(HybridHdrPath.HEVC_DECODER, HybridHdr.path("video/hevc", "hvc1.2.4.L153.B0", "video/hevc"))
        assertEquals(HybridHdrPath.HEVC_DECODER, HybridHdr.path("video/hevc", null, "video/hevc"))
        // Dolby Vision déclaré, téléviseur sans Dolby : Media3 prend le HEVC.
        assertEquals(HybridHdrPath.HEVC_DECODER, HybridHdr.path("video/dolby-vision", "dvhe.08.06", "video/hevc"))
        assertEquals(HybridHdrPath.DOLBY_DECODER, HybridHdr.path("video/dolby-vision", "dvhe.08.06", "video/dolby-vision"))
        assertEquals(HybridHdrPath.DOLBY_DECODER, HybridHdr.path("video/dolby-vision", "dvh1.05.06", "VIDEO/Dolby-Vision"))
    }

    @Test
    fun autresCodecs_leFiltreNEstPasBranche() {
        assertNull(HybridHdr.path("video/avc", "avc1.640028", "video/avc"))
        assertNull(HybridHdr.path("video/av01", null, "video/av01"))
        // Dolby Vision sur H.264 ou AV1 : ce ne sont pas des unités HEVC.
        assertNull(HybridHdr.path("video/dolby-vision", "dvav.09.05", "video/dolby-vision"))
        assertNull(HybridHdr.path("video/dolby-vision", "dav1.10.09", "video/dolby-vision"))
        assertNull(HybridHdr.path("video/dolby-vision", "dvav.09.05", "video/avc"))
        // Base inconnue : on ne devine pas.
        assertNull(HybridHdr.path("video/dolby-vision", null, "video/dolby-vision"))
        assertNull(HybridHdr.path(null, null, null))
        assertNull(HybridHdr.path("video/mv-hevc", null, "video/hevc"))
    }

    // ---- Recherche du code de départ ---------------------------------------

    @Test
    fun codeDeDepartTrouveAToutesLesPositions() {
        for (at in 0..12) {
            val bytes = ByteArray(20) { 0x55 }
            bytes[at] = 0
            bytes[at + 1] = 0
            bytes[at + 2] = 1
            assertEquals(at, HybridHdrFilter.findStartCode(ByteBuffer.wrap(bytes), 0, bytes.size), "position $at")
        }
    }

    @Test
    fun codeDeDepartAbsentOuCoupe() {
        assertEquals(-1, HybridHdrFilter.findStartCode(ByteBuffer.wrap(byteArrayOf(0, 0)), 0, 2))
        assertEquals(-1, HybridHdrFilter.findStartCode(ByteBuffer.wrap(byteArrayOf(1, 0, 0, 2, 0, 0, 3, 0, 0)), 0, 9))
        // Le « 01 » est hors de la limite donnée.
        assertEquals(-1, HybridHdrFilter.findStartCode(ByteBuffer.wrap(byteArrayOf(9, 0, 0, 1)), 0, 3))
        assertEquals(1, HybridHdrFilter.findStartCode(ByteBuffer.wrap(byteArrayOf(9, 0, 0, 1)), 0, 4))
        // Zéros en série devant le code : on rend la position du dernier « 00 00 01 ».
        assertEquals(3, HybridHdrFilter.findStartCode(ByteBuffer.wrap(byteArrayOf(0, 0, 0, 0, 0, 1, 7)), 0, 7))
    }

    // ---- Le défaut : flux hybride sur décodeur HEVC ------------------------

    @Test
    fun auto_hevc_hybride_lesDeuxJeuxPartent_lImageNeChangePas() {
        val slice = slice(IDR, 900, seed = 1)
        val unit = accessUnit(aud(), vps(), sps(), pps(), hdr10PlusSei(), slice, rpu())
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.HEVC_DECODER)
        val out = run(filter, unit, keyFrame = true)
        assertContentEquals(accessUnit(aud(), vps(), sps(), pps(), slice), out)
        assertTrue(filter.hybrid)
        assertEquals(1, filter.removedHdr10Plus)
        assertEquals(1, filter.removedDolbyVision)
    }

    @Test
    fun auto_hevc_imagesSuivantes_toujoursNettoyees() {
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.HEVC_DECODER)
        run(filter, accessUnit(vps(), sps(), pps(), hdr10PlusSei(), slice(IDR, 500, 2), rpu()), keyFrame = true)
        // Bien après la fenêtre d'observation, et sans image clé.
        repeat(40) { n ->
            val picture = slice(TRAIL, 200 + n, seed = 10 + n)
            val out = run(filter, accessUnit(hdr10PlusSei(), picture, rpu()), keyFrame = false)
            assertContentEquals(accessUnit(picture), out, "image $n")
        }
        assertEquals(41, filter.removedHdr10Plus)
        assertEquals(41, filter.removedDolbyVision)
    }

    @Test
    fun auto_hevc_hdr10PlusSeul_rienNeBouge() {
        val unit = accessUnit(aud(), vps(), sps(), pps(), hdr10PlusSei(), slice(IDR, 700, 3))
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.HEVC_DECODER)
        assertUntouched(filter, unit, keyFrame = true)
        assertTrue(filter.sawHdr10Plus)
        assertFalse(filter.sawDolbyVision)
        assertFalse(filter.hybrid)
    }

    @Test
    fun auto_hevc_dolbyVisionSeul_rienNeBouge() {
        val unit = accessUnit(vps(), sps(), pps(), slice(IDR, 700, 4), rpu())
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.HEVC_DECODER)
        assertUntouched(filter, unit, keyFrame = true)
        assertTrue(filter.sawDolbyVision)
        assertFalse(filter.hybrid)
    }

    @Test
    fun auto_hevc_sdr_rienNeBouge() {
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.HEVC_DECODER)
        assertUntouched(filter, accessUnit(aud(), vps(), sps(), pps(), slice(IDR, 2_000, 5)), keyFrame = true)
        repeat(30) { assertUntouched(filter, accessUnit(slice(TRAIL, 300, 6 + it)), keyFrame = false) }
        assertFalse(filter.sawDolbyVision)
        assertFalse(filter.sawHdr10Plus)
    }

    @Test
    fun auto_hevc_secondeCoucheDolby_partAussi() {
        val base = slice(IDR, 600, 7)
        val unit = accessUnit(vps(), sps(), pps(), hdr10PlusSei(), base, dolbyLayer(400), dolbyLayer(120), rpu())
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.HEVC_DECODER)
        assertContentEquals(accessUnit(vps(), sps(), pps(), base), run(filter, unit, keyFrame = true))
        assertEquals(3, filter.removedDolbyVision)
    }

    @Test
    fun auto_hevc_hdr10PlusArriveApresLeDolby_leNettoyageCommenceALImageCle() {
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.HEVC_DECODER)
        // Début Dolby Vision seul : pas hybride, on ne touche pas.
        assertUntouched(filter, accessUnit(vps(), sps(), pps(), slice(IDR, 300, 8), rpu()), keyFrame = true)
        repeat(20) { assertUntouched(filter, accessUnit(slice(TRAIL, 100, 9 + it), rpu()), keyFrame = false) }
        // Une image clé apporte HDR10+ : le flux devient hybride.
        val key = slice(IDR, 300, 40)
        assertContentEquals(
            accessUnit(vps(), sps(), pps(), key),
            run(filter, accessUnit(vps(), sps(), pps(), hdr10PlusSei(), key, rpu()), keyFrame = true),
        )
        val next = slice(TRAIL, 100, 41)
        assertContentEquals(accessUnit(next), run(filter, accessUnit(next, rpu()), keyFrame = false))
    }

    // ---- Décodeur Dolby Vision ---------------------------------------------

    @Test
    fun auto_dolby_hybride_hdr10PlusPart_dolbyVisionReste() {
        val picture = slice(IDR, 800, 11)
        val unit = accessUnit(aud(), vps(), sps(), pps(), hdr10PlusSei(), picture, rpu())
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.DOLBY_DECODER)
        assertContentEquals(accessUnit(aud(), vps(), sps(), pps(), picture, rpu()), run(filter, unit, keyFrame = true))
        assertEquals(1, filter.removedHdr10Plus)
        assertEquals(0, filter.removedDolbyVision)
    }

    @Test
    fun auto_dolby_dolbyVisionSeul_rienNeBouge() {
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.DOLBY_DECODER)
        assertUntouched(filter, accessUnit(vps(), sps(), pps(), slice(IDR, 500, 12), rpu()), keyFrame = true)
        repeat(30) { assertUntouched(filter, accessUnit(slice(TRAIL, 150, 13 + it), rpu()), keyFrame = false) }
    }

    // ---- Réglage « Compatibilité HDR » -------------------------------------

    @Test
    fun strict_hevc_retireChaqueJeuMemeSeul() {
        val picture = slice(IDR, 500, 14)
        val onlyHdr = HybridHdrFilter(HybridHdrMode.STRICT, HybridHdrPath.HEVC_DECODER)
        assertContentEquals(
            accessUnit(vps(), sps(), pps(), picture),
            run(onlyHdr, accessUnit(vps(), sps(), pps(), hdr10PlusSei(), picture), keyFrame = true),
        )
        val onlyDolby = HybridHdrFilter(HybridHdrMode.STRICT, HybridHdrPath.HEVC_DECODER)
        assertContentEquals(
            accessUnit(vps(), sps(), pps(), picture),
            run(onlyDolby, accessUnit(vps(), sps(), pps(), picture, rpu()), keyFrame = true),
        )
        // Et sur les images ordinaires qui suivent.
        val next = slice(TRAIL, 90, 15)
        repeat(20) {
            assertContentEquals(accessUnit(next), run(onlyDolby, accessUnit(next, rpu()), keyFrame = false))
            assertContentEquals(accessUnit(next), run(onlyHdr, accessUnit(hdr10PlusSei(), next), keyFrame = false))
        }
    }

    @Test
    fun strict_dolby_gardeLeDolbyVision() {
        val picture = slice(IDR, 500, 16)
        val filter = HybridHdrFilter(HybridHdrMode.STRICT, HybridHdrPath.DOLBY_DECODER)
        assertContentEquals(
            accessUnit(vps(), sps(), pps(), picture, rpu()),
            run(filter, accessUnit(vps(), sps(), pps(), hdr10PlusSei(), picture, rpu()), keyFrame = true),
        )
    }

    // ---- Observation seule -------------------------------------------------

    @Test
    fun watch_neModifieJamais_maisSaitCeQueLeFluxContient() {
        val filter = HybridHdrFilter(HybridHdrMode.WATCH, HybridHdrPath.HEVC_DECODER)
        assertUntouched(
            filter,
            accessUnit(aud(), vps(), sps(), pps(), hdr10PlusSei(), slice(IDR, 500, 17), rpu()),
            keyFrame = true,
        )
        assertTrue(filter.hybrid)
        assertEquals(0, filter.removedHdr10Plus)
        assertEquals(0, filter.removedDolbyVision)
        repeat(30) {
            assertUntouched(filter, accessUnit(hdr10PlusSei(), slice(TRAIL, 100, 18 + it), rpu()), keyFrame = false)
        }
    }

    // ---- Messages SEI ------------------------------------------------------

    @Test
    fun hdr10PlusRangeAvecDAutresMessages_seulSonNumeroChange() {
        val mastering = seiMessage(137, ByteArray(24) { (it + 1).toByte() })
        val light = seiMessage(144, byteArrayOf(0x03, 0xE8.toByte(), 0x01, 0x90.toByte()))
        val mixed = seiNal(PREFIX_SEI, mastering + hdr10PlusMessage() + light)
        val picture = slice(IDR, 400, 19)
        val unit = accessUnit(vps(), sps(), pps(), mixed, picture, rpu())
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.DOLBY_DECODER)
        val out = run(filter, unit, keyFrame = true)
        // Même taille : l'unité reste, un seul octet diffère.
        assertEquals(unit.size, out.size)
        val differences = unit.indices.filter { unit[it] != out[it] }
        assertEquals(1, differences.size)
        assertEquals(4, unit[differences[0]].toInt())
        assertEquals(254, out[differences[0]].toInt() and 0xFF)
        assertEquals(1, filter.removedHdr10Plus)
        // Relu, le flux ne montre plus de HDR10+.
        val again = HybridHdrFilter(HybridHdrMode.WATCH, HybridHdrPath.DOLBY_DECODER)
        run(again, out, keyFrame = true)
        assertFalse(again.sawHdr10Plus)
    }

    @Test
    fun octetsAntiEmulationDansLeMessage_reconnusEtRetires() {
        // 00 00 dans les données → l'encodeur a inséré un 03 : la signature
        // et la taille doivent être lues SANS ces octets.
        val payload = HDR10_PLUS_HEADER + byteArrayOf(0x01, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x01, 0x40)
        val sei = seiNal(PREFIX_SEI, seiMessage(4, payload))
        assertTrue(sei.toList().windowed(3).any { it == listOf<Byte>(0, 0, 3) }, "le test doit contenir un 00 00 03")
        val picture = slice(IDR, 300, 20)
        val filter = HybridHdrFilter(HybridHdrMode.STRICT, HybridHdrPath.HEVC_DECODER)
        assertContentEquals(
            accessUnit(vps(), sps(), pps(), picture),
            run(filter, accessUnit(vps(), sps(), pps(), sei, picture), keyFrame = true),
        )
    }

    @Test
    fun sousTitresCea708EtAutresT35_nonTouches() {
        // Même type de message (4), autre signature : B5 00 31 « GA94 ».
        val captions = seiNal(
            PREFIX_SEI,
            seiMessage(4, byteArrayOf(0xB5.toByte(), 0x00, 0x31, 0x47, 0x41, 0x39, 0x34, 0x03, 0x42, 0x7F)),
        )
        val unit = accessUnit(vps(), sps(), pps(), captions, slice(IDR, 300, 21), rpu())
        for (path in HybridHdrPath.values()) {
            val filter = HybridHdrFilter(HybridHdrMode.AUTO, path)
            assertUntouched(filter, unit, keyFrame = true)
            assertFalse(filter.sawHdr10Plus)
        }
    }

    @Test
    fun messageSeiCoupe_onNeConclutRien() {
        // Taille annoncée 200, 9 octets présents.
        val broken = nal(PREFIX_SEI, byteArrayOf(4, 200.toByte()) + HDR10_PLUS_HEADER + byteArrayOf(1, 2, 3))
        val unit = accessUnit(vps(), sps(), pps(), broken, slice(IDR, 300, 22), rpu())
        val filter = HybridHdrFilter(HybridHdrMode.STRICT, HybridHdrPath.DOLBY_DECODER)
        assertUntouched(filter, unit, keyFrame = true)
        assertFalse(filter.sawHdr10Plus)
    }

    @Test
    fun seiDeSuffixe_traiteCommeLePrefixe() {
        val picture = slice(IDR, 300, 23)
        val suffix = seiNal(SUFFIX_SEI, hdr10PlusMessage())
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.DOLBY_DECODER)
        assertContentEquals(
            accessUnit(vps(), sps(), pps(), picture, rpu()),
            run(filter, accessUnit(vps(), sps(), pps(), picture, suffix, rpu()), keyFrame = true),
        )
    }

    // ---- Forme du tampon ---------------------------------------------------

    @Test
    fun codesDeDepartSurTroisOctetsEtZerosDeBourrage() {
        val picture = slice(IDR, 300, 24)
        val unit = join(
            START3 + vps(), START4 + sps(), START3 + pps(),
            START4 + seiNal(PREFIX_SEI, hdr10PlusMessage()),
            byteArrayOf(0, 0) + START4 + picture, // bourrage devant l'image
            START3 + rpu(), byteArrayOf(0, 0, 0), // zéros en fin de tampon
        )
        val expected = join(
            START3 + vps(), START4 + sps(), START3 + pps(),
            byteArrayOf(0, 0) + START4 + picture,
        )
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.HEVC_DECODER)
        assertContentEquals(expected, run(filter, unit, keyFrame = true))
    }

    @Test
    fun tamponQuiNEstPasEnAnnexB_nonTouche() {
        // Unités précédées de leur longueur (format des conteneurs) : aucun
        // code de départ au début, on ne devine pas.
        val lengthPrefixed = byteArrayOf(0, 0, 0, 5, 0x4E, 0x01, 4, 1, 0x80.toByte(), 0, 0, 0, 3, 0x7C, 0x01, 9)
        for (mode in HybridHdrMode.values()) {
            assertUntouched(HybridHdrFilter(mode, HybridHdrPath.HEVC_DECODER), lengthPrefixed, keyFrame = true)
        }
        // Octets parasites devant le premier code de départ.
        val garbage = byteArrayOf(7) + accessUnit(hdr10PlusSei(), slice(IDR, 50, 25), rpu())
        assertUntouched(HybridHdrFilter(HybridHdrMode.STRICT, HybridHdrPath.HEVC_DECODER), garbage, keyFrame = true)
    }

    @Test
    fun tamponTropCourtOuVide_nonTouche() {
        val filter = HybridHdrFilter(HybridHdrMode.STRICT, HybridHdrPath.HEVC_DECODER)
        assertUntouched(filter, ByteArray(0), keyFrame = true)
        assertUntouched(filter, byteArrayOf(0, 0, 1), keyFrame = true)
        assertUntouched(filter, byteArrayOf(0, 0, 1, 0x7C), keyFrame = true)
    }

    @Test
    fun seulLIntervallePositionLimiteEstLu() {
        val picture = slice(IDR, 200, 26)
        val unit = accessUnit(vps(), sps(), pps(), hdr10PlusSei(), picture, rpu())
        val before = ByteArray(37) { 0x11 }
        val after = accessUnit(hdr10PlusSei(), rpu()) // hors limite : ne doit pas être lu
        val buffer = ByteBuffer.allocateDirect(before.size + unit.size + after.size)
        buffer.put(before).put(unit).put(after)
        buffer.position(before.size)
        buffer.limit(before.size + unit.size)
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.HEVC_DECODER)
        assertTrue(filter.process(buffer, keyFrame = true))
        assertEquals(before.size, buffer.position())
        val expected = accessUnit(vps(), sps(), pps(), picture)
        assertEquals(before.size + expected.size, buffer.limit())
        val out = ByteArray(buffer.remaining())
        buffer.duplicate().get(out)
        assertContentEquals(expected, out)
        // Ce qui précède la position n'a pas bougé.
        val head = ByteArray(before.size)
        buffer.duplicate().apply { clear() }.get(head)
        assertContentEquals(before, head)
        assertEquals(1, filter.removedDolbyVision)
        assertEquals(1, filter.removedHdr10Plus)
    }

    @Test
    fun tresGrandeImage_laCopieParPaquetsGardeChaqueOctet() {
        // Plus grande que le tableau tampon (64 Kio) : plusieurs paquets.
        val picture = slice(IDR, 700_000, 27)
        val second = slice(IDR, 180_001, 28)
        val unit = accessUnit(aud(), vps(), sps(), pps(), hdr10PlusSei(), picture, second, rpu())
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.HEVC_DECODER)
        assertContentEquals(accessUnit(aud(), vps(), sps(), pps(), picture, second), run(filter, unit, keyFrame = true))
    }

    @Test
    fun beaucoupDeTranches_lIndexGrandit() {
        val slices = List(300) { slice(TRAIL, 20 + it % 7, 100 + it) }
        val unit = accessUnit(hdr10PlusSei(), *slices.toTypedArray(), rpu())
        val filter = HybridHdrFilter(HybridHdrMode.STRICT, HybridHdrPath.HEVC_DECODER)
        assertContentEquals(accessUnit(*slices.toTypedArray()), run(filter, unit, keyFrame = true))
    }

    // ---- Coût sur un flux ordinaire ----------------------------------------

    @Test
    fun fluxOrdinaire_apresLaFenetreSeulesLesImagesClesSontLues() {
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.HEVC_DECODER)
        assertUntouched(filter, accessUnit(vps(), sps(), pps(), slice(IDR, 100, 29)), keyFrame = true)
        repeat(HybridHdrFilter.PROBE_UNITS) {
            assertUntouched(filter, accessUnit(slice(TRAIL, 50, 30 + it)), keyFrame = false)
        }
        // Hors fenêtre, hors image clé : même une image hybride n'est pas
        // lue (c'est le prix d'un coût nul sur les chaînes ordinaires)…
        assertUntouched(filter, accessUnit(hdr10PlusSei(), slice(TRAIL, 50, 60), rpu()), keyFrame = false)
        assertFalse(filter.hybrid)
        // …mais l'image clé suivante la voit, et tout est nettoyé ensuite.
        val key = slice(IDR, 80, 61)
        assertContentEquals(
            accessUnit(vps(), sps(), pps(), key),
            run(filter, accessUnit(vps(), sps(), pps(), hdr10PlusSei(), key, rpu()), keyFrame = true),
        )
        assertTrue(filter.hybrid)
    }

    // ---- Lignes de la boîte noire -----------------------------------------

    @Test
    fun journal_filmHybrideCorrigeSurLaCleAmazon() {
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.HEVC_DECODER)
        run(filter, accessUnit(vps(), sps(), pps(), hdr10PlusSei(), slice(IDR, 100, 70), rpu()), keyFrame = true)
        assertEquals(
            "HDR du flux : Dolby Vision oui, HDR10+ oui (film hybride). " +
                "Décodeur OMX.MTK.VIDEO.DECODER.HEVC. Appareil Amazon AFTKA.",
            HybridHdrReport.content(filter, "OMX.MTK.VIDEO.DECODER.HEVC", "Amazon AFTKA"),
        )
        assertEquals(
            "Correctif HDR (automatique) : Dolby Vision et HDR10+ retirés avant le décodeur HEVC, " +
                "le film passe en HDR10.",
            HybridHdrReport.action(filter),
        )
    }

    @Test
    fun journal_decodeurDolbyVision_ditCeQuiResteEtCeQuiPart() {
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.DOLBY_DECODER)
        run(filter, accessUnit(vps(), sps(), pps(), hdr10PlusSei(), slice(IDR, 100, 71), rpu()), keyFrame = true)
        assertEquals(
            "Correctif HDR (automatique) : HDR10+ retiré avant le décodeur Dolby Vision, Dolby Vision gardé.",
            HybridHdrReport.action(filter),
        )
    }

    @Test
    fun journal_reglageManuel_etUnSeulJeu() {
        val onlyDolby = HybridHdrFilter(HybridHdrMode.STRICT, HybridHdrPath.HEVC_DECODER)
        run(onlyDolby, accessUnit(vps(), sps(), pps(), slice(IDR, 100, 72), rpu()), keyFrame = true)
        assertEquals(
            "HDR du flux : Dolby Vision oui, HDR10+ non. Décodeur c2.test. Appareil Box.",
            HybridHdrReport.content(onlyDolby, "c2.test", "Box"),
        )
        assertEquals(
            "Correctif HDR (réglage) : Dolby Vision retiré avant le décodeur HEVC, le film passe en HDR10.",
            HybridHdrReport.action(onlyDolby),
        )
        val onlyHdr = HybridHdrFilter(HybridHdrMode.STRICT, HybridHdrPath.HEVC_DECODER)
        run(onlyHdr, accessUnit(vps(), sps(), pps(), hdr10PlusSei(), slice(IDR, 100, 73)), keyFrame = true)
        assertEquals(
            "HDR du flux : Dolby Vision non, HDR10+ oui. Décodeur c2.test. Appareil Box.",
            HybridHdrReport.content(onlyHdr, "c2.test", "Box"),
        )
        assertEquals(
            "Correctif HDR (réglage) : HDR10+ retiré avant le décodeur HEVC, le film passe en HDR10.",
            HybridHdrReport.action(onlyHdr),
        )
    }

    @Test
    fun journal_observationSeule_ditQueRienNEstRetireEtQuoiEssayer() {
        val filter = HybridHdrFilter(HybridHdrMode.WATCH, HybridHdrPath.HEVC_DECODER)
        run(filter, accessUnit(vps(), sps(), pps(), hdr10PlusSei(), slice(IDR, 100, 74), rpu()), keyFrame = true)
        val line = HybridHdrReport.content(filter, "OMX.MTK.VIDEO.DECODER.HEVC", "Amazon AFTMM")
        assertTrue(line.startsWith("HDR du flux : Dolby Vision oui, HDR10+ oui (film hybride)."), line)
        assertTrue(line.contains("Rien n'est retiré sur cet appareil"), line)
        // Le nom exact de l'écran : c'est ce que le support lira au client.
        assertTrue(line.contains("allumer « Compatibilité HDR » (Réglages → En plus)."), line)
        assertNull(HybridHdrReport.action(filter))
    }

    @Test
    fun journal_fluxSansHdrDynamique_apresLaFenetre() {
        val filter = HybridHdrFilter(HybridHdrMode.AUTO, HybridHdrPath.HEVC_DECODER)
        assertFalse(filter.settled)
        run(filter, accessUnit(vps(), sps(), pps(), slice(IDR, 100, 75)), keyFrame = true)
        repeat(HybridHdrFilter.PROBE_UNITS - 2) { run(filter, accessUnit(slice(TRAIL, 40, 76 + it)), keyFrame = false) }
        assertFalse(filter.settled, "la fenêtre n'est pas finie")
        run(filter, accessUnit(slice(TRAIL, 40, 99)), keyFrame = false)
        assertTrue(filter.settled)
        assertEquals(
            "HDR du flux : ni Dolby Vision ni HDR10+. Décodeur c2.test. Appareil Amazon AFTKA.",
            HybridHdrReport.content(filter, "c2.test", "Amazon AFTKA"),
        )
        assertNull(HybridHdrReport.action(filter))
    }

    // ---- Après un saut dans le film ---------------------------------------

    @Test
    fun decodeurNeufApresUnSaut_seulementLaOuLeDefautAEteVu() {
        // Appareil en défaut : en 4K seulement. Les chaînes HD gardent le saut rapide.
        assertTrue(HybridHdr.freshDecoderAfterSeek(HybridHdrMode.AUTO, ultraHd = true))
        assertFalse(HybridHdr.freshDecoderAfterSeek(HybridHdrMode.AUTO, ultraHd = false))
        // Réglage allumé par la personne : toujours.
        assertTrue(HybridHdr.freshDecoderAfterSeek(HybridHdrMode.STRICT, ultraHd = true))
        assertTrue(HybridHdr.freshDecoderAfterSeek(HybridHdrMode.STRICT, ultraHd = false))
        // Observation, box ordinaire, repli armé : Media3 vide le décodeur comme avant.
        assertFalse(HybridHdr.freshDecoderAfterSeek(HybridHdrMode.WATCH, ultraHd = true))
        assertFalse(HybridHdr.freshDecoderAfterSeek(null, ultraHd = true))
        assertFalse(HybridHdr.freshDecoderAfterSeek(null, ultraHd = false))
    }

    @Test
    fun decodeurNeufApresUnSaut_suitLAppareilLeReglageEtLeRepli() {
        fun fresh(scope: HybridHdrScope, manual: Boolean, autoOff: Boolean) =
            HybridHdr.freshDecoderAfterSeek(HybridHdr.mode(scope, manual, autoOff), ultraHd = true)
        assertTrue(fresh(HybridHdrScope.FIX, manual = false, autoOff = false))
        assertFalse(fresh(HybridHdrScope.FIX, manual = false, autoOff = true))
        assertFalse(fresh(HybridHdrScope.WATCH, manual = false, autoOff = false))
        assertFalse(fresh(HybridHdrScope.NONE, manual = false, autoOff = false))
        assertTrue(fresh(HybridHdrScope.NONE, manual = true, autoOff = false))
        assertTrue(fresh(HybridHdrScope.NONE, manual = true, autoOff = true))
    }

    @Test
    fun premiereImage_typeLuSansLireLeContenu() {
        fun type(vararg nals: ByteArray): Int =
            HybridHdrFilter.firstPictureType(ByteBuffer.wrap(accessUnit(*nals)))
        assertEquals(IDR, type(aud(), vps(), sps(), pps(), hdr10PlusSei(), slice(IDR, 500, 80), rpu()))
        assertEquals(21, type(aud(), vps(), sps(), pps(), slice(21, 500, 81)))
        assertEquals(TRAIL, type(hdr10PlusSei(), slice(TRAIL, 500, 82), rpu()))
        // La première image compte, pas les tranches suivantes.
        assertEquals(TRAIL, type(slice(TRAIL, 50, 83), slice(IDR, 50, 84)))
        // Pas d'image du tout, ou tampon qui n'est pas en Annex B.
        assertEquals(-1, type(aud(), vps(), sps(), pps()))
        assertEquals(-1, HybridHdrFilter.firstPictureType(ByteBuffer.wrap(byteArrayOf(1, 2, 3, 4, 5, 6))))
        assertEquals(-1, HybridHdrFilter.firstPictureType(ByteBuffer.wrap(ByteArray(0))))
        assertEquals(-1, HybridHdrFilter.firstPictureType(ByteBuffer.wrap(byteArrayOf(0, 0, 1))))
    }

    @Test
    fun premiereImage_respecteLaPositionEtNeChangeRien() {
        val unit = accessUnit(vps(), sps(), pps(), slice(21, 300, 85))
        val buffer = ByteBuffer.allocateDirect(40 + unit.size)
        // Devant la position : une autre image, qui ne doit pas être lue.
        buffer.put(accessUnit(slice(IDR, 30, 86)).copyOf(40)).put(unit)
        buffer.position(40)
        assertEquals(21, HybridHdrFilter.firstPictureType(buffer))
        assertEquals(40, buffer.position())
        assertEquals(40 + unit.size, buffer.limit())
    }

    @Test
    fun journal_apresUnSaut() {
        // Image clé fermée (IDR) : rien à dire.
        assertNull(HybridHdrReport.afterSeek(19))
        assertNull(HybridHdrReport.afterSeek(20))
        // Image clé ouverte (BLA, CRA) : notée, c'est un départ légal.
        for (type in listOf(16, 17, 18, 21)) {
            assertEquals(
                "Après un saut : reprise sur une image clé ouverte (type $type).",
                HybridHdrReport.afterSeek(type),
            )
        }
        // Image ordinaire : le décodeur n'a pas ses images de référence.
        for (type in listOf(0, 1, 8, 9, 15)) {
            val line = HybridHdrReport.afterSeek(type)
            assertTrue(line != null && line.contains("n'est pas une image clé (type $type)"), "$type : $line")
        }
        assertNull(HybridHdrReport.afterSeek(-1))
        assertNull(HybridHdrReport.afterSeek(22))
        assertNull(HybridHdrReport.afterSeek(39))
    }

    // ---- Comparaison avec une écriture naïve, sur des milliers de flux -----

    @Test
    fun milleUnitesAuHasard_memeResultatQuUneReecritureNaive() {
        val random = Random(20261114)
        for (round in 0 until 1_500) {
            val mode = HybridHdrMode.values()[random.nextInt(3)]
            val path = HybridHdrPath.values()[random.nextInt(2)]
            val filter = HybridHdrFilter(mode, path)
            var dolbySeen = false
            var hdrSeen = false
            repeat(1 + random.nextInt(4)) { frame ->
                val parts = ArrayList<Part>()
                if (random.nextBoolean()) parts.add(Part(aud(), Kind.OTHER))
                if (frame == 0) {
                    parts.add(Part(vps(), Kind.OTHER))
                    parts.add(Part(sps(), Kind.OTHER))
                    parts.add(Part(pps(), Kind.OTHER))
                }
                if (random.nextInt(3) == 0) {
                    parts.add(Part(seiNal(PREFIX_SEI, seiMessage(137, ByteArray(24) { random.nextInt(256).toByte() })), Kind.OTHER))
                }
                if (random.nextBoolean()) parts.add(Part(hdr10PlusSei(random), Kind.HDR))
                repeat(1 + random.nextInt(3)) {
                    parts.add(Part(slice(if (frame == 0) IDR else TRAIL, 1 + random.nextInt(3_000), random.nextInt()), Kind.OTHER))
                }
                if (random.nextInt(4) == 0) parts.add(Part(dolbyLayer(1 + random.nextInt(500)), Kind.DOLBY))
                if (random.nextBoolean()) parts.add(Part(rpu(random), Kind.DOLBY))
                if (random.nextInt(6) == 0) parts.add(Part(seiNal(SUFFIX_SEI, seiMessage(132, ByteArray(16) { 0x22 })), Kind.OTHER))

                // Toutes les unités de cette suite sont lues (image clé ou
                // fenêtre d'observation) : la règle naïve s'applique à chacune.
                if (parts.any { it.kind == Kind.DOLBY }) dolbySeen = true
                if (parts.any { it.kind == Kind.HDR }) hdrSeen = true
                val stripHdr = when (mode) {
                    HybridHdrMode.WATCH -> false
                    HybridHdrMode.AUTO -> path == HybridHdrPath.DOLBY_DECODER || (dolbySeen && hdrSeen)
                    HybridHdrMode.STRICT -> true
                }
                val stripDolby = when (mode) {
                    HybridHdrMode.WATCH -> false
                    HybridHdrMode.AUTO -> path == HybridHdrPath.HEVC_DECODER && dolbySeen && hdrSeen
                    HybridHdrMode.STRICT -> path == HybridHdrPath.HEVC_DECODER
                }
                val codes = parts.map { if (random.nextBoolean()) START3 else START4 }
                val input = join(*parts.mapIndexed { i, part -> codes[i] + part.bytes }.toTypedArray())
                val expected = join(
                    *parts.mapIndexedNotNull { i, part ->
                        val gone = (part.kind == Kind.HDR && stripHdr) || (part.kind == Kind.DOLBY && stripDolby)
                        if (gone) null else codes[i] + part.bytes
                    }.toTypedArray(),
                )
                // Sans code de départ de tête retiré, le résultat commence
                // comme l'entrée : le premier code gardé reste tel quel.
                val out = run(filter, input, keyFrame = frame == 0, direct = random.nextBoolean())
                assertContentEquals(expected, out, "tour $round image $frame $mode $path")
            }
        }
    }

    // ---- Fabrique d'unités HEVC --------------------------------------------

    private enum class Kind { OTHER, HDR, DOLBY }

    private class Part(val bytes: ByteArray, val kind: Kind)

    private fun run(
        filter: HybridHdrFilter,
        unit: ByteArray,
        keyFrame: Boolean,
        direct: Boolean = true,
    ): ByteArray {
        // Le décodeur donne un tampon plus grand que l'image : on le laisse
        // rempli d'un motif pour voir un débordement.
        val capacity = unit.size + 64
        val buffer = if (direct) ByteBuffer.allocateDirect(capacity) else ByteBuffer.allocate(capacity)
        buffer.put(unit)
        repeat(64) { buffer.put(0x6B) }
        buffer.position(0)
        buffer.limit(unit.size)
        val changed = filter.process(buffer, keyFrame)
        assertEquals(0, buffer.position(), "la position est rendue")
        assertTrue(buffer.limit() <= unit.size, "le filtre n'ajoute jamais d'octet")
        val out = ByteArray(buffer.remaining())
        buffer.duplicate().get(out)
        assertEquals(changed, !out.contentEquals(unit), "« changé » dit la vérité")
        // Rien n'a été écrit après la fin de l'image d'origine.
        val tail = buffer.duplicate()
        tail.limit(capacity)
        tail.position(unit.size)
        while (tail.hasRemaining()) assertEquals(0x6B, tail.get().toInt())
        return out
    }

    private fun assertUntouched(filter: HybridHdrFilter, unit: ByteArray, keyFrame: Boolean) {
        assertContentEquals(unit, run(filter, unit, keyFrame))
    }

    private fun accessUnit(vararg nals: ByteArray): ByteArray = join(*nals.map { START4 + it }.toTypedArray())

    private fun join(vararg parts: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        for (part in parts) out.write(part)
        return out.toByteArray()
    }

    /** En-tête NAL HEVC (2 octets) + contenu protégé contre l'émulation. */
    private fun nal(type: Int, rbsp: ByteArray): ByteArray =
        byteArrayOf((type shl 1).toByte(), 0x01) + escape(rbsp)

    /** Insère 03 après deux zéros quand l'octet suivant vaut 0 à 3. */
    private fun escape(rbsp: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        var zeros = 0
        for (value in rbsp) {
            if (zeros >= 2 && (value.toInt() and 0xFF) <= 3) {
                out.write(3)
                zeros = 0
            }
            out.write(value.toInt())
            zeros = if (value.toInt() == 0) zeros + 1 else 0
        }
        return out.toByteArray()
    }

    private fun seiMessage(type: Int, payload: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        var left = type
        while (left >= 255) {
            out.write(255)
            left -= 255
        }
        out.write(left)
        left = payload.size
        while (left >= 255) {
            out.write(255)
            left -= 255
        }
        out.write(left)
        out.write(payload)
        return out.toByteArray()
    }

    /** Unité SEI : messages puis bits de fin (1000 0000). */
    private fun seiNal(type: Int, messages: ByteArray): ByteArray = nal(type, messages + byteArrayOf(0x80.toByte()))

    private fun hdr10PlusMessage(random: Random? = null): ByteArray {
        val body = ByteArray(if (random == null) 30 else 1 + random.nextInt(300)) {
            (random?.nextInt(256) ?: (it * 7 + 1)).toByte()
        }
        return seiMessage(4, HDR10_PLUS_HEADER + byteArrayOf(0x01) + body)
    }

    private fun hdr10PlusSei(random: Random? = null): ByteArray = seiNal(PREFIX_SEI, hdr10PlusMessage(random))

    private fun rpu(random: Random? = null): ByteArray =
        nal(62, ByteArray(if (random == null) 90 else 1 + random.nextInt(600)) {
            (random?.nextInt(256) ?: (it * 3 + 5)).toByte()
        } + byteArrayOf(0x80.toByte()))

    private fun dolbyLayer(size: Int): ByteArray = nal(63, ByteArray(size) { (it * 11 + 2).toByte() } + byteArrayOf(0x80.toByte()))

    private fun aud(): ByteArray = nal(35, byteArrayOf(0x50))

    private fun vps(): ByteArray = nal(32, byteArrayOf(0x0C, 0x01, 0xFF.toByte(), 0xFF.toByte(), 0x02, 0x20, 0x00, 0x00, 0x03, 0x00, 0xB0.toByte()))

    private fun sps(): ByteArray = nal(33, ByteArray(40) { (0x40 + it).toByte() })

    private fun pps(): ByteArray = nal(34, byteArrayOf(0xC1.toByte(), 0x72, 0xB4.toByte(), 0x62, 0x40))

    /** Tranche d'image : octets au hasard, dernier octet non nul. */
    private fun slice(type: Int, size: Int, seed: Int): ByteArray {
        val random = Random(seed)
        val body = ByteArray(size) { random.nextInt(256).toByte() }
        body[body.size - 1] = 0x80.toByte()
        return nal(type, body)
    }

    private companion object {
        const val TRAIL = 1
        const val IDR = 19
        const val PREFIX_SEI = 39
        const val SUFFIX_SEI = 40
        val START3 = byteArrayOf(0, 0, 1)
        val START4 = byteArrayOf(0, 0, 0, 1)
        val HDR10_PLUS_HEADER = byteArrayOf(0xB5.toByte(), 0x00, 0x3C, 0x00, 0x01, 0x04)
    }
}
